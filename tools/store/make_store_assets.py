# 產生 App Store／Google Play 上架用的素材，放在 learning-den/store/：
#   icon-1024.png（App Store）、icon-512.png（Google Play）、feature-graphic.png（Google Play 1024×500）
#   screenshots/android/*.png（1080×1920）、screenshots/ios/*.png（1290×2796，6.7 吋）
# 用法：先用 preview 開著 learning-den 伺服器（http://localhost:8780），再執行
#   python3 learning-den/tools/store/make_store_assets.py
# 字型放在 Magic_World_App/.fonts/（DotGothic16.ttf、Cubic_11.ttf，都是 SIL OFL 免費字型）。
import os, shutil, subprocess, sys, time, random
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
FONTS = os.path.abspath(os.path.join(ROOT, '..', '.fonts'))
OUT = os.path.join(ROOT, 'store')
WORK = os.path.join(OUT, '_work')
CH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
NIGHT, INK, GOLD, PAPER, LILAC = (43, 33, 64), (15, 10, 26), (255, 209, 102), (244, 236, 216), (199, 184, 232)

SCENES = [
    ("city", "走進魔法城市", "和同學一起在像素城市裡讀書"),
    ("daily", "每天一題英文", "國小英檢・國中會考・高中學測"),
    ("room", "一起專注讀書", "讀書房有同學陪，還能互相打氣"),
    ("homegarden", "魔法花園", "讀書拿魔法水，種菜收成換配件"),
    ("chars", "17 種角色", "髮型、服裝、寵物，打造自己"),
    ("levels", "小遊戲闖關", "恐怖阿嬤、單字守城、翻牌、快答"),
    ("gachanew", "魔法盲盒", "用讀書賺的金幣抽限定裝扮"),
    ("guild", "班級讀書會", "和同學一起完成公會任務"),
]

def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)

def shoot(scenes):
    os.makedirs(os.path.join(WORK, 'shots'), exist_ok=True)
    subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'promo', 'make_demo.py')], check=True)
    shutil.copy(os.path.join(FONTS, 'DotGothic16.ttf'), os.path.join(ROOT, '_promo_font.ttf'))
    try:
        for sc in scenes:
            out = os.path.join(WORK, 'shots', sc + '.png'); ud = os.path.join(WORK, 'chrome-' + sc)
            if os.path.exists(out): os.remove(out)
            p = subprocess.Popen([CH, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
                "--window-size=390,844", "--force-device-scale-factor=3", "--timeout=7000", f"--user-data-dir={ud}",
                f"--screenshot={out}", "http://localhost:8780/_promo.html#" + sc], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for _ in range(60):
                time.sleep(.5)
                if os.path.exists(out) and os.path.getsize(out) > 0: time.sleep(1); break
            p.kill(); subprocess.run(["pkill", "-f", ud]); shutil.rmtree(ud, ignore_errors=True)
            print('shot', sc, os.path.getsize(out) if os.path.exists(out) else 'missing')
    finally:
        for f in ('_promo.html', '_promo_font.ttf'):
            try: os.remove(os.path.join(ROOT, f))
            except FileNotFoundError: pass

def background(w, h, seed=1):
    im = Image.new('RGB', (w, h), NIGHT); d = ImageDraw.Draw(im); r = random.Random(seed)
    for _ in range(w * h // 9000):
        x, y, s = r.randrange(w), r.randrange(h), r.choice([3, 4, 6])
        c = tuple(int(NIGHT[i] + (GOLD[i] - NIGHT[i]) * r.uniform(.25, .8)) for i in range(3))
        d.rectangle([x, y, x + s, y + s], fill=c)
    return im

def centered(d, cx, y, text, f, fill):
    w = d.textlength(text, font=f); d.text((cx - w / 2, y), text, font=f, fill=fill)

def compose(name, title, sub, W, H):
    shot = Image.open(os.path.join(WORK, 'shots', name + '.png')).convert('RGB')
    im = background(W, H, seed=hash(name) & 0xffff); d = ImageDraw.Draw(im)
    top = int(H * .05)
    centered(d, W / 2, top, title, font('Cubic_11.ttf', int(W * .085)), GOLD)
    centered(d, W / 2, top + int(W * .115), sub, font('Cubic_11.ttf', int(W * .042)), PAPER)
    box_top = top + int(W * .2); box_w = int(W * .84); box_h = H - box_top - int(H * .03)
    scale = box_w / shot.width; sh = shot.resize((box_w, int(shot.height * scale)), Image.LANCZOS)
    sh = sh.crop((0, 0, box_w, min(sh.height, box_h)))
    x = (W - box_w) // 2; b = max(8, W // 90)
    d.rectangle([x - b, box_top - b, x + box_w + b, box_top + sh.height + b], fill=INK)
    d.rectangle([x - b // 2, box_top - b // 2, x + box_w + b // 2, box_top + sh.height + b // 2], outline=GOLD, width=max(3, b // 3))
    im.paste(sh, (x, box_top))
    return im

def icons():
    ic = Image.open(os.path.join(ROOT, 'icons', 'icon-512.png')).convert('RGB')
    ic.save(os.path.join(OUT, 'icon-512.png'))
    ic.resize((1024, 1024), Image.NEAREST).save(os.path.join(OUT, 'icon-1024.png'))
    fg = background(1024, 500, seed=7); d = ImageDraw.Draw(fg)
    fg.paste(ic.resize((320, 320), Image.NEAREST), (70, 90))
    d.text((440, 120), "LEARNING DEN", font=font('DotGothic16.ttf', 72), fill=GOLD)
    d.text((444, 215), "陪你一起讀書啦", font=font('Cubic_11.ttf', 54), fill=PAPER)
    d.text((446, 300), "每天一題英文・一起專注・種菜布置房間", font=font('Cubic_11.ttf', 28), fill=LILAC)
    d.text((446, 345), "國小到高中都能玩・免費・非營利", font=font('Cubic_11.ttf', 28), fill=LILAC)
    fg.save(os.path.join(OUT, 'feature-graphic.png'))

if __name__ == '__main__':
    os.makedirs(os.path.join(OUT, 'screenshots', 'android'), exist_ok=True)
    os.makedirs(os.path.join(OUT, 'screenshots', 'ios'), exist_ok=True)
    shoot([s[0] for s in SCENES])
    for i, (n, t, sub) in enumerate(SCENES, 1):
        compose(n, t, sub, 1080, 1920).save(os.path.join(OUT, 'screenshots', 'android', f'{i:02d}-{n}.png'))
        compose(n, t, sub, 1290, 2796).save(os.path.join(OUT, 'screenshots', 'ios', f'{i:02d}-{n}.png'))
    icons()
    shutil.rmtree(WORK, ignore_errors=True)
    print('done ->', OUT)
