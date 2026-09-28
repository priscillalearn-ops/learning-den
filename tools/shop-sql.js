// 把 index.html 裡 SHOP 目錄的價格同步到 supabase/schema.sql（SHOP_SEED 區塊）。
// 用法：在 Magic_World_App 資料夾執行  node learning-den/tools/shop-sql.js
// 改了商品或價格之後跑一次，再把 schema.sql 貼到 Supabase 重跑。
const fs = require('fs');
const path = require('path');
const html = fs.readFileSync(path.join(__dirname, '../index.html'), 'utf8');
const a = html.indexOf('/* SHOP_START */'), b = html.indexOf('/* SHOP_END */');
if (a < 0 || b < 0) throw new Error('index.html 裡找不到 SHOP_START／SHOP_END');
const SHOP = new Function(html.slice(a, b) + ';return SHOP;')();
const q = s => "'" + String(s).replace(/'/g, "''") + "'";
const rows = SHOP.map(i => `  (${q(i.id)}, ${q(i.slot)}, ${i.price})`).join(',\n');
const block = `-- SHOP_SEED_START\ninsert into public.shop_items (id, slot, price) values\n${rows}\non conflict (id) do update set slot = excluded.slot, price = excluded.price;\n-- SHOP_SEED_END`;
const f = path.join(__dirname, '../supabase/schema.sql');
const sql = fs.readFileSync(f, 'utf8');
const s = sql.indexOf('-- SHOP_SEED_START'), e = sql.indexOf('-- SHOP_SEED_END');
fs.writeFileSync(f, sql.slice(0, s) + block + sql.slice(e + '-- SHOP_SEED_END'.length));
console.log(`已寫入 ${SHOP.length} 個商品的價格`);
