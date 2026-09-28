# Learning Den 宣傳影片：1080×1920、30fps、約 32 秒，配原創 8-bit 背景音樂
import math, random, struct, subprocess, wave, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import imageio_ffmpeg, qrcode

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = "/Users/priscilla/Desktop/Magic_World_App/Learning_Den_宣傳影片.mp4"
W, H, FPS = 1080, 1920, 30
NIGHT, INK, PAPER, GOLD, LILAC, MINT, CORAL = (43, 33, 64), (15, 10, 26), (244, 236, 216), (255, 209, 102), (199, 184, 232), (159, 225, 203), (255, 138, 92)
URL = "priscillalearn-ops.github.io/learning-den"

# ---------- 字型：像素字沒有的字（繁體）改用黑體 ----------
PIX = os.path.join(HERE, "Cubic_11.ttf")  # 俐方體 11 號（SIL OFL 1.1）
HEI = "/System/Library/Fonts/STHeiti Medium.ttc"
_fc = {}
def font(path, size):
    k = (path, size)
    if k not in _fc: _fc[k] = ImageFont.truetype(path, size)
    return _fc[k]
_missing = {}
def has_glyph(ch):
    if ch not in _missing:
        f = font(PIX, 32)
        m = lambda c: bytes(f.getmask(c)); _missing[ch] = ch == " " or m(ch) != m(chr(0xFFFF))
    return _missing[ch]
def text_w(s, size):
    return sum((font(PIX, size) if has_glyph(c) else font(HEI, size)).getlength(c) for c in s)
def draw_text(d, xy, s, size, fill, anchor="mt", shadow=True):
    x, y = xy; w = text_w(s, size)
    if anchor[0] == "m": x -= w / 2
    for off, col in ([((5, 5), INK)] if shadow else []) + [((0, 0), fill)]:
        cx = x + off[0]
        for c in s:
            f = font(PIX, size) if has_glyph(c) else font(HEI, int(size * .92))
            d.text((cx, y + off[1] + (0 if has_glyph(c) else size * .04)), c, font=f, fill=col)
            cx += f.getlength(c)

# ---------- 像素角色（跟 App 裡同一套圖） ----------
PAL = {'p': '#8a5cd6', 's': '#f2c79b', 'k': '#1a1026', 'b': '#3a7bd5', 'g': '#9aa3b5', 'r': '#d94f4f', 'w': '#f4ecd8', 'y': '#ffd166',
       'o': '#c98a3a', 't': '#5dcaa5', 'G': '#4caf50', 'c': '#2b2b33', 'n': '#1d2a5c'}
SPR = {
 'kid': ['...pp...', '..ppyp..', '.pppppp.', '..ssss..', '..ksks..', '..ssss..', '.pbbbbp.', '..b..b..'],
 'teen': ['..gggg..', '.gggggg.', '.gkgkgg.', '.gssssg.', '..ssss..', '.rgggr..', '.rrrrrr.', '..g..g..'],
 'sage': ['...pp...', '..pppp..', '.pppppp.', '..ssss..', '..ksks..', '..wwww..', '.pwwwwp.', '..p..p..'],
 'king': ['........', '.y.yy.y.', '.yyyyyy.', '..ssss..', '..ksks..', 'r.ssss.r', 'rccccccr', 'r.n..n.r'],
 'dino': ['.....GGG', '....GkGG', '....GGGG', 'G..GGG..', 'G.GGGGG.', '.GGGyyG.', '..GGGG..', '..G..G..'],
 'coin': ['..yyyy..', '.yyyyyy.', 'yyoyyyyy', 'yyoyyyyy', 'yyoyyyyy', 'yyyyyyyy', '.yyyyyy.', '..yyyy..'],
}
def sprite(name, z):
    im = Image.new("RGBA", (8 * z, 8 * z)); d = ImageDraw.Draw(im)
    for y, row in enumerate(SPR[name]):
        for x, ch in enumerate(row):
            if ch in PAL: d.rectangle([x * z, y * z, x * z + z - 1, y * z + z - 1], fill=PAL[ch])
    return im

# ---------- 背景：夜空星星 ----------
random.seed(7)
STARS = [(random.randrange(W), random.randrange(H), random.choice([4, 6, 8]), random.random() * 6) for _ in range(90)]
def background(t):
    im = Image.new("RGB", (W, H), NIGHT); d = ImageDraw.Draw(im)
    for x, y, s, ph in STARS:
        a = .35 + .65 * (0.5 + 0.5 * math.sin(t * 2 + ph))
        col = tuple(int(NIGHT[i] + (GOLD[i] - NIGHT[i]) * a * .8) for i in range(3))
        yy = (y + t * 12) % H
        d.rectangle([x, yy, x + s - 1, yy + s - 1], fill=col)
    return im

# ---------- 截圖：自動裁掉下面空白，外面加像素框 ----------
def load_shot(name):
    im = Image.open(os.path.join(HERE, "shots", name + ".png")).convert("RGB")
    px = im.load(); w, h = im.size; bottom = 0
    for y in range(0, h - 280, 6):
        for x in range(40, w - 40, 17):
            r, g, b = px[x, y]
            if abs(r - 43) + abs(g - 33) + abs(b - 64) > 40: bottom = y; break
    return im.crop((0, 0, w, min(h, bottom + 60)))
def framed(shot, width):
    s = shot.resize((width, int(shot.height * width / shot.width)), Image.LANCZOS)
    b = 14; out = Image.new("RGB", (s.width + b * 2, s.height + b * 2), INK)
    d = ImageDraw.Draw(out); d.rectangle([5, 5, out.width - 6, out.height - 6], outline=GOLD, width=4)
    out.paste(s, (b, b)); return out

SCENES = [
 ("city", "走進魔法城市", "走路去上課、吃飯、逛街、存錢"),
 ("start", "先選一個自己的角色", "髮色、膚色都能自己挑"),
 ("food", "每天到餐廳吃飯打卡", "三天沒吃會餓倒，變成小幽靈！"),
 ("daily", "每天一題，打卡不中斷", "答對拿金幣和單字卡"),
 ("room", "和同學一起專注", "讀書房看得到誰在一起讀"),
 ("quest", "任務板每天換新任務", "簡單、普通、困難，完成就領金幣"),
 ("home", "布置你的房間", "還能養一隻恐龍當寵物"),
 ("granny", "逃離恐怖阿嬤！", "答對題目才能打開門"),
 ("tower", "單字守城", "答對就能打倒來襲的怪物"),
 ("gift", "送禮物給好朋友", "連續打卡 7 天，解鎖好友與私訊"),
 ("kid", "國小到高中都能玩", "英檢初級風格・國一到國三・會考・高中"),
]
CROP = {"start": (270, 820), "gift": (150, 700), "granny": (0, 560), "quest": (0, 720)}
# 旁白（macOS 美佳）：每個畫面依旁白長度決定秒數
VO = os.path.join(HERE, "vo")
def vo_len(k):
    with wave.open(os.path.join(VO, k + ".wav")) as w: return w.getnframes() / w.getframerate()
LEAD = .35
TITLE = max(3.5, vo_len("title") + 1.0)
DURS = [max(3.0, vo_len(n) + LEAD + .6) for n, _, _ in SCENES]
STARTS = [TITLE + sum(DURS[:i]) for i in range(len(SCENES))]
END = max(5, vo_len("end") + 2.0)
SCENE = 3.0
SUBS = dict(l.strip().split("|", 1) for l in open(os.path.join(VO, "lines.txt"), encoding="utf-8") if "|" in l)
def subtitle(im, key, y=1668):
    """把旁白文字放在畫面下方（靜音播放也看得懂）"""
    txt = SUBS.get(key, ""); d = ImageDraw.Draw(im)
    lines, cur = [], ""
    for ch in txt:
        cur += ch
        if text_w(cur, 40) > 940 and ch in "，。！、 ":
            lines.append(cur.strip()); cur = ""
        elif text_w(cur, 40) > 980:
            lines.append(cur[:-1]); cur = ch
    if cur.strip(): lines.append(cur.strip())
    h = 18 + 54 * len(lines)
    ov = Image.new("RGBA", (W, h), (15, 10, 26, 205)); im.paste(ov, (0, y), ov)
    for i, l in enumerate(lines): draw_text(d, (W / 2, y + 12 + i * 54), l, 40, PAPER, shadow=False)
DUR = TITLE + sum(DURS) + END
cards = {}
for n, _, _ in SCENES:
    shot = load_shot(n) if n not in CROP else Image.open(os.path.join(HERE, "shots", n + ".png")).convert("RGB").crop((0, CROP[n][0] * 3, 1170, CROP[n][1] * 3))
    c = framed(shot, 900)
    if c.height > 1240: c = c.crop((0, 0, c.width, 1240))
    cards[n] = c

def ease(x): x = max(0, min(1, x)); return 1 - (1 - x) ** 3

def title_frame(t):
    im = background(t); d = ImageDraw.Draw(im)
    k = ease(t / .8)
    draw_text(d, (W / 2, 560 - (1 - k) * 80), "LEARNING DEN", 132, GOLD)
    if t > .5: draw_text(d, (W / 2, 740), "陪你一起讀書啦", 77, PAPER)
    names = ['kid', 'teen', 'sage', 'king']
    for i, nme in enumerate(names):
        if t > .8 + i * .15:
            sp = sprite(nme, 22); x = int(W / 2 - 2 * 210 + i * 210 + 105 - sp.width / 2)
            y = int(1020 - abs(math.sin(t * 5 + i)) * 40)
            im.paste(sp, (x, y), sp)
    if t > 1.8: draw_text(d, (W / 2, 1380), "國小・國中・高中 的英文學習小鎮", 55, LILAC)
    subtitle(im, "title")
    return im

def scene_frame(i, t):
    n, big, small = SCENES[i]
    SCENE = DURS[i]
    im = background(STARTS[i] + t); d = ImageDraw.Draw(im)
    k = ease(t / .5)
    draw_text(d, (W / 2, 150 + (1 - k) * 40), big, 88, GOLD)
    if t > .25: draw_text(d, (W / 2, 270), small, 44, PAPER)
    c = cards[n]; z = 1 + .035 * (t / SCENE)
    cz = c.resize((int(c.width * z), int(c.height * z)), Image.BILINEAR)
    cy = int(400 + (1 - k) * 240 - (cz.height - c.height) / 2)
    im.paste(cz, (int(W / 2 - cz.width / 2), cy))
    subtitle(im, n)
    coin = sprite('coin', 7); im.paste(coin, (70, 1810), coin)
    draw_text(d, (140, 1812), "LEARNING DEN", 44, GOLD, anchor="lt", shadow=False)
    if t > SCENE - .25:  # 轉場閃一下
        a = (t - (SCENE - .25)) / .25
        im = Image.blend(im, Image.new("RGB", (W, H), NIGHT), a * .7)
    return im

qr = qrcode.QRCode(border=2, box_size=14); qr.add_data("https://" + URL + "/"); qr.make(fit=True)
QR = qr.make_image(fill_color="#1a1026", back_color="#f4ecd8").convert("RGB")
def end_frame(t):
    im = background(DUR - END + t); d = ImageDraw.Draw(im)
    k = ease(t / .6)
    draw_text(d, (W / 2, 240 - (1 - k) * 60), "現在就來打卡！", 99, GOLD)
    draw_text(d, (W / 2, 400), "LEARNING DEN", 99, PAPER)
    draw_text(d, (W / 2, 530), "陪你一起讀書啦", 66, LILAC)
    q = QR.resize((520, 520), Image.NEAREST); x = W // 2 - 280
    d.rectangle([x, 650, x + 559, 1209], fill=INK); d.rectangle([x + 6, 656, x + 553, 1203], outline=GOLD, width=5)
    im.paste(q, (x + 20, 670))
    draw_text(d, (W / 2, 1270), "掃描 QR code，或搜尋網址", 44, PAPER)
    draw_text(d, (W / 2, 1345), URL, 33, MINT)
    draw_text(d, (W / 2, 1420), "用 Google 帳號免費登入", 55, GOLD)
    draw_text(d, (W / 2, 1500), "免費・非營利教育用途", 44, LILAC)
    for i, nme in enumerate(['kid', 'teen', 'sage', 'king', 'dino']):
        sp = sprite(nme, 16); y = int(1640 - abs(math.sin(t * 5 + i * .7)) * 30)
        im.paste(sp, (int(W / 2 - 2.5 * 170 + i * 170 + 85 - sp.width / 2), y), sp)
    subtitle(im, "end", y=1740)
    if t > END - .6: im = Image.blend(im, Image.new("RGB", (W, H), (0, 0, 0)), (t - (END - .6)) / .6)
    return im

def frame(t):
    if t < TITLE: return title_frame(t)
    for i in range(len(SCENES)):
        if t < STARTS[i] + DURS[i]: return scene_frame(i, t - STARTS[i])
    return end_frame(t - (TITLE + sum(DURS)))

# ---------- 原創 8-bit 背景音樂（C–Am–F–G，每小節 2 秒） ----------
def make_music(path, dur):
    sr = 44100; n = int(sr * dur); buf = [0.0] * n
    note = lambda m: 440 * 2 ** ((m - 69) / 12)
    chords = [(48, [60, 64, 67, 72]), (45, [57, 60, 64, 69]), (41, [53, 57, 60, 65]), (43, [55, 59, 62, 67])]
    melody = [[72, 76, 79, 76, 74, 72, 74, 76], [76, 72, 69, 72, 76, 79, 76, 72], [77, 76, 74, 72, 69, 72, 74, 77], [79, 77, 76, 74, 71, 74, 79, 83],
              [84, 79, 76, 79, 81, 79, 76, 72], [76, 74, 72, 69, 72, 74, 76, 81], [77, 81, 84, 81, 79, 77, 76, 74], [74, 76, 77, 79, 74, 71, 67, 71]]
    beat = .25  # 八分音符
    def add(start, length, freq, vol, wavef):
        s0 = int(start * sr); s1 = min(n, int((start + length) * sr))
        for i in range(s0, s1):
            tt = (i - s0) / sr; env = min(1, tt * 60) * max(0, 1 - tt / length) ** .6
            buf[i] += wavef(freq * tt) * vol * env
    sq = lambda ph: 1 if (ph % 1) < .5 else -1
    tri = lambda ph: 4 * abs((ph % 1) - .5) - 1
    bars = int(dur // 2)
    for b in range(bars):
        root, arp = chords[b % 4]; t0 = b * 2
        mel = melody[b % 8] if b >= 2 else None
        for k in range(8):
            add(t0 + k * beat, beat * .95, note(root - 12 + (12 if k % 2 else 0)), .16, tri)
            if mel and not (b == bars - 1 and k > 3): add(t0 + k * beat, beat * .8, note(mel[k]), .07, sq)
            add(t0 + k * beat, beat * .5, note(arp[k % 4] + 12), .025, sq)
        for k in range(8):  # 小鼓刷刷
            s0 = int((t0 + k * beat) * sr)
            for i in range(s0, min(n, s0 + int(.03 * sr))):
                buf[i] += (random.random() * 2 - 1) * .05 * (1 - (i - s0) / (.03 * sr)) * (1.6 if k % 4 == 2 else .6)
    fade = int(1.5 * sr)
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        data = bytearray()
        for i, v in enumerate(buf):
            if i > n - fade: v *= (n - i) / fade
            data += struct.pack("<h", int(max(-1, min(1, v)) * 30000))
        w.writeframes(bytes(data))

music = os.path.join(HERE, "music.wav"); make_music(music, DUR)
def mix_voice(music_path, out_path):
    import array
    with wave.open(music_path) as w: sr = w.getframerate(); m = array.array("h", w.readframes(w.getnframes()))
    buf = [v * .38 for v in m]
    cues = [("title", .6)] + [(n, STARTS[i] + LEAD) for i, (n, _, _) in enumerate(SCENES)] + [("end", TITLE + sum(DURS) + .5)]
    for k, at in cues:
        with wave.open(os.path.join(VO, k + ".wav")) as w: v = array.array("h", w.readframes(w.getnframes()))
        s0 = int(at * sr)
        for j, x in enumerate(v):
            if s0 + j < len(buf): buf[s0 + j] += x * 1.15
    peak = max(1, max(abs(x) for x in buf)); g = min(1, 32000 / peak)
    with wave.open(out_path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(array.array("h", [int(x * g) for x in buf]).tobytes())
mixed = os.path.join(HERE, "mixed.wav"); mix_voice(music, mixed); music = mixed
ff = imageio_ffmpeg.get_ffmpeg_exe()
p = subprocess.Popen([ff, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
    "-i", music, "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", "-preset", "medium", "-c:a", "aac", "-b:a", "160k",
    "-shortest", "-movflags", "+faststart", OUT], stdin=subprocess.PIPE)
N = int(DUR * FPS)
for f in range(N):
    p.stdin.write(frame(f / FPS).tobytes())
    if f in (int(1.5 * FPS), int(TITLE * FPS + 2 * FPS), int((DUR - 2) * FPS)):
        frame(f / FPS).save(os.path.join(HERE, f"preview_{f}.png"))
p.stdin.close(); p.wait()
print("done", OUT, round(os.path.getsize(OUT) / 1e6, 1), "MB", DUR, "s")
