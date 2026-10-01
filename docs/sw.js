// Learning Den 離線快取：打開更快、網路不好也能先用。
// 主頁面「先上網拿最新版，拿不到才用快取」，所以老師更新網站後學生一定拿得到新版；
// 題庫、圖示、字型、Supabase 程式庫「先用快取、背景再更新」。資料庫連線（supabase.co）完全不經過快取。
const VER = 'ld-v1';
const SHELL = ['./', 'index.html', 'manifest.webmanifest', 'icons/icon-192.png'];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(VER).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== VER).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const req = e.request, url = new URL(req.url);
  if (req.method !== 'GET' || url.hostname.endsWith('supabase.co')) return;
  const page = req.mode === 'navigate' || (url.origin === location.origin && /\/(index\.html)?$/.test(url.pathname));
  if (page) {
    e.respondWith(fetch(req).then(r => { const copy = r.clone(); caches.open(VER).then(c => c.put(req, copy)); return r; })
      .catch(() => caches.match(req).then(r => r || caches.match('index.html'))));
    return;
  }
  const mine = url.origin === location.origin && /\/(banks|icons)\//.test(url.pathname);
  const cdn = /(cdn\.jsdelivr\.net|fonts\.googleapis\.com|fonts\.gstatic\.com)$/.test(url.hostname);
  if (!mine && !cdn) return;
  e.respondWith(caches.open(VER).then(c => c.match(req).then(hit => {
    const net = fetch(req).then(r => { if (r.ok || r.type === 'opaque') c.put(req, r.clone()); return r; }).catch(() => hit);
    return hit || net;
  })));
});
