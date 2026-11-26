# 把 tools/toeic/*.txt 的原創多益題目放進 banks/sage.json（大魔導師）。
# 題目檔格式：
#   # 單元 TP5A：單元名稱          ← 第一行，冒號前是單元代號，後面是名稱
#   @A 標題｜短文                  ← （Part 7）定義一篇短文，題目行寫「=A 問題 || …」就會把短文放在問題前面
#   [v] 分類名稱                  ← v／g／c 三類，對應題庫的三個分類
#   題目 || 正解 | 錯1 | 錯2 | 錯3 || 解析      ← 第一個選項是正解，這裡會固定亂數打亂
# 重跑會先把舊的同代號單元刪掉再放新的，所以改完題目重跑就好。
# 用法（順序很重要）：
#   node tools/import-granny.js   （如果有同步阿嬤題庫，它會整份覆蓋 sage.json）
#   python3 tools/toeic-bank.py
#   python3 tools/vocab-quiz.py   （選做：會重抽單字意思題）
#   node tools/keys-sql.js       → 把 supabase/question_keys.sql 貼到 Supabase 跑
#   node tools/build-site.js
import json, os, random, re, glob

HERE = os.path.dirname(os.path.abspath(__file__))
PATH = os.path.join(HERE, '..', 'banks', 'sage.json')
# 組合包：放在原本「多益衝刺（商務職場）」前面，大學生預設會推薦第一個名字有「多益」的組合包
PRESETS = [
    {'name': '多益全備（單字＋聽力＋Part 5～7）', 'ids': ['TOEIC', 'TV', 'TP5A', 'TP5B', 'TP5C', 'TP5D', 'TP6', 'TP7', 'TL']},
    {'name': '多益高頻單字（基礎＋進階）', 'ids': ['TOEIC', 'TV']},
    {'name': '多益文法 Part 5（四個單元）', 'ids': ['TP5A', 'TP5B', 'TP5C', 'TP5D']},
    {'name': '多益段落填空 Part 6', 'ids': ['TP6']},
    {'name': '多益閱讀 Part 6＋Part 7', 'ids': ['TP6', 'TP7']},
    {'name': '多益聽力 Part 2～4', 'ids': ['TL']},
]

def parse(path):
    lines = open(path, encoding='utf-8').read().splitlines()
    m = re.match(r'#\s*單元\s*(\w+)：(.+)', lines[0])
    uid, name = m.group(1), m.group(2).strip()
    unit = {'id': uid, 'pub': '多益', 'grade': '', 'name': name, 'short': '多益' + {'TL': '聽力', 'TV': '單字進階'}.get(uid, uid[1:]),
            'src': {}, 'tags': {}, 'v': [], 'g': [], 'c': []}
    rnd = random.Random('toeic-' + uid)
    cat = None
    texts = {}   # Part 7 短文：@代號 標題｜短文
    audio = {}   # 聽力腳本：%代號 標題｜腳本
    for ln in lines[1:]:
        ln = ln.strip()
        if not ln or ln.startswith('#'): continue
        if ln.startswith('@'):
            key, rest = ln[1:].split(' ', 1); title, body = rest.split('｜', 1)
            # 簡訊對話用「 / 」分行；網頁的 .qtext 有 white-space:pre-line，換行會顯示出來
            texts[key] = f'【{title.strip()}】' + ('\n' if ' / ' in body else '') + body.strip().replace(' / ', '\n')
            continue
        if ln.startswith('%'):
            # 聽力：%代號 標題｜腳本（一行一句用「 / 」分，W:／M: 是女生／男生）。腳本不顯示，用播放鈕念
            key, rest = ln[1:].split(' ', 1); title, body = rest.split('｜', 1)
            audio[key] = (title.strip(), '\n'.join(x.strip() for x in body.split(' / ')))
            continue
        say = ''
        if ln.startswith('='):
            key, rest = ln[1:].split(' ', 1)
            if key in audio:
                title, say = audio[key]
                ln = f'【{title}】🎧 先聽音檔再作答\n▶ ' + rest
            else:
                ln = texts[key] + '\n▶ ' + rest
        h = re.match(r'\[([vgc])\]\s*(.+)', ln)
        if h:
            cat = h.group(1); unit['src'][cat] = name.split('：')[0] + '・' + h.group(2).strip(); unit['tags'][cat] = h.group(2).strip()
            continue
        parts = [x.strip() for x in ln.split('||')]
        stem, opts, ex = parts[:3]
        if len(parts) > 3:   # Part 2：題目 || 選項 || 解析 || 念出來的問句
            say = parts[3]
            stem = stem.replace('▶ ', '\n▶ ')
        opts = [o.strip() for o in opts.split('|')]
        assert len(opts) == 4 and len(set(o.lower() for o in opts)) == 4, (path, ln)
        assert '____' in stem or '▶' in stem, (path, ln)
        if uid == 'TV': stem = stem.replace(' ▶ ', '\n▶ ')
        order = list(range(4)); rnd.shuffle(order)
        row = [stem, [opts[i] for i in order], order.index(0), ex]
        if say: row += [None, say]   # 第 5 格是圖（不用），第 6 格是聽力腳本
        unit[cat].append(row)
    return unit

def main():
    data = json.load(open(PATH, encoding='utf-8'))
    units = [parse(p) for p in sorted(glob.glob(os.path.join(HERE, 'toeic', '*.txt')))]
    ids = {u['id'] for u in units}
    data['units'] = [u for u in data['units'] if u['id'] not in ids]
    at = next((i + 1 for i, u in enumerate(data['units']) if u['id'] == 'TOEIC'), len(data['units']))
    data['units'][at:at] = units
    names = {p['name'] for p in PRESETS}
    # 舊版組合包改過名字的也一起拿掉（名字開頭一樣就算）
    data['presets'] = [p for p in data['presets'] if p['name'] not in names and not p['name'].startswith(('多益全備', '多益文法', '多益段落', '多益閱讀', '多益聽力', '多益高頻單字'))]
    at = next((i for i, p in enumerate(data['presets']) if '多益' in p['name']), len(data['presets']))
    data['presets'][at:at] = PRESETS
    json.dump(data, open(PATH, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
    for u in units: print(u['id'], u['name'], {k: len(u[k]) for k in 'vgc'})
    print('合計', sum(len(u[k]) for u in units for k in 'vgc'), '題')

if __name__ == '__main__':
    main()
