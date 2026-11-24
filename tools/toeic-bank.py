# 把 tools/toeic/*.txt 的原創多益題目放進 banks/sage.json（大魔導師）。
# 題目檔格式：
#   # 單元 TP5A：單元名稱          ← 第一行，冒號前是單元代號，後面是名稱
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
    {'name': '多益全備（單字＋文法 Part 5）', 'ids': ['TOEIC', 'TP5A', 'TP5B', 'TP5C', 'TP5D']},
    {'name': '多益文法 Part 5（四個單元）', 'ids': ['TP5A', 'TP5B', 'TP5C', 'TP5D']},
]

def parse(path):
    lines = open(path, encoding='utf-8').read().splitlines()
    m = re.match(r'#\s*單元\s*(\w+)：(.+)', lines[0])
    uid, name = m.group(1), m.group(2).strip()
    unit = {'id': uid, 'pub': '多益', 'grade': '', 'name': name, 'short': '多益' + uid[1:],
            'src': {}, 'tags': {}, 'v': [], 'g': [], 'c': []}
    rnd = random.Random('toeic-' + uid)
    cat = None
    for ln in lines[1:]:
        ln = ln.strip()
        if not ln or ln.startswith('#'): continue
        h = re.match(r'\[([vgc])\]\s*(.+)', ln)
        if h:
            cat = h.group(1); unit['src'][cat] = name.split('：')[0] + '・' + h.group(2).strip(); unit['tags'][cat] = h.group(2).strip()
            continue
        stem, opts, ex = [x.strip() for x in ln.split('||')]
        opts = [o.strip() for o in opts.split('|')]
        assert len(opts) == 4 and len(set(o.lower() for o in opts)) == 4, (path, ln)
        assert '____' in stem, (path, ln)
        order = list(range(4)); rnd.shuffle(order)
        unit[cat].append([stem, [opts[i] for i in order], order.index(0), ex])
    return unit

def main():
    data = json.load(open(PATH, encoding='utf-8'))
    units = [parse(p) for p in sorted(glob.glob(os.path.join(HERE, 'toeic', '*.txt')))]
    ids = {u['id'] for u in units}
    data['units'] = [u for u in data['units'] if u['id'] not in ids]
    at = next((i + 1 for i, u in enumerate(data['units']) if u['id'] == 'TOEIC'), len(data['units']))
    data['units'][at:at] = units
    names = {p['name'] for p in PRESETS}
    data['presets'] = [p for p in data['presets'] if p['name'] not in names]
    at = next((i for i, p in enumerate(data['presets']) if '多益' in p['name']), len(data['presets']))
    data['presets'][at:at] = PRESETS
    json.dump(data, open(PATH, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
    for u in units: print(u['id'], u['name'], {k: len(u[k]) for k in 'vgc'})
    print('合計', sum(len(u[k]) for u in units for k in 'vgc'), '題')

if __name__ == '__main__':
    main()
