# 產生 PWA 用的圖示（加到主畫面、之後包成 Google Play 版也用同一套）：
#   icons/icon-maskable-512.png：Learning Den 的「可裁切」圖示（Android 會裁成圓形／圓角，主角縮小放在安全範圍內）
# 用法：python3 tools/make-pwa-icons.py
import os
from PIL import Image
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

print('ok')
