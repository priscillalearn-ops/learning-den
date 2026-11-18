# Learning Den 陪你一起讀書啦

像素風的英文學習社群原型：每日一題＋一起專注的讀書房＋單字卡收集，分國小／國中／高中三個等級。

**網址**：https://priscillalearn-ops.github.io/learning-den/

- `index.html`：原始檔（也用來發佈 Claude Artifact）
- `docs/index.html`：GitHub Pages 用的版本，由 `node learning-den/tools/build-site.js` 產生，不要手改
- `docs/gram/`：GRAM 英語遊戲樂園（英檢 A–D 組聽力＋閱讀練習遊戲），網址 https://priscillalearn-ops.github.io/learning-den/gram/ ，由 `python3 tools/build-gram.py <artifact 原始 html> <listen 資料夾>` 產生；全班排行榜用同一個 Supabase，資料表與函式在 `supabase/update-2026-10-21c-格蘭英語遊戲排行榜.sql`
- `app/`：iPhone／Android App 外殼（Capacitor）。App 直接開網站版，所以網站更新 App 就跟著更新，不用重新送審；登入時開系統瀏覽器，登入完用 `learningden://login` 跳回 App（Supabase 的 Redirect URLs 要加這一行）。Android 由 GitHub Actions「Android App」自動產生 APK／AAB
- `pwa.js`、`sw.js`、`manifest.webmanifest`、`gram-site/`：可以「加到主畫面」的 PWA。Learning Den（`/learning-den/`）和 GRAM（`/learning-den/gram/`）各自有 manifest 和圖示，可以分開安裝；兩邊共用同一支 service worker。圖示用 `python3 tools/make-pwa-icons.py` 產生，改完跑 `node tools/build-site.js` 同步到 `docs/`
  - 之後包成 Google Play 版（TWA，用 Bubblewrap 或 PWABuilder）時，Google 要求在網域根目錄放 `https://priscillalearn-ops.github.io/.well-known/assetlinks.json`。這個路徑不在這個儲存庫裡，要另外建一個名叫 `priscillalearn-ops.github.io` 的儲存庫放這個檔案（或改用自己的網域）
- `tools/import-granny.js`：從恐怖阿嬤逃脫同步高中題庫
- `tools/jh-bank.py`、`tools/gept-kid.py`：產生國中、國小原創題庫

目前是單機原型：其他玩家、答題人數、留言都是模擬的，資料只存在各自的瀏覽器。

## 授權

非營利教育用途，原創內容以 CC BY-NC-SA 4.0 授權，詳見 [LICENSE.md](LICENSE.md) 與網站的「關於與版權」頁。
