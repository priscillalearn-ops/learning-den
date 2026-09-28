// 產生雙倍挑戰用的答案表 supabase/question_keys.sql（題號、等級、單元、正解）。
// 用法：在 Magic_World_App 資料夾執行  node learning-den/tools/keys-sql.js
// 題庫同步（import-granny.js）之後要重跑，再把 question_keys.sql 貼到 Supabase 執行。
const fs = require('fs');
const path = require('path');
const html = fs.readFileSync(path.join(__dirname, '../index.html'), 'utf8');
const box = {};
for (const key of ['JH', 'HS']) {
  const a = html.indexOf(`/* ${key}_BANK_START */`), b = html.indexOf(`/* ${key}_BANK_END */`);
  new Function('box', html.slice(a, b).replace(/\/\*.*?\*\//, '') + `;box.${key}=${key}_UNITS;`)(box);
}
const rows = [];
const q = s => "'" + String(s).replace(/'/g, "''") + "'";
// 國小題目太少，不開放雙倍挑戰，所以不放答案
for (const [tier, units] of [['teen', box.JH], ['sage', box.HS]])
  units.forEach(u => ['v', 'g', 'c'].forEach(t => (u[t] || []).forEach((r, i) => rows.push(`(${q(`${u.id}:${t}:${i}`)},${q(tier)},${q(u.id)},${r[2]})`))));
let sql = '-- 雙倍挑戰答案表（由 tools/keys-sql.js 產生，不要手改）。整份貼到 Supabase SQL Editor 執行，重跑沒關係。\n';
sql += 'delete from public.question_keys;\n';
for (let i = 0; i < rows.length; i += 500)
  sql += 'insert into public.question_keys (qid, tier, unit, a) values\n' + rows.slice(i, i + 500).join(',\n') + ';\n';
fs.writeFileSync(path.join(__dirname, '../supabase/question_keys.sql'), sql);
console.log(`寫入 ${rows.length} 題答案`);
