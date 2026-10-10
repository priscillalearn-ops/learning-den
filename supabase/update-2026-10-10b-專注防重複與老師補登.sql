
-- =====================================================================
-- 專注紀錄防重複（2026-10-10 更新；整份重跑即可）
-- 每次專注有自己的編號 client_id；存不上會自動重試，有編號就不會重複算兩次。
-- =====================================================================
alter table public.focus_sessions add column if not exists client_id text;
create unique index if not exists focus_sessions_client_id on public.focus_sessions (client_id);

-- =====================================================================
-- 老師補登專注時間（2026-10-10 第二次更新；整份重跑即可）
-- 老師可以幫自己看得到的學生補登最近 30 天內的專注時間（一次 1～120 分鐘），每筆都留紀錄。
-- 補登的時間會照一般專注計算：金幣（每天上限照舊）、連續打卡、排行、讀書會任務都會算進去。
-- =====================================================================
create table if not exists public.teacher_focus_adds (
  id bigint generated always as identity primary key,
  teacher uuid not null references auth.users on delete cascade,
  student uuid not null references public.profiles on delete cascade,
  day date not null,
  minutes int not null,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists teacher_focus_adds_student on public.teacher_focus_adds (student, created_at desc);
alter table public.teacher_focus_adds enable row level security;

create or replace function public.teacher_add_focus(p_student uuid, p_day date, p_minutes int, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare cls text;
begin
  if not public.is_teacher() then raise exception '只有老師可以補登'; end if;
  select class_code into cls from public.profiles where id = p_student;
  if not found then raise exception '找不到這位學生'; end if;
  if not (public.teacher_can_see(cls) or exists (select 1 from public.teachers t where t.user_id = auth.uid() and t.classes is null)) then
    raise exception '你沒有這位學生的權限'; end if;
  if p_minutes is null or p_minutes not between 1 and 120 then raise exception '一次可以補登 1 到 120 分鐘'; end if;
  if p_day is null or p_day > public.taipei_today() or p_day < public.taipei_today() - 30 then raise exception '只能補登最近 30 天內的日期'; end if;
  insert into public.focus_sessions (user_id, day, minutes, client_id)
    values (p_student, p_day, p_minutes, 'teacher-' || gen_random_uuid()::text);
  insert into public.teacher_focus_adds (teacher, student, day, minutes, note)
    values (auth.uid(), p_student, p_day, p_minutes, nullif(trim(coalesce(p_note, '')), ''));
  return json_build_object('ok', true);
end $$;

create or replace function public.teacher_focus_adds_for(p_student uuid)
returns table (day date, minutes int, note text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select day, minutes, note, created_at from public.teacher_focus_adds
  where student = p_student and public.is_teacher()
  order by created_at desc limit 10;
$$;

revoke all on function public.teacher_add_focus(uuid, date, integer, text) from public, anon;
grant execute on function public.teacher_add_focus(uuid, date, integer, text) to authenticated;
revoke all on function public.teacher_focus_adds_for(uuid) from public, anon;
grant execute on function public.teacher_focus_adds_for(uuid) to authenticated;
