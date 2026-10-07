
-- =====================================================================
-- 好友與私訊直接開放（2026-10-08 第五次更新；整份重跑即可）
-- 不用再連續打卡 7 天；國小（kid）一樣不開放私訊。
-- =====================================================================
create or replace function public.dm_ok(p uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = p and tier <> 'kid');
$$;
