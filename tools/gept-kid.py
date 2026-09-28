# 國小（見習魔法師）題庫：全民英檢初級「風格」的原創題目（不是官方考古題）。
# 每題寫法：(題目, [正解, 誘答...], 解析, 圖)；正解一律寫第一個，產生時會固定打散選項順序。
# 用法：在 Magic_World_App 資料夾執行  python3 learning-den/tools/gept-kid.py
# 會把 learning-den/index.html 裡 KID_BANK_START/END 之間換成新的題庫。
import json, random, re, pathlib

P = [  # 看圖認字（圖是 App 裡的像素圖）
 ("What is this?", ["apple", "orange", "banana", "lemon"], "apple (n.) 蘋果", "apple"),
 ("What is this?", ["cat", "dog", "bird", "duck"], "cat (n.) 貓", "cat"),
 ("What is this?", ["fish", "frog", "fox", "fan"], "fish (n.) 魚", "fish"),
 ("What is this?", ["sun", "moon", "star", "rain"], "sun (n.) 太陽", "sun"),
 ("What is this?", ["tree", "flower", "grass", "leaf"], "tree (n.) 樹", "tree"),
 ("What is this?", ["book", "bag", "box", "bed"], "book (n.) 書", "book"),
 ("What is this?", ["dog", "cow", "pig", "horse"], "dog (n.) 狗", "dog"),
 ("What is this?", ["star", "sky", "cloud", "sun"], "star (n.) 星星", "star"),
 ("What is this?", ["owl", "chicken", "duck", "parrot"], "owl (n.) 貓頭鷹", "owl"),
 ("What is this?", ["rabbit", "mouse", "bear", "tiger"], "rabbit (n.) 兔子", "bunny"),
 ("What is this?", ["penguin", "panda", "monkey", "zebra"], "penguin (n.) 企鵝", "penguin"),
 ("What is this?", ["dinosaur", "dragon", "snake", "lion"], "dinosaur (n.) 恐龍", "dino"),
 ("What shape is this?", ["heart", "circle", "square", "triangle"], "heart (n.) 心形；心", "heart"),
 ("What is this?", ["fire", "water", "ice", "wind"], "fire (n.) 火", "fire"),
 ("What is this?", ["coin", "card", "key", "ring"], "coin (n.) 硬幣", "coin"),
 ("What is this?", ["lamp", "chair", "desk", "door"], "lamp (n.) 燈；檯燈", "lamp"),
]
V = [  # 字彙
 ("I'm ____. Can I have some bread?", ["hungry", "angry", "tired", "happy"], "hungry (adj.) 餓的"),
 ("It's cold today. Put on your ____.", ["jacket", "shorts", "sandals", "sunglasses"], "jacket (n.) 夾克；外套"),
 ("My mother's brother is my ____.", ["uncle", "aunt", "cousin", "sister"], "uncle (n.) 舅舅；叔叔；伯伯"),
 ("Tom brushes his ____ every morning.", ["teeth", "feet", "hands", "ears"], "teeth (n.) 牙齒（tooth 的複數）"),
 ("It's raining. Take an ____ with you.", ["umbrella", "apple", "eraser", "egg"], "umbrella (n.) 雨傘"),
 ("The library is a ____ place. Please don't talk.", ["quiet", "noisy", "busy", "dirty"], "quiet (adj.) 安靜的"),
 ("My sister likes to ____ songs.", ["sing", "eat", "cook", "read"], "sing (v.) 唱歌"),
 ("There are seven days in a ____.", ["week", "month", "year", "day"], "week (n.) 星期；週"),
 ("Wednesday comes after ____.", ["Tuesday", "Monday", "Thursday", "Sunday"], "Tuesday (n.) 星期二"),
 ("I drink ____ every morning. It's good for me.", ["milk", "rice", "bread", "noodles"], "milk (n.) 牛奶"),
 ("A doctor works in a ____.", ["hospital", "school", "bank", "zoo"], "hospital (n.) 醫院"),
 ("Please ____ the window. It's cold.", ["close", "open", "clean", "paint"], "close (v.) 關上"),
 ("My grandpa is eighty, but he is very ____.", ["healthy", "sick", "young", "short"], "healthy (adj.) 健康的"),
 ("Look! The baby is ____. Don't wake her up.", ["sleeping", "running", "jumping", "singing"], "sleep (v.) 睡覺"),
 ("We can see many animals at the ____.", ["zoo", "library", "bookstore", "bank"], "zoo (n.) 動物園"),
 ("I use an ____ to fix my mistakes.", ["eraser", "ruler", "marker", "crayon"], "eraser (n.) 橡皮擦"),
 ("Summer is ____. Let's go swimming.", ["hot", "cold", "cool", "snowy"], "hot (adj.) 熱的"),
 ("Ten plus five is ____.", ["fifteen", "fifty", "five", "twenty"], "fifteen (n.) 十五"),
 ("My ____ is a teacher. She teaches English.", ["mother", "father", "brother", "uncle"], "mother (n.) 媽媽"),
 ("I have a ____. I need to see a doctor.", ["headache", "hamburger", "homework", "holiday"], "headache (n.) 頭痛"),
 ("Birds can ____ in the sky.", ["fly", "swim", "sit", "cook"], "fly (v.) 飛"),
 ("It's dark. Please turn ____ the light.", ["on", "off", "in", "at"], "turn on (phr.) 打開（電燈、電器）"),
 ("The ____ is yellow and long. Monkeys love it.", ["banana", "grape", "apple", "watermelon"], "banana (n.) 香蕉"),
 ("I go to school by ____. It's number 25.", ["bus", "bike", "foot", "boat"], "bus (n.) 公車"),
 ("It's seven in the morning. It's time for ____.", ["breakfast", "dinner", "winter", "bed"], "breakfast (n.) 早餐"),
 ("Don't ____ in the classroom. It's dangerous.", ["run", "read", "write", "listen"], "run (v.) 跑"),
 ("My favorite ____ is basketball.", ["sport", "color", "food", "animal"], "sport (n.) 運動"),
 ("Twelve months make one ____.", ["year", "week", "day", "hour"], "year (n.) 年"),
 ("My shoes are too ____. I need a bigger pair.", ["small", "big", "long", "tall"], "small (adj.) 小的"),
 ("Wash your ____ before you eat.", ["hands", "feet", "eyes", "ears"], "hand (n.) 手"),
 ("The ____ is very tall. It has a long neck.", ["giraffe", "rabbit", "mouse", "penguin"], "giraffe (n.) 長頸鹿"),
 ("I'm ____. I want to go to bed.", ["sleepy", "hungry", "thirsty", "angry"], "sleepy (adj.) 想睡的"),
 ("We buy food and drinks at the ____.", ["supermarket", "library", "hospital", "post office"], "supermarket (n.) 超級市場"),
 ("There are no clouds. The sky is ____ today.", ["blue", "gray", "black", "green"], "blue (adj.) 藍色的"),
 ("My brother can ____ the piano.", ["play", "do", "make", "go"], "play (v.) 彈奏；玩"),
 ("Kevin is my good ____. We play together every day.", ["friend", "teacher", "doctor", "parent"], "friend (n.) 朋友"),
 ("The wind is strong. It's ____ today.", ["windy", "sunny", "rainy", "snowy"], "windy (adj.) 颳風的"),
 ("I ____ my homework after dinner.", ["do", "make", "play", "take"], "do homework (phr.) 寫功課"),
 ("A ____ gives us milk.", ["cow", "cat", "duck", "dog"], "cow (n.) 母牛"),
 ("My father drives a ____ to work.", ["car", "plane", "boat", "train"], "car (n.) 汽車"),
 ("January is the ____ month of the year.", ["first", "second", "third", "last"], "first (adj.) 第一的"),
 ("She is ____. She is crying.", ["sad", "happy", "glad", "funny"], "sad (adj.) 傷心的"),
 ("Please ____ your name on the paper.", ["write", "read", "eat", "sing"], "write (v.) 寫"),
 ("The ice cream is ____. I love it!", ["delicious", "terrible", "dirty", "angry"], "delicious (adj.) 美味的"),
 ("We have English class on ____ and Friday.", ["Monday", "June", "spring", "morning"], "Monday (n.) 星期一"),
]
G = [  # 文法
 ("She ____ a student.", ["is", "am", "are", "be"], "She 是第三人稱單數，be 動詞用 is。"),
 ("They ____ my classmates.", ["are", "is", "am", "be"], "They 是複數，be 動詞用 are。"),
 ("I ____ happy today.", ["am", "is", "are", "be"], "I 的 be 動詞用 am。"),
 ("My brother ____ soccer every day.", ["plays", "play", "playing", "is play"], "主詞是第三人稱單數，現在簡單式動詞要加 s。"),
 ("Look! The children ____ in the park.", ["are playing", "play", "plays", "is play"], "Look! 表示正在發生，用現在進行式 be + V-ing。"),
 ("____ you like apples? Yes, I do.", ["Do", "Does", "Are", "Is"], "一般動詞的問句，主詞 you 用 Do。"),
 ("____ your sister like cats?", ["Does", "Do", "Is", "Are"], "your sister 是第三人稱單數，問句用 Does。"),
 ("There ____ two books on the desk.", ["are", "is", "am", "be"], "There are + 複數名詞。"),
 ("There ____ a cat under the chair.", ["is", "are", "am", "be"], "There is + 單數名詞。"),
 ("This is ____ umbrella.", ["an", "a", "two", "many"], "umbrella 是母音開頭，用 an。"),
 ("I have ____ dog. It is very cute.", ["a", "an", "two", "many"], "dog 是子音開頭的單數名詞，用 a。"),
 ("I get up ____ seven o'clock.", ["at", "in", "on", "of"], "幾點鐘前面用 at。"),
 ("My birthday is ____ May.", ["in", "at", "on", "of"], "月份前面用 in。"),
 ("We don't go to school ____ Sunday.", ["on", "in", "at", "of"], "星期幾前面用 on。"),
 ("This is Amy. ____ is my best friend.", ["She", "He", "Her", "It"], "Amy 是女生，當主詞用 She。"),
 ("Tom and I are brothers. ____ live in Taipei.", ["We", "They", "Us", "He"], "Tom and I 就是 We。"),
 ("Is this your pen? No, it's not ____.", ["mine", "my", "me", "I"], "mine 等於 my pen。"),
 ("Please help ____. I can't open the box.", ["me", "I", "my", "mine"], "動詞 help 後面接受詞 me。"),
 ("I ____ to the zoo yesterday.", ["went", "go", "goes", "going"], "yesterday 用過去式，go 的過去式是 went。"),
 ("She ____ TV last night.", ["watched", "watches", "watch", "watching"], "last night 用過去式。"),
 ("____ you at home yesterday?", ["Were", "Was", "Are", "Did"], "you 的過去式 be 動詞是 were。"),
 ("He can ____ very fast.", ["run", "runs", "running", "ran"], "can 後面接原形動詞。"),
 ("I will ____ my grandma tomorrow.", ["visit", "visits", "visited", "visiting"], "will 後面接原形動詞。"),
 ("An elephant is ____ than a dog.", ["bigger", "big", "biggest", "more big"], "比較兩個東西用比較級 bigger than。"),
 ("Today is the ____ day of my life!", ["happiest", "happy", "happier", "most happy"], "the + 最高級 happiest。"),
 ("____ is your birthday? It's in June.", ["When", "Where", "Who", "What color"], "問時間用 When。"),
 ("____ is the bathroom? It's next to the kitchen.", ["Where", "When", "Who", "How"], "問地點用 Where。"),
 ("____ apples do you want? Three, please.", ["How many", "How much", "How old", "What time"], "可數名詞問數量用 How many。"),
 ("____ is this T-shirt? It's 200 dollars.", ["How much", "How many", "How old", "How long"], "問價錢用 How much。"),
 ("____ old are you? I'm ten.", ["How", "What", "Who", "Where"], "How old 問年齡。"),
 ("I don't have ____ money.", ["any", "some", "a", "many"], "否定句用 any。"),
 ("Would you like ____ tea?", ["some", "any", "a", "many"], "請別人吃喝東西的問句用 some。"),
 ("Let's ____ to the park.", ["go", "going", "goes", "went"], "Let's 後面接原形動詞。"),
 ("Don't ____ late for school.", ["be", "is", "are", "being"], "否定祈使句：Don't + 原形動詞。"),
 ("My father ____ coffee. He drinks tea.", ["doesn't drink", "don't drink", "isn't drink", "not drink"], "第三人稱單數的否定：doesn't + 原形動詞。"),
 ("Whose bag is this? It's ____.", ["Mary's", "Mary", "Marys", "of Mary"], "名字的所有格加 ’s。"),
 ("I enjoy ____ comic books.", ["reading", "read", "to read", "reads"], "enjoy 後面接 V-ing。"),
 ("He is good at ____.", ["swimming", "swim", "swims", "swam"], "介系詞 at 後面接 V-ing。"),
 ("It's 7:30. I'm ____ breakfast now.", ["having", "have", "has", "had"], "now 表示正在做，用 be + V-ing。"),
 ("Two cats ____ on the sofa.", ["are sleeping", "is sleeping", "sleeps", "am sleeping"], "Two cats 是複數，用 are + V-ing。"),
]
D = [  # 對話回應
 ("A: How are you?　B: ____", ["I'm fine, thank you.", "I'm ten years old.", "I'm a student.", "I'm from Taiwan."], "How are you? 問你好不好，回答心情或身體狀況。"),
 ("A: Nice to meet you.　B: ____", ["Nice to meet you, too.", "Goodbye.", "I'm sorry.", "You're welcome."], "第一次見面的回答：Nice to meet you, too."),
 ("A: Thank you for your help.　B: ____", ["You're welcome.", "Yes, please.", "I'm fine.", "See you."], "別人道謝時回答 You're welcome.（不客氣）"),
 ("A: I'm sorry I'm late.　B: ____", ["That's OK.", "You're welcome.", "Me too.", "Good idea."], "別人道歉時回答 That's OK.（沒關係）"),
 ("A: What's your name?　B: ____", ["My name is Lily.", "I'm fine.", "It's Monday.", "I'm twelve."], "問名字就回答名字。"),
 ("A: What time is it?　B: ____", ["It's three o'clock.", "It's Friday.", "It's sunny.", "It's my pen."], "What time 問幾點。"),
 ("A: What day is today?　B: ____", ["It's Thursday.", "It's hot.", "It's ten thirty.", "It's my book."], "What day 問星期幾。"),
 ("A: How's the weather today?　B: ____", ["It's rainy.", "It's Sunday.", "It's eight o'clock.", "It's in the box."], "問天氣就回答晴天、下雨等。"),
 ("A: Can I use your eraser?　B: ____", ["Sure. Here you are.", "No, I can't swim.", "Yes, I am.", "It's blue."], "借東西時，Here you are. 是「拿去吧」。"),
 ("A: Would you like some juice?　B: ____", ["Yes, please.", "Yes, I do like.", "No, I'm not.", "Here you are."], "有人請你喝東西，要就說 Yes, please."),
 ("A: Where is my bag?　B: ____", ["It's under your desk.", "It's red.", "It's mine.", "It's Monday."], "Where 問地點，回答在哪裡。"),
 ("A: Happy birthday!　B: ____", ["Thank you!", "Happy birthday!", "You're welcome.", "Me too."], "別人祝你生日快樂，要說謝謝。"),
 ("A: Let's play basketball after school.　B: ____", ["Good idea!", "I'm sorry to hear that.", "You're welcome.", "Here you are."], "別人邀約，同意時說 Good idea!"),
 ("A: How old is your brother?　B: ____", ["He's eight.", "He's tall.", "He's a student.", "He's fine."], "How old 問年齡。"),
 ("A: What do you want to be in the future?　B: ____", ["I want to be a pilot.", "I like pizza.", "I went to the zoo.", "I'm in the kitchen."], "問將來想做什麼工作。"),
 ("A: Whose cap is this?　B: ____", ["It's Jack's.", "It's black.", "It's on the chair.", "It's 100 dollars."], "Whose 問是誰的。"),
 ("A: How do you go to school?　B: ____", ["By bike.", "At seven.", "With my book.", "In the morning."], "How 問交通方式，by + 交通工具。"),
 ("A: What are you doing?　B: ____", ["I'm doing my homework.", "I'm a student.", "I did my homework.", "I like homework."], "問正在做什麼，用 I'm + V-ing 回答。"),
 ("A: May I come in?　B: ____", ["Sure. Come in.", "No, you aren't.", "Yes, I may.", "I'm in."], "May I...? 是請求允許，同意說 Sure."),
 ("A: I have a cold.　B: ____", ["I'm sorry to hear that.", "That's great!", "You're welcome.", "Happy New Year!"], "聽到壞消息說 I'm sorry to hear that."),
 ("A: How much is this pencil?　B: ____", ["It's ten dollars.", "It's yellow.", "It's long.", "I have two."], "How much 問價錢。"),
 ("A: Do you have any brothers or sisters?　B: ____", ["Yes, I have one sister.", "Yes, she is.", "No, I can't.", "I'm in grade five."], "用 Do 問，回答 Yes, I have... 或 No, I don't."),
 ("A: What's your favorite food?　B: ____", ["I like noodles.", "I like green.", "I play baseball.", "I'm hungry."], "問最喜歡的食物。"),
 ("A: Goodbye!　B: ____", ["See you tomorrow!", "Good morning!", "Nice to meet you.", "How are you?"], "道別時說 See you."),
 ("A: Can you swim?　B: ____", ["Yes, I can.", "Yes, I do.", "Yes, I am.", "Yes, it is."], "用 Can 問，就用 can 回答。"),
 ("A: Is this your dog?　B: ____", ["No, it isn't.", "No, I'm not.", "No, it doesn't.", "No, they aren't."], "Is this...? 用 it is / it isn't 回答。"),
 ("A: Where are you from?　B: ____", ["I'm from Taiwan.", "I'm fine.", "I'm at school.", "I'm eleven."], "Where are you from? 問你從哪裡來。"),
 ("A: What color is your bike?　B: ____", ["It's green.", "It's new.", "It's fast.", "It's mine."], "What color 問顏色。"),
 ("A: Excuse me. Where is the library?　B: ____", ["Go straight. It's on your left.", "It opens at nine.", "I like books.", "Yes, it is."], "問路時，回答怎麼走。"),
 ("A: Let's have lunch together.　B: ____", ["Sure. Where do you want to go?", "You're welcome.", "I'm sorry to hear that.", "Nice to meet you."], "答應邀約：Sure."),
]

def shuf(rows, seed, pic=False):
    rnd = random.Random(seed); out = []
    for r in rows:
        opts = list(r[1]); ans = opts[0]; rnd.shuffle(opts)
        row = [r[0], opts, opts.index(ans), r[2]]
        if pic: row.append(r[3])
        out.append(row)
    return out

units = [
  {"id": "GP", "pub": "全民英檢初級風格", "grade": "國小", "name": "看圖認字", "short": "英檢初級", "src": {"v": "看圖認字"}, "tags": {"v": "看圖"}, "v": shuf(P, 1, True), "g": [], "c": []},
  {"id": "GV", "pub": "全民英檢初級風格", "grade": "國小", "name": "英檢初級　字彙", "short": "英檢初級", "src": {"v": "字彙"}, "tags": {"v": "字彙"}, "v": shuf(V, 2), "g": [], "c": []},
  {"id": "GG", "pub": "全民英檢初級風格", "grade": "國小", "name": "英檢初級　文法", "short": "英檢初級", "src": {"g": "文法"}, "tags": {"g": "文法"}, "v": [], "g": shuf(G, 3), "c": []},
  {"id": "GD", "pub": "全民英檢初級風格", "grade": "國小", "name": "英檢初級　對話回應", "short": "英檢初級", "src": {"c": "對話回應"}, "tags": {"c": "對話"}, "v": [], "g": [], "c": shuf(D, 4)},
]
presets = [{"name": "看圖＋字彙", "ids": ["GP", "GV"]}, {"name": "文法＋對話", "ids": ["GG", "GD"]}]
p = pathlib.Path(__file__).parent.parent / "index.html"
s = p.read_text(encoding="utf-8")
block = "/* KID_BANK_START */\nconst KID_UNITS=" + json.dumps(units, ensure_ascii=False) + ";\nconst KID_PRESETS=" + json.dumps(presets, ensure_ascii=False) + ";\n/* KID_BANK_END */"
if "/* KID_BANK_START */" in s:
    s = re.sub(r"/\* KID_BANK_START \*/.*?/\* KID_BANK_END \*/", lambda m: block, s, flags=re.S)
else:
    s = s.replace("/* JH_BANK_START */", block + "\n/* JH_BANK_START */", 1)
p.write_text(s, encoding="utf-8")
print("國小題庫：", sum(len(u["v"]) + len(u["g"]) + len(u["c"]) for u in units), "題")
