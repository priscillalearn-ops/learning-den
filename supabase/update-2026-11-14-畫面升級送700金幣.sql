-- =====================================================================
-- 畫面大升級！全體學生各送 700 金幣（2026-11-14）
-- 學生下次打開會跳出領獎畫面。只發給目前已經有角色的學生，老師不算；重跑也不會重複發。
-- =====================================================================
with t as (select user_id from public.teachers order by user_id limit 1),
s as (
  insert into public.teacher_awards (teacher, student, title, coins, note)
  select t.user_id, p.id, '畫面大升級', 700, '整個 Learning Den 變漂亮了！老師送你 700 金幣慶祝，去百貨公司逛逛吧～'
  from public.profiles p, t
  where p.id not in (select user_id from public.teachers)
    and not exists (select 1 from public.teacher_awards a where a.student = p.id and a.title = '畫面大升級')
  returning student
)
insert into public.coin_tx (user_id, amount, kind, ref)
select student, 700, 'award', '畫面大升級' from s;

-- 看發了幾位
select count(*) as 發出幾位 from public.teacher_awards where title = '畫面大升級';
