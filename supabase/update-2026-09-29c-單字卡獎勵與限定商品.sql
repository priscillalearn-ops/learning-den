-- Learning Den 補充更新：單字卡收集獎勵、稀有商品、萬聖節與聖誕節限定商品
-- 整份貼到 Supabase SQL Editor 執行（重跑也沒關係）

-- =====================================================================
-- 單字卡收集獎勵、稀有與限定商品（2026-09-29 第三次更新；整份重跑即可）
-- =====================================================================
alter table public.shop_items add column if not exists unlock_cards int;
alter table public.shop_items add column if not exists avail_from text;
alter table public.shop_items add column if not exists avail_until text;


-- SHOP_SEED_START
insert into public.shop_items (id, slot, price, unlock_cards, avail_from, avail_until) values
  ('wall_lilac', 'wall', 0, null, null, null),
  ('wall_mint', 'wall', 40, null, null, null),
  ('wall_peach', 'wall', 40, null, null, null),
  ('wall_sky', 'wall', 60, null, null, null),
  ('wall_night', 'wall', 120, null, null, null),
  ('floor_wood', 'floor', 0, null, null, null),
  ('floor_tile', 'floor', 40, null, null, null),
  ('floor_carpet', 'floor', 60, null, null, null),
  ('floor_grass', 'floor', 80, null, null, null),
  ('win_day', 'window', 0, null, null, null),
  ('win_night', 'window', 80, null, null, null),
  ('win_rain', 'window', 80, null, null, null),
  ('win_sakura', 'window', 150, null, null, null),
  ('poster_none', 'poster', 0, null, null, null),
  ('poster_star', 'poster', 50, null, null, null),
  ('poster_heart', 'poster', 50, null, null, null),
  ('poster_book', 'poster', 80, null, null, null),
  ('poster_moon', 'poster', 100, null, null, null),
  ('bed_blue', 'bed', 0, null, null, null),
  ('bed_pink', 'bed', 60, null, null, null),
  ('bed_star', 'bed', 150, null, null, null),
  ('desk_wood', 'desk', 0, null, null, null),
  ('desk_white', 'desk', 60, null, null, null),
  ('desk_pink', 'desk', 80, null, null, null),
  ('chair_wood', 'chair', 0, null, null, null),
  ('chair_pink', 'chair', 60, null, null, null),
  ('chair_gamer', 'chair', 150, null, null, null),
  ('lamp_none', 'lamp', 0, null, null, null),
  ('lamp_yellow', 'lamp', 50, null, null, null),
  ('lamp_mint', 'lamp', 70, null, null, null),
  ('plant_none', 'plant', 0, null, null, null),
  ('plant_green', 'plant', 40, null, null, null),
  ('plant_cactus', 'plant', 60, null, null, null),
  ('plant_flower', 'plant', 90, null, null, null),
  ('rug_none', 'rug', 0, null, null, null),
  ('rug_red', 'rug', 40, null, null, null),
  ('rug_blue', 'rug', 40, null, null, null),
  ('rug_rainbow', 'rug', 120, null, null, null),
  ('pet_none', 'pet', 0, null, null, null),
  ('pet_slime', 'pet', 250, null, null, null),
  ('pet_cat', 'pet', 300, null, null, null),
  ('pet_dog', 'pet', 300, null, null, null),
  ('pet_owl', 'pet', 400, null, null, null),
  ('pet_maltese', 'pet', 300, null, null, null),
  ('pet_bunny', 'pet', 250, null, null, null),
  ('pet_penguin', 'pet', 300, null, null, null),
  ('pet_dino', 'pet', 350, null, null, null),
  ('pet_dino_pink', 'pet', 350, null, null, null),
  ('pet_dino_rex', 'pet', 500, null, null, null),
  ('pet_unicorn', 'pet', 1000, null, null, null),
  ('pet_phoenix', 'pet', 1200, null, null, null),
  ('pet_dragon_gold', 'pet', 1500, null, null, null),
  ('hat_rainbow', 'hat', 800, null, null, null),
  ('wall_galaxy', 'wall', 600, null, null, null),
  ('bed_castle', 'bed', 900, null, null, null),
  ('hat_pumpkin', 'hat', 150, null, '10-01', '11-07'),
  ('pet_bat', 'pet', 350, null, '10-01', '11-07'),
  ('wall_halloween', 'wall', 200, null, '10-01', '11-07'),
  ('hat_santa', 'hat', 150, null, '12-01', '12-31'),
  ('pet_reindeer', 'pet', 400, null, '12-01', '12-31'),
  ('poster_xmas', 'poster', 120, null, '12-01', '12-31'),
  ('hat_grad', 'hat', 9999, 10, null, null),
  ('pet_bookfairy', 'pet', 9999, 30, null, null),
  ('wall_library', 'wall', 9999, 60, null, null),
  ('hat_wiz_gold', 'hat', 9999, 100, null, null),
  ('hat_none', 'hat', 0, null, null, null),
  ('hat_wiz_p', 'hat', 0, null, null, null),
  ('hat_helmet', 'hat', 0, null, null, null),
  ('hat_wiz_b', 'hat', 60, null, null, null),
  ('hat_cap_r', 'hat', 50, null, null, null),
  ('hat_cap_b', 'hat', 50, null, null, null),
  ('hat_bunny', 'hat', 150, null, null, null),
  ('hat_cat', 'hat', 150, null, null, null),
  ('hat_crown', 'hat', 400, null, null, null),
  ('top_blue', 'top', 0, null, null, null),
  ('top_red', 'top', 0, null, null, null),
  ('top_purple', 'top', 0, null, null, null),
  ('top_green', 'top', 30, null, null, null),
  ('top_yellow', 'top', 30, null, null, null),
  ('top_pink', 'top', 30, null, null, null),
  ('top_black', 'top', 60, null, null, null),
  ('top_white', 'top', 60, null, null, null),
  ('hair_brown', 'hair', 0, null, null, null),
  ('hair_black', 'hair', 0, null, null, null),
  ('hair_blond', 'hair', 0, null, null, null),
  ('hair_pink', 'hair', 0, null, null, null),
  ('hair_blue', 'hair', 0, null, null, null),
  ('skin_1', 'skin', 0, null, null, null),
  ('skin_2', 'skin', 0, null, null, null),
  ('skin_3', 'skin', 0, null, null, null),
  ('skin_4', 'skin', 0, null, null, null),
  ('acc_none', 'acc', 0, null, null, null),
  ('acc_beard', 'acc', 0, null, null, null),
  ('acc_glasses', 'acc', 80, null, null, null),
  ('acc_scarf', 'acc', 60, null, null, null),
  ('acc_phones', 'acc', 120, null, null, null),
  ('acc_cape', 'acc', 200, null, null, null),
  ('acc_headband', 'acc', 40, null, null, null),
  ('acc_bow', 'acc', 50, null, null, null),
  ('acc_bowtie', 'acc', 60, null, null, null),
  ('acc_star', 'acc', 70, null, null, null),
  ('acc_round', 'acc', 80, null, null, null),
  ('acc_pearl', 'acc', 90, null, null, null),
  ('acc_halo', 'acc', 250, null, null, null),
  ('acc_wings', 'acc', 300, null, null, null)
on conflict (id) do update set slot = excluded.slot, price = excluded.price, unlock_cards = excluded.unlock_cards, avail_from = excluded.avail_from, avail_until = excluded.avail_until;
-- SHOP_SEED_END

-- 現在買得到嗎：不是單字卡獎勵、而且在限定期間內（月-日）
create or replace function public.item_on_sale(it public.shop_items)
returns boolean language sql stable as $$
  select it.unlock_cards is null and (it.avail_from is null
    or to_char(public.taipei_today(), 'MM-DD') between it.avail_from and it.avail_until);
$$;

create or replace function public.buy_item(p_item text)
returns int language plpgsql security definer set search_path = public as $$
declare it public.shop_items; bal int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select * into it from public.shop_items where id = p_item;
  if not found then raise exception '沒有這個商品'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  bal := public.wallet_balance(auth.uid());
  if it.price = 0 or exists (select 1 from public.purchases where user_id = auth.uid() and item_id = p_item) then return bal; end if;
  if it.unlock_cards is not null then raise exception '這個要收集單字卡才能解鎖'; end if;
  if not public.item_on_sale(it) then raise exception '這個限定商品現在沒有販售'; end if;
  if bal < it.price then raise exception '金幣不夠'; end if;
  insert into public.purchases (user_id, item_id, price) values (auth.uid(), p_item, it.price);
  return bal - it.price;
end $$;

create or replace function public.send_gift(p_to uuid, p_kind text, p_amount int, p_item text, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare it public.shop_items; sent int; note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if not public.are_friends(auth.uid(), p_to) then raise exception '只能送禮物給好友'; end if;
  if public.is_blocked_between(auth.uid(), p_to) then raise exception '沒辦法送給這位同學'; end if;
  if public.is_muted(auth.uid()) then note := null; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if p_kind = 'coins' then
    if p_amount is null or p_amount < 10 or p_amount > 100 then raise exception '一次可以送 10 到 100 金幣'; end if;
    select coalesce(-sum(amount), 0) into sent from public.coin_tx
      where user_id = auth.uid() and kind = 'gift_out' and day = public.taipei_today();
    if sent + p_amount > 200 then raise exception '今天送出的金幣已經到上限 200 了'; end if;
    if public.wallet_balance(auth.uid()) < p_amount then raise exception '金幣不夠'; end if;
    insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), -p_amount, 'gift_out', p_to::text), (p_to, p_amount, 'gift_in', auth.uid()::text);
  elsif p_kind = 'item' then
    select * into it from public.shop_items where id = p_item;
    if not found or it.price = 0 or not public.item_on_sale(it) then raise exception '這個不能當禮物'; end if;
    if exists (select 1 from public.purchases where user_id = p_to and item_id = p_item) then raise exception '對方已經有這個了'; end if;
    if public.wallet_balance(auth.uid()) < it.price then raise exception '金幣不夠'; end if;
    insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), -it.price, 'gift_item', p_to::text);
    insert into public.purchases (user_id, item_id, price) values (p_to, p_item, 0);
  else raise exception '禮物種類不對'; end if;
  insert into public.gifts (sender, recipient, kind, amount, item_id, note)
    values (auth.uid(), p_to, p_kind, case when p_kind = 'coins' then p_amount end, case when p_kind = 'item' then p_item end, note);
  return json_build_object('wallet', public.wallet_balance(auth.uid()));
end $$;

-- 單字卡收集到門檻就自動得到獎勵（用資料庫的單字卡張數判斷）
create or replace function public.claim_card_rewards()
returns json language plpgsql security definer set search_path = public as $$
declare n int; got text[];
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select count(*) into n from public.cards where user_id = auth.uid();
  with ins as (
    insert into public.purchases (user_id, item_id, price)
    select auth.uid(), s.id, 0 from public.shop_items s
    where s.unlock_cards is not null and s.unlock_cards <= n
      and not exists (select 1 from public.purchases p where p.user_id = auth.uid() and p.item_id = s.id)
    returning item_id)
  select coalesce(array_agg(item_id), '{}') into got from ins;
  return json_build_object('cards', n, 'granted', got);
end $$;

revoke all on function public.claim_card_rewards() from public, anon;
grant execute on function public.claim_card_rewards() to authenticated;

