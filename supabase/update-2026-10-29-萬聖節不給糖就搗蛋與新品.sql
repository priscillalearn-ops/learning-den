-- =====================================================================
-- 萬聖節「不給糖就搗蛋」遊戲與 2026 萬聖節新品 11 款（2026-10-29；整份重跑即可）
-- 遊戲：claim_game 多收 'trick'，跟糖果大作戰一樣只在 10/1～11/7、每場最多 20、每天最多 40。
-- 新品：上架期間 10/1～11/7（跟其他萬聖節商品一樣，也算房間評分的萬聖節主題）。
-- =====================================================================

create or replace function public.claim_game(p_game text, p_score int, p_level int default 1)
returns json language plpgsql security definer set search_path = public as $$
declare got int; r int; cap int; lv int := greatest(1, least(coalesce(p_level, 1), 4));
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_game not in ('match', 'speed', 'granny', 'tower', 'halloween', 'trick') then raise exception '沒有這個遊戲'; end if;
  if p_game in ('halloween', 'trick') and not (extract(month from public.taipei_today()) = 10
      or (extract(month from public.taipei_today()) = 11 and extract(day from public.taipei_today()) <= 7)) then
    raise exception '萬聖節活動結束了'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select coalesce(sum(amount), 0) into got from public.coin_tx
    where user_id = auth.uid() and kind = 'game:' || p_game and day = public.taipei_today();
  cap := 15 + 3 * (lv - 1);
  if p_game in ('halloween', 'trick') then cap := 20; end if;
  r := greatest(0, least(coalesce(p_score, 0), cap, 40 - got));
  if r > 0 then insert into public.coin_tx (user_id, amount, kind) values (auth.uid(), r, 'game:' || p_game); end if;
  return json_build_object('reward', r, 'wallet', public.wallet_balance(auth.uid()));
end $$;
revoke all on function public.claim_game(text, integer, integer) from public, anon;
grant execute on function public.claim_game(text, integer, integer) to authenticated;


insert into public.shop_items (id, slot, price, unlock_cards, avail_from, avail_until, gacha, bundle) values
  ('pet_skeleton', 'pet', 380, null, '10-01', '11-07', null, null),
  ('pet_candymon', 'pet', 300, null, '10-01', '11-07', null, null),
  ('plant_cauldron', 'plant', 160, null, '10-01', '11-07', null, null),
  ('poster_candy', 'poster', 100, null, '10-01', '11-07', null, null),
  ('lamp_jack', 'lamp', 140, null, '10-01', '11-07', null, null),
  ('rug_candy', 'rug', 130, null, '10-01', '11-07', null, null),
  ('win_witch', 'window', 180, null, '10-01', '11-07', null, null),
  ('hat_witch_green', 'hat', 200, null, '10-01', '11-07', null, null),
  ('top_witch', 'top', 150, null, '10-01', '11-07', null, null),
  ('acc_bolts', 'acc', 120, null, '10-01', '11-07', null, null),
  ('acc_catears', 'acc', 150, null, '10-01', '11-07', null, null)
on conflict (id) do update set slot = excluded.slot, price = excluded.price, unlock_cards = excluded.unlock_cards, avail_from = excluded.avail_from, avail_until = excluded.avail_until, gacha = excluded.gacha, bundle = excluded.bundle;
