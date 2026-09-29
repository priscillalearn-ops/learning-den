-- Learning Den 陪你一起讀書啦：Supabase 資料庫
-- 用法：Supabase 後台 → SQL Editor → New query → 整份貼上 → Run。重跑也不會壞。
-- 原則：學生只能改自己的資料；留言大家看得到；答題紀錄只有自己看得到，統計數字用函式算。

-- 玩家資料（只存暱稱、等級、班級代碼，不存 email）
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  name text not null check (char_length(name) between 1 and 10),
  tier text not null check (tier in ('kid','teen','sage')),
  class_code text check (char_length(class_code) <= 8),
  created_at timestamptz not null default now()
);

-- 今日一題作答（每人每天每個等級一筆）
create table if not exists public.answers (
  user_id uuid not null references public.profiles on delete cascade,
  day date not null,
  tier text not null,
  qid text not null,
  choice int not null,
  correct boolean not null,
  created_at timestamptz not null default now(),
  primary key (user_id, day, tier)
);
create index if not exists answers_qid_day on public.answers (qid, day);

-- 留言（老師把 hidden 改成 true 就會從畫面消失）
create table if not exists public.comments (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles on delete cascade,
  day date not null,
  tier text not null,
  body text not null check (char_length(body) between 1 and 60),
  hidden boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists comments_day_tier on public.comments (day, tier, created_at);

-- 檢舉（只有老師在後台看得到）
create table if not exists public.reports (
  id bigint generated always as identity primary key,
  comment_id bigint not null references public.comments on delete cascade,
  reporter uuid not null default auth.uid() references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  unique (comment_id, reporter)
);

-- 封鎖名單
create table if not exists public.blocks (
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  blocked_id uuid not null references public.profiles on delete cascade,
  primary key (user_id, blocked_id)
);

-- 讀書房專注紀錄
create table if not exists public.focus_sessions (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  day date not null,
  minutes int not null check (minutes between 1 and 120),
  created_at timestamptz not null default now()
);

-- 單字卡收藏
create table if not exists public.cards (
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  word text not null,
  zh text not null default '',
  n int not null default 1,
  primary key (user_id, word)
);

-- ---------- 權限（Row Level Security） ----------
alter table public.profiles enable row level security;
alter table public.answers enable row level security;
alter table public.comments enable row level security;
alter table public.reports enable row level security;
alter table public.blocks enable row level security;
alter table public.focus_sessions enable row level security;
alter table public.cards enable row level security;

drop policy if exists "看得到大家的暱稱" on public.profiles;
create policy "看得到大家的暱稱" on public.profiles for select to authenticated using (true);
drop policy if exists "建立自己的資料" on public.profiles;
create policy "建立自己的資料" on public.profiles for insert to authenticated with check (id = auth.uid());
drop policy if exists "修改自己的資料" on public.profiles;
create policy "修改自己的資料" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "只看自己的作答" on public.answers;
create policy "只看自己的作答" on public.answers for select to authenticated using (user_id = auth.uid());
drop policy if exists "只寫自己的作答" on public.answers;
create policy "只寫自己的作答" on public.answers for insert to authenticated
  with check (user_id = auth.uid() and day between current_date - 1 and current_date + 1);

drop policy if exists "看得到沒被隱藏的留言" on public.comments;
create policy "看得到沒被隱藏的留言" on public.comments for select to authenticated using (not hidden or user_id = auth.uid());
drop policy if exists "用自己的名義留言" on public.comments;
create policy "用自己的名義留言" on public.comments for insert to authenticated
  with check (user_id = auth.uid() and not hidden
    and tier = (select p.tier from public.profiles p where p.id = auth.uid())
    -- 國小只能送貼圖
    and (tier <> 'kid' or body in ('讚','好難','我答對','加油','好好玩')));

drop policy if exists "送出檢舉" on public.reports;
create policy "送出檢舉" on public.reports for insert to authenticated with check (reporter = auth.uid());

drop policy if exists "管理自己的封鎖名單" on public.blocks;
create policy "管理自己的封鎖名單" on public.blocks for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "自己的專注紀錄" on public.focus_sessions;
create policy "自己的專注紀錄" on public.focus_sessions for select to authenticated using (user_id = auth.uid());
drop policy if exists "寫入自己的專注紀錄" on public.focus_sessions;
create policy "寫入自己的專注紀錄" on public.focus_sessions for insert to authenticated
  with check (user_id = auth.uid() and day between current_date - 1 and current_date + 1);

drop policy if exists "自己的單字卡" on public.cards;
create policy "自己的單字卡" on public.cards for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- 統計：今天這題幾個人答、答對幾個（不透露是誰） ----------
create or replace function public.daily_stats(p_qid text, p_day date)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('total', count(*), 'correct', count(*) filter (where correct))
  from public.answers where qid = p_qid and day = p_day;
$$;
revoke all on function public.daily_stats(text, date) from public, anon;
grant execute on function public.daily_stats(text, date) to authenticated;

-- =====================================================================
-- 好友與私訊：曾經連續打卡才解鎖（後面的更新改成 7 天）；國小不開放；只能加同等級的人
-- （打卡日 = 有作答或有完成專注的那天；只能記今天，不能補登過去）
-- =====================================================================

-- 這個人最長連續打卡幾天
create or replace function public.best_streak(p uuid)
returns int language sql stable security definer set search_path = public as $$
  with d as (
    select day from public.answers where user_id = p
    union select day from public.focus_sessions where user_id = p),
  g as (select day - (row_number() over (order by day))::int as grp from d)
  select coalesce(max(n), 0)::int from (select count(*) as n from g group by grp) x;
$$;

-- 能不能用好友與私訊
create or replace function public.dm_ok(p uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = p and tier <> 'kid')
     and public.best_streak(p) >= 15;
$$;

create table if not exists public.friendships (
  requester uuid not null default auth.uid() references public.profiles on delete cascade,
  addressee uuid not null references public.profiles on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  primary key (requester, addressee),
  check (requester <> addressee)
);

create or replace function public.are_friends(x uuid, y uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.friendships where status = 'accepted'
    and ((requester = x and addressee = y) or (requester = y and addressee = x)));
$$;

create or replace function public.is_blocked_between(x uuid, y uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.blocks
    where (user_id = x and blocked_id = y) or (user_id = y and blocked_id = x));
$$;

alter table public.friendships enable row level security;
drop policy if exists "看自己的好友關係" on public.friendships;
create policy "看自己的好友關係" on public.friendships for select to authenticated
  using (requester = auth.uid() or addressee = auth.uid());
drop policy if exists "送出好友邀請" on public.friendships;
create policy "送出好友邀請" on public.friendships for insert to authenticated
  with check (
    requester = auth.uid() and status = 'pending'
    and public.dm_ok(auth.uid()) and public.dm_ok(addressee)
    and (select tier from public.profiles where id = auth.uid()) = (select tier from public.profiles where id = addressee)
    and not public.is_blocked_between(auth.uid(), addressee)
    and not exists (select 1 from public.friendships f where f.requester = addressee and f.addressee = auth.uid()));
drop policy if exists "接受好友邀請" on public.friendships;
create policy "接受好友邀請" on public.friendships for update to authenticated
  using (addressee = auth.uid()) with check (addressee = auth.uid() and status = 'accepted');
drop policy if exists "取消或刪除好友" on public.friendships;
create policy "取消或刪除好友" on public.friendships for delete to authenticated
  using (requester = auth.uid() or addressee = auth.uid());

-- 私訊（管理員在後台看得到內容；畫面上會提醒學生）
create table if not exists public.messages (
  id bigint generated always as identity primary key,
  sender uuid not null default auth.uid() references public.profiles on delete cascade,
  recipient uuid not null references public.profiles on delete cascade,
  body text not null check (char_length(body) between 1 and 200),
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists messages_pair on public.messages (sender, recipient, created_at);
create index if not exists messages_unread on public.messages (recipient) where read_at is null;

alter table public.messages enable row level security;
drop policy if exists "看自己的私訊" on public.messages;
create policy "看自己的私訊" on public.messages for select to authenticated
  using (sender = auth.uid() or recipient = auth.uid());
drop policy if exists "只能傳給好友" on public.messages;
create policy "只能傳給好友" on public.messages for insert to authenticated
  with check (sender = auth.uid() and read_at is null
    and public.dm_ok(auth.uid()) and public.are_friends(auth.uid(), recipient)
    and not public.is_blocked_between(auth.uid(), recipient));

-- 標成已讀（只改 read_at，不讓人改訊息內容）
create or replace function public.mark_read(p_friend uuid)
returns void language sql security definer set search_path = public as $$
  update public.messages set read_at = now()
  where recipient = auth.uid() and sender = p_friend and read_at is null;
$$;
revoke all on function public.mark_read(uuid) from public, anon;
grant execute on function public.mark_read(uuid) to authenticated;

-- 用好友代碼（使用者編號前 6 碼）找人，只回傳暱稱和等級
create or replace function public.find_by_code(p_code text)
returns table (id uuid, name text, tier text)
language sql stable security definer set search_path = public as $$
  select id, name, tier from public.profiles
  where char_length(p_code) = 6 and upper(left(id::text, 6)) = upper(p_code) limit 1;
$$;
revoke all on function public.find_by_code(text) from public, anon;
grant execute on function public.find_by_code(text) to authenticated;

-- 私訊檢舉（老師在後台看得到被檢舉的訊息）
create table if not exists public.message_reports (
  id bigint generated always as identity primary key,
  message_id bigint not null references public.messages on delete cascade,
  reporter uuid not null default auth.uid() references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  unique (message_id, reporter)
);
alter table public.message_reports enable row level security;
drop policy if exists "檢舉收到的私訊" on public.message_reports;
create policy "檢舉收到的私訊" on public.message_reports for insert to authenticated
  with check (reporter = auth.uid()
    and exists (select 1 from public.messages m where m.id = message_id and m.recipient = auth.uid()));

revoke all on function public.best_streak(uuid) from public, anon;
grant execute on function public.best_streak(uuid) to authenticated;

-- 新私訊即時推播
do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null; end $$;

-- =====================================================================
-- 錯題本、班級排行（2026-09-28 新增；整份重跑即可）
-- =====================================================================
create table if not exists public.mistakes (
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  qid text not null,
  n int not null default 1,
  updated_at timestamptz not null default now(),
  primary key (user_id, qid)
);
alter table public.mistakes enable row level security;
drop policy if exists "自己的錯題本" on public.mistakes;
create policy "自己的錯題本" on public.mistakes for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 目前連續打卡天數（以台灣日期算，今天還沒打卡也算到昨天為止）
create or replace function public.current_streak(p uuid)
returns int language sql stable security definer set search_path = public as $$
  with d as (
    select day from public.answers where user_id = p
    union select day from public.focus_sessions where user_id = p),
  g as (select day, day - (row_number() over (order by day))::int as grp from d),
  runs as (select max(day) as last_day, count(*) as n from g group by grp)
  select coalesce((select n from runs
    where last_day >= (now() at time zone 'Asia/Taipei')::date - 1
    order by last_day desc limit 1), 0)::int;
$$;

-- 同班（同班級代碼）本週專注排行；沒填班級代碼就回傳空的
create or replace function public.class_board()
returns table (name text, tier text, week_minutes int, streak int, is_me boolean)
language sql stable security definer set search_path = public as $$
  select p.name, p.tier,
    coalesce((select sum(f.minutes) from public.focus_sessions f
      where f.user_id = p.id and f.day > (now() at time zone 'Asia/Taipei')::date - 7), 0)::int,
    public.current_streak(p.id),
    p.id = auth.uid()
  from public.profiles p
  where p.class_code is not null
    and p.class_code = (select class_code from public.profiles where id = auth.uid())
  order by 3 desc, 4 desc
  limit 30;
$$;
revoke all on function public.current_streak(uuid) from public, anon;
grant execute on function public.current_streak(uuid) to authenticated;
revoke all on function public.class_board() from public, anon;
grant execute on function public.class_board() to authenticated;

-- =====================================================================
-- 老師後台（2026-09-28 新增；整份重跑即可）
-- teachers：誰是老師（classes 留空 = 看得到所有班）
-- mutes：被老師禁言的學生
-- 兩張表都開 RLS 但不給任何學生權限，只能透過下面的 teacher_* 函式或後台 SQL 操作
-- 把自己設成老師（登入過網站一次之後，在 SQL Editor 執行）：
--   insert into public.teachers (user_id) select id from auth.users where email = '你的 Gmail';
-- =====================================================================
create table if not exists public.teachers (
  user_id uuid primary key references auth.users on delete cascade,
  classes text[]
);
alter table public.teachers enable row level security;

create table if not exists public.mutes (
  user_id uuid primary key references public.profiles on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.mutes enable row level security;

create or replace function public.is_teacher()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.teachers where user_id = auth.uid());
$$;

-- 老師看得到這個班嗎
create or replace function public.teacher_can_see(p_class text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.teachers t where t.user_id = auth.uid()
    and (t.classes is null or p_class = any (t.classes)));
$$;

create or replace function public.is_muted(p uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.mutes where user_id = p);
$$;

-- 被禁言就不能留言、傳私訊
drop policy if exists "用自己的名義留言" on public.comments;
create policy "用自己的名義留言" on public.comments for insert to authenticated
  with check (user_id = auth.uid() and not hidden and not public.is_muted(auth.uid())
    and tier = (select p.tier from public.profiles p where p.id = auth.uid())
    and (tier <> 'kid' or body in ('讚','好難','我答對','加油','好好玩')));
drop policy if exists "只能傳給好友" on public.messages;
create policy "只能傳給好友" on public.messages for insert to authenticated
  with check (sender = auth.uid() and read_at is null and not public.is_muted(auth.uid())
    and public.dm_ok(auth.uid()) and public.are_friends(auth.uid(), recipient)
    and not public.is_blocked_between(auth.uid(), recipient));

-- 老師看得到的班級與人數
create or replace function public.teacher_classes()
returns table (class_code text, students int)
language sql stable security definer set search_path = public as $$
  select coalesce(p.class_code, ''), count(*)::int from public.profiles p
  where public.teacher_can_see(p.class_code)
     or (p.class_code is null and exists (select 1 from public.teachers t where t.user_id = auth.uid() and t.classes is null))
  group by 1 order by 1;
$$;

-- 班級學生報表（p_class 傳 '' 代表沒填班級代碼的學生）
create or replace function public.teacher_class_report(p_class text)
returns table (user_id uuid, name text, email text, tier text, muted boolean,
  today_done boolean, streak int, best int, week_minutes int,
  week_answers int, week_correct int, mistakes int, last_day date)
language sql stable security definer set search_path = public as $$
  with t as (select (now() at time zone 'Asia/Taipei')::date as d),
  s as (select p.* from public.profiles p
    where coalesce(p.class_code, '') = p_class
      and (public.teacher_can_see(p.class_code)
        or (p.class_code is null and exists (select 1 from public.teachers x where x.user_id = auth.uid() and x.classes is null)))),
  act as (select user_id, day from public.answers union select user_id, day from public.focus_sessions)
  select s.id, s.name, u.email::text, s.tier, public.is_muted(s.id),
    exists (select 1 from act a, t where a.user_id = s.id and a.day = t.d),
    public.current_streak(s.id), public.best_streak(s.id),
    coalesce((select sum(f.minutes) from public.focus_sessions f, t where f.user_id = s.id and f.day > t.d - 7), 0)::int,
    (select count(*) from public.answers a, t where a.user_id = s.id and a.day > t.d - 7)::int,
    (select count(*) from public.answers a, t where a.user_id = s.id and a.day > t.d - 7 and a.correct)::int,
    (select count(*) from public.mistakes m where m.user_id = s.id)::int,
    (select max(day) from act a where a.user_id = s.id)
  from s left join auth.users u on u.id = s.id
  order by 6 desc, 7 desc, s.name;
$$;

-- 被檢舉的留言
create or replace function public.teacher_comment_reports()
returns table (comment_id bigint, body text, day date, hidden boolean,
  author_id uuid, author text, class_code text, reports int, last_report timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, c.body, c.day, c.hidden, c.user_id, p.name, p.class_code, count(r.id)::int, max(r.created_at)
  from public.reports r join public.comments c on c.id = r.comment_id join public.profiles p on p.id = c.user_id
  where public.is_teacher() and (public.teacher_can_see(p.class_code)
    or exists (select 1 from public.teachers x where x.user_id = auth.uid() and x.classes is null))
  group by c.id, p.name, p.class_code order by max(r.created_at) desc limit 100;
$$;

-- 被檢舉的私訊
create or replace function public.teacher_message_reports()
returns table (message_id bigint, body text, created_at timestamptz,
  sender_id uuid, sender text, recipient text, class_code text, reports int)
language sql stable security definer set search_path = public as $$
  select m.id, m.body, m.created_at, m.sender, ps.name, pr.name, ps.class_code, count(r.id)::int
  from public.message_reports r join public.messages m on m.id = r.message_id
  join public.profiles ps on ps.id = m.sender join public.profiles pr on pr.id = m.recipient
  where public.is_teacher() and (public.teacher_can_see(ps.class_code)
    or exists (select 1 from public.teachers x where x.user_id = auth.uid() and x.classes is null))
  group by m.id, ps.name, pr.name, ps.class_code order by max(r.created_at) desc limit 100;
$$;

-- 班級最近 7 天的留言（含已隱藏）
create or replace function public.teacher_recent_comments(p_class text)
returns table (comment_id bigint, body text, day date, created_at timestamptz, hidden boolean, author_id uuid, author text)
language sql stable security definer set search_path = public as $$
  select c.id, c.body, c.day, c.created_at, c.hidden, c.user_id, p.name
  from public.comments c join public.profiles p on p.id = c.user_id
  where coalesce(p.class_code, '') = p_class
    and (public.teacher_can_see(p.class_code)
      or (p.class_code is null and exists (select 1 from public.teachers x where x.user_id = auth.uid() and x.classes is null)))
    and c.day > (now() at time zone 'Asia/Taipei')::date - 7
  order by c.created_at desc limit 100;
$$;

-- 老師的處理動作（每個都先確認是老師）
create or replace function public.teacher_hide_comment(p_id bigint, p_hidden boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_teacher() then raise exception '只有老師可以操作'; end if;
  update public.comments set hidden = p_hidden where id = p_id;
end $$;

create or replace function public.teacher_dismiss_comment(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_teacher() then raise exception '只有老師可以操作'; end if;
  delete from public.reports where comment_id = p_id;
end $$;

create or replace function public.teacher_delete_message(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_teacher() then raise exception '只有老師可以操作'; end if;
  delete from public.messages where id = p_id;
end $$;

create or replace function public.teacher_dismiss_message(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_teacher() then raise exception '只有老師可以操作'; end if;
  delete from public.message_reports where message_id = p_id;
end $$;

create or replace function public.teacher_set_muted(p_user uuid, p_muted boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_teacher() then raise exception '只有老師可以操作'; end if;
  if p_muted then insert into public.mutes (user_id) values (p_user) on conflict do nothing;
  else delete from public.mutes where user_id = p_user; end if;
end $$;

do $$ declare f text; begin
  foreach f in array array['is_teacher()','teacher_can_see(text)','is_muted(uuid)','teacher_classes()',
    'teacher_class_report(text)','teacher_comment_reports()','teacher_message_reports()',
    'teacher_recent_comments(text)','teacher_hide_comment(bigint,boolean)','teacher_dismiss_comment(bigint)',
    'teacher_delete_message(bigint)','teacher_dismiss_message(bigint)','teacher_set_muted(uuid,boolean)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- =====================================================================
-- 金幣、商店、房間與服裝（2026-09-28 新增；整份重跑即可）
-- 金幣不存在任何表裡：每次都從作答、專注、連續天數算出來，再扣掉買過的東西
-- =====================================================================
create table if not exists public.shop_items (
  id text primary key,
  slot text not null,
  price int not null check (price >= 0)
);
alter table public.shop_items enable row level security;
drop policy if exists "大家看得到商品" on public.shop_items;
create policy "大家看得到商品" on public.shop_items for select to authenticated using (true);

create table if not exists public.purchases (
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  item_id text not null references public.shop_items,
  price int not null,
  created_at timestamptz not null default now(),
  primary key (user_id, item_id)
);
alter table public.purchases enable row level security;
drop policy if exists "看自己買過的東西" on public.purchases;
create policy "看自己買過的東西" on public.purchases for select to authenticated using (user_id = auth.uid());

-- 房間佈置和服裝（大家都能來參觀，只能透過 save_look 修改）
create table if not exists public.looks (
  user_id uuid primary key references public.profiles on delete cascade,
  room jsonb not null default '{}',
  outfit jsonb not null default '{}',
  updated_at timestamptz not null default now()
);
alter table public.looks enable row level security;
drop policy if exists "可以參觀別人的房間" on public.looks;
create policy "可以參觀別人的房間" on public.looks for select to authenticated using (true);

-- 賺到的金幣（跟網頁 coinsEarned() 同一套算法）
create or replace function public.coins_earned(p uuid)
returns int language sql stable security definer set search_path = public as $$
  select (50
    + coalesce((select sum(10 + case when correct then 5 else 0 end) from public.answers where user_id = p), 0)
    + coalesce((select sum(least(m, 150)) from (
        select sum(minutes) as m from public.focus_sessions where user_id = p group by day) x), 0)
    + coalesce((select sum(c) from (values (3,20),(7,50),(15,100),(30,200),(60,400),(100,800)) v(d, c)
        where public.best_streak(p) >= d), 0)
  )::int;
$$;

create or replace function public.my_wallet()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('earned', e, 'spent', s, 'balance', e - s) from (
    select public.coins_earned(auth.uid()) as e,
      coalesce((select sum(price) from public.purchases where user_id = auth.uid()), 0)::int as s) x;
$$;

-- 買東西：價格以資料庫為準，金幣不夠就擋下
create or replace function public.buy_item(p_item text)
returns int language plpgsql security definer set search_path = public as $$
declare it public.shop_items; bal int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select * into it from public.shop_items where id = p_item;
  if not found then raise exception '沒有這個商品'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if it.price = 0 or exists (select 1 from public.purchases where user_id = auth.uid() and item_id = p_item) then
    return public.coins_earned(auth.uid()) - coalesce((select sum(price) from public.purchases where user_id = auth.uid()), 0);
  end if;
  bal := public.coins_earned(auth.uid()) - coalesce((select sum(price) from public.purchases where user_id = auth.uid()), 0);
  if bal < it.price then raise exception '金幣不夠'; end if;
  insert into public.purchases (user_id, item_id, price) values (auth.uid(), p_item, it.price);
  return bal - it.price;
end $$;

-- 存房間佈置：每一格都要是這個位置的商品，而且是免費或買過的
create or replace function public.save_look(p_room jsonb, p_outfit jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if exists (
    select 1 from (select key, value from jsonb_each_text(coalesce(p_room, '{}'))
                   union all select key, value from jsonb_each_text(coalesce(p_outfit, '{}'))) kv
    left join public.shop_items s on s.id = kv.value
    where s.id is null or s.slot <> kv.key
       or (s.price > 0 and not exists (select 1 from public.purchases pu where pu.user_id = auth.uid() and pu.item_id = s.id))
  ) then raise exception '有還沒買的東西'; end if;
  insert into public.looks (user_id, room, outfit, updated_at) values (auth.uid(), coalesce(p_room, '{}'), coalesce(p_outfit, '{}'), now())
  on conflict (user_id) do update set room = excluded.room, outfit = excluded.outfit, updated_at = now();
end $$;

do $$ declare f text; begin
  foreach f in array array['coins_earned(uuid)','my_wallet()','buy_item(text)','save_look(jsonb,jsonb)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;


-- =====================================================================
-- 送禮給好友（2026-09-28 新增；整份重跑即可）
-- 金幣一次 10–100、每天最多送出 200；禮物是商店裡要付費的東西，對方沒有才能送
-- =====================================================================
create table if not exists public.gifts (
  id bigint generated always as identity primary key,
  sender uuid not null default auth.uid() references public.profiles on delete cascade,
  recipient uuid not null references public.profiles on delete cascade,
  kind text not null check (kind in ('coins', 'item')),
  amount int,
  item_id text,
  note text check (char_length(note) <= 30),
  seen boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.gifts enable row level security;
drop policy if exists "看自己送的和收到的禮物" on public.gifts;
create policy "看自己送的和收到的禮物" on public.gifts for select to authenticated using (sender = auth.uid() or recipient = auth.uid());

create or replace function public.send_gift(p_to uuid, p_kind text, p_amount int, p_item text, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare it public.shop_items; sent int; note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if not public.are_friends(auth.uid(), p_to) then raise exception '只能送禮物給好友'; end if;
  if public.is_blocked_between(auth.uid(), p_to) then raise exception '沒辦法送給這位同學'; end if;
  if public.is_muted(auth.uid()) then note := null; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if p_kind = 'coins' then
    if p_amount is null or p_amount < 10 or p_amount > 100 then raise exception '一次可以送 10 到 100 金幣'; end if;
    select coalesce(-sum(amount), 0) into sent from public.coin_tx
      where user_id = auth.uid() and kind = 'gift_out' and day = public.taipei_today();
    if sent + p_amount > 200 then raise exception '今天送出的金幣已經到上限 200 了'; end if;
    if public.wallet_balance(auth.uid()) < p_amount then raise exception '金幣不夠'; end if;
    insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), -p_amount, 'gift_out', p_to::text), (p_to, p_amount, 'gift_in', auth.uid()::text);
  elsif p_kind = 'item' then
    select * into it from public.shop_items where id = p_item;
    if not found or it.price = 0 then raise exception '這個不能當禮物'; end if;
    if exists (select 1 from public.purchases where user_id = p_to and item_id = p_item) then raise exception '對方已經有這個了'; end if;
    if public.wallet_balance(auth.uid()) < it.price then raise exception '金幣不夠'; end if;
    insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), -it.price, 'gift_item', p_to::text);
    insert into public.purchases (user_id, item_id, price) values (p_to, p_item, 0);
  else raise exception '禮物種類不對'; end if;
  insert into public.gifts (sender, recipient, kind, amount, item_id, note)
    values (auth.uid(), p_to, p_kind, case when p_kind = 'coins' then p_amount end, case when p_kind = 'item' then p_item end, note);
  return json_build_object('wallet', public.wallet_balance(auth.uid()));
end $$;

create or replace function public.my_gifts()
returns table (id bigint, sender_name text, kind text, amount int, item_id text, note text, seen boolean, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select g.id, p.name, g.kind, g.amount, g.item_id, g.note, g.seen, g.created_at
  from public.gifts g join public.profiles p on p.id = g.sender
  where g.recipient = auth.uid() order by g.created_at desc limit 20;
$$;

create or replace function public.gifts_seen()
returns void language sql security definer set search_path = public as $$
  update public.gifts set seen = true where recipient = auth.uid() and not seen;
$$;

do $$ declare f text; begin
  foreach f in array array['send_gift(uuid,text,integer,text,text)','my_gifts()','gifts_seen()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;


-- =====================================================================
-- 魔法餐廳與新小遊戲（2026-09-28 新增；整份重跑即可）
-- 每天吃一次飯＝打卡；復活也算一餐
-- =====================================================================
create table if not exists public.meals (
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  day date not null default public.taipei_today(),
  food text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, day)
);
alter table public.meals enable row level security;
drop policy if exists "看自己的吃飯紀錄" on public.meals;
create policy "看自己的吃飯紀錄" on public.meals for select to authenticated using (user_id = auth.uid());

create or replace function public.eat(p_food text)
returns json language plpgsql security definer set search_path = public as $$
declare price int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  price := case p_food when 'bento' then 0 when 'noodles' then 20 when 'tea' then 15 when 'pizza' then 30
    when 'sushi' then 35 when 'cake' then 40 when 'revive_quiz' then 0 when 'revive_pay' then 100 end;
  if price is null then raise exception '菜單上沒有這個'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if exists (select 1 from public.meals where user_id = auth.uid() and day = public.taipei_today()) then raise exception '今天已經吃過了'; end if;
  if public.wallet_balance(auth.uid()) < price then raise exception '金幣不夠'; end if;
  if price > 0 then insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), -price, 'meal', p_food); end if;
  insert into public.meals (user_id, food) values (auth.uid(), p_food);
  return json_build_object('wallet', public.wallet_balance(auth.uid()));
end $$;

-- 小遊戲領獎（加上恐怖阿嬤、單字守城）
create or replace function public.claim_game(p_game text, p_score int)
returns json language plpgsql security definer set search_path = public as $$
declare got int; r int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_game not in ('match', 'speed', 'granny', 'tower') then raise exception '沒有這個遊戲'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select coalesce(sum(amount), 0) into got from public.coin_tx
    where user_id = auth.uid() and kind = 'game:' || p_game and day = public.taipei_today();
  r := greatest(0, least(coalesce(p_score, 0), 15, 30 - got));
  if r > 0 then insert into public.coin_tx (user_id, amount, kind) values (auth.uid(), r, 'game:' || p_game); end if;
  return json_build_object('reward', r, 'wallet', public.wallet_balance(auth.uid()));
end $$;

revoke all on function public.eat(text) from public, anon;
grant execute on function public.eat(text) to authenticated;
revoke all on function public.claim_game(text, integer) from public, anon;
grant execute on function public.claim_game(text, integer) to authenticated;


-- =====================================================================
-- 老師訊息、布告欄、任務區（2026-09-29 新增；整份重跑即可）
-- =====================================================================
alter table public.teachers add column if not exists title text not null default '宇宙超年輕大魔法師';

-- 老師看得到這位學生嗎（依學生的班級代碼）
create or replace function public.teacher_sees_student(p_student uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_teacher() and public.teacher_can_see((select class_code from public.profiles where id = p_student));
$$;

-- 私訊：好友之間照舊；老師可以傳給自己班的學生；學生可以回覆傳過訊息給他的老師
drop policy if exists "只能傳給好友" on public.messages;
create policy "只能傳給好友" on public.messages for insert to authenticated
  with check (sender = auth.uid() and read_at is null and (
    (not public.is_muted(auth.uid()) and public.dm_ok(auth.uid()) and public.are_friends(auth.uid(), recipient)
      and not public.is_blocked_between(auth.uid(), recipient))
    or public.teacher_sees_student(recipient)
    or (exists (select 1 from public.teachers t where t.user_id = recipient)
        and exists (select 1 from public.messages m where m.sender = recipient and m.recipient = auth.uid()))));

-- 老師的稱號
create or replace function public.teacher_me()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('title', title, 'classes', classes) from public.teachers where user_id = auth.uid();
$$;
create or replace function public.set_teacher_title(p_title text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_teacher() then raise exception '只有老師可以操作'; end if;
  if char_length(trim(coalesce(p_title, ''))) not between 1 and 16 then raise exception '稱號要 1 到 16 個字'; end if;
  update public.teachers set title = trim(p_title) where user_id = auth.uid();
end $$;

-- 學生的「老師信箱」：傳過訊息給我的老師
create or replace function public.my_teacher_contacts()
returns table (teacher_id uuid, title text)
language sql stable security definer set search_path = public as $$
  select distinct t.user_id, t.title from public.teachers t
  where exists (select 1 from public.messages m where m.sender = t.user_id and m.recipient = auth.uid());
$$;

-- 老師的「學生訊息」：跟哪些學生有對話
create or replace function public.teacher_threads()
returns table (student_id uuid, name text, class_code text, last_body text, last_at timestamptz, unread int)
language sql stable security definer set search_path = public as $$
  with m as (
    select case when sender = auth.uid() then recipient else sender end as other, body, created_at, sender, read_at
    from public.messages where sender = auth.uid() or recipient = auth.uid())
  select p.id, p.name, p.class_code,
    (select body from m m2 where m2.other = p.id order by created_at desc limit 1),
    (select max(created_at) from m m3 where m3.other = p.id),
    (select count(*) from m m4 where m4.other = p.id and m4.sender = p.id and m4.read_at is null)::int
  from public.profiles p
  where public.is_teacher() and p.id in (select other from m) and not exists (select 1 from public.teachers x where x.user_id = p.id)
  order by 5 desc limit 100;
$$;

-- 布告欄
create table if not exists public.announcements (
  id bigint generated always as identity primary key,
  teacher uuid not null default auth.uid() references auth.users on delete cascade,
  class_code text,
  title text not null check (char_length(title) between 1 and 30),
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
alter table public.announcements enable row level security;

create or replace function public.list_announcements()
returns table (id bigint, class_code text, title text, body text, created_at timestamptz, author text, mine boolean)
language sql stable security definer set search_path = public as $$
  select a.id, a.class_code, a.title, a.body, a.created_at, t.title, a.teacher = auth.uid()
  from public.announcements a join public.teachers t on t.user_id = a.teacher
  where a.teacher = auth.uid()
     or a.class_code is null
     or a.class_code = (select class_code from public.profiles where id = auth.uid())
  order by a.created_at desc limit 30;
$$;
create or replace function public.post_announcement(p_class text, p_title text, p_body text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_teacher() then raise exception '只有老師可以發公告'; end if;
  if p_class is not null and not public.teacher_can_see(p_class) then raise exception '你沒有這個班的權限'; end if;
  if p_class is null and not exists (select 1 from public.teachers where user_id = auth.uid() and classes is null) then
    raise exception '只有能看全部班級的老師可以發給全部班級'; end if;
  insert into public.announcements (class_code, title, body) values (nullif(p_class, ''), trim(p_title), trim(p_body));
end $$;
create or replace function public.delete_announcement(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.announcements where id = p_id and teacher = auth.uid();
end $$;

-- 任務區：每日、每週（系統）和老師出的任務；進度由資料庫計算，達成才能領金幣
create table if not exists public.missions (
  id bigint generated always as identity primary key,
  teacher uuid not null default auth.uid() references auth.users on delete cascade,
  class_code text,
  title text not null check (char_length(title) between 1 and 30),
  kind text not null check (kind in ('answer_days', 'focus_minutes', 'meal_days', 'challenge_wins', 'checkin_days')),
  target int not null check (target between 1 and 10000),
  reward int not null check (reward between 1 and 100),
  start_day date not null default public.taipei_today(),
  end_day date not null,
  created_at timestamptz not null default now()
);
alter table public.missions enable row level security;
create table if not exists public.quest_claims (
  user_id uuid not null references public.profiles on delete cascade,
  quest text not null,
  period text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, quest, period)
);
alter table public.quest_claims enable row level security;
drop policy if exists "看自己領過的任務" on public.quest_claims;
create policy "看自己領過的任務" on public.quest_claims for select to authenticated using (user_id = auth.uid());

create or replace function public.quest_progress(p uuid, p_kind text, d1 date, d2 date)
returns int language sql stable security definer set search_path = public as $$
  select (case p_kind
    when 'answer_days' then (select count(distinct day) from public.answers where user_id = p and day between d1 and d2)
    when 'focus_minutes' then (select coalesce(sum(minutes), 0) from public.focus_sessions where user_id = p and day between d1 and d2)
    when 'meal_days' then (select count(*) from public.meals where user_id = p and day between d1 and d2)
    when 'challenge_wins' then (select count(*) from public.challenges where user_id = p and day between d1 and d2 and done and payout > stake)
    when 'games' then (select count(*) from public.coin_tx where user_id = p and kind like 'game:%' and day between d1 and d2)
    when 'checkin_days' then (select count(*) from (select day from public.answers where user_id = p and day between d1 and d2
                              union select day from public.focus_sessions where user_id = p and day between d1 and d2) x)
    else 0 end)::int;
$$;

create or replace function public.quest_board()
returns json language sql stable security definer set search_path = public as $$
  with me as (select auth.uid() as uid, (select class_code from public.profiles where id = auth.uid()) as cls,
                     (select tier from public.profiles where id = auth.uid()) as tier),
  d as (select public.taipei_today() as t, date_trunc('week', public.taipei_today())::date as w),
  q as (
    select v.key, v.grp, v.title, v.kind, v.target, v.reward,
      case when v.grp = 'daily' then d.t else d.w end as d1, d.t as d2,
      case when v.grp = 'daily' then d.t::text else 'W' || d.w::text end as period, null::text as author, null::date as end_day
    from d, (values
      ('d_meal', 'daily', '去餐廳吃飯', 'meal_days', 1, 5),
      ('d_answer', 'daily', '答今日一題', 'answer_days', 1, 5),
      ('d_focus', 'daily', '在讀書房專注 25 分鐘', 'focus_minutes', 25, 10),
      ('d_games', 'daily', '玩 2 場小遊戲', 'games', 2, 5),
      ('w_checkin', 'weekly', '本週打卡 5 天', 'checkin_days', 5, 30),
      ('w_focus', 'weekly', '本週專注 3 小時', 'focus_minutes', 180, 40),
      ('w_chal', 'weekly', '雙倍挑戰贏 1 次', 'challenge_wins', 1, 20)) v(key, grp, title, kind, target, reward)
    where not (v.key = 'w_chal' and (select tier from me) = 'kid')
    union all
    select 'm' || m.id, 'teacher', m.title, m.kind, m.target, m.reward, m.start_day, least(d.t, m.end_day), 'm', t.title, m.end_day
    from public.missions m join public.teachers t on t.user_id = m.teacher, d, me
    where d.t between m.start_day and m.end_day and (m.class_code is null or m.class_code = me.cls))
  select coalesce(json_agg(json_build_object('key', q.key, 'grp', q.grp, 'title', q.title, 'kind', q.kind, 'target', q.target,
      'reward', q.reward, 'author', q.author, 'end_day', q.end_day,
      'progress', public.quest_progress(me.uid, q.kind, q.d1, q.d2),
      'claimed', exists (select 1 from public.quest_claims c where c.user_id = me.uid and c.quest = q.key and c.period = q.period))), '[]'::json)
  from q, me;
$$;

create or replace function public.claim_quest(p_key text)
returns json language plpgsql security definer set search_path = public as $$
declare q json; per text;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select x into q from json_array_elements(public.quest_board()) x where x->>'key' = p_key;
  if q is null then raise exception '找不到這個任務'; end if;
  if (q->>'claimed')::boolean then raise exception '已經領過了'; end if;
  if (q->>'progress')::int < (q->>'target')::int then raise exception '任務還沒完成'; end if;
  per := case q->>'grp' when 'daily' then public.taipei_today()::text
                        when 'weekly' then 'W' || date_trunc('week', public.taipei_today())::date::text else 'm' end;
  insert into public.quest_claims (user_id, quest, period) values (auth.uid(), p_key, per);
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), (q->>'reward')::int, 'quest', p_key);
  return json_build_object('wallet', public.wallet_balance(auth.uid()));
end $$;

-- 老師出任務、刪任務、看自己出的任務
create or replace function public.post_mission(p_class text, p_title text, p_kind text, p_target int, p_reward int, p_days int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_teacher() then raise exception '只有老師可以出任務'; end if;
  if p_class is not null and not public.teacher_can_see(p_class) then raise exception '你沒有這個班的權限'; end if;
  if p_class is null and not exists (select 1 from public.teachers where user_id = auth.uid() and classes is null) then
    raise exception '只有能看全部班級的老師可以發給全部班級'; end if;
  if p_days not between 1 and 60 then raise exception '天數要在 1 到 60 天之間'; end if;
  insert into public.missions (class_code, title, kind, target, reward, end_day)
  values (nullif(p_class, ''), trim(p_title), p_kind, p_target, p_reward, public.taipei_today() + p_days - 1);
end $$;
create or replace function public.delete_mission(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.missions where id = p_id and teacher = auth.uid();
end $$;
create or replace function public.my_missions()
returns table (id bigint, class_code text, title text, kind text, target int, reward int, start_day date, end_day date, claims int)
language sql stable security definer set search_path = public as $$
  select m.id, m.class_code, m.title, m.kind, m.target, m.reward, m.start_day, m.end_day,
    (select count(*) from public.quest_claims c where c.quest = 'm' || m.id)::int
  from public.missions m where m.teacher = auth.uid() order by m.created_at desc limit 50;
$$;

do $$ declare f text; begin
  foreach f in array array['teacher_sees_student(uuid)','teacher_me()','set_teacher_title(text)','my_teacher_contacts()','teacher_threads()',
    'list_announcements()','post_announcement(text,text,text)','delete_announcement(bigint)','quest_progress(uuid,text,date,date)',
    'quest_board()','claim_quest(text)','post_mission(text,text,text,integer,integer,integer)','delete_mission(bigint)','my_missions()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public.quest_progress(uuid, text, date, date) from authenticated;

-- =====================================================================
-- 學生回覆老師、老師署名、隨機任務、好友 7 天解鎖（2026-09-29 第二次更新；整份重跑即可）
-- =====================================================================
-- 老師的真名（學生看到「稱號（名字）」）
alter table public.teachers add column if not exists name text;
update public.teachers set name = 'Priscilla 老師' where name is null;

create or replace function public.teacher_label(p uuid)
returns text language sql stable security definer set search_path = public as $$
  select title || coalesce('（' || nullif(trim(name), '') || '）', '') from public.teachers where user_id = p;
$$;

-- 學生只能回覆「傳過訊息給他的老師」（老師名單學生讀不到，所以用函式判斷）
create or replace function public.can_reply_teacher(p_teacher uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.teachers where user_id = p_teacher)
     and exists (select 1 from public.messages where sender = p_teacher and recipient = auth.uid());
$$;

drop policy if exists "只能傳給好友" on public.messages;
create policy "只能傳給好友" on public.messages for insert to authenticated
  with check (sender = auth.uid() and read_at is null and (
    (not public.is_muted(auth.uid()) and public.dm_ok(auth.uid()) and public.are_friends(auth.uid(), recipient)
      and not public.is_blocked_between(auth.uid(), recipient))
    or public.teacher_sees_student(recipient)
    or public.can_reply_teacher(recipient)));

create or replace function public.teacher_me()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('title', title, 'name', name, 'classes', classes) from public.teachers where user_id = auth.uid();
$$;
create or replace function public.set_teacher_name(p_name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_teacher() then raise exception '只有老師可以操作'; end if;
  if char_length(trim(coalesce(p_name, ''))) > 12 then raise exception '名字最多 12 個字'; end if;
  update public.teachers set name = nullif(trim(p_name), '') where user_id = auth.uid();
end $$;

create or replace function public.my_teacher_contacts()
returns table (teacher_id uuid, title text)
language sql stable security definer set search_path = public as $$
  select distinct t.user_id, public.teacher_label(t.user_id) from public.teachers t
  where exists (select 1 from public.messages m where m.sender = t.user_id and m.recipient = auth.uid());
$$;

create or replace function public.list_announcements()
returns table (id bigint, class_code text, title text, body text, created_at timestamptz, author text, mine boolean)
language sql stable security definer set search_path = public as $$
  select a.id, a.class_code, a.title, a.body, a.created_at, public.teacher_label(a.teacher), a.teacher = auth.uid()
  from public.announcements a
  where a.teacher = auth.uid()
     or a.class_code is null
     or a.class_code = (select class_code from public.profiles where id = auth.uid())
  order by a.created_at desc limit 30;
$$;

-- 好友與私訊改成曾經連續打卡 7 天解鎖
create or replace function public.dm_ok(p uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = p and tier <> 'kid')
     and public.best_streak(p) >= 7;
$$;

-- 任務進度（加上：答對、留言、存錢、小遊戲賺的金幣）
create or replace function public.quest_progress(p uuid, p_kind text, d1 date, d2 date)
returns int language sql stable security definer set search_path = public as $$
  select (case p_kind
    when 'answer_days' then (select count(distinct day) from public.answers where user_id = p and day between d1 and d2)
    when 'answer_correct' then (select count(*) from public.answers where user_id = p and correct and day between d1 and d2)
    when 'focus_minutes' then (select coalesce(sum(minutes), 0) from public.focus_sessions where user_id = p and day between d1 and d2)
    when 'meal_days' then (select count(*) from public.meals where user_id = p and day between d1 and d2)
    when 'challenge_wins' then (select count(*) from public.challenges where user_id = p and day between d1 and d2 and done and payout > stake)
    when 'games' then (select count(*) from public.coin_tx where user_id = p and kind like 'game:%' and day between d1 and d2)
    when 'game_coins' then (select coalesce(sum(amount), 0) from public.coin_tx where user_id = p and kind like 'game:%' and day between d1 and d2)
    when 'comments' then (select count(*) from public.comments where user_id = p and day between d1 and d2)
    when 'bank_deposits' then (select count(*) from public.bank_log where user_id = p and kind = 'deposit'
                               and (created_at at time zone 'Asia/Taipei')::date between d1 and d2)
    when 'checkin_days' then (select count(*) from (select day from public.answers where user_id = p and day between d1 and d2
                              union select day from public.focus_sessions where user_id = p and day between d1 and d2) x)
    else 0 end)::int;
$$;

-- 任務板：每日、每週各抽「簡單、普通、困難」一個（每個人每天／每週不一樣），加上老師任務
create or replace function public.quest_board()
returns json language sql stable security definer set search_path = public as $$
  with me as (select auth.uid() as uid, (select class_code from public.profiles where id = auth.uid()) as cls,
                     (select tier from public.profiles where id = auth.uid()) as tier),
  d as (select public.taipei_today() as t, date_trunc('week', public.taipei_today())::date as w),
  pool as (select * from (values
    ('d_meal','daily',1,'去餐廳吃飯','meal_days',1,5,true),
    ('d_answer','daily',1,'答今日一題','answer_days',1,5,true),
    ('d_comment','daily',1,'在今日一題留言或送貼圖','comments',1,5,true),
    ('d_game1','daily',1,'玩 1 場小遊戲','games',1,5,true),
    ('d_bank','daily',1,'到銀行存一次錢','bank_deposits',1,5,true),
    ('d_correct','daily',2,'答對今日一題','answer_correct',1,10,true),
    ('d_focus25','daily',2,'在讀書房專注 25 分鐘','focus_minutes',25,10,true),
    ('d_game2','daily',2,'玩 2 場小遊戲','games',2,10,true),
    ('d_gcoin15','daily',2,'小遊戲賺到 15 金幣','game_coins',15,10,true),
    ('d_focus50','daily',3,'在讀書房專注 50 分鐘','focus_minutes',50,20,true),
    ('d_game4','daily',3,'玩 4 場小遊戲','games',4,20,true),
    ('d_gcoin30','daily',3,'小遊戲賺到 30 金幣','game_coins',30,20,true),
    ('d_chal','daily',3,'雙倍挑戰贏 1 次','challenge_wins',1,20,false),
    ('w_meal4','weekly',1,'本週吃飯 4 天','meal_days',4,20,true),
    ('w_check3','weekly',1,'本週打卡 3 天','checkin_days',3,20,true),
    ('w_answer3','weekly',1,'本週答今日一題 3 天','answer_days',3,20,true),
    ('w_check5','weekly',2,'本週打卡 5 天','checkin_days',5,40,true),
    ('w_focus120','weekly',2,'本週專注 2 小時','focus_minutes',120,40,true),
    ('w_correct4','weekly',2,'本週答對今日一題 4 次','answer_correct',4,40,true),
    ('w_game8','weekly',2,'本週玩 8 場小遊戲','games',8,40,true),
    ('w_check7','weekly',3,'本週每天都打卡（7 天）','checkin_days',7,80,true),
    ('w_focus300','weekly',3,'本週專注 5 小時','focus_minutes',300,80,true),
    ('w_correct7','weekly',3,'本週答對今日一題 7 次','answer_correct',7,80,true),
    ('w_chal3','weekly',3,'本週雙倍挑戰贏 3 次','challenge_wins',3,80,false)
  ) v(key, grp, lvl, title, kind, target, reward, kid_ok)),
  picked as (
    select p.*, case when p.grp = 'daily' then d.t else d.w end as d1, d.t as d2,
      case when p.grp = 'daily' then d.t::text else 'W' || d.w::text end as period,
      row_number() over (partition by p.grp, p.lvl order by md5(me.uid::text || (case when p.grp = 'daily' then d.t else d.w end)::text || p.key)) as rn
    from pool p, d, me where p.kid_ok or me.tier <> 'kid'),
  q as (
    select key, grp, lvl, title, kind, target, reward, d1, d2, period, null::text as author, null::date as end_day from picked where rn = 1
    union all
    select 'm' || m.id, 'teacher', 0, m.title, m.kind, m.target, m.reward, m.start_day, least(d.t, m.end_day), 'm',
      public.teacher_label(m.teacher), m.end_day
    from public.missions m, d, me
    where d.t between m.start_day and m.end_day and (m.class_code is null or m.class_code = me.cls))
  select coalesce(json_agg(json_build_object('key', q.key, 'grp', q.grp, 'lvl', q.lvl, 'title', q.title, 'kind', q.kind,
      'target', q.target, 'reward', q.reward, 'author', q.author, 'end_day', q.end_day,
      'progress', public.quest_progress(me.uid, q.kind, q.d1, q.d2),
      'claimed', exists (select 1 from public.quest_claims c where c.user_id = me.uid and c.quest = q.key and c.period = q.period))
      order by q.grp, q.lvl), '[]'::json)
  from q, me;
$$;

do $$ declare f text; begin
  foreach f in array array['teacher_label(uuid)','can_reply_teacher(uuid)','teacher_me()','set_teacher_name(text)',
    'my_teacher_contacts()','list_announcements()','dm_ok(uuid)','quest_board()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public.quest_progress(uuid, text, date, date) from public, anon, authenticated;


-- =====================================================================
-- 單字卡收集獎勵、稀有與限定商品（2026-09-29 第三次更新；整份重跑即可）
-- =====================================================================
alter table public.shop_items add column if not exists unlock_cards int;
alter table public.shop_items add column if not exists avail_from text;
alter table public.shop_items add column if not exists avail_until text;

-- 現在買得到嗎：不是單字卡獎勵、而且在限定期間內（月-日）
create or replace function public.item_on_sale(it public.shop_items)
returns boolean language sql stable as $$
  select it.unlock_cards is null and (it.avail_from is null
    or to_char(public.taipei_today(), 'MM-DD') between it.avail_from and it.avail_until);
$$;

create or replace function public.buy_item(p_item text)
returns int language plpgsql security definer set search_path = public as $$
declare it public.shop_items; bal int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select * into it from public.shop_items where id = p_item;
  if not found then raise exception '沒有這個商品'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  bal := public.wallet_balance(auth.uid());
  if it.price = 0 or exists (select 1 from public.purchases where user_id = auth.uid() and item_id = p_item) then return bal; end if;
  if it.unlock_cards is not null then raise exception '這個要收集單字卡才能解鎖'; end if;
  if not public.item_on_sale(it) then raise exception '這個限定商品現在沒有販售'; end if;
  if bal < it.price then raise exception '金幣不夠'; end if;
  insert into public.purchases (user_id, item_id, price) values (auth.uid(), p_item, it.price);
  return bal - it.price;
end $$;

create or replace function public.send_gift(p_to uuid, p_kind text, p_amount int, p_item text, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare it public.shop_items; sent int; note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if not public.are_friends(auth.uid(), p_to) then raise exception '只能送禮物給好友'; end if;
  if public.is_blocked_between(auth.uid(), p_to) then raise exception '沒辦法送給這位同學'; end if;
  if public.is_muted(auth.uid()) then note := null; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if p_kind = 'coins' then
    if p_amount is null or p_amount < 10 or p_amount > 100 then raise exception '一次可以送 10 到 100 金幣'; end if;
    select coalesce(-sum(amount), 0) into sent from public.coin_tx
      where user_id = auth.uid() and kind = 'gift_out' and day = public.taipei_today();
    if sent + p_amount > 200 then raise exception '今天送出的金幣已經到上限 200 了'; end if;
    if public.wallet_balance(auth.uid()) < p_amount then raise exception '金幣不夠'; end if;
    insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), -p_amount, 'gift_out', p_to::text), (p_to, p_amount, 'gift_in', auth.uid()::text);
  elsif p_kind = 'item' then
    select * into it from public.shop_items where id = p_item;
    if not found or it.price = 0 or not public.item_on_sale(it) then raise exception '這個不能當禮物'; end if;
    if exists (select 1 from public.purchases where user_id = p_to and item_id = p_item) then raise exception '對方已經有這個了'; end if;
    if public.wallet_balance(auth.uid()) < it.price then raise exception '金幣不夠'; end if;
    insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), -it.price, 'gift_item', p_to::text);
    insert into public.purchases (user_id, item_id, price) values (p_to, p_item, 0);
  else raise exception '禮物種類不對'; end if;
  insert into public.gifts (sender, recipient, kind, amount, item_id, note)
    values (auth.uid(), p_to, p_kind, case when p_kind = 'coins' then p_amount end, case when p_kind = 'item' then p_item end, note);
  return json_build_object('wallet', public.wallet_balance(auth.uid()));
end $$;

-- 單字卡收集到門檻就自動得到獎勵（用資料庫的單字卡張數判斷）
create or replace function public.claim_card_rewards()
returns json language plpgsql security definer set search_path = public as $$
declare n int; got text[];
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select count(*) into n from public.cards where user_id = auth.uid();
  with ins as (
    insert into public.purchases (user_id, item_id, price)
    select auth.uid(), s.id, 0 from public.shop_items s
    where s.unlock_cards is not null and s.unlock_cards <= n
      and not exists (select 1 from public.purchases p where p.user_id = auth.uid() and p.item_id = s.id)
    returning item_id)
  select coalesce(array_agg(item_id), '{}') into got from ins;
  return json_build_object('cards', n, 'granted', got);
end $$;

revoke all on function public.claim_card_rewards() from public, anon;
grant execute on function public.claim_card_rewards() to authenticated;

-- 商品價格（由 tools/shop-sql.js 從 index.html 的 SHOP 自動產生，不要手改）
-- SHOP_SEED_START
insert into public.shop_items (id, slot, price, unlock_cards, avail_from, avail_until) values
  ('wall_lilac', 'wall', 0, null, null, null),
  ('wall_mint', 'wall', 40, null, null, null),
  ('wall_peach', 'wall', 40, null, null, null),
  ('wall_sky', 'wall', 60, null, null, null),
  ('wall_night', 'wall', 120, null, null, null),
  ('floor_wood', 'floor', 0, null, null, null),
  ('floor_tile', 'floor', 40, null, null, null),
  ('floor_carpet', 'floor', 60, null, null, null),
  ('floor_grass', 'floor', 80, null, null, null),
  ('win_day', 'window', 0, null, null, null),
  ('win_night', 'window', 80, null, null, null),
  ('win_rain', 'window', 80, null, null, null),
  ('win_sakura', 'window', 150, null, null, null),
  ('poster_none', 'poster', 0, null, null, null),
  ('poster_star', 'poster', 50, null, null, null),
  ('poster_heart', 'poster', 50, null, null, null),
  ('poster_book', 'poster', 80, null, null, null),
  ('poster_moon', 'poster', 100, null, null, null),
  ('bed_blue', 'bed', 0, null, null, null),
  ('bed_pink', 'bed', 60, null, null, null),
  ('bed_star', 'bed', 150, null, null, null),
  ('desk_wood', 'desk', 0, null, null, null),
  ('desk_white', 'desk', 60, null, null, null),
  ('desk_pink', 'desk', 80, null, null, null),
  ('chair_wood', 'chair', 0, null, null, null),
  ('chair_pink', 'chair', 60, null, null, null),
  ('chair_gamer', 'chair', 150, null, null, null),
  ('lamp_none', 'lamp', 0, null, null, null),
  ('lamp_yellow', 'lamp', 50, null, null, null),
  ('lamp_mint', 'lamp', 70, null, null, null),
  ('plant_none', 'plant', 0, null, null, null),
  ('plant_green', 'plant', 40, null, null, null),
  ('plant_cactus', 'plant', 60, null, null, null),
  ('plant_flower', 'plant', 90, null, null, null),
  ('rug_none', 'rug', 0, null, null, null),
  ('rug_red', 'rug', 40, null, null, null),
  ('rug_blue', 'rug', 40, null, null, null),
  ('rug_rainbow', 'rug', 120, null, null, null),
  ('pet_none', 'pet', 0, null, null, null),
  ('pet_slime', 'pet', 250, null, null, null),
  ('pet_cat', 'pet', 300, null, null, null),
  ('pet_dog', 'pet', 300, null, null, null),
  ('pet_owl', 'pet', 400, null, null, null),
  ('pet_maltese', 'pet', 300, null, null, null),
  ('pet_bunny', 'pet', 250, null, null, null),
  ('pet_penguin', 'pet', 300, null, null, null),
  ('pet_dino', 'pet', 350, null, null, null),
  ('pet_dino_pink', 'pet', 350, null, null, null),
  ('pet_dino_rex', 'pet', 500, null, null, null),
  ('pet_unicorn', 'pet', 1000, null, null, null),
  ('pet_phoenix', 'pet', 1200, null, null, null),
  ('pet_dragon_gold', 'pet', 1500, null, null, null),
  ('hat_rainbow', 'hat', 800, null, null, null),
  ('wall_galaxy', 'wall', 600, null, null, null),
  ('bed_castle', 'bed', 900, null, null, null),
  ('hat_pumpkin', 'hat', 150, null, '10-01', '11-07'),
  ('pet_bat', 'pet', 350, null, '10-01', '11-07'),
  ('wall_halloween', 'wall', 200, null, '10-01', '11-07'),
  ('hat_santa', 'hat', 150, null, '12-01', '12-31'),
  ('pet_reindeer', 'pet', 400, null, '12-01', '12-31'),
  ('poster_xmas', 'poster', 120, null, '12-01', '12-31'),
  ('hat_grad', 'hat', 9999, 10, null, null),
  ('pet_bookfairy', 'pet', 9999, 30, null, null),
  ('wall_library', 'wall', 9999, 60, null, null),
  ('hat_wiz_gold', 'hat', 9999, 100, null, null),
  ('hat_none', 'hat', 0, null, null, null),
  ('hat_wiz_p', 'hat', 0, null, null, null),
  ('hat_helmet', 'hat', 0, null, null, null),
  ('hat_wiz_b', 'hat', 60, null, null, null),
  ('hat_cap_r', 'hat', 50, null, null, null),
  ('hat_cap_b', 'hat', 50, null, null, null),
  ('hat_bunny', 'hat', 150, null, null, null),
  ('hat_cat', 'hat', 150, null, null, null),
  ('hat_crown', 'hat', 400, null, null, null),
  ('top_blue', 'top', 0, null, null, null),
  ('top_red', 'top', 0, null, null, null),
  ('top_purple', 'top', 0, null, null, null),
  ('top_green', 'top', 30, null, null, null),
  ('top_yellow', 'top', 30, null, null, null),
  ('top_pink', 'top', 30, null, null, null),
  ('top_black', 'top', 60, null, null, null),
  ('top_white', 'top', 60, null, null, null),
  ('hair_brown', 'hair', 0, null, null, null),
  ('hair_black', 'hair', 0, null, null, null),
  ('hair_blond', 'hair', 0, null, null, null),
  ('hair_pink', 'hair', 0, null, null, null),
  ('hair_blue', 'hair', 0, null, null, null),
  ('skin_1', 'skin', 0, null, null, null),
  ('skin_2', 'skin', 0, null, null, null),
  ('skin_3', 'skin', 0, null, null, null),
  ('skin_4', 'skin', 0, null, null, null),
  ('acc_none', 'acc', 0, null, null, null),
  ('acc_beard', 'acc', 0, null, null, null),
  ('acc_glasses', 'acc', 80, null, null, null),
  ('acc_scarf', 'acc', 60, null, null, null),
  ('acc_phones', 'acc', 120, null, null, null),
  ('acc_cape', 'acc', 200, null, null, null),
  ('acc_headband', 'acc', 40, null, null, null),
  ('acc_bow', 'acc', 50, null, null, null),
  ('acc_bowtie', 'acc', 60, null, null, null),
  ('acc_star', 'acc', 70, null, null, null),
  ('acc_round', 'acc', 80, null, null, null),
  ('acc_pearl', 'acc', 90, null, null, null),
  ('acc_halo', 'acc', 250, null, null, null),
  ('acc_wings', 'acc', 300, null, null, null)
on conflict (id) do update set slot = excluded.slot, price = excluded.price, unlock_cards = excluded.unlock_cards, avail_from = excluded.avail_from, avail_until = excluded.avail_until;
-- SHOP_SEED_END

-- 內部判斷用的函式不開放給未登入的人（2026-09-28 補）
do $$ declare f text; begin
  foreach f in array array['dm_ok(uuid)','are_friends(uuid,uuid)','is_blocked_between(uuid,uuid)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- =====================================================================
-- 自選範圍的留言、遊戲區、雙倍挑戰、銀行（2026-09-28 新增；整份重跑即可）
-- 金幣流水帳 coin_tx 只能由下面的函式寫入；錢包 = 活動賺的 + 流水帳 − 購物
-- 雙倍挑戰要用到 question_keys（答案表），另外跑 supabase/question_keys.sql
-- =====================================================================
alter table public.comments add column if not exists qid text;
create index if not exists comments_qid_day on public.comments (qid, day);

create or replace function public.taipei_today()
returns date language sql stable as $$ select (now() at time zone 'Asia/Taipei')::date $$;

create table if not exists public.coin_tx (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles on delete cascade,
  amount int not null,
  kind text not null,
  ref text,
  day date not null default public.taipei_today(),
  created_at timestamptz not null default now()
);
create index if not exists coin_tx_user_day on public.coin_tx (user_id, day);
alter table public.coin_tx enable row level security;
drop policy if exists "看自己的金幣紀錄" on public.coin_tx;
create policy "看自己的金幣紀錄" on public.coin_tx for select to authenticated using (user_id = auth.uid());

create or replace function public.wallet_balance(p uuid)
returns int language sql stable security definer set search_path = public as $$
  select (public.coins_earned(p)
    + coalesce((select sum(amount) from public.coin_tx where user_id = p), 0)
    - coalesce((select sum(price) from public.purchases where user_id = p), 0))::int;
$$;

create or replace function public.my_wallet()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('balance', public.wallet_balance(auth.uid()),
    'tx', coalesce((select sum(amount) from public.coin_tx where user_id = auth.uid()), 0));
$$;

create or replace function public.buy_item(p_item text)
returns int language plpgsql security definer set search_path = public as $$
declare it public.shop_items; bal int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select * into it from public.shop_items where id = p_item;
  if not found then raise exception '沒有這個商品'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  bal := public.wallet_balance(auth.uid());
  if it.price = 0 or exists (select 1 from public.purchases where user_id = auth.uid() and item_id = p_item) then return bal; end if;
  if bal < it.price then raise exception '金幣不夠'; end if;
  insert into public.purchases (user_id, item_id, price) values (auth.uid(), p_item, it.price);
  return bal - it.price;
end $$;

-- 小遊戲領獎：每場最多 15，每種遊戲每天最多 30
create or replace function public.claim_game(p_game text, p_score int)
returns json language plpgsql security definer set search_path = public as $$
declare got int; r int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_game not in ('match', 'speed') then raise exception '沒有這個遊戲'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select coalesce(sum(amount), 0) into got from public.coin_tx
    where user_id = auth.uid() and kind = 'game:' || p_game and day = public.taipei_today();
  r := greatest(0, least(coalesce(p_score, 0), 15, 30 - got));
  if r > 0 then insert into public.coin_tx (user_id, amount, kind) values (auth.uid(), r, 'game:' || p_game); end if;
  return json_build_object('reward', r, 'wallet', public.wallet_balance(auth.uid()));
end $$;

-- 銀行：活存每天 2% 利息（每天最多 20），複利，最多補算 30 天
create table if not exists public.bank (
  user_id uuid primary key references public.profiles on delete cascade,
  balance int not null default 0 check (balance >= 0),
  settled date not null default public.taipei_today()
);
create table if not exists public.bank_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles on delete cascade,
  amount int not null,
  kind text not null check (kind in ('deposit', 'withdraw', 'interest')),
  created_at timestamptz not null default now()
);
alter table public.bank enable row level security;
alter table public.bank_log enable row level security;
drop policy if exists "看自己的存款" on public.bank;
create policy "看自己的存款" on public.bank for select to authenticated using (user_id = auth.uid());
drop policy if exists "看自己的存摺" on public.bank_log;
create policy "看自己的存摺" on public.bank_log for select to authenticated using (user_id = auth.uid());

create or replace function public.bank_settle(p uuid)
returns void language plpgsql security definer set search_path = public as $$
declare b public.bank; d int; bal int; add int; total int := 0;
begin
  insert into public.bank (user_id) values (p) on conflict (user_id) do nothing;
  select * into b from public.bank where user_id = p for update;
  d := least(public.taipei_today() - b.settled, 30);
  bal := b.balance;
  for i in 1..greatest(d, 0) loop
    add := least(floor(bal * 0.02)::int, 20);
    bal := bal + add; total := total + add;
  end loop;
  update public.bank set balance = bal, settled = public.taipei_today() where user_id = p;
  if total > 0 then insert into public.bank_log (user_id, amount, kind) values (p, total, 'interest'); end if;
end $$;

create or replace function public.bank_state()
returns json language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  perform public.bank_settle(auth.uid());
  return json_build_object(
    'balance', (select balance from public.bank where user_id = auth.uid()),
    'wallet', public.wallet_balance(auth.uid()),
    'log', coalesce((select json_agg(x) from (select amount, kind, created_at from public.bank_log
      where user_id = auth.uid() order by created_at desc limit 10) x), '[]'::json));
end $$;

-- 存錢（正數）或領錢（負數）
create or replace function public.bank_move(p_amount int)
returns json language plpgsql security definer set search_path = public as $$
declare b int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_amount = 0 then raise exception '金額不能是 0'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  perform public.bank_settle(auth.uid());
  select balance into b from public.bank where user_id = auth.uid();
  if p_amount > 0 and public.wallet_balance(auth.uid()) < p_amount then raise exception '錢包的金幣不夠'; end if;
  if p_amount < 0 and b < -p_amount then raise exception '存款不夠'; end if;
  update public.bank set balance = balance + p_amount where user_id = auth.uid();
  insert into public.coin_tx (user_id, amount, kind) values (auth.uid(), -p_amount, 'bank');
  insert into public.bank_log (user_id, amount, kind) values (auth.uid(), abs(p_amount), case when p_amount > 0 then 'deposit' else 'withdraw' end);
  return public.bank_state();
end $$;

-- 雙倍挑戰：押 10–100 金幣答 5 題，資料庫出題也由資料庫改
create table if not exists public.question_keys (
  qid text primary key,
  tier text not null,
  unit text not null,
  a int not null
);
alter table public.question_keys enable row level security;

create table if not exists public.challenges (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles on delete cascade,
  stake int not null,
  qids text[] not null,
  created_at timestamptz not null default now(),
  day date not null default public.taipei_today(),
  done boolean not null default false,
  correct int,
  payout int
);
alter table public.challenges enable row level security;
drop policy if exists "看自己的挑戰" on public.challenges;
create policy "看自己的挑戰" on public.challenges for select to authenticated using (user_id = auth.uid());

create or replace function public.start_challenge(p_stake int, p_units text[])
returns json language plpgsql security definer set search_path = public as $$
declare t text; qs text[]; cid bigint;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select tier into t from public.profiles where id = auth.uid();
  if t is null or t = 'kid' then raise exception '雙倍挑戰要國中以上才能玩'; end if;
  if p_stake < 10 or p_stake > 100 then raise exception '押注要在 10 到 100 金幣之間'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if (select count(*) from public.challenges where user_id = auth.uid() and day = public.taipei_today()) >= 3 then
    raise exception '今天的 3 次挑戰用完了，明天再來'; end if;
  if public.wallet_balance(auth.uid()) < p_stake then raise exception '金幣不夠'; end if;
  select array_agg(qid) into qs from (select qid from public.question_keys
    where tier = t and (coalesce(cardinality(p_units), 0) = 0 or unit = any (p_units))
    order by random() limit 5) x;
  if coalesce(cardinality(qs), 0) < 5 then raise exception '這個範圍的題目不夠 5 題'; end if;
  insert into public.challenges (user_id, stake, qids) values (auth.uid(), p_stake, qs) returning id into cid;
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), -p_stake, 'challenge', cid::text);
  return json_build_object('id', cid, 'qids', qs, 'wallet', public.wallet_balance(auth.uid()));
end $$;

create or replace function public.submit_challenge(p_id bigint, p_answers int[])
returns json language plpgsql security definer set search_path = public as $$
declare c public.challenges; k int[]; n int := 0; pay int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select * into c from public.challenges where id = p_id and user_id = auth.uid() and not done for update;
  if not found then raise exception '找不到這場挑戰'; end if;
  select array_agg(q.a order by x.i) into k from unnest(c.qids) with ordinality x(qid, i) join public.question_keys q on q.qid = x.qid;
  if now() - c.created_at <= interval '5 minutes' then
    for i in 1..cardinality(c.qids) loop
      if p_answers[i] is not null and p_answers[i] = k[i] then n := n + 1; end if;
    end loop;
  end if;
  pay := case n when 5 then c.stake * 2 when 4 then c.stake * 3 / 2 when 3 then c.stake else 0 end;
  update public.challenges set done = true, correct = n, payout = pay where id = p_id;
  if pay > 0 then insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), pay, 'challenge_win', p_id::text); end if;
  return json_build_object('correct', n, 'payout', pay, 'keys', k, 'wallet', public.wallet_balance(auth.uid()));
end $$;

do $$ declare f text; begin
  foreach f in array array['wallet_balance(uuid)','claim_game(text,integer)','bank_settle(uuid)','bank_state()','bank_move(integer)',
    'start_challenge(integer,text[])','submit_challenge(bigint,integer[])'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public.bank_settle(uuid) from authenticated;
