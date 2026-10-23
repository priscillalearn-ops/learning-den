# 把老師的高一第二次段考講義／週作業本（Word 檔）轉成題庫單元，加進 banks/sage.json。
#   龍騰 B1 L4–L6 → B1L4／B1L5／B1L6；三民乙版 B1 U4–U6（含 Review 2）→ SM1U4／SM1U5／SM1U6
# 用法：python3 learning-den/tools/import-exam2.py [講義資料夾，預設 ~/Downloads]
# 會讀：
#   高一英文第二次段考講義_L4-L6_教師版.docx、115學年度高一週作業本（龍騰）二段.docx
#   115A 高一英文 三民U4-U6_R2.docx、高一英文三民第二次段考_週作業本_U4-U6.docx
# 選擇題（中選英、英選中、單字選擇、詞彙題、文法選擇）直接用；文意字彙、詞類變化改成四選一；
# 綜合測驗、文意選填取出題目那一句（其他空格填好答案）。閱讀測驗、篇章結構、翻譯題不收（要看整篇或要自己寫）。
# 改完要重跑 node learning-den/tools/keys-sql.js，請老師在 Supabase 跑 question_keys.sql。
import json, os, random, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BANK = os.path.join(HERE, '..', 'banks', 'sage.json')
SRC = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else '~/Downloads')
CIRC = '①②③④⑤⑥⑦⑧⑨⑩'

DOCS = [
    # 檔名, 單元代碼對應, 標籤
    ('高一英文第二次段考講義_L4-L6_教師版.docx', {'L4': 'B1L4', 'L5': 'B1L5', 'L6': 'B1L6'}, '講義'),
    ('115學年度高一週作業本（龍騰）二段.docx', {'W1': 'B1L4', 'W2': 'B1L4', 'W3': 'B1L5', 'W4': 'B1L5', 'W5': 'B1L6', 'W6': 'B1L6'}, '週作業'),
    ('115A 高一英文 三民U4-U6_R2.docx', {'U4': 'SM1U4', 'U5': 'SM1U5', 'U6': 'SM1U6', 'R2': 'SM1U6'}, '講義'),
    ('高一英文三民第二次段考_週作業本_U4-U6.docx', {'W1': 'SM1U4', 'W2': 'SM1U4', 'W3': 'SM1U5', 'W4': 'SM1U5', 'W5': 'SM1U6', 'W6': 'SM1U6'}, '週作業'),
]
UNITS = [
    ('B1L4', '龍騰', '龍騰 B1 L4　Sniffing Out More Than Just Bones', 'B1 L4', '關係代名詞（限定／非限定用法）'),
    ('B1L5', '龍騰', '龍騰 B1 L5　The Life of a Plastic Bag', 'B1 L5', '使役動詞 make／have／let、because／because of'),
    ('B1L6', '龍騰', '龍騰 B1 L6　Built for Freedom: The Statue of Liberty', 'B1 L6', '強調句 It is/was...that、so／such...that'),
    ('SM1U4', '三民乙版', '三民乙版 B1 U4　The Sugar Feast and More: Welcome to Eid al-Fitr', '三民 B1U4', '冠詞、N, + which/who（非限定用法）'),
    ('SM1U5', '三民乙版', '三民乙版 B1 U5　Creative Traffic Signals Around the World', '三民 B1U5', '現在完成式、現在完成進行式'),
    ('SM1U6', '三民乙版', '三民乙版 B1 U6　Reaching for Space（含 Review 2）', '三民 B1U6', '疑問詞引導的名詞子句、轉折語'),
]
PRESETS = [('龍騰高一第二次段考（L4–L6）', ['B1L4', 'B1L5', 'B1L6'], '龍騰高一第一次段考'),
           ('三民乙版 B1 U4–U6（第二次段考）', ['SM1U4', 'SM1U5', 'SM1U6'], '三民乙版 B1 U1–U3')]

def text_of(name):
    p = os.path.join(SRC, name)
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, 'x.txt')
        subprocess.run(['textutil', '-convert', 'txt', '-output', out, p], check=True)
        return open(out, encoding='utf-8').read()

def unit_key(line):
    m = re.match(r'^(Lesson|Unit|Week|Review)\s*(\d+)(?:\s*[　（(]|$)', line)
    if not m: return None
    return {'Lesson': 'L', 'Unit': 'U', 'Week': 'W', 'Review': 'R'}[m.group(1)] + m.group(2)

def split_doc(txt):
    """回傳 (題目區, 答案區)，各自是 {(單元, 大題名稱): [行]}"""
    lines = [l.rstrip() for l in txt.split('\n')]
    cut = max(i for i, l in enumerate(lines) if l.strip() in ('解答', '解答（簡答）', 'Answer', '簡答'))
    def group(ls):
        out, u, sec = {}, None, None
        for l in ls:
            k = unit_key(l.strip())
            if k: u, sec = k, None; continue
            m = re.match(r'^[一二三四五六七八九十]+、(.+)$', l.strip())
            if m and u: sec = re.sub(r'[（(].*$', '', m.group(1)).strip() if not m.group(1).startswith('文法選擇') else m.group(1).strip(); out.setdefault((u, sec), []); continue
            if u and sec is not None: out[(u, sec)].append(l)
        return out
    return group(lines[:cut]), group(lines[cut + 1:])

def opts4(s):
    m = re.search(r'\(A\)\s*(.*?)\s*\(B\)\s*(.*?)\s*\(C\)\s*(.*?)\s*\(D\)\s*(.*?)\s*$', s, re.S)
    return [re.sub(r'\s+', ' ', x).strip() for x in m.groups()] if m else None

def numbered_mc(ls):
    body = '\n'.join(ls)
    items = re.findall(r'(?:^|\n)(\d+)\.\s*（\s*）(.*?)(?=\n\d+\.\s*（|\Z)', body, re.S)
    out = []
    for n, rest in items:
        i = rest.find('(A)')
        if i < 0: continue
        o = opts4(rest[i:])
        if o: out.append((int(n), re.sub(r'\s+', ' ', rest[:i]).strip(), o))
    return out

def mc_keys(ls):
    return {int(n): a for n, a in re.findall(r'(\d+)\.\s*([A-D])\b', ' '.join(ls))}

def blank(s):
    return re.sub(r'_{3,}', '____', s)

def fill(stem, ans):
    if '____' not in stem: return None
    parts = [a.strip() for a in ans.split(';')]
    out = stem
    for p in parts: out = out.replace('____', '' if p == '×' else p, 1)
    return re.sub(r'\s+([,.?!])', r'\1', re.sub(r'\s{2,}', ' ', out)).strip()

def sentences(p):
    return [x for x in re.split(r'(?<=[.!?”"])\s+(?=[A-Z“"(　①-⑩])', p) if x.strip()]

def passages(ls):
    """綜合測驗：回傳 [(文章, {題號: 選項})]"""
    out, text, qs = [], [], {}
    for l in ls:
        s = l.strip()
        if not s: continue
        m = re.match(r'^（\s*）\s*\((\d+)\)\s*(.*)$', s)
        if m:
            o = opts4(m.group(2))
            if o: qs[int(m.group(1))] = o
            continue
        if qs:
            out.append((' '.join(text), qs)); text, qs = [], {}
        if s.startswith('註') or s.startswith('作答'): continue
        text.append(re.sub(r'^\d+\.\s*', '', s))
    if qs: out.append((' '.join(text), qs))
    return out

def answer_lines(ls):
    """每篇一行：'1. (1)B (2)D' 或 '(1)D (2)A' 或 '1. ①B ②E'"""
    res = []
    for l in ls:
        a = re.findall(r'\((\d+)\)\s*([A-J])', l)
        b = re.findall(r'([①-⑩])\s*([A-J])', l)
        if a: res.append({int(n): x for n, x in a})
        elif b: res.append({CIRC.index(c) + 1: x for c, x in b})
    return res

def cloze(ls, keys, tag):
    out = []
    for (text, qs), key in zip(passages(ls), keys):
        ans = {n: qs[n]['ABCD'.index(key[n])] for n in qs if n in key and key[n] in 'ABCD'}
        for s in sentences(text):
            nums = [int(x) for x in re.findall(r'\((\d+)\)', s)]
            for n in dict.fromkeys(nums):
                if n not in qs or n not in ans: continue
                stem = s
                for m in dict.fromkeys(nums):
                    if m != n and m in ans: stem = re.sub(r'\s*\(%d\)\s*' % m, ' ' + ans[m].replace('×', '').split(';')[0].strip() + ' ', stem)
                parts = [p.strip() for p in ans[n].split(';')]
                k = 0
                def rep(_):
                    nonlocal k; k += 1; return ' ____ '
                stem = re.sub(r'\s*\(%d\)\s*' % n, rep, stem)
                stem = re.sub(r'\s{2,}', ' ', stem).replace(' ,', ',').replace(' .', '.').strip()
                full = fill(stem, ans[n])
                out.append([f'【{tag}綜合測驗】{stem}', qs[n], 'ABCD'.index(key[n]), f'完整句：{full}' if full else ''])
    return out

def fill_bank(ls, keys, tag, rnd):
    """文意選填：選項庫 (A)…(J)，文章裡 ①…⑩"""
    out, cur, text = [], None, []
    blocks = []
    for l in ls:
        s = l.strip()
        if not s or s.startswith('作答') or s.startswith('註') or re.match(r'^[①-⑩]_', s): continue
        if re.match(r'^(\d+\.\s*)?\(A\)', s):
            if cur and text: blocks.append((cur, ' '.join(text))); cur, text = None, []
            cur = dict(re.findall(r'\(([A-J])\)\s*([^()（]+?)\s*(?=\([A-J]\)|$)', re.sub(r'^\d+\.\s*', '', s)))
            continue
        if cur is not None and re.match(r'^\([F-J]\)', s) and not text:
            cur.update(re.findall(r'\(([A-J])\)\s*([^()（]+?)\s*(?=\([A-J]\)|$)', s)); continue
        if cur is not None: text.append(s)
    if cur and text: blocks.append((cur, ' '.join(text)))
    for (bank, text), key in zip(blocks, keys):
        bank = {k: v.strip() for k, v in bank.items()}
        ans = {n: bank.get(x) for n, x in key.items()}
        for s in sentences(text):
            nums = [CIRC.index(c) + 1 for c in re.findall(r'[①-⑩]', s)]
            for n in nums:
                if not ans.get(n): continue
                stem = s
                for m in nums:
                    if m != n and ans.get(m): stem = re.sub(r'\s*' + CIRC[m - 1] + r'\s*', ' ' + ans[m] + ' ', stem)
                stem = re.sub(r'\s*' + CIRC[n - 1] + r'\s*', ' ____ ', stem)
                stem = re.sub(r'\s{2,}', ' ', stem).replace(' ,', ',').replace(' .', '.').strip()
                others = [v for v in bank.values() if v != ans[n]]
                rnd.shuffle(others)
                o = others[:3] + [ans[n]]; rnd.shuffle(o)
                out.append([f'【{tag}文意選填】{stem}', o, o.index(ans[n]), f'完整句：{fill(stem, ans[n])}'])
    return out

def keyed_words(ls):
    """填空題答案：'1. sensitive　2. exposure'，遇到不是題號開頭的行就停（後面是別的練習）"""
    out = {}
    for l in ls:
        t = l.strip()
        if not t: continue
        if not re.match(r'^\d+\.', t): break
        for n, w in re.findall(r'(\d+)\.\s*([^　\t]+?)\s*(?=\d+\.|$)', t): out.setdefault(int(n), w.strip())
    return out

def keyed_items(ls):
    out = {}
    for l in ls:
        m = re.match(r'^(\d+)\.\s*(?:_{3,}\s*)?(.*)$', l.strip())
        if m and '___' in m.group(2): out.setdefault(int(m.group(1)), m.group(2))
    return out

def glossary(txt):
    g = {}
    for l in txt.split('\n'):
        m = re.match(r'^\s*(?:\d+\.\s+)?([A-Za-z][A-Za-z \-’\'.]*?)\s*(?:\[[^\]]*\])?\s+((?:n|v|vt|vi|adj|adv|prep|conj|phr|pron)\.[^一-鿿]{0,20}?)\s*([一-鿿（][^　]*)', l)
        if m and len(m.group(1)) <= 30:
            w = m.group(1).strip().lower()
            pos = re.sub(r'\s+', ' ', m.group(2)).strip()
            zh = re.split(r'\s{2,}|　', m.group(3))[0].strip()
            if w not in g: g[w] = f'{m.group(1).strip()} ({pos}) {zh}'
    return g

def gloss_for(g, w):
    w = w.lower().strip()
    if w in g: return g[w]
    for cut in (1, 2, 3, 4):
        if len(w) - cut >= 4:
            for k in g:
                if k.startswith(w[:-cut]) and abs(len(k) - len(w)) <= 3: return g[k]
    return ''

def build():
    rnd = random.Random(20261024)
    units = {u[0]: {'v': [], 'g': [], 'c': []} for u in UNITS}
    for name, umap, kind in DOCS:
        txt = text_of(name)
        g = glossary(txt)
        Q, A = split_doc(txt)
        words = sorted({w for w in g if re.fullmatch(r'[a-z]+', w)})
        for (u, sec), ls in Q.items():
            uid = umap.get(u)
            if not uid: continue
            key = A.get((u, sec), [])
            lab = {'W': f'W{u[1]} ', 'R': 'Review 2 '}.get(u[0], '')
            tag = lab + ('週作業・' if kind == '週作業' else '')
            if sec in ('中選英', '英選中', '單字選擇', '詞彙題', '詞彙複習') or sec.startswith('文法選擇') or sec == '文法複習':
                ks = mc_keys(key)
                for n, stem, o in numbered_mc(ls):
                    if n not in ks: continue
                    a = 'ABCD'.index(ks[n]); stem = blank(stem)
                    if sec.startswith('文法') :
                        full = fill(stem, o[a])
                        units[uid]['g'].append([f'【{tag}文法】{stem}', o, a, f'完整句：{full}' if full else ''])
                    elif sec == '中選英':
                        units[uid]['v'].append([f'「{stem}」的英文是？', o, a, gloss_for(g, o[a]) or f'{o[a]} {stem}'])
                    elif sec == '英選中':
                        units[uid]['v'].append([f'「{stem}」是什麼意思？', o, a, gloss_for(g, stem) or f'{stem} {o[a]}'])
                    else:
                        full = fill(stem, o[a])
                        units[uid]['v'].append([f'【{tag}單字】{stem}', o, a, gloss_for(g, o[a]) or (f'完整句：{full}' if full else '')])
            elif sec in ('文意字彙',):
                kw, it = keyed_words(key), keyed_items(ls)
                ans = list(kw.values())
                pool = list(dict.fromkeys([x.lower() for x in ans] + words))
                for stem, a in ((it[n], kw[n]) for n in kw if n in it):
                    s2 = re.sub(r'[A-Za-z]*_{3,}[A-Za-z]*', '____', stem, count=1)
                    if '____' not in s2: continue
                    a = a.strip()
                    suf = lambda w: w[-2:] if len(w) > 3 else w
                    cands = [w for w in pool if w != a.lower() and suf(w) == suf(a.lower())] or [w for w in pool if w != a.lower()]
                    rnd.shuffle(cands)
                    if len(cands) < 3: cands += [w for w in pool if w != a.lower() and w not in cands]
                    o = cands[:3] + [a]; rnd.shuffle(o)
                    if a[0].isupper(): o = [x[0].upper() + x[1:] for x in o]
                    units[uid]['v'].append([f'【{tag}文意字彙】{s2}', o, o.index(a), gloss_for(g, a) or f'答案：{a}'])
            elif sec == '詞類變化':
                kw, it = keyed_words(key), keyed_items(ls)
                for stem, a in ((it[n], kw[n]) for n in kw if n in it):
                    m = re.search(r'_{3,}\s*\(([A-Za-z]+)\)', stem)
                    if not m: continue
                    base = m.group(1).lower(); a = a.strip()
                    fam = [w for w in g if re.fullmatch(r'[a-z]+', w) and w[:4] == base[:4] and w != a.lower()]
                    fam = list(dict.fromkeys([base] + fam if base != a.lower() else fam))
                    if len(fam) < 3: continue
                    rnd.shuffle(fam)
                    o = fam[:3] + [a.lower()]; rnd.shuffle(o)
                    if a[0].isupper(): o = [x[0].upper() + x[1:] for x in o]
                    s2 = stem[:m.start()] + f'____ ({m.group(1)})' + stem[m.end():]
                    units[uid]['v'].append([f'【{tag}詞類變化】{s2}', o, o.index(a if a[0].isupper() else a.lower()), gloss_for(g, a) or f'答案：{a}'])
            elif sec == '綜合測驗':
                units[uid]['c'] += cloze(ls, answer_lines(key), tag)
            elif sec == '文意選填':
                units[uid]['c'] += fill_bank(ls, answer_lines(key), tag, rnd)
    return units

def main():
    units = build()
    d = json.load(open(BANK, encoding='utf-8'))
    meta = {u[0]: u for u in UNITS}
    d['units'] = [u for u in d['units'] if u['id'] not in meta]
    for uid, (_, pub, name, short, gram) in meta.items():
        q = units[uid]
        for t in 'vgc':  # 去掉重複題
            seen, keep = set(), []
            for x in q[t]:
                k = (x[0], tuple(x[1]))
                if k not in seen and len(set(x[1])) == 4: seen.add(k); keep.append(x)
            q[t] = keep
        lab = short.replace('三民 ', '')
        unit = {'id': uid, 'pub': pub, 'grade': '高一', 'name': name, 'short': short,
                'src': {'v': f'{lab} 單字・片語', 'g': f'{lab} 文法：{gram}', 'c': f'{lab} 綜合測驗・文意選填'}, **q}
        after = {'B1L4': 'B1L2', 'B1L5': 'B1L4', 'B1L6': 'B1L5', 'SM1U4': 'SM1U3', 'SM1U5': 'SM1U4', 'SM1U6': 'SM1U5'}[uid]
        i = next(i for i, u in enumerate(d['units']) if u['id'] == after)
        d['units'].insert(i + 1, unit)
        print(uid, {t: len(q[t]) for t in 'vgc'})
    for name, ids, after in PRESETS:
        d['presets'] = [p for p in d['presets'] if p['name'] != name]
        i = next(i for i, p in enumerate(d['presets']) if p['name'] == after)
        d['presets'].insert(i + 1, {'name': name, 'ids': ids})
    json.dump(d, open(BANK, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))

if __name__ == '__main__':
    main()
