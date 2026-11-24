-- =====================================================================
-- 知識競技場（2026-11-24 更新；整份貼到 Supabase SQL Editor 執行，重跑沒關係）
-- 1 對 1 搶答：每場 5 題、每題 12 秒，答越快分數越高（答對 10～20 分），最後一題分數 ×2。
-- 只跟同等級（國小／國中／高中・大學）配對；等 10 秒沒人，改跟「影子對手」打：
--   重播其他玩家以前真實的作答紀錄（選了什麼、花幾毫秒）；還沒有紀錄時用練習機器人。
-- 出題、計時、對答案、算分、段位分、金幣全部在資料庫做，網頁只顯示結果。
-- 金幣：贏 20、平手 10、輸 5；每天前 5 場有獎勵；這場至少要答 3 題才有。
-- 需要先有的表：profiles、looks、question_keys、coin_tx、blocks（之前的 SQL 都建好了）。
-- =====================================================================

create table if not exists public.arena_matches (
  id bigint generated always as identity primary key,
  tier text not null,
  p1 uuid not null references public.profiles on delete cascade,
  p2 uuid references public.profiles on delete set null,
  kind text not null default 'live' check (kind in ('live', 'ghost', 'bot')),
  ghost_uid uuid references public.profiles on delete set null,
  opp_name text,
  opp_outfit jsonb,
  opp_rating int,
  ghost_plan jsonb,
  qids text[] not null,
  status text not null default 'waiting' check (status in ('waiting', 'playing', 'done', 'cancelled')),
  cur int not null default 0,
  cur_at timestamptz,
  seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  s1 int not null default 0,
  s2 int not null default 0,
  winner int,
  done_at timestamptz
);
create index if not exists arena_matches_wait on public.arena_matches (tier, status, seen_at);
create index if not exists arena_matches_p1 on public.arena_matches (p1, status);
create index if not exists arena_matches_p2 on public.arena_matches (p2, status);
alter table public.arena_matches enable row level security;

create table if not exists public.arena_answers (
  match_id bigint not null references public.arena_matches on delete cascade,
  player smallint not null check (player in (1, 2)),
  idx smallint not null check (idx between 0 and 4),
  choice int not null,
  ms int not null,
  correct boolean not null,
  pts int not null,
  at timestamptz not null default now(),
  primary key (match_id, player, idx)
);
alter table public.arena_answers enable row level security;

create table if not exists public.arena_ratings (
  user_id uuid primary key references public.profiles on delete cascade,
  rating int not null default 1000,
  best int not null default 1000,
  wins int not null default 0,
  losses int not null default 0,
  draws int not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.arena_ratings enable row level security;

create table if not exists public.arena_results (
  match_id bigint not null references public.arena_matches on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  player smallint not null,
  tier text not null,
  kind text not null,
  score int not null,
  opp_score int not null,
  result int not null,
  answered int not null,
  delta int not null,
  coins int not null default 0,
  day date not null default public.taipei_today(),
  week date not null default date_trunc('week', public.taipei_today())::date,
  created_at timestamptz not null default now(),
  primary key (match_id, user_id)
);
create index if not exists arena_results_week on public.arena_results (tier, week);
create index if not exists arena_results_user_day on public.arena_results (user_id, day);
create index if not exists arena_results_ghost on public.arena_results (tier, created_at);
alter table public.arena_results enable row level security;
-- 這四張表都不開放直接讀寫，只能透過下面的函式。

-- 抽 5 題：只出單字、文法題（克漏字和考古題的長題目 12 秒讀不完）
create or replace function public.arena_pick(t text)
returns text[] language sql volatile security definer set search_path = public as $$
  select array_agg(qid) from (select qid from public.question_keys
    where tier = t and split_part(qid, ':', 2) in ('v', 'g') and unit !~ '(EXAM|PAST|CAP|TP6)'
    order by random() limit 5) x;
$$;

-- 答對 10～20 分（越快越多），最後一題 ×2
create or replace function public.arena_pts(ok boolean, ms int, i int)
returns int language sql immutable as $$
  select case when not ok then 0
    else (10 + round(10.0 * greatest(0, 12000 - ms) / 12000))::int * case when i = 4 then 2 else 1 end end;
$$;

-- 結算一位玩家：段位分、戰績、金幣
create or replace function public.arena_settle(p_match bigint, p_player int, p_uid uuid, p_tier text, p_kind text,
  p_score int, p_opp int, p_answered int, p_delta int)
returns void language plpgsql security definer set search_path = public as $$
declare res int; c int := 0;
begin
  res := case when p_score > p_opp then 1 when p_score < p_opp then -1 else 0 end;
  update public.arena_ratings set rating = greatest(0, rating + p_delta), best = greatest(best, rating + p_delta),
    wins = wins + (res = 1)::int, losses = losses + (res = -1)::int, draws = draws + (res = 0)::int, updated_at = now()
    where user_id = p_uid;
  if p_answered >= 3 and (select count(*) from public.arena_results where user_id = p_uid and day = public.taipei_today() and coins > 0) < 5 then
    c := case res when 1 then 20 when 0 then 10 else 5 end;
  end if;
  insert into public.arena_results (match_id, user_id, player, tier, kind, score, opp_score, result, answered, delta, coins)
    values (p_match, p_uid, p_player, p_tier, p_kind, p_score, p_opp, res, p_answered, p_delta, c)
    on conflict do nothing;
  if found and c > 0 then
    insert into public.coin_tx (user_id, amount, kind, ref) values (p_uid, c, 'arena', p_match::text);
  end if;
end $$;

create or replace function public.arena_finish(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare m public.arena_matches; a1 int; a2 int; n1 int; n2 int; w int; r1 int; r2 int; e1 numeric; res1 numeric; k int; d1 int;
begin
  select * into m from public.arena_matches where id = p_id for update;
  if not found or m.status <> 'playing' then return; end if;
  select coalesce(sum(pts) filter (where player = 1), 0), coalesce(sum(pts) filter (where player = 2), 0),
         count(*) filter (where player = 1), count(*) filter (where player = 2)
    into a1, a2, n1, n2 from public.arena_answers where match_id = m.id;
  w := case when a1 > a2 then 1 when a2 > a1 then 2 else 0 end;
  update public.arena_matches set status = 'done', s1 = a1, s2 = a2, winner = w, done_at = now() where id = m.id;
  insert into public.arena_ratings (user_id) values (m.p1) on conflict do nothing;
  select rating into r1 from public.arena_ratings where user_id = m.p1 for update;
  if m.kind = 'live' and m.p2 is not null then
    insert into public.arena_ratings (user_id) values (m.p2) on conflict do nothing;
    select rating into r2 from public.arena_ratings where user_id = m.p2 for update;
    k := 32;
  else
    r2 := coalesce(m.opp_rating, 1000); k := 24;
  end if;
  res1 := case w when 1 then 1 when 0 then 0.5 else 0 end;
  e1 := 1 / (1 + power(10, (r2 - r1) / 400.0));
  d1 := round(k * (res1 - e1));
  perform public.arena_settle(m.id, 1, m.p1, m.tier, m.kind, a1, a2, n1, d1);
  if m.kind = 'live' and m.p2 is not null then
    perform public.arena_settle(m.id, 2, m.p2, m.tier, m.kind, a2, a1, n2, -d1);
  end if;
end $$;

-- 推進回合：兩人都答完、或 12 秒到了，就進下一題（中間停 3 秒看答案）；影子／機器人在這裡作答
create or replace function public.arena_tick(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare m public.arena_matches; dl timestamptz; t_end timestamptz; n int; g jsonb; gc int; gms int; k int;
begin
  select * into m from public.arena_matches where id = p_id for update;
  if not found or m.status <> 'playing' then return; end if;
  loop
    exit when m.cur >= 5 or now() < m.cur_at;
    dl := m.cur_at + interval '12 seconds';
    if m.kind <> 'live' and not exists (select 1 from public.arena_answers where match_id = m.id and player = 2 and idx = m.cur) then
      g := m.ghost_plan -> m.cur;
      if g is not null and jsonb_typeof(g) = 'array' then
        gc := (g ->> 0)::int; gms := (g ->> 1)::int;
        if gms <= 12000 and m.cur_at + gms * interval '1 millisecond' <= least(now(), dl) then
          select a into k from public.question_keys where qid = m.qids[m.cur + 1];
          insert into public.arena_answers (match_id, player, idx, choice, ms, correct, pts, at)
            values (m.id, 2, m.cur, gc, gms, coalesce(gc = k, false), public.arena_pts(coalesce(gc = k, false), gms, m.cur), m.cur_at + gms * interval '1 millisecond')
            on conflict do nothing;
        end if;
      end if;
    end if;
    select count(*), max(at) into n, t_end from public.arena_answers where match_id = m.id and idx = m.cur;
    if n >= 2 then
      null;
    elsif now() >= dl + interval '300 milliseconds' then
      t_end := dl;
    else
      exit;
    end if;
    m.cur := m.cur + 1;
    m.cur_at := t_end + interval '3 seconds';
    update public.arena_matches set cur = m.cur, cur_at = m.cur_at where id = m.id;
  end loop;
  if m.cur >= 5 then perform public.arena_finish(m.id); end if;
end $$;

-- 等待中的人加入另一場還在等、而且比較早開的對戰（避免兩個人同時開房間結果都沒配到）
create or replace function public.arena_join_waiting(p_uid uuid, p_tier text, p_before bigint)
returns bigint language plpgsql security definer set search_path = public as $$
declare mid bigint;
begin
  select id into mid from public.arena_matches m
    where m.tier = p_tier and m.status = 'waiting' and m.p1 <> p_uid and m.seen_at > now() - interval '4 seconds'
      and (p_before is null or m.id < p_before)
      and not exists (select 1 from public.blocks b where (b.user_id = p_uid and b.blocked_id = m.p1) or (b.user_id = m.p1 and b.blocked_id = p_uid))
    order by m.id limit 1 for update skip locked;
  if mid is null then return null; end if;
  update public.arena_matches set p2 = p_uid, status = 'playing', cur = 0, cur_at = now() + interval '4 seconds' where id = mid;
  return mid;
end $$;

-- 網頁每秒問一次：這場現在怎樣了
create or replace function public.arena_state(p_id bigint)
returns json language plpgsql security definer set search_path = public as $$
declare m public.arena_matches; me int; opp uuid; mid bigint; oname text; ofit jsonb; orat int; r public.arena_results; rt public.arena_ratings;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  perform public.arena_tick(p_id);
  select * into m from public.arena_matches where id = p_id;
  if not found or not (m.p1 = auth.uid() or coalesce(m.p2 = auth.uid(), false)) then raise exception '找不到這場對戰'; end if;
  if m.status = 'waiting' and m.p1 = auth.uid() then
    update public.arena_matches set seen_at = now() where id = m.id;
    mid := public.arena_join_waiting(auth.uid(), m.tier, m.id);
    if mid is not null then
      update public.arena_matches set status = 'cancelled' where id = m.id;
      select * into m from public.arena_matches where id = mid;
    end if;
  end if;
  me := case when m.p1 = auth.uid() then 1 else 2 end;
  if m.kind = 'live' then
    opp := case when me = 1 then m.p2 else m.p1 end;
    if opp is not null then
      select p.name, l.outfit, coalesce(ar.rating, 1000) into oname, ofit, orat
        from public.profiles p left join public.looks l on l.user_id = p.id left join public.arena_ratings ar on ar.user_id = p.id
        where p.id = opp;
    end if;
  else
    oname := m.opp_name; ofit := m.opp_outfit; orat := m.opp_rating;
  end if;
  select * into r from public.arena_results where match_id = m.id and user_id = auth.uid();
  select * into rt from public.arena_ratings where user_id = auth.uid();
  return json_build_object(
    'id', m.id, 'status', m.status, 'kind', m.kind, 'me', me, 'cur', m.cur, 'rating', coalesce(rt.rating, 1000),
    'cur_at', (extract(epoch from m.cur_at) * 1000)::bigint, 'now', (extract(epoch from clock_timestamp()) * 1000)::bigint,
    'qids', m.qids,
    'opp', json_build_object('name', oname, 'outfit', ofit, 'rating', orat),
    'mine', coalesce((select json_agg(json_build_object('i', idx, 'c', choice, 'ok', correct, 'pts', pts, 'ms', ms) order by idx)
      from public.arena_answers where match_id = m.id and player = me), '[]'),
    'theirs', coalesce((select json_agg(json_build_object('i', a.idx, 'c', a.choice, 'ok', a.correct, 'pts', a.pts, 'ms', a.ms) order by a.idx)
      from public.arena_answers a where a.match_id = m.id and a.player <> me and a.at <= now()
        and (m.status = 'done' or a.idx < m.cur or exists (select 1 from public.arena_answers b where b.match_id = m.id and b.player = me and b.idx = a.idx))), '[]'),
    'opp_done', exists (select 1 from public.arena_answers where match_id = m.id and player <> me and idx = m.cur and at <= now()),
    'keys', (select json_agg(case when m.status = 'done' or x.i - 1 < m.cur
        or exists (select 1 from public.arena_answers b where b.match_id = m.id and b.player = me and b.idx = x.i - 1)
        then q.a end order by x.i)
      from unnest(m.qids) with ordinality x(qid, i) left join public.question_keys q on q.qid = x.qid),
    'result', case when r.match_id is null then null else json_build_object('score', r.score, 'opp', r.opp_score, 'result', r.result,
      'delta', r.delta, 'coins', r.coins, 'rating', coalesce(rt.rating, 1000), 'wallet', public.wallet_balance(auth.uid())) end);
end $$;

-- 開始配對：有人在等就直接開打，沒有就開一場等別人
create or replace function public.arena_find()
returns json language plpgsql security definer set search_path = public as $$
declare t text; mid bigint; qs text[];
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select tier into t from public.profiles where id = auth.uid();
  if t is null then raise exception '請先建立角色'; end if;
  perform pg_advisory_xact_lock(hashtext('arena:' || auth.uid()::text));
  update public.arena_matches set status = 'cancelled' where p1 = auth.uid() and status = 'waiting';
  -- 上一場還沒打完（例如重新整理網頁）就回到那場
  select id into mid from public.arena_matches where (p1 = auth.uid() or p2 = auth.uid()) and status = 'playing'
    and created_at > now() - interval '5 minutes' order by id desc limit 1;
  if mid is not null then return public.arena_state(mid); end if;
  mid := public.arena_join_waiting(auth.uid(), t, null);
  if mid is not null then return public.arena_state(mid); end if;
  qs := public.arena_pick(t);
  if coalesce(cardinality(qs), 0) < 5 then raise exception '題庫還沒準備好，請稍後再試'; end if;
  insert into public.arena_matches (tier, p1, qids) values (t, auth.uid(), qs) returning id into mid;
  return public.arena_state(mid);
end $$;

-- 等了 10 秒沒人：改跟影子對手（別人以前的真實作答）打；沒有紀錄就用練習機器人
create or replace function public.arena_ghost(p_id bigint)
returns json language plpgsql security definer set search_path = public as $$
declare m public.arena_matches; src public.arena_results; plan jsonb; nm text; fit jsonb; rat int; ks int[]; i int; ok boolean;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select * into m from public.arena_matches where id = p_id and p1 = auth.uid() and status = 'waiting' for update;
  if not found then return public.arena_state(p_id); end if;
  select * into src from public.arena_results r
    where r.tier = m.tier and r.user_id <> auth.uid() and r.answered >= 3 and r.created_at > now() - interval '60 days'
      and not exists (select 1 from public.blocks b where (b.user_id = auth.uid() and b.blocked_id = r.user_id) or (b.user_id = r.user_id and b.blocked_id = auth.uid()))
    order by random() limit 1;
  if src.match_id is not null then
    select jsonb_agg(case when a.idx is null then null else jsonb_build_array(a.choice, a.ms) end order by g.i)
      into plan from generate_series(0, 4) g(i)
      left join public.arena_answers a on a.match_id = src.match_id and a.player = src.player and a.idx = g.i;
    select p.name, l.outfit, coalesce(ar.rating, 1000) into nm, fit, rat
      from public.profiles p left join public.looks l on l.user_id = p.id left join public.arena_ratings ar on ar.user_id = p.id
      where p.id = src.user_id;
    update public.arena_matches set kind = 'ghost', ghost_uid = src.user_id, opp_name = nm, opp_outfit = fit, opp_rating = rat,
      ghost_plan = plan, qids = (select qids from public.arena_matches where id = src.match_id),
      status = 'playing', cur = 0, cur_at = now() + interval '4 seconds'
      where id = m.id;
  else
    select array_agg(q.a order by x.i) into ks from unnest(m.qids) with ordinality x(qid, i) join public.question_keys q on q.qid = x.qid;
    plan := '[]'::jsonb;
    for i in 1..5 loop
      ok := random() < 0.6;
      plan := plan || jsonb_build_array(jsonb_build_array(
        case when ok then ks[i] else (ks[i] + 1 + floor(random() * 3)::int) % 4 end,
        2500 + floor(random() * 7000)::int));
    end loop;
    update public.arena_matches set kind = 'bot',
      opp_name = (array['練習機器人・小咕','練習機器人・阿鐵','練習機器人・波波','練習機器人・嗶嗶'])[1 + floor(random() * 4)::int],
      opp_rating = 1000, ghost_plan = plan, status = 'playing', cur = 0, cur_at = now() + interval '4 seconds'
      where id = m.id;
  end if;
  return public.arena_state(m.id);
end $$;

-- 作答：只能答目前這一題、每題一次、12 秒內
create or replace function public.arena_answer(p_id bigint, p_idx int, p_choice int)
returns json language plpgsql security definer set search_path = public as $$
declare m public.arena_matches; me int; ms int; ok boolean;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  perform public.arena_tick(p_id);
  select * into m from public.arena_matches where id = p_id for update;
  if not found then raise exception '找不到這場對戰'; end if;
  me := case when m.p1 = auth.uid() then 1 when m.p2 = auth.uid() and m.kind = 'live' then 2 end;
  if me is null then raise exception '找不到這場對戰'; end if;
  if m.status = 'playing' and p_idx = m.cur and now() >= m.cur_at and now() <= m.cur_at + interval '12300 milliseconds' then
    ms := least(12000, (extract(epoch from now() - m.cur_at) * 1000)::int);
    ok := exists (select 1 from public.question_keys where qid = m.qids[p_idx + 1] and a = p_choice);
    insert into public.arena_answers (match_id, player, idx, choice, ms, correct, pts)
      values (m.id, me, p_idx, p_choice, ms, ok, public.arena_pts(ok, ms, p_idx))
      on conflict do nothing;
  end if;
  return public.arena_state(p_id);
end $$;

-- 段位與本週排行（同等級）：本週贏最多場的排前面，同場數比總分
create or replace function public.arena_board()
returns json language plpgsql security definer set search_path = public as $$
declare t text; wk date := date_trunc('week', public.taipei_today())::date; rt public.arena_ratings;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select tier into t from public.profiles where id = auth.uid();
  select * into rt from public.arena_ratings where user_id = auth.uid();
  return json_build_object(
    'rating', coalesce(rt.rating, 1000), 'best', coalesce(rt.best, 1000),
    'wins', coalesce(rt.wins, 0), 'losses', coalesce(rt.losses, 0), 'draws', coalesce(rt.draws, 0),
    'today', (select count(*) from public.arena_results where user_id = auth.uid() and day = public.taipei_today() and coins > 0),
    'board', coalesce((select json_agg(x order by x.wins desc, x.pts desc) from (
        select p.id = auth.uid() as me, p.name, count(*) filter (where r.result = 1) as wins, count(*) as played, sum(r.score) as pts,
               coalesce(ar.rating, 1000) as rating
        from public.arena_results r join public.profiles p on p.id = r.user_id left join public.arena_ratings ar on ar.user_id = r.user_id
        where r.tier = t and r.week = wk
        group by p.id, p.name, ar.rating
        order by wins desc, pts desc limit 20) x), '[]'));
end $$;

do $$ declare f text; begin
  foreach f in array array['arena_find()', 'arena_state(bigint)', 'arena_ghost(bigint)', 'arena_answer(bigint,integer,integer)', 'arena_board()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array['arena_pick(text)', 'arena_settle(bigint,integer,uuid,text,text,integer,integer,integer,integer)',
    'arena_finish(bigint)', 'arena_tick(bigint)', 'arena_join_waiting(uuid,text,bigint)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- 檢查：下面這行應該列出 4 張表
select table_name from information_schema.tables where table_schema = 'public' and table_name like 'arena_%' order by 1;
