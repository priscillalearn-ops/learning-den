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
