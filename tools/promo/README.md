# 宣傳影片

1. 做一份帶示範資料的 app.html（index.html 的單機版＋種子資料，場景用網址 #city、#daily… 切換），放在這個資料夾。
2. `python3 shoot.py city daily room home shop games kid me`：用 Chrome headless 截圖到 shots/。
3. 下載字型 Cubic_11.ttf（俐方體 11 號，SIL OFL 1.1：https://github.com/ACh-K/Cubic-11）到這個資料夾。
4. `python3 make_video.py`：產生 1080×1920、32 秒、配原創 8-bit 音樂的 MP4（需要 `pip install imageio-ffmpeg qrcode`）。

字型與截圖不放進 repo。
5. 旁白：`vo/lines.txt` 每行「場景|台詞」，用 macOS 的美佳配音：`say -v Meijia -r 185 -o vo/場景.aiff "台詞"`，再用 ffmpeg 轉成 44.1kHz 單聲道 wav。影片長度依旁白自動調整，字幕也從 lines.txt 來。
