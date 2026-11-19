# 產生錄影用的示範頁 learning-den/_rec.html（單機版、只在錄影時用，不影響線上）
import re, sys, os
ROOT = sys.argv[1]
s = open(os.path.join(ROOT, 'index.html'), encoding='utf-8').read()
STYLE = ("<style>@font-face{font-family:'DotGothic16';src:url('_rec_font.ttf')}"
         ".demo,#spd{display:none!important}.toast{display:none!important}</style>\n")
s = '<meta charset="utf-8">\n' + s.replace('<link rel="preconnect"', STYLE + '<link rel="preconnect"', 1)
s = re.sub(r'<link rel="(preconnect|stylesheet)" href="https://fonts[^>]*>\n', '', s)
s = re.sub(r'<script src="https://cdn.jsdelivr[^>]*></script>\n', '', s)
s = re.sub(r"const ONLINE=[^;]*;", "const ONLINE=false;", s, count=1)
# 錄影環境才有：盲盒照劇本開（線上機率不動）；每日上限那句拿掉
s = s.replace("・今天還能抽 ${GACHA_DAY-g.pulls} 次", "", 1)
SCENE = r"""
loadBank('sage').then(function(){
 S=fresh();S.tutorialDone=true;S.starterDone=true;S.scopeTipDone=true;S.loginDay=today();EVENTS=[];S.lastGreet=today();
 S.name='小明';S.tier='sage';S.grade='高二';S.cls='167';S.remind='2000';S.cityV=CITY_V;S.seenVer=CHANGES[0].v;
 const d=new Date();for(let i=0;i<12;i++){const x=new Date(d);x.setDate(d.getDate()-i);S.days[keyOf(x)]=true;S.minutes[keyOf(x)]=60}
 S.meals={[today()]:'noodles'};S.newbieDone=true;S.joined=today();S.answers[dkey()]={c:0,ok:true,q:todayQ(),card:null};
 S.owned={hat_santa:150};S.look={room:{...DEFAULT_LOOK.room},outfit:{...DEFAULT_LOOK.outfit,hat:'hat_santa'}};
 S.gacha={pity:3,day:today(),pulls:0,free:today(),tickets:0};
 S.advent={yr:d.getFullYear(),opened:{}};
 S.tx=0;S.tx=1260-(coinsEarned()-coinsSpent());
 S.gday={d:today(),match:0,speed:0,granny:0,tower:0,halloween:0,chal:1};
 save();
 go('city');
 const place=(o,x,y)=>Object.assign(o,{x,y,px:x*16+8,py:y*16+8,path:[],petX:null});
 place(city.me,16,14);
 window.REC_READY=true;
});
/* 錄影劇本：20 抽裡只有一個 SSR，十連抽的保底 SR 照規則保留 */
window.REC_PLAN=[['N','R','N','N','R','N','N','R','N','SR'],['N','R','N','N','N','SSR','N','R','N','N']];
gachaLocal=function(n){
  const g=gstate(),plan=REC_PLAN.shift()||[],out=[];g.pulls=0;S.tx=(S.tx||0)-(n===1?GACHA_ONE:GACHA_TEN);
  for(let i=0;i<n;i++){g.pity++;const rar=plan[i]||'N';if(rar==='SSR')g.pity=0;
    const l=SHOP.filter(x=>x.gacha===rar),fresh_=l.filter(x=>S.owned[x.id]==null),it=(fresh_.length?fresh_:l)[Math.floor(Math.random()*(fresh_.length||l.length))];
    const dup=S.owned[it.id]!=null,refund=dup?RARITY[rar][3]:0;if(dup)S.tx+=refund;else S.owned[it.id]=0;out.push({item:it.id,rarity:rar,dup,refund})}
  save();return out};
"""
assert "\nboot();\n</script>" in s
s = s.replace("\nboot();\n</script>", "\n" + SCENE + "\n</script>", 1)
open(os.path.join(ROOT, '_rec.html'), 'w', encoding='utf-8').write(s)
print('ok')
