
-- =====================================================================
-- 全部同學排行（2026-10-05 更新；整份重跑即可）
-- 不分年級、不分班，所有人最近 7 天專注排行；回傳前 200 名，自己不在裡面也會附上（排名照算）。
-- =====================================================================
create or replace function public.all_board()
returns table (name text, tier text, week_minutes int, streak int, is_me boolean, rank int)
language sql stable security definer set search_path = public as $$
  with s as (
    select p.id, p.name, p.tier,
      coalesce((select sum(f.minutes) from public.focus_sessions f
        where f.user_id = p.id and f.day > public.taipei_today() - 7), 0)::int as week_minutes
    from public.profiles p
  ), r as (
    select s.*, rank() over (order by week_minutes desc)::int as rk from s
  )
  select r.name, r.tier, r.week_minutes, public.current_streak(r.id), r.id = auth.uid(), r.rk
  from r
  where r.rk <= 200 or r.id = auth.uid()
  order by r.rk, r.name
  limit 201;
$$;
revoke all on function public.all_board() from public, anon;
grant execute on function public.all_board() to authenticated;
