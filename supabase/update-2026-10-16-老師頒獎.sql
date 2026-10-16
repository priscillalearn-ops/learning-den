-- =====================================================================
-- 老師頒獎（2026-10-16 更新；整份重跑即可）
-- 老師可以頒獎給自己看得到的學生（例如「段考考王」），一次送 1～5000 金幣，學生下次打開會看到慶祝畫面。
-- =====================================================================
create table if not exists public.teacher_awards (
  id bigint generated always as identity primary key,
  teacher uuid not null references auth.users on delete cascade,
  student uuid not null references public.profiles on delete cascade,
  title text not null check (char_length(title) between 1 and 20),
  coins int not null check (coins between 0 and 5000),
  note text check (char_length(note) <= 60),
  seen boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists teacher_awards_student on public.teacher_awards (student, created_at desc);
alter table public.teacher_awards enable row level security;
drop policy if exists "看自己的獎" on public.teacher_awards;
create policy "看自己的獎" on public.teacher_awards for select to authenticated using (student = auth.uid());

create or replace function public.teacher_award(p_student uuid, p_title text, p_coins int, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare cls text;
begin
  if not public.is_teacher() then raise exception '只有老師可以頒獎'; end if;
  select class_code into cls from public.profiles where id = p_student;
  if not found then raise exception '找不到這位學生'; end if;
  if not (public.teacher_can_see(cls) or exists (select 1 from public.teachers t where t.user_id = auth.uid() and t.classes is null)) then
    raise exception '你沒有這位學生的權限'; end if;
  if coalesce(trim(p_title), '') = '' then raise exception '要寫獎項名稱'; end if;
  if p_coins is null or p_coins not between 0 and 5000 then raise exception '金幣要在 0 到 5000 之間'; end if;
  insert into public.teacher_awards (teacher, student, title, coins, note)
    values (auth.uid(), p_student, left(trim(p_title), 20), p_coins, left(nullif(trim(coalesce(p_note, '')), ''), 60));
  if p_coins > 0 then insert into public.coin_tx (user_id, amount, kind, ref) values (p_student, p_coins, 'award', left(trim(p_title), 20)); end if;
  return json_build_object('ok', true);
end $$;

-- 學生：我的獎（含還沒看過的）
create or replace function public.my_awards()
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', a.id, 'title', a.title, 'coins', a.coins, 'note', a.note, 'seen', a.seen,
    'created_at', a.created_at, 'teacher', public.teacher_label(a.teacher)) order by a.created_at desc), '[]'::json)
  from public.teacher_awards a where a.student = auth.uid();
$$;
create or replace function public.awards_seen()
returns void language sql security definer set search_path = public as $$
  update public.teacher_awards set seen = true where student = auth.uid() and not seen;
$$;

revoke all on function public.teacher_award(uuid, text, integer, text) from public, anon;
grant execute on function public.teacher_award(uuid, text, integer, text) to authenticated;
revoke all on function public.my_awards() from public, anon;
grant execute on function public.my_awards() to authenticated;
revoke all on function public.awards_seen() from public, anon;
grant execute on function public.awards_seen() to authenticated;

-- =====================================================================
-- 段考辛苦了！全體學生各送 1000 金幣（只發給目前已經有角色的學生，老師不算；重跑也不會重複發）
-- =====================================================================
with t as (select user_id from public.teachers order by user_id limit 1),
s as (
  insert into public.teacher_awards (teacher, student, title, coins, note)
  select t.user_id, p.id, '段考辛苦了', 1000, '恭喜大家考完段考！這是老師送你的慶祝禮，好好休息一下～'
  from public.profiles p, t
  where p.id not in (select user_id from public.teachers)
    and not exists (select 1 from public.teacher_awards a where a.student = p.id and a.title = '段考辛苦了')
  returning student
)
insert into public.coin_tx (user_id, amount, kind, ref)
select student, 1000, 'award', '段考辛苦了' from s;

-- 看發了幾位
select count(*) as 發出幾位 from public.teacher_awards where title = '段考辛苦了';
