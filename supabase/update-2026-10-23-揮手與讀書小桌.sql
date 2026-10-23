-- =====================================================================
-- 揮手打招呼、讀書小桌（2026-10-23；整份重跑即可）
-- 揮手：好友之間每天第一次揮手 +1 好感度（揮手本身走即時連線，不存資料庫）。
-- 讀書小桌：同一桌的人專注時間重疊 10 分鐘以上，雙方各 +20 金幣（每人每天最多 3 次），是好友再 +1 好感度。
--   後完成的人送出時，資料庫會找同桌的人剛存的專注紀錄比對時間，一次發給兩邊，先完成的人也拿得到。
-- =====================================================================

-- 加減好感度（觸發器呼叫）
create or replace function public.bump_affinity(x uuid, y uuid, p_kind text, p_amt int, p_actor uuid)
returns void language plpgsql security definer set search_path = public as $$
declare pa uuid := least(x, y); pb uuid := greatest(x, y); got int; n int; amt int := p_amt; oldlv int; newlv int; pts int; lv int;
begin
  if x = y or not public.are_friends(x, y) then return; end if;
  perform pg_advisory_xact_lock(hashtext(pa::text || pb::text));
  if amt > 0 then
    select count(*) into n from public.friend_point_log where a = pa and b = pb and day = public.taipei_today() and actor = p_actor and kind = p_kind;
    if p_kind in ('msg', 'gift', 'wave', 'table') and n >= 1 then return; end if;
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

create or replace function public.wave_friend(p_to uuid)
returns json language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or p_to is null or p_to = auth.uid() then return json_build_object('ok', false); end if;
  if public.are_friends(auth.uid(), p_to) then
    perform public.bump_affinity(auth.uid(), p_to, 'wave', 1, auth.uid());
  end if;
  return json_build_object('ok', true);
end $$;
revoke all on function public.wave_friend(uuid) from public, anon;
grant execute on function public.wave_friend(uuid) to authenticated;

create table if not exists public.table_bonus (
  client_id text primary key,
  user_id uuid not null references public.profiles on delete cascade,
  day date not null default public.taipei_today(),
  created_at timestamptz not null default now()
);
create index if not exists table_bonus_user_day on public.table_bonus (user_id, day);
alter table public.table_bonus enable row level security;
drop policy if exists "看自己的小桌獎勵" on public.table_bonus;
create policy "看自己的小桌獎勵" on public.table_bonus for select to authenticated using (user_id = auth.uid());

-- 發一次小桌獎勵（同一次專注只發一次、每人每天最多 3 次）；有發回傳 true
create or replace function public.give_table_bonus(p_user uuid, p_cid text)
returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_cid is null then return false; end if;
  perform pg_advisory_xact_lock(hashtext('table' || p_user::text));
  select count(*)::int into n from public.table_bonus where user_id = p_user and day = public.taipei_today();
  if n >= 3 then return false; end if;
  insert into public.table_bonus (client_id, user_id) values (p_cid, p_user) on conflict do nothing;
  if not found then return false; end if;
  insert into public.coin_tx (user_id, amount, kind, ref) values (p_user, 20, 'table', p_cid);
  return true;
end $$;
revoke all on function public.give_table_bonus(uuid, text) from public, anon, authenticated;

create or replace function public.claim_table_bonus(p_sid text, p_mates uuid[])
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); s record; m record; b1 timestamptz; got boolean := false; names text[] := '{}';
begin
  if me is null then return json_build_object('got', 0); end if;
  select * into s from public.focus_sessions where client_id = p_sid and user_id = me;
  if not found or s.minutes < 15 then return json_build_object('got', 0, 'wallet', public.wallet_balance(me)); end if;
  b1 := s.created_at - make_interval(mins => s.minutes);
  for m in
    select f.user_id, f.client_id, f.created_at, f.minutes, p.name from public.focus_sessions f join public.profiles p on p.id = f.user_id
    where f.user_id = any(p_mates[1:3]) and f.user_id <> me and f.day >= s.day - 1 and f.minutes >= 15
      and f.created_at > b1 and f.created_at - make_interval(mins => f.minutes) < s.created_at
      and least(s.created_at, f.created_at) - greatest(b1, f.created_at - make_interval(mins => f.minutes)) >= interval '10 minutes'
  loop
    if public.give_table_bonus(me, s.client_id) then got := true; end if;
    perform public.give_table_bonus(m.user_id, m.client_id);
    perform public.bump_affinity(me, m.user_id, 'table', 1, me);
    names := names || m.name;
  end loop;
  return json_build_object('got', case when got then 20 else 0 end, 'mates', to_json(names), 'wallet', public.wallet_balance(me));
end $$;
revoke all on function public.claim_table_bonus(text, uuid[]) from public, anon;
grant execute on function public.claim_table_bonus(text, uuid[]) to authenticated;
