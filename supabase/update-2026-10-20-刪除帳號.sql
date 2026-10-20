-- =====================================================================
-- 學生自己刪除帳號（2026-10-20 更新；整份重跑即可）
-- App Store 和 Google Play 都規定 app 裡要能自己刪除帳號。
-- 刪除後：角色、作答、專注、單字卡、房間、花園、好友、私訊、留言、金幣紀錄全部一起刪掉，無法復原。
-- =====================================================================
create or replace function public.delete_my_account(p_confirm text)
returns void language plpgsql security definer set search_path = public, auth as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception '請先登入'; end if;
  if coalesce(p_confirm, '') <> '刪除' then raise exception '請輸入「刪除」確認'; end if;
  -- 沒有外鍵連到帳號的紀錄先手動清掉
  delete from public.friend_point_log where a = u or b = u or actor = u;
  delete from public.friend_points where a = u or b = u;
  -- 刪掉登入帳號；角色和所有學習紀錄會跟著一起刪除（on delete cascade）
  delete from auth.users where id = u;
end $$;
revoke all on function public.delete_my_account(text) from public, anon;
grant execute on function public.delete_my_account(text) to authenticated;
