-- =====================================================================
-- 每日特別訪客、成就、房間評分（2026-10-21 修正版：修正數字型別錯誤；整份重跑即可）
-- =====================================================================

-- ---------- 每日特別訪客：owl 貓頭鷹博士（3 題，每題 +10）、merchant 旅行商人（高價收購作物）、cat 幸運貓（每天抽一次）----------
create table if not exists public.visitor_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles on delete cascade,
  day date not null default public.taipei_today(),
  kind text not null,
  ref text,
  amount int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists visitor_log_user_day on public.visitor_log (user_id, day);
alter table public.visitor_log enable row level security;

create or replace function public.visitor_kind(d date)
returns text language sql immutable as $$
  select (array['owl', 'merchant', 'cat'])[(1 + (abs(hashtext('visitor' || d::text)::bigint) % 3))::int];
$$;
-- 旅行商人今天要的作物、數量、每個價格（市場原價的 2.2 倍）
create or replace function public.visitor_wants(d date, out crop text, out qty int, out each_price int)
language sql immutable as $$
  select c, (1 + (abs(hashtext('want' || d::text)::bigint) % 3))::int, round(public.market_base(c) * 2.2)::int
  from (select (array['wheat','carrot','tomato','pumpkin','sunflower','starfruit'])[(1 + (abs(hashtext('crop' || d::text)::bigint) % 6))::int] c) x;
$$;

create or replace function public.visitor_today()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('kind', public.visitor_kind(public.taipei_today()),
    'wants', (select json_build_object('crop', w.crop, 'qty', w.qty, 'each', w.each_price) from public.visitor_wants(public.taipei_today()) w),
    'done', coalesce((select json_agg(json_build_object('kind', kind, 'ref', ref, 'amount', amount)) from public.visitor_log
      where user_id = auth.uid() and day = public.taipei_today()), '[]'::json));
$$;

create or replace function public.visitor_owl(p_qid text, p_choice int)
returns json language plpgsql security definer set search_path = public as $$
declare n int; ok boolean;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if public.visitor_kind(public.taipei_today()) <> 'owl' then raise exception '貓頭鷹博士今天不在'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select count(*) into n from public.visitor_log where user_id = auth.uid() and day = public.taipei_today() and kind = 'owl';
  if n >= 3 then raise exception '今天的 3 題已經答完了'; end if;
  ok := exists (select 1 from public.question_keys where qid = p_qid and a = p_choice);
  insert into public.visitor_log (user_id, kind, ref, amount) values (auth.uid(), 'owl', p_qid, case when ok then 10 else 0 end);
  if ok then insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), 10, 'visitor', 'owl'); end if;
  return json_build_object('correct', ok, 'left', 2 - n, 'wallet', public.wallet_balance(auth.uid()));
end $$;

create or replace function public.visitor_trade()
returns json language plpgsql security definer set search_path = public as $$
declare w record; amt int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if public.visitor_kind(public.taipei_today()) <> 'merchant' then raise exception '旅行商人今天不在'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if exists (select 1 from public.visitor_log where user_id = auth.uid() and day = public.taipei_today() and kind = 'merchant') then
    raise exception '今天已經賣給商人了'; end if;
  select * into w from public.visitor_wants(public.taipei_today());
  perform public.use_items(auth.uid(), jsonb_build_object(w.crop, w.qty));
  amt := w.qty * w.each_price;
  insert into public.visitor_log (user_id, kind, ref, amount) values (auth.uid(), 'merchant', w.crop, amt);
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'visitor', 'merchant');
  return json_build_object('amount', amt, 'wallet', public.wallet_balance(auth.uid()));
end $$;

create or replace function public.visitor_cat()
returns json language plpgsql security definer set search_path = public as $$
declare r float; amt int := 0; tk int := 0;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if public.visitor_kind(public.taipei_today()) <> 'cat' then raise exception '幸運貓今天不在'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if exists (select 1 from public.visitor_log where user_id = auth.uid() and day = public.taipei_today() and kind = 'cat') then
    raise exception '今天已經抽過了，明天再來'; end if;
  r := random();
  if r < 0.15 then
    tk := 1;
    insert into public.gacha_state (user_id, tickets) values (auth.uid(), 1)
      on conflict (user_id) do update set tickets = public.gacha_state.tickets + 1;
  else
    amt := case when r < 0.25 then 100 when r < 0.5 then 50 when r < 0.75 then 30 else 10 end;
    insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'visitor', 'cat');
  end if;
  insert into public.visitor_log (user_id, kind, ref, amount) values (auth.uid(), 'cat', case when tk > 0 then 'ticket' else 'coins' end, amt);
  return json_build_object('coins', amt, 'ticket', tk, 'wallet', public.wallet_balance(auth.uid()),
    'tickets', (select tickets from public.gacha_state where user_id = auth.uid()));
end $$;

-- ---------- 成就：15 種、每種 3 級（20／60／150 金幣）----------
create table if not exists public.achievement_claims (
  user_id uuid not null references public.profiles on delete cascade,
  metric text not null,
  tier int not null,
  created_at timestamptz not null default now(),
  primary key (user_id, metric, tier)
);
alter table public.achievement_claims enable row level security;
drop policy if exists "看自己的成就" on public.achievement_claims;
create policy "看自己的成就" on public.achievement_claims for select to authenticated using (user_id = auth.uid());

create or replace function public.achievement_metrics(u uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'answers', (select count(*) from public.answers where user_id = u),
    'correct', (select count(*) from public.answers where user_id = u and correct),
    'focus_hours', (select (coalesce(sum(minutes), 0) / 60)::int from public.focus_sessions where user_id = u),
    'streak', public.best_streak(u),
    'cards', (select count(*) from public.cards where user_id = u),
    'buys', (select count(*) from public.purchases where user_id = u and price > 0),
    'harvests', (select count(*) from public.coin_tx where user_id = u and kind in ('harvest', 'market')),
    'fish', (select count(*) from public.fish_log where user_id = u),
    'fish_kinds', (select count(distinct species) from public.fish_log where user_id = u),
    'friends', (select count(*) from public.friendships where status = 'accepted' and (requester = u or addressee = u)),
    'gifts', (select count(*) from public.gifts where sender = u),
    'waters', (select count(*) from public.garden_helps where helper = u and owner <> u),
    'dishes', (select count(*) from public.cook_log where user_id = u),
    'games', (select count(*) from public.coin_tx where user_id = u and kind like 'game:%'),
    'login', (select coalesce(max(streak), 0) from public.login_claims where user_id = u));
$$;
create or replace function public.achievement_tiers(p text)
returns int[] language sql immutable as $$
  select case p
    when 'answers' then array[10,50,200] when 'correct' then array[10,50,200] when 'focus_hours' then array[5,30,100]
    when 'streak' then array[3,7,30] when 'cards' then array[20,100,300] when 'buys' then array[5,20,50]
    when 'harvests' then array[5,30,100] when 'fish' then array[10,50,200] when 'fish_kinds' then array[5,10,14]
    when 'friends' then array[1,5,10] when 'gifts' then array[1,10,30] when 'waters' then array[5,30,100]
    when 'dishes' then array[3,20,60] when 'games' then array[10,50,200] when 'login' then array[7,30,100] end;
$$;
create or replace function public.my_achievements()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('metrics', public.achievement_metrics(auth.uid()),
    'claimed', coalesce((select json_agg(metric || ':' || tier) from public.achievement_claims where user_id = auth.uid()), '[]'::json));
$$;
create or replace function public.claim_achievement(p_metric text, p_tier int)
returns json language plpgsql security definer set search_path = public as $$
declare t int[] := public.achievement_tiers(p_metric); v int; amt int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if t is null or p_tier not between 1 and 3 then raise exception '沒有這個成就'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if exists (select 1 from public.achievement_claims where user_id = auth.uid() and metric = p_metric and tier = p_tier) then raise exception '已經領過了'; end if;
  v := (public.achievement_metrics(auth.uid()) ->> p_metric)::int;
  if v < t[p_tier] then raise exception '還沒達成'; end if;
  amt := (array[20, 60, 150])[p_tier];
  insert into public.achievement_claims (user_id, metric, tier) values (auth.uid(), p_metric, p_tier);
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'achievement', p_metric || ':' || p_tier);
  return json_build_object('coins', amt, 'wallet', public.wallet_balance(auth.uid()));
end $$;

-- ---------- 房間評分：依家具稀有度和成套主題算分，每週領一次 ----------
create table if not exists public.room_claims (
  user_id uuid not null references public.profiles on delete cascade,
  week date not null,
  stars int not null,
  primary key (user_id, week)
);
alter table public.room_claims enable row level security;

create or replace function public.room_score(u uuid)
returns int language sql stable security definer set search_path = public as $$
  with items as (
    select s.* from public.looks l, jsonb_each_text(l.room) kv
    join public.shop_items s on s.id = kv.value
    where l.user_id = u and kv.key in ('wall','floor','window','poster','bed','desk','chair','lamp','plant','rug','pet')),
  pts as (
    select sum(case
      when gacha = 'SSR' then 300 when gacha = 'SR' then 150 when gacha = 'R' then 80 when gacha = 'N' then 40
      when bundle is not null or unlock_cards is not null then 120
      when price > 0 then least(300, price / 2) else 0 end) as p,
      count(*) filter (where price > 0 or gacha is not null or bundle is not null or unlock_cards is not null) as filled,
      count(*) filter (where avail_from = '10-01') as halloween,
      count(*) filter (where avail_from = '12-01') as xmas
    from items)
  select (coalesce(p, 0) + case when filled >= 11 then 200 else 0 end
    + case when halloween >= 3 then 200 else 0 end + case when xmas >= 3 then 200 else 0 end)::int from pts;
$$;
create or replace function public.room_stars(score int)
returns int language sql immutable as $$
  select case when score >= 1500 then 5 when score >= 1000 then 4 when score >= 600 then 3 when score >= 300 then 2 when score >= 100 then 1 else 0 end;
$$;
create or replace function public.room_rating(p_user uuid default null)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('score', public.room_score(coalesce(p_user, auth.uid())), 'stars', public.room_stars(public.room_score(coalesce(p_user, auth.uid()))),
    'claimed', exists (select 1 from public.room_claims where user_id = auth.uid() and week = date_trunc('week', public.taipei_today())::date));
$$;
create or replace function public.claim_room_rating()
returns json language plpgsql security definer set search_path = public as $$
declare st int := public.room_stars(public.room_score(auth.uid())); w date := date_trunc('week', public.taipei_today())::date; amt int; tk int := 0;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if st < 1 then raise exception '房間還要再布置一下，至少要 1 顆星（100 分）'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if exists (select 1 from public.room_claims where user_id = auth.uid() and week = w) then raise exception '這週已經領過了，下週一再來'; end if;
  amt := (array[20, 50, 100, 200, 300])[st];
  insert into public.room_claims (user_id, week, stars) values (auth.uid(), w, st);
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'room_rating', st::text);
  if st = 5 then
    tk := 1;
    insert into public.gacha_state (user_id, tickets) values (auth.uid(), 1)
      on conflict (user_id) do update set tickets = public.gacha_state.tickets + 1;
  end if;
  return json_build_object('stars', st, 'coins', amt, 'ticket', tk, 'wallet', public.wallet_balance(auth.uid()));
end $$;

do $$ declare f text; begin
  foreach f in array array['visitor_today()','visitor_owl(text,integer)','visitor_trade()','visitor_cat()','my_achievements()',
    'claim_achievement(text,integer)','room_rating(uuid)','claim_room_rating()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public.achievement_metrics(uuid) from public, anon, authenticated;
revoke all on function public.room_score(uuid) from public, anon, authenticated;
