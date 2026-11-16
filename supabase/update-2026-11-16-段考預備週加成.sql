-- =====================================================================
-- 第二次段考預備週加成（2026-11-16～11-22）
-- 這週答今日一題、專注、個人任務、讀書會任務的金幣 ×2，答題／專注有 40% 機會掉盲盒券（每天各一次）。
-- 重跑也不會重複新增。
-- =====================================================================
insert into public.app_events (name, start_day, end_day, mult, drop_rate)
  values ('段考預備週加成', '2026-11-16', '2026-11-22', 2, 0.4) on conflict (name, start_day) do nothing;

select name, start_day, end_day, mult from public.app_events order by start_day desc limit 3;
