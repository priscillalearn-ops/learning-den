# 產生「單字意思（自動出題）」單元，放進 banks/{kid,teen,sage}.json：
#   題庫裡出現過的單字（從解析抓英文＋中文）＋下面補充的基本單字，
#   兩個方向出題：「apple」是什麼意思？／「蘋果」的英文是？
# 釣魚和貓頭鷹博士會從這個單元出題（今日一題不會用到）。
# 用法：在 Magic_World_App 資料夾執行  python3 learning-den/tools/vocab-quiz.py
#       再執行 node learning-den/tools/keys-sql.js，把 question_keys.sql 貼到 Supabase 跑。
import json, os, random, re

HERE = os.path.dirname(os.path.abspath(__file__))
BANKS = os.path.join(HERE, '..', 'banks')
UNIT = {'kid': 'VQK', 'teen': 'VQT', 'sage': 'VQS'}
LIMIT = {'kid': 9999, 'teen': 9999, 'sage': 600}   # 高中題庫本來就很大，只取 600 個字

# 國小常用單字（全民英檢初級／國小課綱常見字）
KID_WORDS = """dog 狗|cat 貓|bird 鳥|fish 魚|pig 豬|cow 乳牛|horse 馬|sheep 綿羊|duck 鴨子|chicken 雞|rabbit 兔子|monkey 猴子|tiger 老虎|lion 獅子|elephant 大象|bear 熊|panda 熊貓|frog 青蛙|snake 蛇|mouse 老鼠|zebra 斑馬|giraffe 長頸鹿|turtle 烏龜|butterfly 蝴蝶|bee 蜜蜂|ant 螞蟻|owl 貓頭鷹|penguin 企鵝|whale 鯨魚|dolphin 海豚
apple 蘋果|banana 香蕉|orange 柳橙|grape 葡萄|watermelon 西瓜|strawberry 草莓|lemon 檸檬|egg 蛋|milk 牛奶|bread 麵包|rice 米飯|noodles 麵|cake 蛋糕|cookie 餅乾|candy 糖果|juice 果汁|water 水|tea 茶|pizza 披薩|hamburger 漢堡|sandwich 三明治|chocolate 巧克力|ice cream 冰淇淋|soup 湯|vegetable 蔬菜|tomato 番茄|carrot 紅蘿蔔|corn 玉米|potato 馬鈴薯|meat 肉
red 紅色|blue 藍色|yellow 黃色|green 綠色|black 黑色|white 白色|pink 粉紅色|purple 紫色|brown 棕色|gray 灰色
father 爸爸|mother 媽媽|brother 兄弟|sister 姊妹|grandfather 爺爺|grandmother 奶奶|uncle 叔叔|aunt 阿姨|baby 嬰兒|family 家人|friend 朋友|teacher 老師|student 學生|doctor 醫生|nurse 護士|farmer 農夫|cook 廚師|police officer 警察
head 頭|eye 眼睛|ear 耳朵|nose 鼻子|mouth 嘴巴|hand 手|foot 腳|leg 腿|arm 手臂|hair 頭髮|face 臉|tooth 牙齒|finger 手指
book 書|pen 原子筆|pencil 鉛筆|eraser 橡皮擦|ruler 尺|bag 書包|desk 書桌|chair 椅子|door 門|window 窗戶|classroom 教室|school 學校|library 圖書館|music 音樂|art 美術|math 數學|English 英文|computer 電腦|clock 時鐘|map 地圖
home 家|house 房子|park 公園|zoo 動物園|store 商店|hospital 醫院|bed 床|table 桌子|cup 杯子|ball 球|kite 風箏|doll 洋娃娃|car 汽車|bus 公車|bike 腳踏車|train 火車|plane 飛機|boat 船|hat 帽子|shoes 鞋子|shirt 襯衫|dress 洋裝|umbrella 雨傘
sun 太陽|moon 月亮|star 星星|rain 雨|snow 雪|wind 風|cloud 雲|tree 樹|flower 花|sea 海|mountain 山|river 河
morning 早上|afternoon 下午|evening 傍晚|night 晚上|today 今天|tomorrow 明天|yesterday 昨天|week 星期|Monday 星期一|Sunday 星期日|spring 春天|summer 夏天|fall 秋天|winter 冬天|birthday 生日
one 一|two 二|three 三|four 四|five 五|six 六|seven 七|eight 八|nine 九|ten 十|twenty 二十|hundred 一百
run 跑|walk 走路|jump 跳|swim 游泳|fly 飛|eat 吃|drink 喝|sleep 睡覺|read 閱讀|write 寫|sing 唱歌|dance 跳舞|play 玩|draw 畫畫|open 打開|close 關上|sit 坐|stand 站|listen 聽|look 看|help 幫忙|like 喜歡|go 去|come 來
big 大的|small 小的|tall 高的|short 矮的|long 長的|hot 熱的|cold 冷的|happy 快樂的|sad 難過的|angry 生氣的|tired 累的|hungry 餓的|thirsty 口渴的|new 新的|old 舊的|fast 快的|slow 慢的|good 好的|bad 壞的|beautiful 漂亮的|cute 可愛的"""

# 國中常用單字（會考常見字）
TEEN_WORDS = """abroad 在國外|achieve 達成|advice 建議|afford 負擔得起|agree 同意|airport 機場|allow 允許|almost 幾乎|already 已經|amazing 令人驚奇的|ancient 古代的|announce 宣布|anxious 焦慮的|appear 出現|apply 申請|arrive 抵達|attend 參加|attention 注意|avoid 避免|award 獎
balance 平衡|battery 電池|behavior 行為|believe 相信|belong 屬於|borrow 借入|brave 勇敢的|breathe 呼吸|bright 明亮的|broadcast 廣播|budget 預算|burn 燃燒|business 生意|celebrate 慶祝|century 世紀|challenge 挑戰|chance 機會|cheap 便宜的|choose 選擇|citizen 公民
climate 氣候|collect 收集|comfortable 舒適的|common 常見的|communicate 溝通|compare 比較|complain 抱怨|complete 完成|confident 有自信的|connect 連接|consider 考慮|continue 繼續|control 控制|convenient 方便的|conversation 對話|culture 文化|curious 好奇的|customer 顧客|damage 損害|dangerous 危險的
decide 決定|decorate 裝飾|delicious 美味的|depend 依賴|describe 描述|develop 發展|difference 差異|difficult 困難的|disappear 消失|discover 發現|discuss 討論|distance 距離|earn 賺|education 教育|effort 努力|electricity 電|emergency 緊急狀況|encourage 鼓勵|energy 能量|enjoy 享受
environment 環境|especially 尤其|event 活動|exactly 確切地|excellent 優秀的|exchange 交換|excited 興奮的|exercise 運動|experience 經驗|explain 解釋|express 表達|factory 工廠|fail 失敗|famous 有名的|fashion 時尚|favorite 最喜愛的|festival 節慶|final 最後的|foreign 外國的|forget 忘記
forgive 原諒|freedom 自由|friendly 友善的|furniture 家具|future 未來|generous 慷慨的|government 政府|graduate 畢業|guess 猜|guest 客人|habit 習慣|health 健康|history 歷史|honest 誠實的|hope 希望|imagine 想像|important 重要的|improve 改善|include 包括|increase 增加
information 資訊|interview 面試|introduce 介紹|invent 發明|invite 邀請|journey 旅程|knowledge 知識|language 語言|lazy 懶惰的|librarian 圖書館員|lonely 寂寞的|medicine 藥|memory 記憶|message 訊息|mistake 錯誤|modern 現代的|moment 片刻|nervous 緊張的|nobody 沒有人|notice 注意到
ocean 海洋|opinion 意見|patient 有耐心的|peace 和平|perfect 完美的|perhaps 也許|pollution 汙染|polite 有禮貌的|popular 受歡迎的|possible 可能的|practice 練習|prepare 準備|present 禮物|prevent 預防|price 價格|prize 獎品|problem 問題|produce 生產|promise 承諾|protect 保護
proud 驕傲的|provide 提供|purpose 目的|quiet 安靜的|raise 舉起|reason 理由|receive 收到|recycle 回收|refuse 拒絕|relax 放鬆|remember 記得|repeat 重複|report 報告|respect 尊重|responsible 負責的|result 結果|return 歸還|rule 規則|safe 安全的|save 節省
scared 害怕的|scenery 風景|science 科學|season 季節|secret 祕密|serious 嚴重的|share 分享|shy 害羞的|silent 沉默的|simple 簡單的|skill 技能|society 社會|solve 解決|special 特別的|spend 花費|strange 奇怪的|stranger 陌生人|success 成功|suddenly 突然地|suggest 建議
support 支持|surprise 驚喜|survive 生存|talent 天分|technology 科技|temperature 溫度|terrible 糟糕的|thankful 感激的|tradition 傳統|traffic 交通|translate 翻譯|travel 旅行|trust 信任|typhoon 颱風|uniform 制服|universe 宇宙|useful 有用的|vacation 假期|valuable 有價值的|village 村莊
visitor 訪客|volunteer 志工|wallet 錢包|waste 浪費|weather 天氣|weight 體重|wonderful 美好的|worry 擔心"""

def cut(t):
    return re.split(r'[＝=；;。]|\s\(', t)[0].strip()[:18]

def card_of(ex):
    m = re.match(r"^([A-Za-z][A-Za-z '’.\-\/]*?)\s*\(([a-z]+\.?[^)]*)\)\s*(?:\[[^\]]*\]\s*)?(.+)$", ex or '')
    if m: return m.group(1).strip(), cut(m.group(3))
    n = re.match(r"^([A-Za-z][^一-鿿（]*?)\s*([一-鿿（].*)$", ex or '')
    if n and len(n.group(1)) <= 30: return n.group(1).strip(), cut(n.group(2))
    return None

def parse_list(text):
    out = []
    for item in text.replace('\n', '|').split('|'):
        item = item.strip()
        if not item: continue
        w, zh = item.rsplit(' ', 1)
        out.append((w.strip(), zh.strip()))
    return out

def build(tier, extra):
    path = os.path.join(BANKS, tier + '.json'); data = json.load(open(path, encoding='utf-8'))
    data['units'] = [u for u in data['units'] if u['id'] != UNIT[tier]]
    pairs = {}
    for u in data['units']:
        for k in 'vgc':
            for r in u.get(k, []):
                c = card_of(r[3] if len(r) > 3 else '')
                # 只要「小寫開頭的單字／短語」配「8 個字以內的純中文」，把文法說明之類的排除掉
                if c and re.fullmatch(r"[a-z][a-z '\-]{0,24}", c[0]) and re.fullmatch(r'[一-鿿、]{1,8}', c[1]) \
                   and not re.search(r'動詞|名詞|形容詞|副詞|介系詞|被動|用法|句型|片語|不可|後接|搭配|問|表示', c[1]):
                    pairs.setdefault(c[0].lower(), c)
    for w, zh in extra: pairs.setdefault(w.lower(), (w, zh))
    rnd = random.Random('vocab-' + tier)
    items = sorted(pairs.values(), key=lambda p: p[0].lower())
    if len(items) > LIMIT[tier]: items = sorted(rnd.sample(items, LIMIT[tier]), key=lambda p: p[0].lower())
    # 同一個中文意思只留一個字，免得選項裡有兩個對的
    seen_zh, uniq = set(), []
    for w, zh in items:
        if zh in seen_zh: continue
        seen_zh.add(zh); uniq.append((w, zh))
    qs = []
    for i, (w, zh) in enumerate(uniq):
        others = [p for p in uniq if p[0] != w]
        for direction in ('en', 'zh'):
            wrong = rnd.sample(others, 3)
            if direction == 'en':
                opts = [zh] + [p[1] for p in wrong]; q = f'「{w}」是什麼意思？'
            else:
                opts = [w] + [p[0] for p in wrong]; q = f'「{zh}」的英文是？'
            order = list(range(4)); rnd.shuffle(order)
            shuffled = [opts[j] for j in order]
            qs.append([q, shuffled, order.index(0), f'{w} {zh}'])
    data['units'].append({'id': UNIT[tier], 'pub': '自動出題', 'grade': {'kid': '國小', 'teen': '國中', 'sage': '高中'}[tier],
        'name': '單字意思（自動出題）', 'short': '單字意思', 'src': {'v': '單字意思'}, 'tags': {'v': '單字'}, 'v': qs, 'g': [], 'c': []})
    json.dump(data, open(path, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
    print(tier, '單字', len(uniq), '題', len(qs))

if __name__ == '__main__':
    build('kid', parse_list(KID_WORDS))
    build('teen', parse_list(TEEN_WORDS))
    build('sage', [])
