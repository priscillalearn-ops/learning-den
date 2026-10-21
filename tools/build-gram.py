# 把「GRAM 英語遊戲樂園」單頁（Claude Artifact 原始檔）包成 GitHub Pages 用的完整網頁：docs/gram/index.html
# 用法：python3 tools/build-gram.py <artifact 原始 html> <listen 資料夾>
import sys, shutil, os, re
src, listen = sys.argv[1], sys.argv[2]
body = open(src, encoding="utf-8").read()
m = re.match(r"\s*<title>.*?</title>\s*", body, re.S)
body = body[m.end():] if m else body
head = """<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>GRAM 英語遊戲樂園</title>
<meta name="description" content="GRAM 2026 英檢 A、B、C、D 四組聽力與閱讀練習：跑酷、賽車、釣魚、射氣球、打地鼠，邊玩邊練。">
<meta property="og:title" content="GRAM 英語遊戲樂園">
<meta property="og:description" content="英檢 A、B、C、D 四組聽力與閱讀練習遊戲，手機打開就能玩。">
<meta property="og:type" content="website">
<meta name="theme-color" content="#2E4C40">
<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px);box-sizing:border-box}*,*::before,*::after{box-sizing:border-box}img{max-width:100%}</style>
"""
out = head + body + "\n</html>\n"
os.makedirs("docs/gram", exist_ok=True)
open("docs/gram/index.html", "w", encoding="utf-8").write(out)
dst = "docs/gram/listen"
if os.path.isdir(dst): shutil.rmtree(dst)
shutil.copytree(listen, dst)
print("ok", len(out), len(os.listdir(dst)))
