-- =====================================================================
-- 太平格蘭 英語遊戲樂園：全班分數排行榜（2026-10-21；整份重跑即可）
-- 遊戲網頁 docs/gram 不需要登入，用公開 key 呼叫下面兩個函式：
--   gram_submit  玩完一局送出分數（有名字才送）
--   gram_board   看某一組、某個遊戲、某個難度的排行（本週或全部）
-- 資料表本身沒有開放任何讀寫政策，只能透過這兩個函式存取。
--
-- 老師管理用（需要時在 SQL Editor 執行）：
--   刪掉某個名字的紀錄：delete from public.gram_scores where name = '要刪的名字';
--   清空全部紀錄：      truncate public.gram_scores;
-- =====================================================================

create table if not exists public.gram_scores (
  id bigint generated always as identity primary key,
  grp text not null check (grp in ('A', 'B', 'C', 'D')),
  game text not null check (game in ('run', 'race', 'fish', 'balloon', 'mole')),
  diff text not null check (diff in ('easy', 'normal', 'hard')),
  name text not null check (char_length(name) between 1 and 12),
  score int not null check (score between 0 and 30000),
  correct int not null check (correct between 0 and 200),
  answered int not null check (answered between 0 and 200),
  level int not null default 1 check (level between 1 and 5),
  device text not null check (char_length(device) between 8 and 40),
  created_at timestamptz not null default now()
);
create index if not exists gram_scores_board on public.gram_scores (grp, game, diff, created_at desc);
create index if not exists gram_scores_device on public.gram_scores (device, created_at desc);
alter table public.gram_scores enable row level security;
revoke all on public.gram_scores from anon, authenticated;

-- 送出分數：檢查名字、分數合理性，同一台裝置 15 秒內只收一筆
create or replace function public.gram_submit(
  p_grp text, p_game text, p_diff text, p_name text,
  p_score int, p_correct int, p_answered int, p_level int, p_device text)
returns json language plpgsql security definer set search_path = public as $$
declare nm text := left(btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')), 12);
begin
  if char_length(nm) < 1 then raise exception '請先寫名字'; end if;
  if p_answered < 1 then raise exception '這局沒有作答'; end if;
  if p_correct > p_answered or p_score > p_answered * 400 + 10000 then raise exception '分數不合理'; end if;
  if exists (select 1 from public.gram_scores
             where device = p_device and created_at > now() - interval '15 seconds') then
    raise exception '送太快了，等一下再試';
  end if;
  insert into public.gram_scores (grp, game, diff, name, score, correct, answered, level, device)
  values (p_grp, p_game, p_diff, nm, greatest(p_score, 0), greatest(p_correct, 0), p_answered, least(greatest(p_level, 1), 5), p_device);
  return json_build_object('ok', true);
end $$;

-- 排行：同一台裝置的同一個名字只算最高分；p_diff 可以是 'all'；p_period 是 'week'（台北時間週一起算）或 'all'
create or replace function public.gram_board(
  p_grp text, p_game text, p_diff text default 'all', p_period text default 'week', p_device text default '')
returns table (rank int, name text, score int, correct int, answered int, level int, diff text, is_me boolean, played_at timestamptz)
language sql stable security definer set search_path = public as $$
  with base as (
    select * from public.gram_scores
    where grp = p_grp and game = p_game
      and (p_diff = 'all' or diff = p_diff)
      and (p_period = 'all' or created_at >= (date_trunc('week', now() at time zone 'Asia/Taipei') at time zone 'Asia/Taipei'))
  ), best as (
    select distinct on (device, name) * from base order by device, name, score desc, created_at
  ), r as (
    select best.*, rank() over (order by score desc, created_at)::int as rk from best
  )
  select r.rk, r.name, r.score, r.correct, r.answered, r.level, r.diff, r.device = p_device, r.created_at
  from r where r.rk <= 20 or r.device = p_device
  order by r.rk, r.created_at
  limit 25;
$$;

revoke all on function public.gram_submit(text, text, text, text, int, int, int, int, text) from public;
revoke all on function public.gram_board(text, text, text, text, text) from public;
grant execute on function public.gram_submit(text, text, text, text, int, int, int, int, text) to anon, authenticated;
grant execute on function public.gram_board(text, text, text, text, text) to anon, authenticated;
