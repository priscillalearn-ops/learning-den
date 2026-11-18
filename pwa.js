// 網站版專用（Artifact 不載入）：離線快取＋「加到主畫面」小提示。Learning Den 和 GRAM 共用這一支。
// 用法：<script src="pwa.js" data-name="Learning Den" defer></script>（GRAM 用 ../pwa.js）
(function () {
  var me = document.currentScript;
  if (!me || window.top !== window) return;
  // App（Capacitor）裡面不用：App 本身已經在主畫面上了
  if (window.Capacitor && Capacitor.isNativePlatform && Capacitor.isNativePlatform()) return;

  // 一支 service worker 管整個 /learning-den/（含 /gram/）
  if ('serviceWorker' in navigator) navigator.serviceWorker.register(new URL('sw.js', me.src).href).catch(function () {});

  var NAME = me.getAttribute('data-name') || document.title;
  var KEY = 'ld.pwa.hide';
  var standalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  if (standalone) return;
  try { if (Date.now() < +localStorage.getItem(KEY)) return; } catch (e) {}

  var ua = navigator.userAgent;
  var ios = /iPhone|iPad|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  var line = /\bLine\//i.test(ua);
  var inApp = line || /Instagram|FBAN|FBAV|FB_IAB|Threads|MicroMessenger|Messenger/i.test(ua);
  var iosSafari = ios && /Safari\//.test(ua) && !/CriOS|FxiOS|EdgiOS/.test(ua) && !inApp;
  var deferred = null, shown = false;

  function hide(days) {
    try { localStorage.setItem(KEY, String(Date.now() + days * 864e5)); } catch (e) {}
    var el = document.getElementById('pwa-tip'); if (el) el.remove();
  }
  function show(msg, btnText, onBtn) {
    if (shown) return; shown = true;
    var st = document.createElement('style');
    st.textContent = '#pwa-tip{position:fixed;left:50%;top:calc(env(safe-area-inset-top,0px) + 10px);transform:translateX(-50%);z-index:99;' +
      'width:min(92vw,420px);display:flex;align-items:center;gap:10px;padding:10px 12px;background:#fff8e6;color:#2b2140;' +
      'border:3px solid #2b2140;box-shadow:4px 4px 0 rgba(0,0,0,.35);font:14px/1.45 system-ui,"PingFang TC","Microsoft JhengHei",sans-serif}' +
      '#pwa-tip p{margin:0;flex:1}#pwa-tip button{font:inherit;cursor:pointer;border:2px solid #2b2140;padding:6px 10px;background:#ffd166;color:#2b2140;white-space:nowrap}' +
      '#pwa-tip .x{background:none;border:0;padding:4px 6px;font-size:18px;line-height:1}';
    document.head.appendChild(st);
    var box = document.createElement('div'); box.id = 'pwa-tip'; box.setAttribute('role', 'status');
    var p = document.createElement('p'); p.textContent = msg; box.appendChild(p);
    if (btnText) { var b = document.createElement('button'); b.textContent = btnText; b.onclick = onBtn; box.appendChild(b); }
    var x = document.createElement('button'); x.className = 'x'; x.setAttribute('aria-label', '關閉'); x.textContent = '×';
    x.onclick = function () { hide(14); }; box.appendChild(x);
    document.body.appendChild(box);
  }

  // Android／電腦的 Chrome、Edge：攔下瀏覽器的安裝提示，改成我們自己的小按鈕
  addEventListener('beforeinstallprompt', function (e) {
    e.preventDefault(); deferred = e;
    setTimeout(function () {
      show('把「' + NAME + '」加到主畫面，下次一點就開，全螢幕更好玩。', '安裝', function () {
        if (!deferred) return hide(14);
        deferred.prompt();
        deferred.userChoice.then(function (r) { hide(r.outcome === 'accepted' ? 3650 : 14); });
        deferred = null;
      });
    }, 15000);
  });
  addEventListener('appinstalled', function () { hide(3650); });

  setTimeout(function () {
    if (line) {
      // LINE 內建瀏覽器認得 openExternalBrowser=1，會改用手機的瀏覽器打開
      show('在 LINE 裡沒辦法加到主畫面，改用瀏覽器打開就可以安裝。', '用瀏覽器開', function () {
        var u = new URL(location.href); u.searchParams.set('openExternalBrowser', '1'); location.href = u.href;
      });
    } else if (inApp) {
      show('想加到主畫面的話，點右上角「⋯」選「用瀏覽器開啟」。', null, null);
    } else if (iosSafari) {
      show('加到主畫面：點分享鍵（方框加向上箭頭，新版 iOS 在「⋯」裡），再選「加入主畫面」。', '知道了', function () { hide(30); });
    }
  }, 15000);
})();
