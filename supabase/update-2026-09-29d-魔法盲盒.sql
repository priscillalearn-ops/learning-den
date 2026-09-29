-- Learning Den 補充更新：魔法盲盒
-- 整份貼到 Supabase SQL Editor 執行（重跑也沒關係）
-- 如果上一份「單字卡獎勵與限定商品」還沒跑，請先跑那份

-- =====================================================================
-- 魔法盲盒（2026-09-29 第四次更新；整份重跑即可）
-- 機率 SSR 2%／SR 10%／R 28%／N 60%；50 抽保底 SSR；十連保底 SR；每天最多 10 抽；
-- 重複轉金幣（N 10／R 25／SR 80／SSR 200）；答完今日一題每天免費抽一次；只能用讀書賺的金幣
-- =====================================================================
alter table public.shop_items add column if not exists gacha text;


-- SHOP_SEED_START
insert into public.shop_items (id, slot, price, unlock_cards, avail_from, avail_until, gacha) values
  ('wall_lilac', 'wall', 0, null, null, null, null),
  ('wall_mint', 'wall', 40, null, null, null, null),
  ('wall_peach', 'wall', 40, null, null, null, null),
  ('wall_sky', 'wall', 60, null, null, null, null),
  ('wall_night', 'wall', 120, null, null, null, null),
  ('floor_wood', 'floor', 0, null, null, null, null),
  ('floor_tile', 'floor', 40, null, null, null, null),
  ('floor_carpet', 'floor', 60, null, null, null, null),
  ('floor_grass', 'floor', 80, null, null, null, null),
  ('win_day', 'window', 0, null, null, null, null),
  ('win_night', 'window', 80, null, null, null, null),
  ('win_rain', 'window', 80, null, null, null, null),
  ('win_sakura', 'window', 150, null, null, null, null),
  ('poster_none', 'poster', 0, null, null, null, null),
  ('poster_star', 'poster', 50, null, null, null, null),
  ('poster_heart', 'poster', 50, null, null, null, null),
  ('poster_book', 'poster', 80, null, null, null, null),
  ('poster_moon', 'poster', 100, null, null, null, null),
  ('bed_blue', 'bed', 0, null, null, null, null),
  ('bed_pink', 'bed', 60, null, null, null, null),
  ('bed_star', 'bed', 150, null, null, null, null),
  ('desk_wood', 'desk', 0, null, null, null, null),
  ('desk_white', 'desk', 60, null, null, null, null),
  ('desk_pink', 'desk', 80, null, null, null, null),
  ('chair_wood', 'chair', 0, null, null, null, null),
  ('chair_pink', 'chair', 60, null, null, null, null),
  ('chair_gamer', 'chair', 150, null, null, null, null),
  ('lamp_none', 'lamp', 0, null, null, null, null),
  ('lamp_yellow', 'lamp', 50, null, null, null, null),
  ('lamp_mint', 'lamp', 70, null, null, null, null),
  ('plant_none', 'plant', 0, null, null, null, null),
  ('plant_green', 'plant', 40, null, null, null, null),
  ('plant_cactus', 'plant', 60, null, null, null, null),
  ('plant_flower', 'plant', 90, null, null, null, null),
  ('rug_none', 'rug', 0, null, null, null, null),
  ('rug_red', 'rug', 40, null, null, null, null),
  ('rug_blue', 'rug', 40, null, null, null, null),
  ('rug_rainbow', 'rug', 120, null, null, null, null),
  ('pet_none', 'pet', 0, null, null, null, null),
  ('pet_slime', 'pet', 250, null, null, null, null),
  ('pet_cat', 'pet', 300, null, null, null, null),
  ('pet_dog', 'pet', 300, null, null, null, null),
  ('pet_owl', 'pet', 400, null, null, null, null),
  ('pet_maltese', 'pet', 300, null, null, null, null),
  ('pet_bunny', 'pet', 250, null, null, null, null),
  ('pet_penguin', 'pet', 300, null, null, null, null),
  ('pet_dino', 'pet', 350, null, null, null, null),
  ('pet_dino_pink', 'pet', 350, null, null, null, null),
  ('pet_dino_rex', 'pet', 500, null, null, null, null),
  ('pet_unicorn', 'pet', 1000, null, null, null, null),
  ('pet_phoenix', 'pet', 1200, null, null, null, null),
  ('pet_dragon_gold', 'pet', 1500, null, null, null, null),
  ('hat_rainbow', 'hat', 800, null, null, null, null),
  ('wall_galaxy', 'wall', 600, null, null, null, null),
  ('bed_castle', 'bed', 900, null, null, null, null),
  ('hat_pumpkin', 'hat', 150, null, '10-01', '11-07', null),
  ('pet_bat', 'pet', 350, null, '10-01', '11-07', null),
  ('wall_halloween', 'wall', 200, null, '10-01', '11-07', null),
  ('hat_santa', 'hat', 150, null, '12-01', '12-31', null),
  ('pet_reindeer', 'pet', 400, null, '12-01', '12-31', null),
  ('poster_xmas', 'poster', 120, null, '12-01', '12-31', null),
  ('poster_potion', 'poster', 9999, null, null, null, 'N'),
  ('poster_rune', 'poster', 9999, null, null, null, 'N'),
  ('rug_star', 'rug', 9999, null, null, null, 'N'),
  ('plant_mushroom', 'plant', 9999, null, null, null, 'N'),
  ('lamp_candle', 'lamp', 9999, null, null, null, 'N'),
  ('acc_leaf', 'acc', 9999, null, null, null, 'N'),
  ('hat_witch', 'hat', 9999, null, null, null, 'R'),
  ('top_robe_star', 'top', 9999, null, null, null, 'R'),
  ('pet_frog', 'pet', 9999, null, null, null, 'R'),
  ('wall_rune', 'wall', 9999, null, null, null, 'R'),
  ('acc_moon', 'acc', 9999, null, null, null, 'R'),
  ('pet_blackcat', 'pet', 9999, null, null, null, 'SR'),
  ('hat_crystal', 'hat', 9999, null, null, null, 'SR'),
  ('bed_cloud', 'bed', 9999, null, null, null, 'SR'),
  ('acc_fairy', 'acc', 9999, null, null, null, 'SR'),
  ('pet_dragon_rainbow', 'pet', 9999, null, null, null, 'SSR'),
  ('hat_star_crown', 'hat', 9999, null, null, null, 'SSR'),
  ('wall_aurora', 'wall', 9999, null, null, null, 'SSR'),
  ('hat_grad', 'hat', 9999, 10, null, null, null),
  ('pet_bookfairy', 'pet', 9999, 30, null, null, null),
  ('wall_library', 'wall', 9999, 60, null, null, null),
  ('hat_wiz_gold', 'hat', 9999, 100, null, null, null),
  ('hat_none', 'hat', 0, null, null, null, null),
  ('hat_wiz_p', 'hat', 0, null, null, null, null),
  ('hat_helmet', 'hat', 0, null, null, null, null),
  ('hat_wiz_b', 'hat', 60, null, null, null, null),
  ('hat_cap_r', 'hat', 50, null, null, null, null),
  ('hat_cap_b', 'hat', 50, null, null, null, null),
  ('hat_bunny', 'hat', 150, null, null, null, null),
  ('hat_cat', 'hat', 150, null, null, null, null),
  ('hat_crown', 'hat', 400, null, null, null, null),
  ('top_blue', 'top', 0, null, null, null, null),
  ('top_red', 'top', 0, null, null, null, null),
  ('top_purple', 'top', 0, null, null, null, null),
  ('top_green', 'top', 30, null, null, null, null),
  ('top_yellow', 'top', 30, null, null, null, null),
  ('top_pink', 'top', 30, null, null, null, null),
  ('top_black', 'top', 60, null, null, null, null),
  ('top_white', 'top', 60, null, null, null, null),
  ('hair_brown', 'hair', 0, null, null, null, null),
  ('hair_black', 'hair', 0, null, null, null, null),
  ('hair_blond', 'hair', 0, null, null, null, null),
  ('hair_pink', 'hair', 0, null, null, null, null),
  ('hair_blue', 'hair', 0, null, null, null, null),
  ('skin_1', 'skin', 0, null, null, null, null),
  ('skin_2', 'skin', 0, null, null, null, null),
  ('skin_3', 'skin', 0, null, null, null, null),
  ('skin_4', 'skin', 0, null, null, null, null),
  ('acc_none', 'acc', 0, null, null, null, null),
  ('acc_beard', 'acc', 0, null, null, null, null),
  ('acc_glasses', 'acc', 80, null, null, null, null),
  ('acc_scarf', 'acc', 60, null, null, null, null),
  ('acc_phones', 'acc', 120, null, null, null, null),
  ('acc_cape', 'acc', 200, null, null, null, null),
  ('acc_headband', 'acc', 40, null, null, null, null),
  ('acc_bow', 'acc', 50, null, null, null, null),
  ('acc_bowtie', 'acc', 60, null, null, null, null),
  ('acc_star', 'acc', 70, null, null, null, null),
  ('acc_round', 'acc', 80, null, null, null, null),
  ('acc_pearl', 'acc', 90, null, null, null, null),
  ('acc_halo', 'acc', 250, null, null, null, null),
  ('acc_wings', 'acc', 300, null, null, null, null)
on conflict (id) do update set slot = excluded.slot, price = excluded.price, unlock_cards = excluded.unlock_cards, avail_from = excluded.avail_from, avail_until = excluded.avail_until, gacha = excluded.gacha;
-- SHOP_SEED_END

create or replace function public.item_on_sale(it public.shop_items)
returns boolean language sql stable as $$
  select it.unlock_cards is null and it.gacha is null and (it.avail_from is null
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
  if it.gacha is not null then raise exception '這個只能從魔法盲盒抽到'; end if;
  if it.unlock_cards is not null then raise exception '這個要收集單字卡才能解鎖'; end if;
  if not public.item_on_sale(it) then raise exception '這個限定商品現在沒有販售'; end if;
  if bal < it.price then raise exception '金幣不夠'; end if;
  insert into public.purchases (user_id, item_id, price) values (auth.uid(), p_item, it.price);
  return bal - it.price;
end $$;

create table if not exists public.gacha_state (
  user_id uuid primary key references public.profiles on delete cascade,
  pity int not null default 0,
  day date,
  pulls int not null default 0,
  free_day date
);
alter table public.gacha_state enable row level security;
drop policy if exists "看自己的盲盒紀錄" on public.gacha_state;
create policy "看自己的盲盒紀錄" on public.gacha_state for select to authenticated using (user_id = auth.uid());

create or replace function public.gacha_info()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'pity', coalesce((select pity from public.gacha_state where user_id = auth.uid()), 0),
    'pulls', coalesce((select pulls from public.gacha_state where user_id = auth.uid() and day = public.taipei_today()), 0),
    'free_used', coalesce((select free_day = public.taipei_today() from public.gacha_state where user_id = auth.uid()), false));
$$;

create or replace function public.gacha_pull(p_n int, p_free boolean)
returns json language plpgsql security definer set search_path = public as $$
declare st public.gacha_state; res json[] := '{}'; r float; rar text; it text; got_sr boolean := false; dup boolean; refund int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_n not in (1, 10) then raise exception '一次抽 1 個或 10 個'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  insert into public.gacha_state (user_id) values (auth.uid()) on conflict (user_id) do nothing;
  select * into st from public.gacha_state where user_id = auth.uid() for update;
  if st.day is distinct from public.taipei_today() then st.day := public.taipei_today(); st.pulls := 0; end if;
  if coalesce(p_free, false) then
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
    select id into it from public.shop_items where gacha = rar order by random() limit 1;
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
  update public.gacha_state set pity = st.pity, day = st.day, pulls = st.pulls, free_day = st.free_day where user_id = auth.uid();
  return json_build_object('results', array_to_json(res), 'wallet', public.wallet_balance(auth.uid()), 'pity', st.pity, 'pulls', st.pulls);
end $$;

revoke all on function public.gacha_info() from public, anon;
grant execute on function public.gacha_info() to authenticated;
revoke all on function public.gacha_pull(integer, boolean) from public, anon;
grant execute on function public.gacha_pull(integer, boolean) to authenticated;

