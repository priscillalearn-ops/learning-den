
-- =====================================================================
-- 新手大禮包（2026-09-30 更新；整份重跑即可）
-- 每個帳號領一次：300 金幣、禮包限定寵物「新手小雞」、3 張盲盒券。舊帳號下次登入也會領到。
-- =====================================================================
alter table public.shop_items add column if not exists bundle text;
alter table public.gacha_state add column if not exists tickets int not null default 0;
insert into public.shop_items (id, slot, price, bundle) values ('pet_chick', 'pet', 9999, 'starter')
  on conflict (id) do update set slot = excluded.slot, price = excluded.price, bundle = excluded.bundle;

create table if not exists public.starter_claims (
  user_id uuid primary key references public.profiles on delete cascade,
  claimed_at timestamptz not null default now()
);
alter table public.starter_claims enable row level security;
drop policy if exists "看自己的新手禮包" on public.starter_claims;
create policy "看自己的新手禮包" on public.starter_claims for select to authenticated using (user_id = auth.uid());

create or replace function public.claim_starter_pack()
returns json language plpgsql security definer set search_path = public as $$
declare got boolean;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid()) then raise exception '請先建立角色'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  insert into public.starter_claims (user_id) values (auth.uid()) on conflict (user_id) do nothing;
  got := found;
  if got then
    insert into public.coin_tx (user_id, amount, kind) values (auth.uid(), 300, 'starter');
    insert into public.purchases (user_id, item_id, price)
      select auth.uid(), 'pet_chick', 0
      where not exists (select 1 from public.purchases where user_id = auth.uid() and item_id = 'pet_chick');
    insert into public.gacha_state (user_id, tickets) values (auth.uid(), 3)
      on conflict (user_id) do update set tickets = public.gacha_state.tickets + 3;
  end if;
  return json_build_object('claimed', got, 'wallet', public.wallet_balance(auth.uid()),
    'tickets', coalesce((select tickets from public.gacha_state where user_id = auth.uid()), 0));
end $$;

-- 禮包限定、盲盒限定、單字卡解鎖的東西都不能直接買
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
  if it.bundle is not null then raise exception '這個是新手大禮包限定的'; end if;
  if it.price = 0 then return bal; end if;
  if it.gacha is not null then raise exception '這個只能從魔法盲盒抽到'; end if;
  if it.unlock_cards is not null then raise exception '這個要收集單字卡才能解鎖'; end if;
  if not public.item_on_sale(it) then raise exception '這個限定商品現在沒有販售'; end if;
  if bal < it.price then raise exception '金幣不夠'; end if;
  insert into public.purchases (user_id, item_id, price) values (auth.uid(), p_item, it.price);
  return bal - it.price;
end $$;

create or replace function public.gacha_info()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'pity', coalesce((select pity from public.gacha_state where user_id = auth.uid()), 0),
    'pulls', coalesce((select pulls from public.gacha_state where user_id = auth.uid() and day = public.taipei_today()), 0),
    'free_used', coalesce((select free_day = public.taipei_today() from public.gacha_state where user_id = auth.uid()), false),
    'tickets', coalesce((select tickets from public.gacha_state where user_id = auth.uid()), 0));
$$;

-- 抽盲盒：多了 p_ticket（用盲盒券抽一次，不算每日 10 抽）
drop function if exists public.gacha_pull(integer, boolean);
create or replace function public.gacha_pull(p_n int, p_free boolean, p_ticket boolean default false)
returns json language plpgsql security definer set search_path = public as $$
declare st public.gacha_state; res json[] := '{}'; r float; rar text; it text; got_sr boolean := false; dup boolean; refund int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_n not in (1, 10) then raise exception '一次抽 1 個或 10 個'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  insert into public.gacha_state (user_id) values (auth.uid()) on conflict (user_id) do nothing;
  select * into st from public.gacha_state where user_id = auth.uid() for update;
  if st.day is distinct from public.taipei_today() then st.day := public.taipei_today(); st.pulls := 0; end if;
  if coalesce(p_ticket, false) then
    if p_n <> 1 then raise exception '一張盲盒券抽 1 個'; end if;
    if st.tickets < 1 then raise exception '沒有盲盒券了'; end if;
    st.tickets := st.tickets - 1;
  elsif coalesce(p_free, false) then
    if p_n <> 1 then raise exception '免費抽一次只能抽 1 個'; end if;
    if st.free_day = public.taipei_today() then raise exception '今天的免費抽已經用過了'; end if;
    if not exists (select 1 from public.answers where user_id = auth.uid() and day = public.taipei_today()) then
      raise exception '先答今日一題，就能免費抽一次'; end if;
    st.free_day := public.taipei_today();
  else
    if st.pulls + p_n > 10 then raise exception '今天最多抽 10 次，明天再來'; end if;
    if public.wallet_balance(auth.uid()) < (case p_n when 1 then 50 else 450 end) then raise exception '金幣不夠'; end if;
    st.pulls := st.pulls + p_n;
    insert into public.coin_tx (user_id, amount, kind) values (auth.uid(), -(case p_n when 1 then 50 else 450 end), 'gacha');
  end if;
  for i in 1..p_n loop
    st.pity := st.pity + 1;
    r := random();
    rar := case when st.pity >= 50 or r < .02 then 'SSR' when r < .12 then 'SR' when r < .40 then 'R' else 'N' end;
    if p_n = 10 and i = 10 and not got_sr and rar in ('N', 'R') then rar := 'SR'; end if;
    if rar in ('SR', 'SSR') then got_sr := true; end if;
    if rar = 'SSR' then st.pity := 0; end if;
    select id into it from public.shop_items where gacha = rar order by random() limit 1;
    dup := exists (select 1 from public.purchases where user_id = auth.uid() and item_id = it);
    if dup then
      refund := case rar when 'N' then 10 when 'R' then 25 when 'SR' then 80 else 200 end;
      insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), refund, 'gacha_refund', it);
    else
      refund := 0;
      insert into public.purchases (user_id, item_id, price) values (auth.uid(), it, 0);
    end if;
    res := res || json_build_object('item', it, 'rarity', rar, 'dup', dup, 'refund', refund);
  end loop;
  update public.gacha_state set pity = st.pity, day = st.day, pulls = st.pulls, free_day = st.free_day, tickets = st.tickets where user_id = auth.uid();
  return json_build_object('results', array_to_json(res), 'wallet', public.wallet_balance(auth.uid()), 'pity', st.pity, 'pulls', st.pulls, 'tickets', st.tickets);
end $$;

revoke all on function public.claim_starter_pack() from public, anon;
grant execute on function public.claim_starter_pack() to authenticated;
revoke all on function public.gacha_info() from public, anon;
grant execute on function public.gacha_info() to authenticated;
revoke all on function public.gacha_pull(integer, boolean, boolean) from public, anon;
grant execute on function public.gacha_pull(integer, boolean, boolean) to authenticated;
revoke all on function public.buy_item(text) from public, anon;
grant execute on function public.buy_item(text) to authenticated;
