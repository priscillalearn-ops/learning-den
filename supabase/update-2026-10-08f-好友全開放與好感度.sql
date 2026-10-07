
-- =====================================================================
-- 好友全面開放＋友情好感度（2026-10-08 第六次更新；整份重跑即可）
-- 好友：不用連續打卡；國中、高中可以互加；國小只能加國小（國小之間也能私訊）。
-- 好感度：私訊（每人每天第一則 +1）、送禮 +3、幫忙澆水 +1（每天最多 2）、偷好友的菜 −2；
--         每對好友每天最多加 6 點。升級時雙方都拿獎勵：好朋友 10 點 +20、麻吉 30 點 +50、
--         摯友 60 點 +100＋友情手環、靈魂伴侶 100 點 +200＋愛心翅膀。
-- =====================================================================
create or replace function public.dm_ok(p uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = p);
$$;

-- 國小只能加國小；國中、高中可以互加
drop policy if exists "送出好友邀請" on public.friendships;
create policy "送出好友邀請" on public.friendships for insert to authenticated
  with check (
    requester = auth.uid() and status = 'pending'
    and public.dm_ok(auth.uid()) and public.dm_ok(addressee)
    and ((select tier from public.profiles where id = auth.uid()) = 'kid') = ((select tier from public.profiles where id = addressee) = 'kid')
    and not public.is_blocked_between(auth.uid(), addressee)
    and not exists (select 1 from public.friendships f where f.requester = addressee and f.addressee = auth.uid()));

insert into public.shop_items (id, slot, price, bundle) values
  ('acc_friendband', 'acc', 9999, 'friend'), ('acc_heartwings', 'acc', 9999, 'friend')
  on conflict (id) do update set slot = excluded.slot, price = excluded.price, bundle = excluded.bundle;

create table if not exists public.friend_points (
  a uuid not null references public.profiles on delete cascade,
  b uuid not null references public.profiles on delete cascade,
  points int not null default 0,
  level int not null default 1,
  primary key (a, b),
  check (a < b)
);
alter table public.friend_points enable row level security;
drop policy if exists "看自己的好感度" on public.friend_points;
create policy "看自己的好感度" on public.friend_points for select to authenticated using (a = auth.uid() or b = auth.uid());

create table if not exists public.friend_point_log (
  id bigint generated always as identity primary key,
  a uuid not null, b uuid not null, actor uuid not null,
  kind text not null, amount int not null,
  day date not null default public.taipei_today(),
  created_at timestamptz not null default now()
);
create index if not exists friend_point_log_pair_day on public.friend_point_log (a, b, day);
alter table public.friend_point_log enable row level security;

create or replace function public.friend_level(pts int)
returns int language sql immutable as $$
  select case when pts >= 100 then 5 when pts >= 60 then 4 when pts >= 30 then 3 when pts >= 10 then 2 else 1 end;
$$;

-- 加減好感度（觸發器呼叫）
create or replace function public.bump_affinity(x uuid, y uuid, p_kind text, p_amt int, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare pa uuid := least(x, y); pb uuid := greatest(x, y); got int; n int; amt int := p_amt; oldlv int; newlv int; pts int; lv int;
begin
  if x = y or not public.are_friends(x, y) then return; end if;
  perform pg_advisory_xact_lock(hashtext(pa::text || pb::text));
  if amt > 0 then
    select count(*) into n from public.friend_point_log where a = pa and b = pb and day = public.taipei_today() and actor = p_actor and kind = p_kind;
    if p_kind in ('msg', 'gift') and n >= 1 then return; end if;
    if p_kind = 'water' and n >= 2 then return; end if;
    select coalesce(sum(amount), 0) into got from public.friend_point_log where a = pa and b = pb and day = public.taipei_today() and amount > 0;
    amt := least(amt, 6 - got);
    if amt <= 0 then return; end if;
  end if;
  insert into public.friend_point_log (a, b, actor, kind, amount) values (pa, pb, p_actor, p_kind, amt);
  insert into public.friend_points (a, b, points) values (pa, pb, 0) on conflict (a, b) do nothing;
  select level into oldlv from public.friend_points where a = pa and b = pb for update;
  update public.friend_points set points = greatest(0, points + amt) where a = pa and b = pb returning points into pts;
  newlv := public.friend_level(pts);
  -- 只在第一次升到某一級時發獎勵（等級不會往下掉）
  if newlv > oldlv then
    for lv in oldlv + 1 .. newlv loop
      insert into public.coin_tx (user_id, amount, kind, ref) values
        (pa, (array[0, 20, 50, 100, 200])[lv], 'friend_lv', pb::text), (pb, (array[0, 20, 50, 100, 200])[lv], 'friend_lv', pa::text);
      if lv = 4 then
        insert into public.purchases (user_id, item_id, price) select u, 'acc_friendband', 0 from unnest(array[pa, pb]) u
          where not exists (select 1 from public.purchases where user_id = u and item_id = 'acc_friendband');
      elsif lv = 5 then
        insert into public.purchases (user_id, item_id, price) select u, 'acc_heartwings', 0 from unnest(array[pa, pb]) u
          where not exists (select 1 from public.purchases where user_id = u and item_id = 'acc_heartwings');
      end if;
    end loop;
    update public.friend_points set level = newlv where a = pa and b = pb;
  end if;
end $$;
revoke all on function public.bump_affinity(uuid, uuid, text, int, uuid) from public, anon, authenticated;

create or replace function public.trg_aff_msg() returns trigger language plpgsql security definer set search_path = public as $$
begin perform public.bump_affinity(new.sender, new.recipient, 'msg', 1, new.sender); return new; end $$;
drop trigger if exists aff_msg on public.messages;
create trigger aff_msg after insert on public.messages for each row execute function public.trg_aff_msg();

create or replace function public.trg_aff_gift() returns trigger language plpgsql security definer set search_path = public as $$
begin perform public.bump_affinity(new.sender, new.recipient, 'gift', 3, new.sender); return new; end $$;
drop trigger if exists aff_gift on public.gifts;
create trigger aff_gift after insert on public.gifts for each row execute function public.trg_aff_gift();

create or replace function public.trg_aff_water() returns trigger language plpgsql security definer set search_path = public as $$
begin if new.helper <> new.owner then perform public.bump_affinity(new.helper, new.owner, 'water', 1, new.helper); end if; return new; end $$;
drop trigger if exists aff_water on public.garden_helps;
create trigger aff_water after insert on public.garden_helps for each row execute function public.trg_aff_water();

create or replace function public.trg_aff_steal() returns trigger language plpgsql security definer set search_path = public as $$
begin if not new.caught then perform public.bump_affinity(new.thief, new.owner, 'steal', -2, new.thief); end if; return new; end $$;
drop trigger if exists aff_steal on public.garden_steals;
create trigger aff_steal after insert on public.garden_steals for each row execute function public.trg_aff_steal();

-- 我和每位好友的好感度
create or replace function public.my_affinity()
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('uid', case when a = auth.uid() then b else a end, 'points', points, 'level', level,
    'today', coalesce((select sum(amount) from public.friend_point_log l where l.a = f.a and l.b = f.b and l.day = public.taipei_today() and amount > 0), 0))), '[]'::json)
  from public.friend_points f where a = auth.uid() or b = auth.uid();
$$;
revoke all on function public.my_affinity() from public, anon;
grant execute on function public.my_affinity() to authenticated;
