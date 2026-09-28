// 把「恐怖阿嬤逃脫」主站的高中題庫（UNITS、PRESETS）搬進 Learning Den：
// （國中題庫改成原創題，由 tools/jh-bank.py 產生，不再從阿嬤搬）
//   高中（HS）← granny-escape-b3l1 主站
// 用法：在 Magic_World_App 資料夾執行  node learning-den/tools/import-granny.js
// 阿嬤那邊的題庫更新後，重跑一次就會同步。
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../..');
const DST = path.join(__dirname, '../index.html');
const SOURCES = [
  { key: 'HS', label: '高中', file: 'granny-escape-b3l1/index.html' }
];

function extract(file) {
  const src = fs.readFileSync(path.join(ROOT, file), 'utf8');
  const a = src.indexOf('const UNITS=['), b = src.indexOf('const TAGNAME');
  if (a < 0 || b < 0) throw new Error(`在 ${file} 找不到 UNITS 或 PRESETS`);
  const box = {};
  new Function('box', src.slice(a, b) + ';box.UNITS=UNITS;box.PRESETS=PRESETS;')(box);
  const units = box.UNITS.map(u => ({
    id: u.id, pub: u.pub, grade: u.grade, name: u.name, short: u.short, src: u.src,
    v: u.v || [], g: u.g || [], c: u.c || []
  }));
  const ids = new Set(units.map(u => u.id));
  return { units, presets: box.PRESETS.filter(p => p.ids.every(i => ids.has(i))) };
}

let dst = fs.readFileSync(DST, 'utf8');
for (const { key, label, file } of SOURCES) {
  const { units, presets } = extract(file);
  const START = `/* ${key}_BANK_START */`, END = `/* ${key}_BANK_END */`;
  const s = dst.indexOf(START), e = dst.indexOf(END);
  if (s < 0 || e < 0) throw new Error(`Word Den 的 index.html 裡找不到 ${key}_BANK 標記`);
  const block = `${START}\nconst ${key}_UNITS=${JSON.stringify(units)};\nconst ${key}_PRESETS=${JSON.stringify(presets)};\n${END}`;
  dst = dst.slice(0, s) + block + dst.slice(e + END.length);
  const total = units.reduce((n, u) => n + u.v.length + u.g.length + u.c.length, 0);
  console.log(`${label}：${units.length} 個單元、${total} 題、${presets.length} 個組合包`);
}
fs.writeFileSync(DST, dst);
