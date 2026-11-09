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
