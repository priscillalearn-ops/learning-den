# 把錄好的畫面組成 1080×1920 直式影片：上方字卡、中間手機畫面、最後 QR 收尾，配原創 8-bit 音樂
import json, bisect, math, random, struct, subprocess, wave, os, sys
from PIL import Image, ImageDraw, ImageFont
import qrcode
SP = '/tmp/claude-0/sp'; OUT = sys.argv[1]
W, H, FPS = 1080, 1920, 30
NIGHT, INK, PAPER, GOLD, LILAC, MINT, CORAL = (43, 33, 64), (15, 10, 26), (244, 236, 216), (255, 209, 102), (199, 184, 232), (159, 225, 203), (255, 138, 92)
URL = "priscillalearn-ops.github.io/learning-den"
PIX = SP + '/fonts/Cubic_11.ttf'; HEI = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc'
_fc = {}
def font(path, size):
    k = (path, size)
    if k not in _fc: _fc[k] = ImageFont.truetype(path, size)
    return _fc[k]
_has = {}
def has_glyph(ch):
    if ch not in _has:
        f = font(PIX, 32); m = lambda c: bytes(f.getmask(c)); _has[ch] = ch == " " or m(ch) != m(chr(0xFFFF))
    return _has[ch]
def fnt(c, size): return font(PIX, size) if has_glyph(c) else font(HEI, int(size * .92))
def text_w(s, size): return sum(fnt(c, size).getlength(c) for c in s)
def draw_text(d, xy, s, size, fill, anchor="mt", shadow=True):
    x, y = xy; w = text_w(s, size)
    if anchor[0] == "m": x -= w / 2
    for off, col in ([((5, 5), INK)] if shadow else []) + [((0, 0), fill)]:
        cx = x + off[0]
        for c in s:
            f = fnt(c, size); d.text((cx, y + off[1] + (0 if has_glyph(c) else size * .04)), c, font=f, fill=col); cx += f.getlength(c)

# ---------- 素材：錄影幀 ----------
D = json.load(open(SP + '/rec/frames.json')); FR = D['frames']; T0 = FR[0][1]
TS = [f[1] - T0 for f in FR]; M = {k: t - T0 for k, t in D['marks']}
_cache = {}
def src_frame(t):
    i = max(0, bisect.bisect_right(TS, t) - 1); fn = FR[i][0]
    if fn not in _cache:
        if len(_cache) > 40: _cache.clear()
        _cache[fn] = Image.open(fn).convert('RGB').resize((PW, PH), Image.LANCZOS)
    return _cache[fn]
PW = 640; PH = int(1688 * PW / 780); PX = (W - PW) // 2; PY = 360

# ---------- 剪輯表：(來源起點, 來源終點, 速度, 大字, 小字) ----------
CUTS = [
 (0.2, M['tree'], 1.0, "走去廣場的聖誕樹", "英文讀書小鎮 Learning Den"),
 (M['tree'], M['walk2'] - .3, 1.0, "答對聖誕單字 開一格月曆", "12/1～12/25 每天一格・開滿送限定寵物"),
 (M['walk2'], M['room'], 2.2, "再去讀書房", "跟同年級的人一起專注"),
 (M['room'], M['walk3'] - .3, 1.0, "留言互相打氣", "讀書不再是一個人"),
 (M['walk3'], M['gacha'], 2.2, "讀完書 去抽盲盒！", "金幣只能靠讀書賺"),
 (M['gacha'], M['ten2'] - .2, 1.0, "十連抽 ×2 = 20 抽", "第一輪…保底的 SR 而已"),
 (M['ten2'] - .2, M['ten2'] + 1.05, 1.0, "第二輪…", "拜託拜託拜託"),
 (M['ten2'] + 1.05, M['end'] - .2, 1.0, "第 16 抽 出 SSR 了！！", "其他 19 抽都很普通 XD"),
]
SEG = []; t = 0
for a, b, sp, big, small in CUTS:
    dur = (b - a) / sp; SEG.append((t, dur, a, sp, big, small)); t += dur
CLIP = t; END = 4.5; DUR = CLIP + END
print('clip', round(CLIP, 1), 'total', round(DUR, 1))

random.seed(7)
STARS = [(random.randrange(W), random.randrange(H), random.choice([4, 6, 8]), random.random() * 6) for _ in range(90)]
def background(t):
    im = Image.new("RGB", (W, H), NIGHT); d = ImageDraw.Draw(im)
    for x, y, s, ph in STARS:
        a = .35 + .65 * (0.5 + 0.5 * math.sin(t * 2 + ph)); col = tuple(int(NIGHT[i] + (GOLD[i] - NIGHT[i]) * a * .8) for i in range(3))
        yy = (y + t * 12) % H; d.rectangle([x, yy, x + s - 1, yy + s - 1], fill=col)
    return im
def ease(x): x = max(0, min(1, x)); return 1 - (1 - x) ** 3

COIN = ['..yyyy..', '.yyyyyy.', 'yyoyyyyy', 'yyoyyyyy', 'yyoyyyyy', 'yyyyyyyy', '.yyyyyy.', '..yyyy..']
def coin(z):
    im = Image.new("RGBA", (8 * z, 8 * z)); d = ImageDraw.Draw(im)
    for y, r in enumerate(COIN):
        for x, ch in enumerate(r):
            if ch != '.': d.rectangle([x * z, y * z, x * z + z - 1, y * z + z - 1], fill={'y': '#ffd166', 'o': '#c98a3a'}[ch])
    return im
COIN7 = coin(7)

def clip_frame(t):
    i = max(k for k in range(len(SEG)) if SEG[k][0] <= t)
    t0, dur, a, sp, big, small = SEG[i]; lt = t - t0
    im = background(t); d = ImageDraw.Draw(im)
    # 字卡：換段才有進場動畫（同一個大字延續就不動）
    fresh = i == 0 or SEG[i - 1][4] != big; k = ease(lt / .45) if fresh else 1
    col = GOLD if 'SSR' not in big else (255, 225, 120)
    sz = 86 if text_w(big, 86) < 1000 else int(86 * 1000 / text_w(big, 86))
    draw_text(d, (W / 2, 110 + (1 - k) * 40), big, sz, col)
    if lt > .2 or not fresh: draw_text(d, (W / 2, 232), small, 44, PAPER)
    # 手機畫面
    fr = src_frame(a + lt * sp)
    d.rectangle([PX - 14, PY - 14, PX + PW + 13, PY + PH + 13], fill=INK); d.rectangle([PX - 9, PY - 9, PX + PW + 8, PY + PH + 8], outline=GOLD, width=4)
    im.paste(fr, (PX, PY))
    if sp > 1: tx_ = f">> x{sp:g}"; d.rectangle([PX + PW - 30 - text_w(tx_, 34), PY + 10, PX + PW - 10, PY + 58], fill=INK); draw_text(d, (PX + PW - 20 - text_w(tx_, 34), PY + 14), tx_, 34, MINT, anchor="lt", shadow=False)
    # SSR 那段閃一下
    if 'SSR' in big:
        f = max(0, 1 - abs(lt - .25) / .4)
        if f > 0: im = Image.blend(im, Image.new("RGB", (W, H), (255, 236, 160)), f * .35)
    d = ImageDraw.Draw(im)
    im.paste(COIN7, (60, PY + PH + 40), COIN7)
    draw_text(d, (130, PY + PH + 42), "LEARNING DEN", 44, GOLD, anchor="lt", shadow=False)
    draw_text(d, (W - 60 - text_w("12/1 開放降臨月曆", 34), PY + PH + 50), "12/1 開放降臨月曆", 34, LILAC, anchor="lt", shadow=False)
    return im

qr = qrcode.QRCode(border=2, box_size=14); qr.add_data("https://" + URL + "/"); qr.make(fit=True)
QR = qr.make_image(fill_color="#1a1026", back_color="#f4ecd8").convert("RGB")
def end_frame(t):
    im = background(CLIP + t); d = ImageDraw.Draw(im); k = ease(t / .6)
    draw_text(d, (W / 2, 230 - (1 - k) * 60), "邊讀書邊玩", 99, GOLD)
    draw_text(d, (W / 2, 380), "LEARNING DEN", 99, PAPER)
    draw_text(d, (W / 2, 510), "陪你一起讀書啦", 66, LILAC)
    q = QR.resize((520, 520), Image.NEAREST); x = W // 2 - 280
    d.rectangle([x, 640, x + 559, 1199], fill=INK); d.rectangle([x + 6, 646, x + 553, 1193], outline=GOLD, width=5); im.paste(q, (x + 20, 660))
    draw_text(d, (W / 2, 1260), "掃 QR code 或搜尋網址", 44, PAPER)
    draw_text(d, (W / 2, 1335), URL, 33, MINT)
    draw_text(d, (W / 2, 1420), "免費・手機打開就能玩", 55, GOLD)
    draw_text(d, (W / 2, 1500), "高中・學測・多益單字都有", 44, LILAC)
    if t > END - .5: im = Image.blend(im, Image.new("RGB", (W, H), (0, 0, 0)), (t - (END - .5)) / .5)
    if t < .25: im = Image.blend(Image.new("RGB", (W, H), NIGHT), im, t / .25)
    return im
def frame(t): return clip_frame(t) if t < CLIP else end_frame(t - CLIP)

# ---------- 原創 8-bit 背景音樂（跟 tools/promo/make_video.py 同一首，C–Am–F–G） ----------
def make_music(path, dur):
    sr = 44100; n = int(sr * dur); buf = [0.0] * n
    note = lambda m: 440 * 2 ** ((m - 69) / 12)
    chords = [(48, [60, 64, 67, 72]), (45, [57, 60, 64, 69]), (41, [53, 57, 60, 65]), (43, [55, 59, 62, 67])]
    melody = [[72, 76, 79, 76, 74, 72, 74, 76], [76, 72, 69, 72, 76, 79, 76, 72], [77, 76, 74, 72, 69, 72, 74, 77], [79, 77, 76, 74, 71, 74, 79, 83],
              [84, 79, 76, 79, 81, 79, 76, 72], [76, 74, 72, 69, 72, 74, 76, 81], [77, 81, 84, 81, 79, 77, 76, 74], [74, 76, 77, 79, 74, 71, 67, 71]]
    beat = .25
    def add(start, length, freq, vol, wavef):
        s0 = int(start * sr); s1 = min(n, int((start + length) * sr))
        for i in range(s0, s1):
            tt = (i - s0) / sr; env = min(1, tt * 60) * max(0, 1 - tt / length) ** .6; buf[i] += wavef(freq * tt) * vol * env
    sq = lambda ph: 1 if (ph % 1) < .5 else -1
    tri = lambda ph: 4 * abs((ph % 1) - .5) - 1
    bars = int(dur // 2) + 1
    for b in range(bars):
        root, arp = chords[b % 4]; t0 = b * 2; mel = melody[b % 8] if b >= 2 else None
        for k in range(8):
            add(t0 + k * beat, beat * .95, note(root - 12 + (12 if k % 2 else 0)), .16, tri)
            if mel: add(t0 + k * beat, beat * .8, note(mel[k]), .07, sq)
            add(t0 + k * beat, beat * .5, note(arp[k % 4] + 12), .025, sq)
        for k in range(8):
            s0 = int((t0 + k * beat) * sr)
            for i in range(s0, min(n, s0 + int(.03 * sr))):
                buf[i] += (random.random() * 2 - 1) * .05 * (1 - (i - s0) / (.03 * sr)) * (1.6 if k % 4 == 2 else .6)
    # SSR 出現時加一段上升琶音
    ssr = SEG[-1][0] + .1
    for j, m in enumerate([72, 76, 79, 84, 88, 91, 96]): add(ssr + j * .07, .5, note(m), .09, sq)
    fade = int(1.2 * sr)
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); data = bytearray()
        for i, v in enumerate(buf):
            if i > n - fade: v *= (n - i) / fade
            data += struct.pack("<h", int(max(-1, min(1, v)) * 30000))
        w.writeframes(bytes(data))
music = SP + '/music.wav'; make_music(music, DUR)
p = subprocess.Popen(['ffmpeg', "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
    "-i", music, "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "19", "-preset", "medium", "-profile:v", "high", "-c:a", "aac", "-b:a", "160k",
    "-shortest", "-movflags", "+faststart", OUT], stdin=subprocess.PIPE)
N = int(DUR * FPS)
for f in range(N):
    im = frame(f / FPS); p.stdin.write(im.tobytes())
    if f % (FPS * 3) == 0: im.resize((270, 480)).save(f"{SP}/pv/{f // FPS:03d}.png")
p.stdin.close(); p.wait()
print("done", OUT, round(os.path.getsize(OUT) / 1e6, 1), "MB", round(DUR, 1), "s")
