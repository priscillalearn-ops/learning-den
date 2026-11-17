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

