# 宣傳影片

1. 做一份帶示範資料的 app.html（index.html 的單機版＋種子資料，場景用網址 #city、#daily… 切換），放在這個資料夾。
2. `python3 shoot.py city daily room home shop games kid me`：用 Chrome headless 截圖到 shots/。
3. 下載字型 Cubic_11.ttf（俐方體 11 號，SIL OFL 1.1：https://github.com/ACh-K/Cubic-11）到這個資料夾。
4. `python3 make_video.py`：產生 1080×1920、32 秒、配原創 8-bit 音樂的 MP4（需要 `pip install imageio-ffmpeg qrcode`）。

字型與截圖不放進 repo。
5. 旁白：`vo/lines.txt` 每行「場景|台詞」，用 macOS 的美佳配音：`say -v Meijia -r 185 -o vo/場景.aiff "台詞"`，再用 ffmpeg 轉成 44.1kHz 單聲道 wav。影片長度依旁白自動調整，字幕也從 lines.txt 來。
6. `make_video.py` 最上面的 `VOICE = False` 是不要人聲的版本（只有標題字卡和音樂）；改成 True 就會加上旁白和字幕。
7. 題庫現在是 banks/*.json，要用本機伺服器截圖：把示範頁放在 learning-den/ 底下，用 `BASE=http://localhost:8780/示範頁.html python3 shoot.py …`；headless Chrome 常抓不到 Google 字型，要用 @font-face 指向本機的 DotGothic16.ttf。
