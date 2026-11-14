-- =====================================================================
-- 冒險打怪、躲貓貓、坐騎（2026-11-15；整份重跑即可）
-- 冒險：claim_game('adventure')，每場最多 20、每天最多 40。
-- 躲貓貓：claim_game('hideseek')，每場最多 15、每天最多 40。
-- 坐騎：6 個新商品（服裝欄位 ride），買了就能騎，走路變快。
-- =====================================================================

create or replace function public.claim_game(p_game text, p_score int, p_level int default 1)
returns json language plpgsql security definer set search_path = public as $$
declare got int; r int; cap int; lv int := greatest(1, least(coalesce(p_level, 1), 4));
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_game not in ('match', 'speed', 'granny', 'tower', 'halloween', 'trick', 'words', 'adventure', 'hideseek') then raise exception '沒有這個遊戲'; end if;
  if p_game in ('halloween', 'trick') and not (extract(month from public.taipei_today()) = 10
      or (extract(month from public.taipei_today()) = 11 and extract(day from public.taipei_today()) <= 7)) then
    raise exception '萬聖節活動結束了'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select coalesce(sum(amount), 0) into got from public.coin_tx
    where user_id = auth.uid() and kind = 'game:' || p_game and day = public.taipei_today();
  cap := 15 + 3 * (lv - 1);
  if p_game in ('halloween', 'trick', 'adventure') then cap := 20; end if;
  if p_game = 'hideseek' then cap := 15; end if;
  r := greatest(0, least(coalesce(p_score, 0), cap, 40 - got));
  if r > 0 then insert into public.coin_tx (user_id, amount, kind) values (auth.uid(), r, 'game:' || p_game); end if;
  return json_build_object('reward', r, 'wallet', public.wallet_balance(auth.uid()));
end $$;
revoke all on function public.claim_game(text, integer, integer) from public, anon;
grant execute on function public.claim_game(text, integer, integer) to authenticated;


insert into public.shop_items (id, slot, price, unlock_cards, avail_from, avail_until, gacha, bundle) values
  ('ride_none', 'ride', 0, null, null, null, null, null),
  ('ride_skate', 'ride', 200, null, null, null, null, null),
  ('ride_broom', 'ride', 350, null, null, null, null, null),
  ('ride_bike', 'ride', 500, null, null, null, null, null),
  ('ride_cloud', 'ride', 900, null, null, null, null, null),
  ('ride_unicorn', 'ride', 1500, null, null, null, null, null)
on conflict (id) do update set slot = excluded.slot, price = excluded.price, unlock_cards = excluded.unlock_cards, avail_from = excluded.avail_from, avail_until = excluded.avail_until, gacha = excluded.gacha, bundle = excluded.bundle;
