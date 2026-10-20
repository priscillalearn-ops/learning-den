-- =====================================================================
-- 湖邊釣單字＋大頭菜市場（2026-10-20 第四次更新；整份重跑即可）
-- 釣魚：拋竿（資料庫決定是哪種魚）→ 答對單字題才釣得上來（答案由資料庫對 question_keys 判斷）。
--       有的魚只在早上／白天／傍晚／晚上出現，楓葉魚只在 10～11 月。每天前 15 隻有金幣。
--       圖鑑收集 5 種 +50、10 種 +150、全部 14 種送「釣魚帽」。
-- 市場：作物收購價每天中午和半夜各變一次，原價的 0.6～2 倍。
-- ※ 國小的答案也要加進 question_keys：請另外再跑一次最新的 supabase/question_keys.sql。
-- =====================================================================
create table if not exists public.fish_casts (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles on delete cascade,
  species text not null,
  used boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists fish_casts_user on public.fish_casts (user_id, created_at desc);
alter table public.fish_casts enable row level security;

create table if not exists public.fish_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles on delete cascade,
  species text not null,
  coins int not null default 0,
  day date not null default public.taipei_today(),
  created_at timestamptz not null default now()
);
create index if not exists fish_log_user on public.fish_log (user_id, day);
alter table public.fish_log enable row level security;
drop policy if exists "看自己的魚" on public.fish_log;
create policy "看自己的魚" on public.fish_log for select to authenticated using (user_id = auth.uid());

create table if not exists public.fish_bonus (
  user_id uuid not null references public.profiles on delete cascade,
  level int not null,
  primary key (user_id, level)
);
alter table public.fish_bonus enable row level security;

insert into public.shop_items (id, slot, price, bundle) values ('hat_fisher', 'hat', 9999, 'fish')
  on conflict (id) do update set slot = excluded.slot, price = excluded.price, bundle = excluded.bundle;

-- 魚的資料：id、稀有度、出現時段（any／morning 5–11／day 11–17／evening 17–21／night 21–5／autumn 10～11 月）
create or replace function public.fish_table()
returns table (id text, rarity text, slot text)
language sql immutable as $$
  select * from (values
    ('crucian','N','any'), ('goldfish','N','any'), ('loach','N','day'),
    ('carp','R','any'), ('puffer','R','evening'), ('salmon','R','morning'), ('jelly','R','night'),
    ('koi','SR','day'), ('octopus','SR','evening'), ('tuna','SR','morning'), ('maple','SR','autumn'),
    ('shark','SSR','evening'), ('moonfish','SSR','night'), ('starfish','SSR','any')
  ) v(id, rarity, slot);
$$;

create or replace function public.fish_cast()
returns json language plpgsql security definer set search_path = public as $$
declare h int := extract(hour from now() at time zone 'Asia/Taipei'); m int := extract(month from public.taipei_today());
  slotnow text; r float; rar text; sp text; cid bigint;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid()) then raise exception '請先建立角色'; end if;
  if (select count(*) from public.fish_casts where user_id = auth.uid() and created_at > now() - interval '3 seconds') > 0 then
    raise exception '慢一點，魚會被嚇跑'; end if;
  slotnow := case when h between 5 and 10 then 'morning' when h between 11 and 16 then 'day' when h between 17 and 20 then 'evening' else 'night' end;
  r := random();
  rar := case when r < 0.03 then 'SSR' when r < 0.15 then 'SR' when r < 0.45 then 'R' else 'N' end;
  select f.id into sp from public.fish_table() f
    where f.rarity = rar and (f.slot = 'any' or f.slot = slotnow or (f.slot = 'autumn' and m in (10, 11)))
    order by random() limit 1;
  if sp is null then select f.id into sp from public.fish_table() f where f.rarity = 'N' and f.slot = 'any' order by random() limit 1; end if;
  insert into public.fish_casts (user_id, species) values (auth.uid(), sp) returning id into cid;
  return json_build_object('cast', cid, 'species', sp);
end $$;

create or replace function public.fish_reel(p_cast bigint, p_qid text, p_choice int)
returns json language plpgsql security definer set search_path = public as $$
declare c public.fish_casts; ok boolean; rar text; amt int := 0; n int; kinds int; bonus int := 0; lv int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select * into c from public.fish_casts where id = p_cast and user_id = auth.uid() for update;
  if not found or c.used then raise exception '這次釣魚已經結束了'; end if;
  if c.created_at < now() - interval '3 minutes' then raise exception '魚等太久跑掉了'; end if;
  update public.fish_casts set used = true where id = p_cast;
  ok := exists (select 1 from public.question_keys where qid = p_qid and a = p_choice);
  if not ok then return json_build_object('caught', false); end if;
  select f.rarity into rar from public.fish_table() f where f.id = c.species;
  select count(*) into n from public.fish_log where user_id = auth.uid() and day = public.taipei_today();
  if n < 15 then amt := case rar when 'N' then 3 when 'R' then 6 when 'SR' then 15 else 40 end; end if;
  insert into public.fish_log (user_id, species, coins) values (auth.uid(), c.species, amt);
  if amt > 0 then insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'fish', c.species); end if;
  -- 圖鑑獎勵：5 種 +50、10 種 +150、14 種送釣魚帽
  select count(distinct species) into kinds from public.fish_log where user_id = auth.uid();
  foreach lv in array array[5, 10, 14] loop
    if kinds >= lv and not exists (select 1 from public.fish_bonus where user_id = auth.uid() and level = lv) then
      insert into public.fish_bonus (user_id, level) values (auth.uid(), lv);
      if lv = 14 then
        insert into public.purchases (user_id, item_id, price) select auth.uid(), 'hat_fisher', 0
          where not exists (select 1 from public.purchases where user_id = auth.uid() and item_id = 'hat_fisher');
      else
        bonus := bonus + case lv when 5 then 50 else 150 end;
        insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), case lv when 5 then 50 else 150 end, 'fish_dex', lv::text);
      end if;
    end if;
  end loop;
  return json_build_object('caught', true, 'species', c.species, 'coins', amt, 'bonus', bonus, 'kinds', kinds,
    'hat', kinds >= 14, 'today', n + 1, 'wallet', public.wallet_balance(auth.uid()));
end $$;

create or replace function public.my_fish()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'counts', coalesce((select json_object_agg(species, c) from (select species, count(*) c from public.fish_log where user_id = auth.uid() group by species) x), '{}'::json),
    'today', (select count(*) from public.fish_log where user_id = auth.uid() and day = public.taipei_today()));
$$;

-- ---------- 大頭菜市場 ----------
create or replace function public.market_base(p text)
returns int language sql immutable as $$
  select case p when 'wheat' then 4 when 'carrot' then 12 when 'tomato' then 19 when 'pumpkin' then 50 when 'sunflower' then 85 when 'starfruit' then 140 end;
$$;
-- 倍率：每種作物、每天、上午／下午各一個，0.60～2.00
create or replace function public.market_mult(p text, d date, half int)
returns numeric language sql immutable as $$
  select round(0.6 + (abs(hashtext(p || d::text || half::text)::bigint) % 141) / 100.0, 2);
$$;
create or replace function public.market_now()
returns table (d date, half int) language sql stable as $$
  select public.taipei_today(), case when extract(hour from now() at time zone 'Asia/Taipei') < 12 then 0 else 1 end;
$$;
create or replace function public.market_prices()
returns json language sql stable security definer set search_path = public as $$
  with n as (select * from public.market_now()),
  crops as (select unnest(array['wheat','carrot','tomato','pumpkin','sunflower','starfruit']) c)
  select json_build_object('day', n.d, 'half', n.half, 'prices', json_agg(json_build_object(
    'crop', crops.c, 'base', public.market_base(crops.c),
    'mult', public.market_mult(crops.c, n.d, n.half),
    'prev', case when n.half = 1 then public.market_mult(crops.c, n.d, 0) else public.market_mult(crops.c, n.d - 1, 1) end,
    'price', round(public.market_base(crops.c) * public.market_mult(crops.c, n.d, n.half)))))
  from n, crops group by n.d, n.half;
$$;
create or replace function public.market_sell(p_crop text, p_qty int)
returns json language plpgsql security definer set search_path = public as $$
declare n record; each_price int; amt int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if public.market_base(p_crop) is null then raise exception '市場不收這個'; end if;
  if p_qty is null or p_qty < 1 or p_qty > 999 then raise exception '數量不對'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select * into n from public.market_now();
  each_price := round(public.market_base(p_crop) * public.market_mult(p_crop, n.d, n.half));
  perform public.use_items(auth.uid(), jsonb_build_object(p_crop, p_qty));
  amt := each_price * p_qty;
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'market', p_crop);
  return json_build_object('amount', amt, 'each', each_price, 'wallet', public.wallet_balance(auth.uid()));
end $$;

revoke all on function public.fish_cast() from public, anon;
grant execute on function public.fish_cast() to authenticated;
revoke all on function public.fish_reel(bigint, text, integer) from public, anon;
grant execute on function public.fish_reel(bigint, text, integer) to authenticated;
revoke all on function public.my_fish() from public, anon;
grant execute on function public.my_fish() to authenticated;
revoke all on function public.market_prices() from public, anon;
grant execute on function public.market_prices() to authenticated;
revoke all on function public.market_sell(text, integer) from public, anon;
grant execute on function public.market_sell(text, integer) to authenticated;
