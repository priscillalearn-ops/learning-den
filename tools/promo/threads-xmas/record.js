// 錄影：CDP screencast 抓每一幀（JPEG 高畫質）＋時間戳，之後用 ffmpeg 組回影片
const {chromium}=require('playwright');const fs=require('fs');
const OUT='/tmp/claude-0/sp/rec';fs.rmSync(OUT,{recursive:true,force:true});fs.mkdirSync(OUT,{recursive:true});
(async()=>{
 const b=await chromium.launch();
 const ctx=await b.newContext({viewport:{width:390,height:844},deviceScaleFactor:2,timezoneId:'Asia/Taipei',locale:'zh-TW',hasTouch:false});
 const p=await ctx.newPage();p.on('pageerror',e=>console.log('ERR',e.message));
 await p.clock.setSystemTime(new Date('2026-12-01T15:30:00+08:00'));
 await p.goto('http://localhost:8780/_rec.html');await p.waitForFunction(()=>window.REC_READY);
 await p.evaluate(()=>{window.fx=(x,y)=>{const d=document.createElement('div');d.style.cssText=`position:fixed;left:${x-24}px;top:${y-24}px;width:48px;height:48px;border-radius:50%;border:5px solid #ffd166;box-shadow:0 0 0 3px #0f0a1a;z-index:99999;pointer-events:none`;document.body.appendChild(d);d.animate([{transform:'scale(.35)',opacity:1},{transform:'scale(1.3)',opacity:0}],{duration:650,easing:'ease-out'});setTimeout(()=>d.remove(),700)}});
 await p.waitForTimeout(800);
 const cdp=await ctx.newCDPSession(p);const frames=[];let n=0;
 cdp.on('Page.screencastFrame',async f=>{const fn=`${OUT}/f${String(n++).padStart(5,'0')}.jpg`;fs.writeFileSync(fn,Buffer.from(f.data,'base64'));frames.push([fn,f.metadata.timestamp]);try{await cdp.send('Page.screencastFrameAck',{sessionId:f.sessionId})}catch(e){}});
 await cdp.send('Page.startScreencast',{format:'jpeg',quality:92,maxWidth:780,maxHeight:1688,everyNthFrame:1});
 const marks=[];const mark=k=>{marks.push([k,Date.now()/1000]);console.log('mark',k)};
 const W=ms=>p.waitForTimeout(ms);
 const tap=async(sel,opt={})=>{const el=typeof sel==='string'?p.locator(sel).first():sel;await el.scrollIntoViewIfNeeded();const bb=await el.boundingBox();const x=bb.x+bb.width/2,y=bb.y+bb.height/2;
   await p.mouse.move(x,y);await p.evaluate(([x,y])=>fx(x,y),[x,y]);await W(opt.pre??180);await p.mouse.click(x,y)};
 const tile=async(tx,ty)=>{const [x,y]=await p.evaluate(([tx,ty])=>{const r=$('#ccv').getBoundingClientRect(),[cx,cy]=cityCam();return [r.left+(tx*TS+8-cx)/(VW*TS)*r.width,r.top+(ty*TS+8-cy)/(VH*TS)*r.height]},[tx,ty]);
   await p.evaluate(([x,y])=>fx(x,y),[x,y]);await W(180);await p.mouse.click(x,y);console.log('tile',tx,ty,x|0,y|0)};
 // ---- 1. 走到聖誕樹 ----
 mark('city');await W(1200);
 await tile(12,10);
 await p.waitForSelector('#xadv',{timeout:15000});mark('tree');await W(1600);
 await tap('#xadv');await p.waitForSelector('[data-ad="1"]');await W(900);
 await tap('[data-ad="1"]');await p.waitForSelector('[data-ao]');mark('quiz');await W(1500);
 const right=await p.evaluate(()=>{const q=document.querySelector('#adq .qtext').textContent,m=q.match(/「(.+)」/)[1],w=XMAS_WORDS.find(x=>x[0]===m||x[1]===m),ans=q.includes('意思')?w[1]:w[0];
   return [...document.querySelectorAll('[data-ao]')].findIndex(b=>b.textContent.slice(3)===ans)});
 await tap(`[data-ao="${right}"]`);await W(900);mark('opened');
 await p.waitForSelector('#adback');await W(1600);
 await p.evaluate(()=>document.querySelectorAll('.modal').forEach(m=>m.remove()));await W(500);
 // ---- 2. 走去讀書房留言 ----
 mark('walk2');await tap('#cmap');await p.waitForSelector('[data-mb="study"]');await W(900);await tap('[data-mb="study"]');
 await p.waitForSelector('#rchat .bub',{timeout:20000});
 await p.evaluate(()=>{const n=Date.now();rchat.msgs=[{id:1,user_id:'bot',name:'喝第三杯咖啡的貓頭鷹',tier:'sage',body:'學測倒數 50 天，大家撐住',created_at:new Date(n-420000).toISOString()},
   {id:2,user_id:'bot',name:'熬夜刷題的熊貓',tier:'sage',body:'effect / affect 我又搞混了',created_at:new Date(n-240000).toISOString()},
   {id:3,user_id:'bot',name:'愛讀冷笑話的鷹',tier:'sage',body:'今天也專注 2 小時！',created_at:new Date(n-90000).toISOString()}];drawRoomChat()});await W(700);
 await p.evaluate(()=>{const v=$('#view');v.scrollTo({top:$('#rchat').offsetTop-330,behavior:'smooth'})});mark('room');await W(1200);
 await tap('#rcin',{pre:150});await p.keyboard.type('聖誕節前要把這本單字背完！',{delay:110});await W(400);
 await tap('#rcsend');mark('sent');await W(1800);
 const nb=await p.evaluate(()=>rchat.msgs.filter(m=>m.user_id==='bot').length);
 await p.evaluate(()=>{rchat.msgs.push({id:Date.now(),user_id:'bot',name:'喝第三杯咖啡的貓頭鷹',tier:'sage',body:'一起衝！我也在背 7000 單',created_at:new Date().toISOString()});drawRoomChat()});
 await W(1800);
 // ---- 3. 去遊樂場抽盲盒 ----
 await tap('[data-tab="city"], #nav button:first-child');await p.waitForSelector('#ccv');await W(700);mark('walk3');
 await tap('#cmap');await p.waitForSelector('[data-mb="arcade"]');await W(900);await tap('[data-mb="arcade"]');await p.waitForSelector('[data-g="gacha"]',{timeout:20000});await W(600);
 await tap('[data-g="gacha"]');await p.waitForSelector('#g10');mark('gacha');await W(1300);
 await tap('#g10');await p.waitForSelector('#gok');await W(3300);mark('ten1');await W(1300);
 await tap('#gok');await p.waitForSelector('#g10');await W(700);
 await tap('#g10');await p.waitForSelector('#gok');mark('ten2');await W(5200);
 mark('end');
 await cdp.send('Page.stopScreencast');await W(300);
 fs.writeFileSync(OUT+'/frames.json',JSON.stringify({frames,marks}));
 console.log('frames',frames.length,'dur',frames.at(-1)[1]-frames[0][1]);
 await b.close()})();
