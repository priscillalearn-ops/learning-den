-- =====================================================================
-- 一次補齊（2026-11-18）：把 11/9 之後要跑的更新合在一起，照順序執行。
-- 每一段都可以重跑：已經跑過的部分不會出錯，也不會重複發金幣。
--   1. 11/09 聖誕降臨月曆
--   2. 11/15 冒險打怪、躲貓貓、坐騎
--   3. 11/16 段考預備週加成
--   4. 11/17 探險隊、NPC 謝禮（含最新的 claim_game：所有小遊戲都在這裡）
--   5. 11/18 探險隊員存資料庫
-- =====================================================================


-- ▼▼▼ update-2026-11-09-聖誕降臨月曆.sql ▼▼▼
-- =====================================================================
-- 聖誕降臨月曆（2026-11-09；整份重跑即可）
-- 12/1～12/25 每天可以開當天那一格：資料庫出一題聖誕單字（照學生等級），答對才打開。
--   答錯會告訴你正確答案，可以再要一題，直到答對為止（每 2 秒最多出一題）。
-- 獎勵：平常 20 金幣、5／10／15／20 號 50 金幣、24／25 號 100 金幣。
--   今年開滿 10 格送「雪人」寵物、開滿 20 格送「金色聖誕帽」（只能從月曆拿，不能買）。
-- 錯過的日子不能補開，所以 25 格裡開到 20 格就夠了。
-- =====================================================================

create table if not exists public.advent_opens (
  user_id uuid not null references public.profiles on delete cascade,
  yr int not null,
  day int not null,
  coins int not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, yr, day)
);
alter table public.advent_opens enable row level security;
drop policy if exists "看自己開過的月曆" on public.advent_opens;
create policy "看自己開過的月曆" on public.advent_opens for select to authenticated using (user_id = auth.uid());

-- 出過的題目（只給資料庫函式用，學生看不到答案）
create table if not exists public.advent_asks (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles on delete cascade,
  right_text text not null,
  ans int not null,
  used boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.advent_asks enable row level security;

insert into public.shop_items (id, slot, price, avail_from, avail_until, bundle) values
  ('pet_snowman', 'pet', 9999, '12-01', '12-31', 'advent'),
  ('hat_goldsanta', 'hat', 9999, '12-01', '12-31', 'advent')
on conflict (id) do update set slot = excluded.slot, price = excluded.price, avail_from = excluded.avail_from,
  avail_until = excluded.avail_until, bundle = excluded.bundle;

-- 聖誕單字：1 國小、2 國中、3 高中（網頁的 XMAS_WORDS 要跟這裡一樣）
create or replace function public.xmas_words()
returns table (en text, zh text, lv int)
language sql immutable as $$
  values
  ('snow','雪',1),('tree','樹',1),('star','星星',1),('gift','禮物',1),('bell','鈴鐺',1),('sock','襪子',1),('cake','蛋糕',1),('cold','冷的',1),
  ('red','紅色的',1),('green','綠色的',1),('hat','帽子',1),('card','卡片',1),('candle','蠟燭',1),('cookie','餅乾',1),('snowman','雪人',1),('happy','快樂的',1),
  ('reindeer','麋鹿',2),('chimney','煙囪',2),('sleigh','雪橇',2),('ornament','裝飾品',2),('stocking','聖誕襪',2),('wrap','包裝',2),('celebrate','慶祝',2),('holiday','假期',2),
  ('jingle','叮噹聲',2),('carol','聖誕頌歌',2),('snowflake','雪花',2),('mitten','連指手套',2),('scarf','圍巾',2),('fireplace','壁爐',2),('wish','願望',2),('angel','天使',2),
  ('wreath','花圈',3),('mistletoe','槲寄生',3),('festive','節日氣氛的',3),('gingerbread','薑餅',3),('tradition','傳統',3),('generous','慷慨的',3),('eve','前夕',3),('merry','歡樂的',3),
  ('frost','霜',3),('blizzard','暴風雪',3),('cozy','溫暖舒適的',3),('gratitude','感激',3),('tinsel','金蔥彩條',3),('evergreen','常青樹',3),('festival','節慶',3),('chestnut','栗子',3)
$$;

-- 今天是月曆的第幾格（12/1～12/25 以外是 null）
create or replace function public.advent_day()
returns int language sql stable as $$
  select case when extract(month from public.taipei_today()) = 12 and extract(day from public.taipei_today()) <= 25
    then extract(day from public.taipei_today())::int end;
$$;

create or replace function public.advent_state()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'today', public.advent_day(),
    'opened', coalesce((select json_object_agg(day, coins) from public.advent_opens
      where user_id = auth.uid() and yr = extract(year from public.taipei_today())::int), '{}'::json));
$$;

create or replace function public.advent_ask()
returns json language plpgsql security definer set search_path = public as $$
declare d int := public.advent_day(); y int := extract(year from public.taipei_today())::int;
  t text; lvs int[]; w record; en_q boolean := random() < 0.5; rt text; opts text[]; aid bigint;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if d is null then raise exception '降臨月曆只在 12/1 到 12/25 開放'; end if;
  if exists (select 1 from public.advent_opens where user_id = auth.uid() and yr = y and day = d) then
    raise exception '今天這格已經打開了，明天再來！'; end if;
  if exists (select 1 from public.advent_asks where user_id = auth.uid() and created_at > now() - interval '2 seconds') then
    raise exception '慢一點，再試一次'; end if;
  select tier into t from public.profiles where id = auth.uid();
  if t is null then raise exception '請先建立角色'; end if;
  lvs := case t when 'kid' then array[1] when 'sage' then array[2, 3] else array[1, 2] end;
  select * into w from public.xmas_words() x where x.lv = any(lvs) order by random() limit 1;
  rt := case when en_q then w.zh else w.en end;
  select array_agg(o order by random()) into opts from (
    select rt as o
    union all
    select * from (select case when en_q then x.zh else x.en end from public.xmas_words() x
      where x.lv = any(lvs) and x.en <> w.en order by random() limit 3) z
  ) q;
  insert into public.advent_asks (user_id, right_text, ans) values (auth.uid(), rt, array_position(opts, rt) - 1) returning id into aid;
  return json_build_object('ask', aid, 'q', case when en_q then '「' || w.en || '」是什麼意思？' else '「' || w.zh || '」的英文是？' end,
    'options', to_json(opts));
end $$;

create or replace function public.advent_open(p_ask bigint, p_choice int)
returns json language plpgsql security definer set search_path = public as $$
declare d int := public.advent_day(); y int := extract(year from public.taipei_today())::int;
  a public.advent_asks; amt int; total int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select * into a from public.advent_asks where id = p_ask and user_id = auth.uid() for update;
  if not found or a.used then raise exception '這題已經答過了，再開一次'; end if;
  if a.created_at < now() - interval '5 minutes' then raise exception '想太久了，再開一次'; end if;
  update public.advent_asks set used = true where id = p_ask;
  if d is null then raise exception '降臨月曆只在 12/1 到 12/25 開放'; end if;
  if exists (select 1 from public.advent_opens where user_id = auth.uid() and yr = y and day = d) then
    raise exception '今天這格已經打開了，明天再來！'; end if;
  if p_choice is distinct from a.ans then return json_build_object('ok', false, 'right', a.right_text); end if;
  amt := case when d in (24, 25) then 100 when d % 5 = 0 then 50 else 20 end;
  insert into public.advent_opens (user_id, yr, day, coins) values (auth.uid(), y, d, amt);
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'advent', y || '-' || d);
  select count(*) into total from public.advent_opens where user_id = auth.uid() and yr = y;
  if total >= 10 then
    insert into public.purchases (user_id, item_id, price) select auth.uid(), 'pet_snowman', 0
      where not exists (select 1 from public.purchases where user_id = auth.uid() and item_id = 'pet_snowman');
  end if;
  if total >= 20 then
    insert into public.purchases (user_id, item_id, price) select auth.uid(), 'hat_goldsanta', 0
      where not exists (select 1 from public.purchases where user_id = auth.uid() and item_id = 'hat_goldsanta');
  end if;
  return json_build_object('ok', true, 'right', a.right_text, 'day', d, 'coins', amt, 'total', total,
    'snowman', total = 10, 'gold', total = 20, 'wallet', public.wallet_balance(auth.uid()));
end $$;

revoke all on function public.advent_state() from public, anon;
revoke all on function public.advent_ask() from public, anon;
revoke all on function public.advent_open(bigint, int) from public, anon;
grant execute on function public.advent_state() to authenticated;
grant execute on function public.advent_ask() to authenticated;
grant execute on function public.advent_open(bigint, int) to authenticated;

-- ▼▼▼ update-2026-11-15-冒險躲貓貓坐騎.sql ▼▼▼
-- =====================================================================
-- 冒險打怪、躲貓貓、坐騎（2026-11-15；整份重跑即可）
-- 冒險：claim_game('adventure')，每場最多 20、每天最多 40。
-- 躲貓貓：claim_game('hideseek')，每場最多 15、每天最多 40。
-- 坐騎：6 個新商品（服裝欄位 ride），買了就能騎，走路變快。
-- =====================================================================

create or replace function public.claim_game(p_game text, p_score int, p_level int default 1)
returns json language plpgsql security definer set search_path = public as $$
declare got int; r int; cap int; lv int := greatest(1, least(coalesce(p_level, 1), 4));
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_game not in ('match', 'speed', 'granny', 'tower', 'halloween', 'trick', 'words', 'adventure', 'hideseek') then raise exception '沒有這個遊戲'; end if;
  if p_game in ('halloween', 'trick') and not (extract(month from public.taipei_today()) = 10
      or (extract(month from public.taipei_today()) = 11 and extract(day from public.taipei_today()) <= 7)) then
    raise exception '萬聖節活動結束了'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select coalesce(sum(amount), 0) into got from public.coin_tx
    where user_id = auth.uid() and kind = 'game:' || p_game and day = public.taipei_today();
  cap := 15 + 3 * (lv - 1);
  if p_game in ('halloween', 'trick', 'adventure') then cap := 20; end if;
  if p_game = 'hideseek' then cap := 15; end if;
  r := greatest(0, least(coalesce(p_score, 0), cap, 40 - got));
  if r > 0 then insert into public.coin_tx (user_id, amount, kind) values (auth.uid(), r, 'game:' || p_game); end if;
  return json_build_object('reward', r, 'wallet', public.wallet_balance(auth.uid()));
end $$;
revoke all on function public.claim_game(text, integer, integer) from public, anon;
grant execute on function public.claim_game(text, integer, integer) to authenticated;


insert into public.shop_items (id, slot, price, unlock_cards, avail_from, avail_until, gacha, bundle) values
  ('ride_none', 'ride', 0, null, null, null, null, null),
  ('ride_skate', 'ride', 200, null, null, null, null, null),
  ('ride_broom', 'ride', 350, null, null, null, null, null),
  ('ride_bike', 'ride', 500, null, null, null, null, null),
  ('ride_cloud', 'ride', 900, null, null, null, null, null),
  ('ride_unicorn', 'ride', 1500, null, null, null, null, null)
on conflict (id) do update set slot = excluded.slot, price = excluded.price, unlock_cards = excluded.unlock_cards, avail_from = excluded.avail_from, avail_until = excluded.avail_until, gacha = excluded.gacha, bundle = excluded.bundle;

-- ▼▼▼ update-2026-11-16-段考預備週加成.sql ▼▼▼
-- =====================================================================
-- 第二次段考預備週加成（2026-11-16～11-22）
-- 這週答今日一題、專注、個人任務、讀書會任務的金幣 ×2，答題／專注有 40% 機會掉盲盒券（每天各一次）。
-- 重跑也不會重複新增。
-- =====================================================================
insert into public.app_events (name, start_day, end_day, mult, drop_rate)
  values ('段考預備週加成', '2026-11-16', '2026-11-22', 2, 0.4) on conflict (name, start_day) do nothing;


-- ▼▼▼ update-2026-11-17-探險隊與NPC任務.sql ▼▼▼
-- =====================================================================
-- 派遣探險隊、NPC 謝禮（2026-11-17；整份重跑即可）
-- 探險隊：選城裡的 NPC 當隊員，出發前答 3 題補給問答（資料庫對答案），時間到回來領獎。
--   迷霧森林 1 小時（1 人）15～25 金幣、水晶洞穴 3 小時（2 人）40～60、暗影城堡 8 小時（3 人）90～130。
--   成功率 50% ＋ 每答對一題 10% ＋ 隊員等級 × 2%（最高 95%）；失敗只拿 3 成。
--   隊員每出隊 3 次升 1 級（最高 10 級）；小雪在隊上探險時間少 20%。最多同時 2 隊，每天探險金幣最多 200。
--   洞穴、城堡成功有 6% 掉「探險家帽」，城堡成功有 5% 掉「小火龍」寵物（只能從探險拿）。
-- NPC 謝禮：幫城裡的人做完當天的事，領 5 金幣（claim_game('npc')，每天最多 40）。
-- =====================================================================
create table if not exists public.expeditions (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles on delete cascade,
  area text not null,
  heroes text[] not null,
  correct int not null default 0,
  started_at timestamptz not null default now(),
  ends_at timestamptz not null,
  claimed boolean not null default false,
  result jsonb
);
create index if not exists expeditions_user on public.expeditions (user_id, claimed);
alter table public.expeditions enable row level security;
drop policy if exists "看自己的探險隊" on public.expeditions;
create policy "看自己的探險隊" on public.expeditions for select to authenticated using (user_id = auth.uid());

insert into public.shop_items (id, slot, price, bundle) values
  ('hat_explorer', 'hat', 9999, 'expedition'), ('pet_babydragon', 'pet', 9999, 'expedition')
on conflict (id) do update set slot = excluded.slot, price = excluded.price, bundle = excluded.bundle;

create or replace function public.exp_heroes()
returns text[] language sql immutable as $$
  select array['owl','keeper','libr','chef','gardener','fisher','knight','snow','merchant','banker','postman','clown','clerk','guildmaster']
$$;

create or replace function public.exp_level(u uuid, h text)
returns int language sql stable security definer set search_path = public as $$
  select least(10, 1 + (select count(*)::int from public.expeditions x where x.user_id = u and x.claimed and h = any(x.heroes)) / 3);
$$;

create or replace function public.start_expedition(p_area text, p_heroes text[], p_answers jsonb)
returns json language plpgsql security definer set search_path = public as $$
declare need int; hrs numeric; ok int; nid bigint; ends timestamptz;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  need := case p_area when 'forest' then 1 when 'cave' then 2 when 'castle' then 3 end;
  if need is null then raise exception '沒有這個地方'; end if;
  hrs := case p_area when 'forest' then 1 when 'cave' then 3 else 8 end;
  if coalesce(array_length(p_heroes, 1), 0) <> need or (select count(distinct h) from unnest(p_heroes) h) <> need
     or not (p_heroes <@ public.exp_heroes()) then raise exception '這個地方要 % 位不同的隊員', need; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if (select count(*) from public.expeditions where user_id = auth.uid() and not claimed) >= 2 then raise exception '最多同時派 2 支探險隊'; end if;
  if exists (select 1 from public.expeditions where user_id = auth.uid() and not claimed and heroes && p_heroes) then raise exception '有隊員還在探險中'; end if;
  with a as (select e from jsonb_array_elements(case when jsonb_typeof(p_answers) = 'array' then p_answers else '[]'::jsonb end) e limit 3)
  select count(distinct k.qid) into ok from a join public.question_keys k on k.qid = a.e->>'qid' and k.a = (a.e->>'choice')::int;
  ends := now() + make_interval(secs => (hrs * 3600 * case when 'snow' = any(p_heroes) then 0.8 else 1 end)::int);
  insert into public.expeditions (user_id, area, heroes, correct, ends_at) values (auth.uid(), p_area, p_heroes, ok, ends) returning id into nid;
  return json_build_object('id', nid, 'ends_at', ends, 'correct', ok);
end $$;

create or replace function public.claim_expedition(p_id bigint)
returns json language plpgsql security definer set search_path = public as $$
declare e public.expeditions; lv int; chance numeric; ok boolean; lo int; hi int; amt int; got int; r int; drp text;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select * into e from public.expeditions where id = p_id and user_id = auth.uid() for update;
  if not found or e.claimed then raise exception '這支探險隊已經領過了'; end if;
  if now() < e.ends_at then raise exception '探險隊還沒回來'; end if;
  select coalesce(sum(public.exp_level(auth.uid(), h)), 0) into lv from unnest(e.heroes) h;
  chance := least(0.95, 0.5 + 0.1 * e.correct + 0.02 * lv);
  ok := random() < chance;
  lo := case e.area when 'forest' then 15 when 'cave' then 40 else 90 end;
  hi := case e.area when 'forest' then 25 when 'cave' then 60 else 130 end;
  amt := lo + floor(random() * (hi - lo + 1))::int;
  if not ok then amt := ceil(amt * 0.3)::int; end if;
  select coalesce(sum(amount), 0) into got from public.coin_tx where user_id = auth.uid() and kind = 'expedition' and day = public.taipei_today();
  r := greatest(0, least(amt, 200 - got));
  if r > 0 then insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), r, 'expedition', e.area); end if;
  if ok and e.area <> 'forest' and random() < 0.06 and not exists (select 1 from public.purchases where user_id = auth.uid() and item_id = 'hat_explorer') then
    drp := 'hat_explorer';
  elsif ok and e.area = 'castle' and random() < 0.05 and not exists (select 1 from public.purchases where user_id = auth.uid() and item_id = 'pet_babydragon') then
    drp := 'pet_babydragon';
  end if;
  if drp is not null then insert into public.purchases (user_id, item_id, price) values (auth.uid(), drp, 0); end if;
  update public.expeditions set claimed = true, result = json_build_object('ok', ok, 'coins', r, 'drop', drp)::jsonb where id = p_id;
  return json_build_object('ok', ok, 'coins', r, 'raw', amt, 'drop', drp, 'chance', round(chance * 100), 'wallet', public.wallet_balance(auth.uid()));
end $$;

create or replace function public.my_expeditions()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'active', coalesce((select json_agg(json_build_object('id', id, 'area', area, 'heroes', heroes, 'correct', correct, 'ends_at', ends_at) order by ends_at)
      from public.expeditions where user_id = auth.uid() and not claimed), '[]'::json),
    'levels', (select json_object_agg(h, public.exp_level(auth.uid(), h)) from unnest(public.exp_heroes()) h),
    'today', (select coalesce(sum(amount), 0) from public.coin_tx where user_id = auth.uid() and kind = 'expedition' and day = public.taipei_today()));
$$;

revoke all on function public.start_expedition(text, text[], jsonb) from public, anon;
revoke all on function public.claim_expedition(bigint) from public, anon;
revoke all on function public.my_expeditions() from public, anon;
grant execute on function public.start_expedition(text, text[], jsonb) to authenticated;
grant execute on function public.claim_expedition(bigint) to authenticated;
grant execute on function public.my_expeditions() to authenticated;

-- NPC 謝禮：claim_game 多收 'npc'（每次 5、每天 40）
create or replace function public.claim_game(p_game text, p_score int, p_level int default 1)
returns json language plpgsql security definer set search_path = public as $$
declare got int; r int; cap int; lv int := greatest(1, least(coalesce(p_level, 1), 4));
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_game not in ('match', 'speed', 'granny', 'tower', 'halloween', 'trick', 'words', 'adventure', 'hideseek', 'npc') then raise exception '沒有這個遊戲'; end if;
  if p_game in ('halloween', 'trick') and not (extract(month from public.taipei_today()) = 10
      or (extract(month from public.taipei_today()) = 11 and extract(day from public.taipei_today()) <= 7)) then
    raise exception '萬聖節活動結束了'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select coalesce(sum(amount), 0) into got from public.coin_tx
    where user_id = auth.uid() and kind = 'game:' || p_game and day = public.taipei_today();
  cap := 15 + 3 * (lv - 1);
  if p_game in ('halloween', 'trick', 'adventure') then cap := 20; end if;
  if p_game = 'hideseek' then cap := 15; end if;
  if p_game = 'npc' then cap := 5; end if;
  r := greatest(0, least(coalesce(p_score, 0), cap, 40 - got));
  if r > 0 then insert into public.coin_tx (user_id, amount, kind) values (auth.uid(), r, 'game:' || p_game); end if;
  return json_build_object('reward', r, 'wallet', public.wallet_balance(auth.uid()));
end $$;
revoke all on function public.claim_game(text, integer, integer) from public, anon;
grant execute on function public.claim_game(text, integer, integer) to authenticated;


-- ▼▼▼ update-2026-11-18-探險隊員存資料庫.sql ▼▼▼
-- =====================================================================
-- 探險隊員存進資料庫（2026-11-18；整份重跑即可）
-- 以前「邀請加入探險隊」只記在學生自己的裝置，換手機要重收；現在存在資料庫，跨裝置都一樣。
-- 冒險公會騎士每個人一開始就有。派遣時資料庫會確認隊員真的已經邀請過。
-- =====================================================================
create table if not exists public.hero_recruits (
  user_id uuid not null references public.profiles on delete cascade,
  hero text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, hero)
);
alter table public.hero_recruits enable row level security;
drop policy if exists "看自己的隊員" on public.hero_recruits;
create policy "看自己的隊員" on public.hero_recruits for select to authenticated using (user_id = auth.uid());

-- 邀請一位或多位隊員（網頁第一次連上時，會把以前存在裝置裡的隊員一起補上）
create or replace function public.recruit_heroes(p_heroes text[])
returns json language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid()) then raise exception '請先建立角色'; end if;
  insert into public.hero_recruits (user_id, hero)
    select auth.uid(), h from unnest(coalesce(p_heroes, '{}')) h where h = any(public.exp_heroes())
    on conflict do nothing;
  return (select json_agg(hero) from public.hero_recruits where user_id = auth.uid());
end $$;

create or replace function public.my_recruits()
returns text[] language sql stable security definer set search_path = public as $$
  select array['knight'] || coalesce((select array_agg(hero) from public.hero_recruits where user_id = auth.uid() and hero <> 'knight'), '{}');
$$;

-- 派遣：多檢查隊員是不是自己的
create or replace function public.start_expedition(p_area text, p_heroes text[], p_answers jsonb)
returns json language plpgsql security definer set search_path = public as $$
declare need int; hrs numeric; ok int; nid bigint; ends timestamptz;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  need := case p_area when 'forest' then 1 when 'cave' then 2 when 'castle' then 3 end;
  if need is null then raise exception '沒有這個地方'; end if;
  hrs := case p_area when 'forest' then 1 when 'cave' then 3 else 8 end;
  if coalesce(array_length(p_heroes, 1), 0) <> need or (select count(distinct h) from unnest(p_heroes) h) <> need
     or not (p_heroes <@ public.exp_heroes()) then raise exception '這個地方要 % 位不同的隊員', need; end if;
  if not (p_heroes <@ public.my_recruits()) then raise exception '有隊員還沒加入你的探險隊'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if (select count(*) from public.expeditions where user_id = auth.uid() and not claimed) >= 2 then raise exception '最多同時派 2 支探險隊'; end if;
  if exists (select 1 from public.expeditions where user_id = auth.uid() and not claimed and heroes && p_heroes) then raise exception '有隊員還在探險中'; end if;
  with a as (select e from jsonb_array_elements(case when jsonb_typeof(p_answers) = 'array' then p_answers else '[]'::jsonb end) e limit 3)
  select count(distinct k.qid) into ok from a join public.question_keys k on k.qid = a.e->>'qid' and k.a = (a.e->>'choice')::int;
  ends := now() + make_interval(secs => (hrs * 3600 * case when 'snow' = any(p_heroes) then 0.8 else 1 end)::int);
  insert into public.expeditions (user_id, area, heroes, correct, ends_at) values (auth.uid(), p_area, p_heroes, ok, ends) returning id into nid;
  return json_build_object('id', nid, 'ends_at', ends, 'correct', ok);
end $$;

-- 我的探險隊：多回傳 recruits
create or replace function public.my_expeditions()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'active', coalesce((select json_agg(json_build_object('id', id, 'area', area, 'heroes', heroes, 'correct', correct, 'ends_at', ends_at) order by ends_at)
      from public.expeditions where user_id = auth.uid() and not claimed), '[]'::json),
    'levels', (select json_object_agg(h, public.exp_level(auth.uid(), h)) from unnest(public.exp_heroes()) h),
    'recruits', to_json(public.my_recruits()),
    'today', (select coalesce(sum(amount), 0) from public.coin_tx where user_id = auth.uid() and kind = 'expedition' and day = public.taipei_today()));
$$;

revoke all on function public.recruit_heroes(text[]) from public, anon;
revoke all on function public.my_recruits() from public, anon;
grant execute on function public.recruit_heroes(text[]) to authenticated;
grant execute on function public.my_recruits() to authenticated;

select '全部完成！' as 結果;
