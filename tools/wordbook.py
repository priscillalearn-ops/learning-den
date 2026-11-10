# 產生「單字本」用的單字表：banks/words-{kid,teen,sage}.json
#   依「版本 → 冊 → 課」分好，每個字有 英文、中文、詞性、例句（題目裡有挖空的句子就拿來當例句）。
#   高中：從題庫的課本單元抓（龍騰、三民乙版、學測、多益）；國中、國小：用 vocab-quiz.py 的常用字＋原創題庫。
# 用法：在 Magic_World_App 資料夾執行  python3 learning-den/tools/wordbook.py
#       再執行 node learning-den/tools/build-site.js（會幫新單字表加上內容指紋）。
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
BANKS = os.path.join(HERE, '..', 'banks')
VQ_SRC = open(os.path.join(HERE, 'vocab-quiz.py'), encoding='utf-8').read()

def words_const(name):
    m = re.search(name + r' = """(.*?)"""', VQ_SRC, re.S)
    return [line for line in m.group(1).split('\n')]

POS_RE = r'(?:n|v|vt|vi|adj|adv|prep|conj|pron|phr|aux|int|art)\.'
ZH = re.compile(r'[一-鿿]')

def clean_zh(s):
    s = re.sub(r'\[[^\]]*\]', '', s or '')
    s = re.split(r'[；;＝=。／/　]|\s同\s|同義|字根|反義|\s\(|例：|e\.g\.', s)[0]
    s = s.replace('，', '；').strip(' ，,、：:')
    s = s.split('；')[0] if len(s) > 12 else s
    s = s.strip()
    if not ZH.search(s) or re.search(r'答案|正解|題|[A-Za-z]{3,}|\d', s) or len(s) > 14:
        return ''
    return s

def clean_en(s):
    s = re.sub(r'\s+' + POS_RE + r'.*$', '', (s or '').strip())
    s = re.sub(r'\s*\(.*$', '', s).strip(' .')
    if not re.fullmatch(r"[A-Za-z][A-Za-z '’\-]*", s) or len(s.split()) > 4 or len(s) > 28:
        return ''
    return s

def from_question(r):
    """題目 → (英文, 中文, 詞性, 例句)"""
    q, opts, a, ex = r[0], r[1], r[2], (r[3] if len(r) > 3 else '') or ''
    ans = opts[a] if 0 <= a < len(opts) else ''
    en = zh = pos = sent = ''
    m = re.match(r'^「(.+?)」(?:（[^）]*）)?的英文是', q)
    if m:
        en, zh = ans, m.group(1)
    m2 = re.match(r'^「(.+?)」是什麼意思', q)
    if m2:
        en, zh = m2.group(1), ans
    m3 = re.match(r"^([A-Za-z][A-Za-z '’.\-/]*?)\s*\(([a-z][^)]*)\)\s*(?:\[[^\]]*\]\s*)?(.+)$", ex)
    m4 = re.match(r"^([A-Za-z][A-Za-z '’\-]*?)\s+(" + POS_RE + r"[^一-鿿]*)\s*(.+)$", ex)
    if m3:
        en = en or m3.group(1); pos = m3.group(2).split(';')[0].strip()[:8]; zh = zh or m3.group(3)
    elif m4:
        en = en or m4.group(1); pos = m4.group(2).split()[0][:8]; zh = zh or m4.group(3)
    # 挖空的英文句子 → 例句
    if re.search(r'_{2,}', q) and len(re.findall(r'[A-Za-z]+', q)) >= 5 and ans:
        s = re.sub(r'^【[^】]*】\s*', '', q)
        s = re.sub(r'_{2,}', ans, s, count=1)
        if len(s) <= 170 and '_' not in s:
            sent = s.strip()
        en = en or ans
    return clean_en(en), clean_zh(zh), pos, sent

def lemmas(w):
    w = w.lower()
    out = [w]
    for suf, rep in (('ies', 'y'), ('ied', 'y'), ('es', ''), ('s', ''), ('ed', ''), ('ed', 'e'), ('d', ''), ('ing', ''), ('ing', 'e'), ('ly', '')):
        if w.endswith(suf) and len(w) - len(suf) >= 3:
            out.append(w[:-len(suf)] + rep)
    return out

def build_dict(banks):
    d = {}
    for line in words_const('KID_WORDS') + words_const('TEEN_WORDS'):
        for item in line.split('|'):
            m = re.match(r'(.+?)\s+([一-鿿].*)$', item.strip())
            if m:
                d.setdefault(m.group(1).lower(), m.group(2))
    for data in banks.values():
        for u in data['units']:
            for r in u.get('v', []):
                en, zh, _, _ = from_question(r)
                if en and zh:
                    d.setdefault(en.lower(), zh)
    return d

def unit_words(u, dic):
    seen, out = {}, []
    for r in u.get('v', []):
        en, zh, pos, sent = from_question(r)
        if not en:
            continue
        if not zh:
            for l in lemmas(en):
                if l in dic:
                    zh, en = dic[l], (l if l != en.lower() else en)
                    break
        key = en.lower()
        if not zh:
            continue
        if key in seen:
            row = seen[key]
            if not row[3] and sent:
                row[3] = sent
            continue
        row = [en, zh, pos, sent]
        seen[key] = row
        out.append(row)
    return out

def chunks(words, size=25):
    return [words[i:i + size] for i in range(0, len(words), size)]

def lesson_name(u):
    n = u['name']
    n = re.sub(r'^(龍騰|三民乙版)\s*B\d\s*', '', n)
    return n.replace('　', ' ').strip()

def plain_list(lines):
    out = []
    for line in lines:
        for item in line.split('|'):
            m = re.match(r'(.+?)\s+([一-鿿].*)$', item.strip())
            if m:
                out.append([m.group(1), m.group(2), '', ''])
    return out

def main():
    banks = {t: json.load(open(os.path.join(BANKS, t + '.json'), encoding='utf-8')) for t in ('kid', 'teen', 'sage')}
    dic = build_dict(banks)
    U = {t: {u['id']: u for u in banks[t]['units']} for t in banks}
    result = {}

    # ---------- 高中：照版本 ----------
    def book(bid, name, ids, split=0):
        units = []
        for uid in ids:
            if uid not in U['sage']:
                continue
            ws = unit_words(U['sage'][uid], dic)
            if split:
                for i, c in enumerate(chunks(ws, split)):
                    units.append({'id': f'{uid}-{i + 1}', 'name': f'第 {i + 1} 組（{c[0][0]}～{c[-1][0]}）', 'words': c})
            else:
                units.append({'id': uid, 'name': lesson_name(U['sage'][uid]), 'words': ws})
        return {'id': bid, 'name': name, 'units': [x for x in units if x['words']]}
    ids = list(U['sage'])
    result['sage'] = {'pubs': [
        {'name': '龍騰', 'books': [
            book('LT-B1', '龍騰 B1（高一上）', [i for i in ids if re.fullmatch(r'B1L\d', i)]),
            book('LT-B3', '龍騰 B3（高二上）', [i for i in ids if re.fullmatch(r'B3L\d', i)]),
            book('LT-EX', '龍騰 段考複習題本', ['B3EXAM1', 'B5EXAM1'], split=25)]},
        {'name': '三民乙版', 'books': [
            book('SM-B1', '三民乙版 B1（高一上）', [i for i in ids if re.fullmatch(r'SM1U\d', i)])]},
        {'name': '學測', 'books': [
            book('GSAT', '學測高頻單字（字根字首）', ['GSAT'], split=25)]},
        {'name': '多益', 'books': [book('TOEIC', '多益商務職場單字', ['TOEIC'], split=25)]},
    ]}

    # ---------- 國中：會考常用字（各版本通用） ----------
    teen_core = plain_list(words_const('TEEN_WORDS'))
    result['teen'] = {'pubs': [
        {'name': '會考常用字（各版本通用）', 'books': [
            {'id': 'JH-G', 'name': '國一～國三 課堂字彙', 'units': [
                {'id': g, 'name': U['teen'][g]['name'].replace('　', ' '), 'words': unit_words(U['teen'][g], dic)}
                for g in ('J1V', 'J2V', 'J3V') if g in U['teen']]},
            {'id': 'JH-CORE', 'name': '會考核心單字（A–Z）', 'units': [
                {'id': f'JC-{i + 1}', 'name': f'第 {i + 1} 組（{c[0][0]}～{c[-1][0]}）', 'words': c}
                for i, c in enumerate(chunks(teen_core, 25))]},
        ]},
    ]}

    # ---------- 國小：主題分類 ----------
    THEMES = ['動物', '食物', '顏色', '家人與職業', '身體', '學校', '家與交通', '天氣與自然', '時間', '數字', '動作', '形容詞']
    kid_lines = [l for l in words_const('KID_WORDS') if l.strip()]
    result['kid'] = {'pubs': [
        {'name': '國小常用字', 'books': [
            {'id': 'KID-THEME', 'name': '主題單字', 'units': [
                {'id': f'KT-{i + 1}', 'name': THEMES[i] if i < len(THEMES) else f'第 {i + 1} 組', 'words': plain_list([l])}
                for i, l in enumerate(kid_lines)]},
            {'id': 'KID-GEPT', 'name': '英檢初級單字', 'units': [
                {'id': g, 'name': U['kid'][g]['name'].replace('　', ' '), 'words': unit_words(U['kid'][g], dic)}
                for g in ('GP', 'GV') if g in U['kid']]},
        ]},
    ]}

    for t, data in result.items():
        n = sum(len(u['words']) for p in data['pubs'] for b in p['books'] for u in b['units'])
        with open(os.path.join(BANKS, f'words-{t}.json'), 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
        print(f'words-{t}.json：{n} 個字')

if __name__ == '__main__':
    main()
