
-- =====================================================================
-- 花園倉庫、交換所、自己下廚（2026-10-08 第四次更新；整份重跑即可）
-- 收成可以「賣掉換金幣」或「收進倉庫」：小麥 4、胡蘿蔔／番茄 3、南瓜／向日葵／星星果 2 個，澆滿 3 次多 1 個，被偷 2 次以上少 1 個。
-- 倉庫的作物可以到交換所換花園限定配件，或到餐廳自己下廚（每天最多 3 道，第一道也算當天吃飯）。
-- =====================================================================
create table if not exists public.garden_items (
  user_id uuid not null references public.profiles on delete cascade,
  item text not null,
  qty int not null default 0 check (qty >= 0),
  primary key (user_id, item)
);
alter table public.garden_items enable row level security;
drop policy if exists "看自己的倉庫" on public.garden_items;
create policy "看自己的倉庫" on public.garden_items for select to authenticated using (user_id = auth.uid());

create table if not exists public.cook_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles on delete cascade,
  day date not null default public.taipei_today(),
  dish text not null,
  water int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists cook_log_user_day on public.cook_log (user_id, day);
alter table public.cook_log enable row level security;
drop policy if exists "看自己的料理" on public.cook_log;
create policy "看自己的料理" on public.cook_log for select to authenticated using (user_id = auth.uid());

create or replace function public.garden_units(p text)
returns int language sql immutable as $$
  select case p when 'wheat' then 4 when 'carrot' then 3 when 'tomato' then 3 else 2 end;
$$;

-- 用掉倉庫的作物（不夠就報錯）
create or replace function public.use_items(p_user uuid, p_need jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare k text; v int; have int;
begin
  for k, v in select key, value::int from jsonb_each_text(p_need) loop
    select qty into have from public.garden_items where user_id = p_user and item = k for update;
    if coalesce(have, 0) < v then raise exception '材料不夠'; end if;
    update public.garden_items set qty = qty - v where user_id = p_user and item = k;
  end loop;
end $$;

-- 魔法水：再加上今天下廚得到的水
create or replace function public.garden_water_left(p uuid)
returns int language sql stable security definer set search_path = public as $$
  select greatest(0, 1
    + case when exists (select 1 from public.answers where user_id = p and day = public.taipei_today()) then 2 else 0 end
    + least(3, (select count(*) from public.focus_sessions where user_id = p and day = public.taipei_today() and minutes >= 25))::int
    + coalesce((select sum(water) from public.cook_log where user_id = p and day = public.taipei_today()), 0)::int
    - (select count(*) from public.garden_helps where helper = p and owner = p and day = public.taipei_today())::int);
$$;

-- 收成：p_keep = true 收進倉庫，否則賣掉換金幣
drop function if exists public.garden_harvest(integer);
create or replace function public.garden_harvest(p_slot int, p_keep boolean default false)
returns json language plpgsql security definer set search_path = public as $$
declare g public.garden_plots; c record; amt int; n int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select * into g from public.garden_plots where user_id = auth.uid() and slot = p_slot for update;
  if g.crop is null then raise exception '這塊地沒有種東西'; end if;
  select * into c from public.garden_crop(g.crop);
  if now() < g.planted_at + make_interval(hours => c.hours) then raise exception '還沒成熟喔'; end if;
  update public.garden_plots set crop = null, planted_at = null, waters = 0, stolen = 0 where user_id = auth.uid() and slot = p_slot;
  if coalesce(p_keep, false) then
    n := greatest(1, public.garden_units(g.crop) + case when g.waters >= 3 then 1 else 0 end - case when g.stolen >= 2 then 1 else 0 end);
    insert into public.garden_items (user_id, item, qty) values (auth.uid(), g.crop, n)
      on conflict (user_id, item) do update set qty = public.garden_items.qty + n;
    return json_build_object('kept', n, 'crop', g.crop, 'wallet', public.wallet_balance(auth.uid()));
  end if;
  amt := round(c.coins * (1 + 0.15 * least(g.waters, 3)) * (1 - 0.1 * least(g.stolen, 3)));
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'harvest', g.crop);
  return json_build_object('amount', amt, 'wallet', public.wallet_balance(auth.uid()));
end $$;

-- 交換所：作物換花園限定配件
create or replace function public.farm_exchange(p_item text)
returns json language plpgsql security definer set search_path = public as $$
declare need jsonb;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  need := case p_item
    when 'hat_straw' then '{"wheat":8}' when 'acc_carrot' then '{"carrot":5}' when 'top_apron' then '{"tomato":5}'
    when 'hat_pumpkinhelm' then '{"pumpkin":4}' when 'acc_sunflower' then '{"sunflower":3}' when 'acc_starcape' then '{"starfruit":3}' end;
  if need is null then raise exception '交換所沒有這個'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if exists (select 1 from public.purchases where user_id = auth.uid() and item_id = p_item) then raise exception '你已經有了'; end if;
  perform public.use_items(auth.uid(), need);
  insert into public.purchases (user_id, item_id, price) values (auth.uid(), p_item, 0);
  return json_build_object('ok', true);
end $$;

-- 自己下廚：每天最多 3 道；第一道也算當天吃飯
create or replace function public.cook(p_dish text)
returns json language plpgsql security definer set search_path = public as $$
declare need jsonb; coins int := 0; water int := 0; ticket int := 0; n int; meal boolean := false;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select r.need::jsonb, r.c, r.w, r.t into need, coins, water, ticket from (values
    ('d_bread',  '{"wheat":2}',               0, 1, 0),
    ('d_soup',   '{"carrot":1,"tomato":1}',  45, 0, 0),
    ('d_pasta',  '{"wheat":1,"tomato":2}',   20, 2, 0),
    ('d_pie',    '{"pumpkin":1,"wheat":1}',  80, 0, 0),
    ('d_salad',  '{"sunflower":1,"carrot":1}', 140, 0, 0),
    ('d_sundae', '{"starfruit":1,"wheat":1}', 100, 0, 1)
  ) r(id, need, c, w, t) where r.id = p_dish;
  if need is null then raise exception '沒有這道料理'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select count(*) into n from public.cook_log where user_id = auth.uid() and day = public.taipei_today();
  if n >= 3 then raise exception '今天已經煮 3 道了，明天再來'; end if;
  perform public.use_items(auth.uid(), need);
  insert into public.cook_log (user_id, dish, water) values (auth.uid(), p_dish, water);
  if coins > 0 then insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), coins, 'dish', p_dish); end if;
  if ticket > 0 then
    insert into public.gacha_state (user_id, tickets) values (auth.uid(), ticket)
      on conflict (user_id) do update set tickets = public.gacha_state.tickets + ticket;
  end if;
  if not exists (select 1 from public.meals where user_id = auth.uid() and day = public.taipei_today()) then
    insert into public.meals (user_id, food) values (auth.uid(), p_dish); meal := true;
  end if;
  return json_build_object('coins', coins, 'water', water, 'ticket', ticket, 'meal', meal, 'cooked_today', n + 1,
    'wallet', public.wallet_balance(auth.uid()));
end $$;

-- 花園資訊：自己的話多回傳倉庫
create or replace function public.my_items()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'items', coalesce((select json_object_agg(item, qty) from public.garden_items where user_id = auth.uid() and qty > 0), '{}'::json),
    'cooked_today', (select count(*) from public.cook_log where user_id = auth.uid() and day = public.taipei_today()));
$$;

revoke all on function public.use_items(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.garden_harvest(integer, boolean) from public, anon;
grant execute on function public.garden_harvest(integer, boolean) to authenticated;
revoke all on function public.farm_exchange(text) from public, anon;
grant execute on function public.farm_exchange(text) to authenticated;
revoke all on function public.cook(text) from public, anon;
grant execute on function public.cook(text) to authenticated;
revoke all on function public.my_items() from public, anon;
grant execute on function public.my_items() to authenticated;

-- 花園交換所限定配件
insert into public.shop_items (id, slot, price, unlock_cards, avail_from, avail_until, gacha, bundle) values
  ('hat_straw', 'hat', 9999, null, null, null, null, 'farm'),
  ('hat_pumpkinhelm', 'hat', 9999, null, null, null, null, 'farm'),
  ('top_apron', 'top', 9999, null, null, null, null, 'farm'),
  ('acc_carrot', 'acc', 9999, null, null, null, null, 'farm'),
  ('acc_sunflower', 'acc', 9999, null, null, null, null, 'farm'),
  ('acc_starcape', 'acc', 9999, null, null, null, null, 'farm')
on conflict (id) do update set slot = excluded.slot, price = excluded.price, unlock_cards = excluded.unlock_cards, avail_from = excluded.avail_from, avail_until = excluded.avail_until, gacha = excluded.gacha, bundle = excluded.bundle;
