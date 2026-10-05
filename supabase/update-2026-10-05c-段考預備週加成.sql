
-- =====================================================================
-- 活動週（段考預備週加成）（2026-10-05 第二次更新；整份重跑即可）
-- app_events 放活動期間：期間內 答今日一題、專注、個人任務、讀書會任務 的金幣 × mult；
-- 答完今日一題、專注滿 25 分鐘各有一次機會（drop_rate）抽到盲盒券，每天最多 2 張。
-- 以後段考週只要新增一列，例如：
--   insert into public.app_events (name, start_day, end_day) values ('期中考加成', '2026-11-16', '2026-11-22');
-- =====================================================================
create table if not exists public.app_events (
  id bigint generated always as identity primary key,
  name text not null,
  start_day date not null,
  end_day date not null,
  mult int not null default 2 check (mult between 1 and 5),
  drop_rate numeric not null default 0.4 check (drop_rate between 0 and 1),
  unique (name, start_day)
);
alter table public.app_events enable row level security;
drop policy if exists "大家看得到活動" on public.app_events;
create policy "大家看得到活動" on public.app_events for select to authenticated using (true);
-- 10/5 這週是段考預備週（段考在下週）；如果之前已經用「段考週加成」建好，就改名
update public.app_events set name = '段考預備週加成' where name = '段考週加成' and start_day = '2026-10-05';
insert into public.app_events (name, start_day, end_day, mult, drop_rate)
  values ('段考預備週加成', '2026-10-05', '2026-10-11', 2, 0.4) on conflict (name, start_day) do nothing;

create or replace function public.event_mult(d date)
returns int language sql stable security definer set search_path = public as $$
  select coalesce((select max(mult) from public.app_events where d between start_day and end_day), 1);
$$;

-- 今天的活動（沒有就回傳 null）
create or replace function public.current_event()
returns json language sql stable security definer set search_path = public as $$
  select (select json_build_object('name', name, 'start', start_day, 'end', end_day, 'mult', mult, 'drop', drop_rate)
    from public.app_events where public.taipei_today() between start_day and end_day order by mult desc limit 1);
$$;

-- 金幣公式：活動期間的答題、專注再多算 (mult − 1) 倍
create or replace function public.coins_earned(p uuid)
returns int language sql stable security definer set search_path = public as $$
  select (50
    + coalesce((select sum((10 + case when correct then 5 else 0 end) * public.event_mult(day)) from public.answers where user_id = p), 0)
    + coalesce((select sum(least(m, 150) * public.event_mult(day)) from (
        select day, sum(minutes) as m from public.focus_sessions where user_id = p group by day) x), 0)
    + coalesce((select sum(c) from (values (3,20),(7,50),(15,100),(30,200),(60,400),(100,800)) v(d, c)
        where public.best_streak(p) >= d), 0)
  )::int;
$$;

-- 個人任務：活動期間獎勵 × mult
create or replace function public.claim_quest(p_key text)
returns json language plpgsql security definer set search_path = public as $$
declare q json; per text; amt int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select value into q from json_array_elements(public.quest_board()) where value->>'key' = p_key;
  if q is null then raise exception '找不到這個任務'; end if;
  if (q->>'claimed')::boolean then raise exception '已經領過了'; end if;
  if (q->>'progress')::int < (q->>'target')::int then raise exception '任務還沒完成'; end if;
  per := case q->>'grp' when 'daily' then public.taipei_today()::text
                        when 'weekly' then 'W' || date_trunc('week', public.taipei_today())::date::text else 'm' end;
  amt := (q->>'reward')::int * public.event_mult(public.taipei_today());
  insert into public.quest_claims (user_id, quest, period) values (auth.uid(), p_key, per);
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'quest', p_key);
  return json_build_object('wallet', public.wallet_balance(auth.uid()), 'reward', amt);
end $$;

-- 讀書會任務：活動期間獎勵 × mult
create or replace function public.claim_guild(p_key text)
returns json language plpgsql security definer set search_path = public as $$
declare g json; m json; w date := date_trunc('week', public.taipei_today())::date; amt int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  g := public.guild_info();
  if g->>'name' is null then raise exception '先填班級代碼加入讀書會'; end if;
  select value into m from json_array_elements(g->'missions') where value->>'key' = p_key;
  if m is null then raise exception '沒有這個公會任務'; end if;
  if (m->>'claimed')::boolean then raise exception '這週已經領過了'; end if;
  if (m->>'progress')::int < (m->>'target')::int then raise exception '讀書會還沒完成這個任務'; end if;
  amt := (m->>'reward')::int * public.event_mult(public.taipei_today());
  insert into public.guild_claims (user_id, week, key) values (auth.uid(), w, p_key);
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'guild', p_key);
  return json_build_object('reward', amt, 'wallet', public.wallet_balance(auth.uid()));
end $$;

-- 活動驚喜：答完今日一題、專注滿 25 分鐘，各抽一次盲盒券
create table if not exists public.event_drops (
  user_id uuid not null references public.profiles on delete cascade,
  day date not null default public.taipei_today(),
  kind text not null check (kind in ('answer', 'focus')),
  won boolean not null,
  primary key (user_id, day, kind)
);
alter table public.event_drops enable row level security;

create or replace function public.event_roll(p_kind text)
returns json language plpgsql security definer set search_path = public as $$
declare t date := public.taipei_today(); rate numeric; win boolean; tk int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select max(drop_rate) into rate from public.app_events where t between start_day and end_day;
  if rate is null then return json_build_object('won', false, 'active', false); end if;
  if p_kind = 'answer' and not exists (select 1 from public.answers where user_id = auth.uid() and day = t) then
    return json_build_object('won', false); end if;
  if p_kind = 'focus' and not exists (select 1 from public.focus_sessions where user_id = auth.uid() and day = t and minutes >= 25) then
    return json_build_object('won', false); end if;
  if p_kind not in ('answer', 'focus') then raise exception '沒有這種抽獎'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if exists (select 1 from public.event_drops where user_id = auth.uid() and day = t and kind = p_kind) then
    return json_build_object('won', false, 'rolled', true); end if;
  win := random() < rate;
  insert into public.event_drops (user_id, day, kind, won) values (auth.uid(), t, p_kind, win);
  if win then
    insert into public.gacha_state (user_id, tickets) values (auth.uid(), 1)
      on conflict (user_id) do update set tickets = public.gacha_state.tickets + 1;
  end if;
  select tickets into tk from public.gacha_state where user_id = auth.uid();
  return json_build_object('won', win, 'tickets', coalesce(tk, 0));
end $$;

revoke all on function public.event_mult(date) from public, anon;
grant execute on function public.event_mult(date) to authenticated;
revoke all on function public.current_event() from public, anon;
grant execute on function public.current_event() to authenticated;
revoke all on function public.event_roll(text) from public, anon;
grant execute on function public.event_roll(text) to authenticated;
