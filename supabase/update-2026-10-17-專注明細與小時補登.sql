-- =====================================================================
-- 專注時數明細、補登改成小時、全班補登（2026-10-17 更新；整份重跑即可）
-- 「本週」都是最近 7 天：上週讀的時間會滑出本週，但沒有不見。這裡讓老師看到每位學生的累計總時數和每天明細。
-- 補登：一次最多 60 小時，資料庫會自動拆成每筆 2 小時存（每天的專注金幣上限照舊）。
-- =====================================================================
-- 每位學生：累計總分鐘、最近 7 天、最近 14 天每天的分鐘
create or replace function public.teacher_focus_totals(p_class text)
returns table (user_id uuid, total_minutes int, week_minutes int, days json)
language sql stable security definer set search_path = public as $$
  select p.id,
    coalesce((select sum(f.minutes) from public.focus_sessions f where f.user_id = p.id), 0)::int,
    coalesce((select sum(f.minutes) from public.focus_sessions f where f.user_id = p.id and f.day > public.taipei_today() - 7), 0)::int,
    coalesce((select json_object_agg(d.day, d.m) from (select f.day, sum(f.minutes)::int as m from public.focus_sessions f
      where f.user_id = p.id and f.day > public.taipei_today() - 14 group by f.day) d), '{}'::json)
  from public.profiles p
  where public.is_teacher() and coalesce(p.class_code, '') = coalesce(p_class, '')
    and (public.teacher_can_see(p.class_code)
      or exists (select 1 from public.teachers x where x.user_id = auth.uid() and x.classes is null));
$$;

-- 學生自己的累計總分鐘
create or replace function public.my_focus_total()
returns int language sql stable security definer set search_path = public as $$
  select coalesce(sum(minutes), 0)::int from public.focus_sessions where user_id = auth.uid();
$$;

-- 補登：一次 1～3600 分鐘（60 小時），拆成每筆最多 120 分鐘
drop function if exists public.teacher_add_focus(uuid, date, integer, text);
create or replace function public.teacher_add_focus(p_student uuid, p_day date, p_minutes int, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare cls text; left_m int := p_minutes; chunk int;
begin
  if not public.is_teacher() then raise exception '只有老師可以補登'; end if;
  select class_code into cls from public.profiles where id = p_student;
  if not found then raise exception '找不到這位學生'; end if;
  if not (public.teacher_can_see(cls) or exists (select 1 from public.teachers t where t.user_id = auth.uid() and t.classes is null)) then
    raise exception '你沒有這位學生的權限'; end if;
  if p_minutes is null or p_minutes not between 1 and 3600 then raise exception '一次可以補登 1 分鐘到 60 小時'; end if;
  if p_day is null or p_day > public.taipei_today() or p_day < public.taipei_today() - 30 then raise exception '只能補登最近 30 天內的日期'; end if;
  while left_m > 0 loop
    chunk := least(left_m, 120);
    insert into public.focus_sessions (user_id, day, minutes, client_id) values (p_student, p_day, chunk, 'teacher-' || gen_random_uuid()::text);
    left_m := left_m - chunk;
  end loop;
  insert into public.teacher_focus_adds (teacher, student, day, minutes, note)
    values (auth.uid(), p_student, p_day, p_minutes, nullif(trim(coalesce(p_note, '')), ''));
  return json_build_object('ok', true);
end $$;

-- 全班補登：班上每位學生都補一樣的時數
create or replace function public.teacher_add_focus_class(p_class text, p_day date, p_minutes int, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  if not public.is_teacher() then raise exception '只有老師可以補登'; end if;
  for r in select p.id from public.profiles p
    where coalesce(p.class_code, '') = coalesce(p_class, '') and p.id not in (select user_id from public.teachers)
  loop
    perform public.teacher_add_focus(r.id, p_day, p_minutes, p_note);
    n := n + 1;
  end loop;
  return json_build_object('count', n);
end $$;

revoke all on function public.teacher_focus_totals(text) from public, anon;
grant execute on function public.teacher_focus_totals(text) to authenticated;
revoke all on function public.my_focus_total() from public, anon;
grant execute on function public.my_focus_total() to authenticated;
revoke all on function public.teacher_add_focus(uuid, date, integer, text) from public, anon;
grant execute on function public.teacher_add_focus(uuid, date, integer, text) to authenticated;
revoke all on function public.teacher_add_focus_class(text, date, integer, text) from public, anon;
grant execute on function public.teacher_add_focus_class(text, date, integer, text) to authenticated;
