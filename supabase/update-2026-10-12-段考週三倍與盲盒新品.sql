
 ˇ
-- =====================================================================
-- 段考週 ×3、盲盒秋季新品（2026-10-12 更新；整份重跑即可）
-- =====================================================================
-- 段考週：10/12～10/18 答題、專注、任務金幣 ×3，盲盒券掉落一樣 40%
insert into public.app_events (name, start_day, end_day, mult, drop_rate)
  values ('段考週加成', '2026-10-12', '2026-10-18', 3, 0.4)
  on conflict (name, start_day) do update set end_day = excluded.end_day, mult = excluded.mult, drop_rate = excluded.drop_rate;

-- 盲盒秋季新品 10 款（N：楓葉髮夾、楓葉海報、秋葉地毯；R：紅色貝雷帽、小刺蝟、紅燈籠；SR：九尾狐、花冠；SSR：月兔、星河魔法帽）
insert into public.shop_items (id, slot, price, unlock_cards, avail_from, avail_until, gacha, bundle) values
  ('acc_maple', 'acc', 9999, null, null, null, 'N', null),
  ('poster_maple', 'poster', 9999, null, null, null, 'N', null),
  ('rug_autumn', 'rug', 9999, null, null, null, 'N', null),
  ('hat_beret', 'hat', 9999, null, null, null, 'R', null),
  ('pet_hedgehog', 'pet', 9999, null, null, null, 'R', null),
  ('lamp_lantern', 'lamp', 9999, null, null, null, 'R', null),
  ('pet_fox', 'pet', 9999, null, null, null, 'SR', null),
  ('acc_flowercrown', 'acc', 9999, null, null, null, 'SR', null),
  ('pet_moonrabbit', 'pet', 9999, null, null, null, 'SSR', null),
  ('hat_galaxy', 'hat', 9999, null, null, null, 'SSR', null)
on conflict (id) do update set slot = excluded.slot, price = excluded.price, unlock_cards = excluded.unlock_cards, avail_from = excluded.avail_from, avail_until = excluded.avail_until, gacha = excluded.gacha, bundle = excluded.bundle;
