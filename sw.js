// Learning Den 離線快取：打開更快、網路不好也能先用。管整個 /learning-den/，包含 GRAM 英語遊戲樂園（/gram/）。
// 頁面「先上網拿最新版，拿不到才用快取」，所以老師更新網站後學生一定拿得到新版；
// 題庫、圖示、字型、Supabase 程式庫「先用快取、背景再更新」。資料庫連線（supabase.co）完全不經過快取。
// GRAM 的聽力音檔（gram/listen/）不放進快取：檔案大，而且 iPhone 播音檔需要分段下載，交給瀏覽器自己處理。
const VER = 'ld-v2';
const SHELL = ['./', 'manifest.webmanifest', 'pwa.js', 'icons/icon-192.png',
  'gram/', 'gram/manifest.webmanifest', 'gram/icons/icon-192.png'];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(VER).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== VER).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
const BASE = new URL('./', self.location).pathname;           // /learning-den/
self.addEventListener('fetch', e => {
  const req = e.request, url = new URL(req.url);
  if (req.method !== 'GET' || url.hostname.endsWith('supabase.co')) return;
  const same = url.origin === location.origin;
  const page = req.mode === 'navigate' || (same && /\/(index\.html)?$/.test(url.pathname));
  if (page) {
    // 離線時：先找這一頁的快取（不管網址後面的 ?invite= 之類），找不到就給那個遊戲的首頁
    const home = same && url.pathname.startsWith(BASE + 'gram/') ? 'gram/' : './';
    e.respondWith(fetch(req).then(r => {
      if (r.ok && same) { const copy = r.clone(); caches.open(VER).then(c => c.put(url.origin + url.pathname, copy)); }
      return r;
    }).catch(() => caches.match(url.origin + url.pathname, { ignoreSearch: true }).then(r => r || caches.match(home))));
    return;
  }
  const mine = same && /\/(banks|icons|screenshots)\//.test(url.pathname) || same && /\/(pwa\.js|manifest\.webmanifest)$/.test(url.pathname);
  const cdn = /(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|fonts\.googleapis\.com|fonts\.gstatic\.com)$/.test(url.hostname);
  if (!mine && !cdn) return;
  e.respondWith(caches.open(VER).then(c => c.match(req).then(hit => {
    const net = fetch(req).then(r => {
      if (r.ok || r.type === 'opaque') {
        c.put(req, r.clone());
        // 題庫換版本（?v= 不一樣）時，把同一個檔案的舊版本刪掉
        if (same && url.search) c.keys().then(ks => ks.forEach(k => { const u = new URL(k.url); if (u.pathname === url.pathname && u.search !== url.search) c.delete(k); }));
      }
      return r;
    }).catch(() => hit);
    return hit || net;
  })));
});
