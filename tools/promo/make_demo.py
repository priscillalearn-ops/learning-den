# 從目前的 index.html 產生宣傳影片用的示範頁 learning-den/_promo.html（單機版＋示範資料，網址 #場景 切換）。
# 用法：python3 make_demo.py  →  BASE=http://localhost:8780/_promo.html python3 shoot.py 場景…
# 字型：把 DotGothic16.ttf 放在 learning-den/_promo_font.ttf（headless Chrome 抓不到 Google 字型）。截完圖記得刪掉這兩個檔案。
import os, re
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
s = open(os.path.join(ROOT, 'index.html'), encoding='utf-8').read()
STYLE = ("<style>@font-face{font-family:'DotGothic16';src:url('_promo_font.ttf')}"
         ".demo,#spd{display:none!important}html,body{width:390px!important;max-width:390px;overflow:hidden}"
         ".app{border-inline:0!important}.modal{right:auto!important;width:390px}.toast{display:none!important}</style>\n")
s = s.replace('<link rel="preconnect"', STYLE + '<link rel="preconnect"', 1)
s = s.replace('<script src="https://cdn.jsdelivr.net', "<script>window.requestAnimationFrame=f=>setTimeout(()=>f(performance.now()),16);window.cancelAnimationFrame=id=>clearTimeout(id);</script>\n<script src=\"https://cdn.jsdelivr.net", 1)
s = re.sub(r"const ONLINE=[^;]*;", "const ONLINE=false;", s, 1)
SCENES = r"""
/* 題庫是另外載入的，等載完再擺場景 */
loadBank(location.hash.slice(1).startsWith('kid')?'kid':'sage').then(function(){
 const sc=location.hash.slice(1)||'city';
 S=fresh();S.tutorialDone=true;S.starterDone=true;S.scopeTipDone=true;S.loginDay=today();EVENTS=[];/* 宣傳影片不放有日期的活動橫幅，才不會過期 */S.lastGreet=today();S.name='小明';S.tier=sc.startsWith('kid')?'kid':'sage';S.grade=sc.startsWith('kid')?'國小':'高二';S.cls='167';S.remind='2000';S.cityV=CITY_V;
 const d=new Date();
 for(let i=0;i<12;i++){const x=new Date(d);x.setDate(d.getDate()-i);S.days[keyOf(x)]=true;S.minutes[keyOf(x)]=60}
 ['serene','deliberate','fasten','reduce','interpret','overwhelmed','memorable','recall','skim','discover','curious','journey'].forEach((w,i)=>S.cards[w]={zh:['寧靜的','深思熟慮的','繫緊','降低','詮釋','不知所措的','難忘的','回想起','略讀','發現','好奇的','旅程'][i],n:1+(i%3===0)});
 S.meals={[today()]:'noodles'};S.joined=today();
 const HW=['wall_halloween','floor_halloween','win_hallow','poster_ghost','bed_coffin','lamp_ghost','plant_jack','rug_web','pet_pumpkin','hat_witch_purple','top_vampire','acc_fangs'];
 S.owned={};HW.forEach(id=>S.owned[id]=ITEM[id].price);
 S.look={room:{...DEFAULT_LOOK.room,wall:'wall_halloween',floor:'floor_halloween',window:'win_hallow',poster:'poster_ghost',bed:'bed_coffin',plant:'plant_jack',rug:'rug_web',lamp:'lamp_ghost',pet:'pet_pumpkin'},outfit:{hat:'hat_witch_purple',top:'top_vampire',acc:'acc_fangs',hair:'hair_brown',skin:'skin_1'}};
 if(sc==='kid')S.scopes.kid=['GP'];
 S.farm={items:{wheat:6,carrot:3,tomato:4,pumpkin:2,sunflower:1},cooked:{}};
 {const now=Date.now(),H=3600e3;S.garden={used:{},helpers:[{name:'熬夜刷題的熊貓',kind:'help',crop:'pumpkin'},{name:'喝珍奶的企鵝',kind:'steal',crop:'tomato',amount:6},{name:'背單字的仙人掌',kind:'steal',crop:'carrot',caught:true}],scare:new Date(now+20*H).toISOString(),
   plots:[{slot:0,crop:'pumpkin',planted_at:new Date(now-13*H).toISOString(),waters:3},{slot:1,crop:'sunflower',planted_at:new Date(now-10*H).toISOString(),waters:2},{slot:2,crop:'carrot',planted_at:new Date(now-1*H).toISOString(),waters:1},
     {slot:3,crop:'tomato',planted_at:new Date(now-7*H).toISOString(),waters:2,stolen:1},{slot:4,crop:'wheat',planted_at:new Date(now-.2*H).toISOString(),waters:0}]}}
 S.seenVer=CHANGES[0].v;
 S.tx=0;S.tx=1280-(coinsEarned()-coinsSpent());
 S.gday={d:today(),match:12,speed:0,granny:0,tower:0,halloween:0,chal:1};S.bank={balance:860,settled:today(),log:[]};S.glv={match:3,speed:2,granny:4,tower:3};
 save();
 const place=(o,x,y)=>Object.assign(o,{x,y,px:x*16+8,py:y*16+8,path:[],petX:null});
 if(sc==='city'||sc==='map'){go('city');{place(city.me,12,11);const sp=[[9,9],[16,11],[19,8],[7,12],[20,11],[14,12],[11,8]];city.npcs.forEach((n,i)=>place(n,...sp[i%sp.length]));
   city.bubbles.push({who:city.npcs[1],txt:'今天打卡了嗎？',until:performance.now()+99999});if(sc==='map')openCityMap()}}
 if(sc==='hw'){go('city');{place(city.me,12,11);hwStart();const h=city.hw;h.got=9;h.end=performance.now()+52000;
   h.candies=[[9,11],[10,13],[13,13],[15,11],[17,12],[8,9],[19,13],[14,7]].map(([x,y],i)=>({x,y,k:i%3}));
   h.ghosts.forEach((g,i)=>{g.cool=0;g.px=[8,17,15][i]*16+8;g.py=[13,9,13][i]*16+8})}}
 if(sc==='daily'){const q=todayQ();const k=(!q.t||q.t==='v')?q:cardPool()[0];S.answers[dkey()]={c:q.a,ok:true,q,card:{w:k.w,zh:k.zh}};S.days[today()]=true;S.comments[dkey()]=['這題我上週才背過！'];save();go('daily')}
 if(sc==='room'){S.timerLen=120;save();go('room');startFocus(120);tm.end=Date.now()+(83*60+45)*1000;tm.left=83*60+45;drawClock();{rchat.open=true;
   rchat.msgs=[{id:1,user_id:'bot',name:'喝第三杯咖啡的貓頭鷹',tier:'sage',body:'學測倒數 100 天，大家一起撐住',created_at:new Date(Date.now()-420000).toISOString()},
     {id:2,user_id:'bot',name:'熬夜刷題的熊貓',tier:'sage',body:'這題的 effect / affect 我又錯了',created_at:new Date(Date.now()-240000).toISOString()},
     {id:3,user_id:'me',name:'小明',tier:'sage',body:'加油',created_at:new Date(Date.now()-60000).toISOString()}];drawRoomChat();
     const v=$('#view');v.scrollTop=$('#rchat').offsetTop-260}}
 if(sc==='home'){renderHome();setTimeout(()=>{},0)}
 if(sc==='homegarden'){renderHome();const v=$('#view');v.scrollTop=($('#gdn')||v).offsetTop-60}
 if(sc==='cook'){renderFood();}
 if(sc==='whatsnew'){go('city');showWhatsNew()}
 if(sc==='login'){const y=new Date();y.setDate(y.getDate()-1);S.logins=[keyOf(y)];S.loginStreak=4;S.loginDay='';save();go('city');showLoginReward()}
 if(sc==='chars'){S=fresh();save();renderOnboard();document.querySelector('#view').scrollTop=document.querySelector('#cpick').offsetTop-140}
 if(sc==='garden'){const now=Date.now(),H=3600e3;S.garden={used:{},helpers:[{name:'熬夜刷題的熊貓',crop:'pumpkin'},{name:'喝珍奶的企鵝',crop:'sunflower'},{name:'背單字的仙人掌',crop:'carrot'}],
   plots:[{slot:0,crop:'pumpkin',planted_at:new Date(now-13*H).toISOString(),waters:3},{slot:1,crop:'sunflower',planted_at:new Date(now-10*H).toISOString(),waters:2},{slot:2,crop:'carrot',planted_at:new Date(now-1*H).toISOString(),waters:1},
     {slot:3,crop:'tomato',planted_at:new Date(now-7*H).toISOString(),waters:2},{slot:4,crop:'wheat',planted_at:new Date(now-.2*H).toISOString(),waters:0}]};save();renderGarden()}
 if(sc==='guild'){S.cls='167';save();renderGuild()}
 if(sc==='board'){go('room');boardTab='all';drawBoard();const v=$('#view');v.scrollTop=$('#board').offsetTop-120}
 if(sc==='mistakes'){const p=pool();[0,3,5,8].forEach((i,k)=>{for(let j=0;j<=k%3;j++)addWrong(p[i])});S.wrongOk={[p[0].id]:2,[p[3].id]:1};save();renderMistakes();const dd=document.querySelector('#view details');if(dd)dd.open=true}
 if(sc==='shop'){renderShop('room','city');setTimeout(()=>{const v=$('#view'),it=v.querySelector('[data-it=bed_coffin],[data-id=bed_coffin]');if(it)v.scrollTop=it.offsetTop-200},300)}
 if(sc==='levels'){go('games');pickLevel('tower')}
 if(sc==='games')go('games');
 if(sc==='kid')go('daily');
 if(sc==='me')go('me');
 if(sc==='food'){S.meals={};save();renderFood()}
 if(sc==='quest')renderQuests();
 if(sc==='gacha'){gGacha()}
 if(sc==='granny'){gGranny(3);setTimeout(()=>{const k=key=>document.dispatchEvent(new KeyboardEvent('keydown',{key}));['ArrowRight','ArrowRight','ArrowDown','ArrowDown'].forEach(k)},300)}
 if(sc==='tower')gTower(3);
 if(sc==='start'){S=fresh();save();renderOnboard();document.querySelector('#nm').value='小美';document.querySelector('[data-t=teen]').click();setTimeout(()=>{const g=document.querySelector('[data-gr=國二]');g&&g.click();document.querySelector('[data-ci="4"]').click();const v=document.querySelector('#view');v.scrollTop=document.querySelector('#gradeBox').offsetTop-200},100)}
 if(sc==='gift'){ME='me';const F='f1';curTab='friends';$('#nav').hidden=false;openChat(F,'芸芸').then(()=>{chatWith.msgs=[{id:1,sender:F,body:'明天一起去讀書房嗎？',created_at:new Date(Date.now()-600000).toISOString()},{id:2,sender:'me',body:'好啊！我連續 12 天了',created_at:new Date(Date.now()-300000).toISOString()}];drawChat();giftModal(F,'芸芸')})}
});
"""
s = s.replace("\nboot();\n</script>", "\n" + SCENES + "\n</script>", 1)
open(os.path.join(ROOT, '_promo.html'), 'w', encoding='utf-8').write(s)
print('wrote _promo.html')
