-- Learning Den 補充更新：老師傳訊息、布告欄公告、任務板
-- 整份貼到 Supabase SQL Editor 執行（重跑也沒關係）

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

