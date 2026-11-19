# Threads 聖誕盲盒影片（2026-11-19）

只在本機錄影用，不會改到線上機率。

1. `python3 make_rec_page.py <learning-den 路徑>`：產生 `_rec.html`（單機版、日期設成 12/1 讓降臨月曆打開、盲盒照劇本開：20 抽裡 1 個 SSR，十連保底的 SR 照規則保留）。字型 DotGothic16.ttf 複製成 `_rec_font.ttf`。
2. 在 learning-den 資料夾開 `python3 -m http.server 8780`，跑 `node record.js`（Playwright，CDP 逐幀錄影到 /tmp/claude-0/sp/rec）。
3. 下載 Cubic_11.ttf 到 /tmp/claude-0/sp/fonts，跑 `python3 compose.py 輸出.mp4`。
4. 錄完刪掉 `_rec.html`、`_rec_font.ttf`。
