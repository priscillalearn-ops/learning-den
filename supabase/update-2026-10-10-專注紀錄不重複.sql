
-- =====================================================================
-- 專注紀錄防重複（2026-10-10 更新；整份重跑即可）
-- 每次專注有自己的編號 client_id；存不上會自動重試，有編號就不會重複算兩次。
-- =====================================================================
alter table public.focus_sessions add column if not exists client_id text;
create unique index if not exists focus_sessions_client_id on public.focus_sessions (client_id);
