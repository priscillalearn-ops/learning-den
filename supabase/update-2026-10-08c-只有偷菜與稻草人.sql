
-- =====================================================================
-- 魔法花園：偷菜與稻草人（2026-10-08 第二次更新；整份重跑即可）
-- 別人的作物成熟 30 分鐘後可以偷：每次偷走收成的 10%（至少 2 金幣），每株最多被偷 3 次，
-- 同一株一個人只能偷一次，每人每天最多偷 5 次。
-- 稻草人：30 金幣守 24 小時，小偷有 40% 會被抓到，被抓到要賠主人 5 金幣。
-- =====================================================================
alter table public.garden_plots add column if not exists stolen int not null default 0;

create table if not exists public.garden_steals (
  id bigint generated always as identity primary key,
  owner uuid not null references public.profiles on delete cascade,
  thief uuid not null references public.profiles on delete cascade,
  slot int not null,
  planted_at timestamptz not null,
  crop text,
  amount int not null,
  caught boolean not null default false,
  day date not null default public.taipei_today(),
  created_at timestamptz not null default now(),
  unique (owner, slot, planted_at, thief)
);
create index if not exists garden_steals_owner on public.garden_steals (owner, created_at desc);
create index if not exists garden_steals_thief_day on public.garden_steals (thief, day);
alter table public.garden_steals enable row level security;

create table if not exists public.garden_scarecrows (
  user_id uuid primary key references public.profiles on delete cascade,
  until timestamptz not null
);
alter table public.garden_scarecrows enable row level security;

create or replace function public.garden_info(p_user uuid default null)
returns json language plpgsql stable security definer set search_path = public as $$
declare u uuid := coalesce(p_user, auth.uid());
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  return json_build_object(
    'is_me', u = auth.uid(),
    'name', (select name from public.profiles where id = u),
    'scarecrow_until', (select until from public.garden_scarecrows where user_id = u and until > now()),
    'plots', coalesce((select json_agg(json_build_object('slot', g.slot, 'crop', g.crop, 'planted_at', g.planted_at, 'waters', g.waters, 'stolen', g.stolen,
        'watered_by_me', exists (select 1 from public.garden_helps h where h.owner = u and h.slot = g.slot and h.planted_at = g.planted_at and h.helper = auth.uid()),
        'stolen_by_me', exists (select 1 from public.garden_steals t where t.owner = u and t.slot = g.slot and t.planted_at = g.planted_at and t.thief = auth.uid()))
        order by g.slot) from public.garden_plots g where g.user_id = u and g.crop is not null), '[]'::json),
    'water_left', case when u = auth.uid() then public.garden_water_left(u) end,
    'helps_today', (select count(*) from public.garden_helps where helper = auth.uid() and owner <> auth.uid() and day = public.taipei_today()),
    'steals_today', (select count(*) from public.garden_steals where thief = auth.uid() and day = public.taipei_today()),
    'helpers', case when u = auth.uid() then coalesce((select json_agg(x order by x.at desc) from (
        select p.name, 'help' as kind, h.created_at as at, (select crop from public.garden_plots g where g.user_id = u and g.slot = h.slot) as crop, 0 as amount, false as caught
        from public.garden_helps h join public.profiles p on p.id = h.helper
        where h.owner = u and h.helper <> u and h.created_at > now() - interval '3 days'
        union all
        select p.name, 'steal', t.created_at, t.crop, t.amount, t.caught
        from public.garden_steals t join public.profiles p on p.id = t.thief
        where t.owner = u and t.created_at > now() - interval '3 days'
        order by 3 desc limit 15) x), '[]'::json) end);
end $$;

create or replace function public.garden_steal(p_owner uuid, p_slot int)
returns json language plpgsql security definer set search_path = public as $$
declare g public.garden_plots; c record; amt int; n int; guard boolean;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_owner = auth.uid() then raise exception '不能偷自己的菜'; end if;
  perform pg_advisory_xact_lock(hashtext(p_owner::text));
  select * into g from public.garden_plots where user_id = p_owner and slot = p_slot for update;
  if g.crop is null then raise exception '這塊地沒有東西可以偷'; end if;
  select * into c from public.garden_crop(g.crop);
  if now() < g.planted_at + make_interval(hours => c.hours) + interval '30 minutes' then raise exception '成熟 30 分鐘後才能偷，給主人一點時間收成'; end if;
  if g.stolen >= 3 then raise exception '這株已經被偷 3 次了，留一點給主人吧'; end if;
  if exists (select 1 from public.garden_steals where owner = p_owner and slot = p_slot and planted_at = g.planted_at and thief = auth.uid()) then
    raise exception '這株你已經偷過了'; end if;
  select count(*) into n from public.garden_steals where thief = auth.uid() and day = public.taipei_today();
  if n >= 5 then raise exception '今天已經偷 5 次了，明天再來'; end if;
  guard := exists (select 1 from public.garden_scarecrows where user_id = p_owner and until > now());
  if guard and random() < 0.4 then
    insert into public.garden_steals (owner, thief, slot, planted_at, crop, amount, caught) values (p_owner, auth.uid(), p_slot, g.planted_at, g.crop, 5, true);
    insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), -5, 'steal_caught', p_owner::text);
    insert into public.coin_tx (user_id, amount, kind, ref) values (p_owner, 5, 'scarecrow', auth.uid()::text);
    return json_build_object('caught', true, 'amount', 5, 'wallet', public.wallet_balance(auth.uid()));
  end if;
  amt := greatest(2, round(c.coins * (1 + 0.15 * least(g.waters, 3)) * 0.1));
  insert into public.garden_steals (owner, thief, slot, planted_at, crop, amount) values (p_owner, auth.uid(), p_slot, g.planted_at, g.crop, amt);
  update public.garden_plots set stolen = stolen + 1 where user_id = p_owner and slot = p_slot;
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'steal', p_owner::text);
  return json_build_object('caught', false, 'amount', amt, 'wallet', public.wallet_balance(auth.uid()));
end $$;

create or replace function public.garden_scarecrow()
returns json language plpgsql security definer set search_path = public as $$
declare u timestamptz;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if public.wallet_balance(auth.uid()) < 30 then raise exception '金幣不夠（稻草人要 30 金幣）'; end if;
  insert into public.coin_tx (user_id, amount, kind) values (auth.uid(), -30, 'scarecrow_buy');
  insert into public.garden_scarecrows (user_id, until) values (auth.uid(), now() + interval '24 hours')
    on conflict (user_id) do update set until = greatest(public.garden_scarecrows.until, now()) + interval '24 hours'
    returning until into u;
  return json_build_object('until', u, 'wallet', public.wallet_balance(auth.uid()));
end $$;

-- 收成：扣掉被偷走的部分（每次 10%）
create or replace function public.garden_harvest(p_slot int)
returns json language plpgsql security definer set search_path = public as $$
declare g public.garden_plots; c record; amt int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select * into g from public.garden_plots where user_id = auth.uid() and slot = p_slot for update;
  if g.crop is null then raise exception '這塊地沒有種東西'; end if;
  select * into c from public.garden_crop(g.crop);
  if now() < g.planted_at + make_interval(hours => c.hours) then raise exception '還沒成熟喔'; end if;
  amt := round(c.coins * (1 + 0.15 * least(g.waters, 3)) * (1 - 0.1 * least(g.stolen, 3)));
  update public.garden_plots set crop = null, planted_at = null, waters = 0, stolen = 0 where user_id = auth.uid() and slot = p_slot;
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'harvest', g.crop);
  return json_build_object('amount', amt, 'wallet', public.wallet_balance(auth.uid()));
end $$;

-- 種新的作物時，被偷次數歸零
create or replace function public.garden_plant(p_slot int, p_crop text)
returns json language plpgsql security definer set search_path = public as $$
declare c record;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_slot not between 0 and 5 then raise exception '沒有這塊地'; end if;
  select * into c from public.garden_crop(p_crop);
  if c.hours is null then raise exception '沒有這種種子'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if exists (select 1 from public.garden_plots where user_id = auth.uid() and slot = p_slot and crop is not null) then raise exception '這塊地已經種了'; end if;
  if public.wallet_balance(auth.uid()) < c.seed then raise exception '金幣不夠買種子'; end if;
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), -c.seed, 'seed', p_crop);
  insert into public.garden_plots (user_id, slot, crop, planted_at, waters, stolen) values (auth.uid(), p_slot, p_crop, now(), 0, 0)
    on conflict (user_id, slot) do update set crop = excluded.crop, planted_at = excluded.planted_at, waters = 0, stolen = 0;
  return json_build_object('wallet', public.wallet_balance(auth.uid()));
end $$;

revoke all on function public.garden_steal(uuid, integer) from public, anon;
grant execute on function public.garden_steal(uuid, integer) to authenticated;
revoke all on function public.garden_scarecrow() from public, anon;
grant execute on function public.garden_scarecrow() to authenticated;
