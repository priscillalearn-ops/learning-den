# 產生 PWA 用的圖示（加到主畫面、之後包成 Google Play 版也用同一套）：
#   icons/icon-maskable-512.png：Learning Den 的「可裁切」圖示（Android 會裁成圓形／圓角，主角縮小放在安全範圍內）
#   gram-site/icons/：GRAM 英語遊戲樂園的 192／512／maskable／apple-touch 圖示（像素風黑板＋粉筆字）
# 用法：python3 tools/make-pwa-icons.py
import os
from PIL import Image, ImageDraw
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))

def maskable(src, bg, size=512, scale=0.72):
    im = Image.open(src).convert('RGB')
    s = int(size * scale)
    inner = im.resize((s, s), Image.NEAREST)
    out = Image.new('RGB', (size, size), bg)
    out.paste(inner, ((size - s) // 2, (size - s) // 2))
    return out

# Learning Den
LD_BG = (43, 33, 64)
maskable(os.path.join(ROOT, 'store/icon-1024.png'), LD_BG).save(os.path.join(ROOT, 'icons/icon-maskable-512.png'), optimize=True)

# GRAM：32×32 格的像素畫
BOARD, BOARD2, CHALK, WOOD, WOODD = (46, 76, 64), (37, 64, 58), (243, 240, 230), (182, 124, 71), (135, 86, 40)
A, B, C, Y = (232, 85, 62), (46, 111, 216), (47, 154, 76), (255, 226, 122)
FONT = {
 'G': ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
 'R': ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
 'A': ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
 'M': ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
}
def gram(size):
    N = 32; px = Image.new('RGB', (N, N), BOARD); d = ImageDraw.Draw(px)
    for y in range(N):            # 黑板上淡淡的擦痕
        for x in range(N):
            if (x * 7 + y * 13) % 29 == 0: px.putpixel((x, y), BOARD2)
    x0, y0 = 5, 9
    for i, ch in enumerate('GRAM'):
        for r, row in enumerate(FONT[ch]):
            for c, v in enumerate(row):
                if v == '1': px.putpixel((x0 + i * 6 + c, y0 + r), CHALK)
    for i, col in enumerate((A, B, C, Y)):   # 四組 A／B／C／D 的彩色粉筆
        d.rectangle([7 + i * 5, 19, 9 + i * 5, 19], fill=col)
    d.rectangle([4, 23, 27, 24], fill=WOOD); d.rectangle([4, 25, 27, 25], fill=WOODD)   # 粉筆槽
    return px.resize((size, size), Image.NEAREST)

out = os.path.join(ROOT, 'gram-site/icons'); os.makedirs(out, exist_ok=True)
big = gram(1024)
for n, s in (('icon-192.png', 192), ('icon-512.png', 512), ('apple-touch-icon.png', 180)):
    big.resize((s, s), Image.NEAREST).save(os.path.join(out, n), optimize=True)
big.save(os.path.join(ROOT, 'gram-site/icons/icon-1024.png'), optimize=True)
maskable(os.path.join(out, 'icon-1024.png'), BOARD).save(os.path.join(out, 'icon-maskable-512.png'), optimize=True)
print('ok')
