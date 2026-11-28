// 把 index.html 裡 SHOP 目錄的價格同步到 supabase/schema.sql（SHOP_SEED 區塊）。
// 用法：在 Magic_World_App 資料夾執行  node learning-den/tools/shop-sql.js
// 盲盒商品標 old:1 會寫成 gacha_off = true（絕版，抽不到；抽過的人照樣保留）。
// 改了商品或價格之後跑一次，再把 schema.sql 貼到 Supabase 重跑。
const fs = require('fs');
const path = require('path');
const html = fs.readFileSync(path.join(__dirname, '../index.html'), 'utf8');
const a = html.indexOf('/* SHOP_START */'), b = html.indexOf('/* SHOP_END */');
if (a < 0 || b < 0) throw new Error('index.html 裡找不到 SHOP_START／SHOP_END');
const SHOP = new Function(html.slice(a, b) + ';return SHOP;')();
const q = s => "'" + String(s).replace(/'/g, "''") + "'";
const n = v => v == null ? 'null' : v;
const rows = SHOP.map(i => `  (${q(i.id)}, ${q(i.slot)}, ${i.price}, ${n(i.cards)}, ${i.from ? q(i.from) : 'null'}, ${i.until ? q(i.until) : 'null'}, ${i.gacha ? q(i.gacha) : 'null'}, ${i.bundle ? q(i.bundle) : 'null'}, ${i.old ? 'true' : 'false'})`).join(',\n');
const block = `-- SHOP_SEED_START\ninsert into public.shop_items (id, slot, price, unlock_cards, avail_from, avail_until, gacha, bundle, gacha_off) values\n${rows}\non conflict (id) do update set slot = excluded.slot, price = excluded.price, unlock_cards = excluded.unlock_cards, avail_from = excluded.avail_from, avail_until = excluded.avail_until, gacha = excluded.gacha, bundle = excluded.bundle, gacha_off = excluded.gacha_off;\n-- SHOP_SEED_END`;
const f = path.join(__dirname, '../supabase/schema.sql');
const sql = fs.readFileSync(f, 'utf8');
const s = sql.indexOf('-- SHOP_SEED_START'), e = sql.indexOf('-- SHOP_SEED_END');
fs.writeFileSync(f, sql.slice(0, s) + block + sql.slice(e + '-- SHOP_SEED_END'.length));
console.log(`已寫入 ${SHOP.length} 個商品的價格`);
