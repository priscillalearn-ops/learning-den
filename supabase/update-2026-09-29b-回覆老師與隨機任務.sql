-- Learning Den 補充更新：學生回覆老師、老師署名、隨機任務、好友 7 天解鎖
-- 整份貼到 Supabase SQL Editor 執行（重跑也沒關係）

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

