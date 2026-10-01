// 產生 GitHub Pages 用的 docs/index.html（加上完整的 HTML 外框）。
// 用法：在 Magic_World_App 資料夾執行  node learning-den/tools/build-site.js
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '../index.html'), 'utf8');
const out = path.join(__dirname, '../docs');
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'index.html'),
  '<!doctype html>\n<html lang="zh-Hant">\n<head>\n<meta charset="utf-8">\n' +
  // 加到主畫面時像 App 一樣（只放網站版；Artifact 不需要）
  '<link rel="manifest" href="manifest.webmanifest">\n<meta name="theme-color" content="#2b2140">\n' +
  '<link rel="apple-touch-icon" href="icons/apple-touch-icon.png">\n<link rel="icon" href="icons/icon-192.png">\n' +
  '<meta name="apple-mobile-web-app-capable" content="yes">\n<meta name="apple-mobile-web-app-title" content="Learning Den">\n' +
  '<meta name="apple-mobile-web-app-status-bar-style" content="black">\n' +
  src.replace(/<\/style>\n/, '</style>\n</head>\n<body>\n') +
  // 離線快取（只有網站版；Artifact 裡不註冊）
  "\n<script>if('serviceWorker' in navigator&&window.top===window)navigator.serviceWorker.register('sw.js').catch(()=>{})</script>" +
  '\n</body>\n</html>\n');
for (const f of ['privacy.html', 'about.html', 'manifest.webmanifest', 'sw.js']) fs.copyFileSync(path.join(__dirname, '..', f), path.join(out, f));
fs.cpSync(path.join(__dirname, '../icons'), path.join(out, 'icons'), { recursive: true });
fs.cpSync(path.join(__dirname, '../banks'), path.join(out, 'banks'), { recursive: true });
// 每日打卡提醒：給 iPhone／其他行事曆用的 .ics（每天重複，時間到跳通知）
const SITE = 'https://priscillalearn-ops.github.io/learning-den/';
fs.mkdirSync(path.join(out, 'reminders'), { recursive: true });
for (const t of ['0700', '1230', '1700', '1800', '1900', '2000', '2100', '2200']) {
  const ics = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Learning Den//Reminder//ZH', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    'BEGIN:VTIMEZONE', 'TZID:Asia/Taipei', 'BEGIN:STANDARD', 'DTSTART:19700101T000000', 'TZOFFSETFROM:+0800', 'TZOFFSETTO:+0800', 'TZNAME:CST', 'END:STANDARD', 'END:VTIMEZONE',
    'BEGIN:VEVENT', `UID:learning-den-reminder-${t}@priscillalearn-ops.github.io`, 'DTSTAMP:20260928T000000Z',
    `DTSTART;TZID=Asia/Taipei:20260929T${t}00`, 'DURATION:PT10M', 'RRULE:FREQ=DAILY',
    'SUMMARY:Learning Den 打卡時間', `DESCRIPTION:答今日一題或專注一次，連續天數不要斷！ ${SITE}`, `URL:${SITE}`,
    'BEGIN:VALARM', 'ACTION:DISPLAY', 'DESCRIPTION:Learning Den 打卡時間', 'TRIGGER:PT0M', 'END:VALARM',
    'END:VEVENT', 'END:VCALENDAR'].join('\r\n') + '\r\n';
  fs.writeFileSync(path.join(out, 'reminders', t + '.ics'), ics);
}
console.log('已產生 docs/：index.html、privacy.html、manifest、icons、reminders');
