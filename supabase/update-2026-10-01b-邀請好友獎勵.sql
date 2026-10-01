
-- =====================================================================
-- 邀請好友獎勵（2026-10-01 更新；整份重跑即可）
-- 被邀請的人：建角色 7 天內填邀請碼，+100。
-- 邀請的人：好友答今日一題滿 3 天，+100（最多 10 位）；成功 3 位送「友情皇冠」（hat_friend_crown，買不到）。
-- =====================================================================
alter table public.profiles add column if not exists invite_code text;
update public.profiles set invite_code = upper(substr(md5(random()::text || id::text), 1, 6)) where invite_code is null;
alter table public.profiles alter column invite_code set default upper(substr(md5(random()::text), 1, 6));
create unique index if not exists profiles_invite_code on public.profiles (invite_code);

insert into public.shop_items (id, slot, price, bundle) values ('hat_friend_crown', 'hat', 9999, 'invite')
  on conflict (id) do update set slot = excluded.slot, price = excluded.price, bundle = excluded.bundle;

create table if not exists public.referrals (
  invitee uuid primary key references public.profiles on delete cascade,
  inviter uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  paid boolean not null default false
);
create index if not exists referrals_inviter on public.referrals (inviter);
alter table public.referrals enable row level security;
drop policy if exists "看自己的邀請" on public.referrals;
create policy "看自己的邀請" on public.referrals for select to authenticated
  using (inviter = auth.uid() or invitee = auth.uid());

-- 填邀請碼
create or replace function public.use_invite(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare me public.profiles; who public.profiles;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select * into me from public.profiles where id = auth.uid();
  if not found then raise exception '請先建立角色'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if exists (select 1 from public.referrals where invitee = auth.uid()) then raise exception '你已經填過邀請碼了'; end if;
  if me.created_at < now() - interval '7 days' then raise exception '加入超過 7 天就不能填邀請碼了'; end if;
  select * into who from public.profiles where invite_code = upper(trim(p_code));
  if not found then raise exception '找不到這個邀請碼，檢查一下有沒有打錯'; end if;
  if who.id = auth.uid() then raise exception '不能填自己的邀請碼'; end if;
  if exists (select 1 from public.referrals where invitee = who.id and inviter = auth.uid()) then
    raise exception '你邀請過他，不能互相填喔'; end if;
  insert into public.referrals (invitee, inviter) values (auth.uid(), who.id);
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), 100, 'invite_join', who.id::text);
  return json_build_object('inviter', who.name, 'wallet', public.wallet_balance(auth.uid()));
end $$;

-- 結算邀請獎勵＋回傳邀請狀態
create or replace function public.claim_invites()
returns json language plpgsql security definer set search_path = public as $$
declare r record; done int; newly text[] := '{}'; crown_new boolean := false; me public.profiles;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select * into me from public.profiles where id = auth.uid();
  if not found then raise exception '請先建立角色'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select count(*) into done from public.referrals where inviter = auth.uid() and paid;
  for r in
    select f.invitee, p.name from public.referrals f join public.profiles p on p.id = f.invitee
    where f.inviter = auth.uid() and not f.paid
      and (select count(distinct a.day) from public.answers a where a.user_id = f.invitee) >= 3
    order by f.created_at
  loop
    exit when done >= 10;
    update public.referrals set paid = true where invitee = r.invitee;
    insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), 100, 'invite_reward', r.invitee::text);
    done := done + 1; newly := newly || r.name;
  end loop;
  if done >= 3 and not exists (select 1 from public.purchases where user_id = auth.uid() and item_id = 'hat_friend_crown') then
    insert into public.purchases (user_id, item_id, price) values (auth.uid(), 'hat_friend_crown', 0);
    crown_new := true;
  end if;
  return json_build_object(
    'code', me.invite_code,
    'wallet', public.wallet_balance(auth.uid()),
    'newly', to_json(newly),
    'crown', done >= 3,
    'crown_new', crown_new,
    'can_enter', me.created_at >= now() - interval '7 days'
      and not exists (select 1 from public.referrals where invitee = auth.uid()),
    'friends', coalesce((select json_agg(json_build_object('name', p.name, 'paid', f.paid,
        'days', (select count(distinct a.day) from public.answers a where a.user_id = f.invitee)) order by f.created_at)
      from public.referrals f join public.profiles p on p.id = f.invitee where f.inviter = auth.uid()), '[]'::json));
end $$;

revoke all on function public.use_invite(text) from public, anon;
grant execute on function public.use_invite(text) to authenticated;
revoke all on function public.claim_invites() from public, anon;
grant execute on function public.claim_invites() to authenticated;

-- 活動限定（禮包、邀請）都不能直接買
create or replace function public.buy_item(p_item text)
returns int language plpgsql security definer set search_path = public as $$
declare it public.shop_items; bal int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select * into it from public.shop_items where id = p_item;
  if not found then raise exception '沒有這個商品'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  bal := public.wallet_balance(auth.uid());
  if exists (select 1 from public.purchases where user_id = auth.uid() and item_id = p_item) then return bal; end if;
  if it.bundle = 'invite' then raise exception '友情皇冠要成功邀請 3 位好友才拿得到'; end if;
  if it.bundle is not null then raise exception '這個是新手大禮包限定的'; end if;
  if it.price = 0 then return bal; end if;
  if it.gacha is not null then raise exception '這個只能從魔法盲盒抽到'; end if;
  if it.unlock_cards is not null then raise exception '這個要收集單字卡才能解鎖'; end if;
  if not public.item_on_sale(it) then raise exception '這個限定商品現在沒有販售'; end if;
  if bal < it.price then raise exception '金幣不夠'; end if;
  insert into public.purchases (user_id, item_id, price) values (auth.uid(), p_item, it.price);
  return bal - it.price;
end $$;
revoke all on function public.buy_item(text) from public, anon;
grant execute on function public.buy_item(text) to authenticated;
