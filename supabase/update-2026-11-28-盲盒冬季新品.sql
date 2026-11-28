-- =====================================================================
-- 魔法盲盒換新一批：冬季雪夜系列 13 款（2026-11-28；整份重跑也沒關係）
-- 舊的兩批（第一批 18 款＋秋季 10 款）標成絕版 gacha_off = true，之後抽不到；
-- 已經抽到的人 purchases 不動，照樣保留、可以穿戴擺設。
-- 機率、保底、每天 10 抽、重複換金幣都不變。
-- ⚠ 請先合併 PR、等網站更新好（約 1～2 分鐘）再執行，否則舊版網頁看不懂新獎品。
-- =====================================================================

-- 1. 絕版欄位
alter table public.shop_items add column if not exists gacha_off boolean not null default false;

-- 2. 新一批獎品（N 4／R 4／SR 3／SSR 2）
insert into public.shop_items (id, slot, price, unlock_cards, avail_from, avail_until, gacha, bundle, gacha_off) values
  ('acc_snowflake', 'acc', 9999, null, null, null, 'N', null, false),
  ('poster_snow', 'poster', 9999, null, null, null, 'N', null, false),
  ('rug_snow', 'rug', 9999, null, null, null, 'N', null, false),
  ('plant_holly', 'plant', 9999, null, null, null, 'N', null, false),
  ('hat_beanie', 'hat', 9999, null, null, null, 'R', null, false),
  ('top_sweater', 'top', 9999, null, null, null, 'R', null, false),
  ('pet_polar', 'pet', 9999, null, null, null, 'R', null, false),
  ('lamp_icicle', 'lamp', 9999, null, null, null, 'R', null, false),
  ('pet_snowfox', 'pet', 9999, null, null, null, 'SR', null, false),
  ('acc_earmuff', 'acc', 9999, null, null, null, 'SR', null, false),
  ('win_snow', 'window', 9999, null, null, null, 'SR', null, false),
  ('pet_icedragon', 'pet', 9999, null, null, null, 'SSR', null, false),
  ('hat_icecrown', 'hat', 9999, null, null, null, 'SSR', null, false)
on conflict (id) do update set slot = excluded.slot, price = excluded.price, unlock_cards = excluded.unlock_cards, avail_from = excluded.avail_from, avail_until = excluded.avail_until, gacha = excluded.gacha, bundle = excluded.bundle, gacha_off = excluded.gacha_off;

-- 3. 舊的盲盒獎品全部絕版（只改抽獎池，不刪任何人的收藏）
update public.shop_items set gacha_off = true
where gacha is not null and id not in ('acc_snowflake','poster_snow','rug_snow','plant_holly','hat_beanie','top_sweater','pet_polar','lamp_icicle','pet_snowfox','acc_earmuff','win_snow','pet_icedragon','hat_icecrown');

-- 4. 抽盲盒只從沒絕版的抽（其他邏輯跟原本一樣）
create or replace function public.gacha_pull(p_n int, p_free boolean, p_ticket boolean default false)
returns json language plpgsql security definer set search_path = public as $$
declare st public.gacha_state; res json[] := '{}'; r float; rar text; it text; got_sr boolean := false; dup boolean; refund int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_n not in (1, 10) then raise exception '一次抽 1 個或 10 個'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  insert into public.gacha_state (user_id) values (auth.uid()) on conflict (user_id) do nothing;
  select * into st from public.gacha_state where user_id = auth.uid() for update;
  if st.day is distinct from public.taipei_today() then st.day := public.taipei_today(); st.pulls := 0; end if;
  if coalesce(p_ticket, false) then
    if p_n <> 1 then raise exception '一張盲盒券抽 1 個'; end if;
    if st.tickets < 1 then raise exception '沒有盲盒券了'; end if;
    st.tickets := st.tickets - 1;
  elsif coalesce(p_free, false) then
    if p_n <> 1 then raise exception '免費抽一次只能抽 1 個'; end if;
    if st.free_day = public.taipei_today() then raise exception '今天的免費抽已經用過了'; end if;
    if not exists (select 1 from public.answers where user_id = auth.uid() and day = public.taipei_today()) then
      raise exception '先答今日一題，就能免費抽一次'; end if;
    st.free_day := public.taipei_today();
  else
    if st.pulls + p_n > 10 then raise exception '今天最多抽 10 次，明天再來'; end if;
    if public.wallet_balance(auth.uid()) < (case p_n when 1 then 50 else 450 end) then raise exception '金幣不夠'; end if;
    st.pulls := st.pulls + p_n;
    insert into public.coin_tx (user_id, amount, kind) values (auth.uid(), -(case p_n when 1 then 50 else 450 end), 'gacha');
  end if;
  for i in 1..p_n loop
    st.pity := st.pity + 1;
    r := random();
    rar := case when st.pity >= 50 or r < .02 then 'SSR' when r < .12 then 'SR' when r < .40 then 'R' else 'N' end;
    if p_n = 10 and i = 10 and not got_sr and rar in ('N', 'R') then rar := 'SR'; end if;
    if rar in ('SR', 'SSR') then got_sr := true; end if;
    if rar = 'SSR' then st.pity := 0; end if;
    select id into it from public.shop_items where gacha = rar and not gacha_off order by random() limit 1;
    dup := exists (select 1 from public.purchases where user_id = auth.uid() and item_id = it);
    if dup then
      refund := case rar when 'N' then 10 when 'R' then 25 when 'SR' then 80 else 200 end;
      insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), refund, 'gacha_refund', it);
    else
      refund := 0;
      insert into public.purchases (user_id, item_id, price) values (auth.uid(), it, 0);
    end if;
    res := res || json_build_object('item', it, 'rarity', rar, 'dup', dup, 'refund', refund);
  end loop;
  update public.gacha_state set pity = st.pity, day = st.day, pulls = st.pulls, free_day = st.free_day, tickets = st.tickets where user_id = auth.uid();
  return json_build_object('results', array_to_json(res), 'wallet', public.wallet_balance(auth.uid()), 'pity', st.pity, 'pulls', st.pulls, 'tickets', st.tickets);
end $$;
revoke all on function public.gacha_pull(integer, boolean, boolean) from public, anon;
grant execute on function public.gacha_pull(integer, boolean, boolean) to authenticated;

-- 5. 檢查（跑完看結果）：
--    現在抽得到的應該是 N 4／R 4／SR 3／SSR 2；絕版應該是 28 款
select case when gacha_off then '絕版' else '抽得到' end as 狀態, gacha, count(*)
from public.shop_items where gacha is not null group by 1, 2 order by 1, 2;
--    程式用到的資料表都在（應該 6 張全部 true）
select t, to_regclass('public.' || t) is not null as 存在
from unnest(array['shop_items','gacha_state','purchases','coin_tx','answers','profiles']) t;
