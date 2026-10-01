
-- =====================================================================
-- 年級排行、讀書會（公會）與公會任務（2026-10-02 第二次更新；整份重跑即可）
-- 年級排行：同年級（還沒選年級就同等級）最近 7 天專注排行。
-- 讀書會：填一樣班級代碼的同學就是同一個讀書會；每週有大家一起完成的公會任務，
--         目標依人數調整，達成後每個成員各自領一次獎勵。
-- =====================================================================
create or replace function public.grade_board()
returns table (name text, tier text, week_minutes int, streak int, is_me boolean)
language sql stable security definer set search_path = public as $$
  with me as (select coalesce('g-' || grade, 't-' || tier) as k from public.profiles where id = auth.uid())
  select p.name, p.tier,
    coalesce((select sum(f.minutes) from public.focus_sessions f
      where f.user_id = p.id and f.day > public.taipei_today() - 7), 0)::int,
    public.current_streak(p.id),
    p.id = auth.uid()
  from public.profiles p, me
  where coalesce('g-' || p.grade, 't-' || p.tier) = me.k
  order by 3 desc, 4 desc
  limit 30;
$$;

create table if not exists public.guild_claims (
  user_id uuid not null references public.profiles on delete cascade,
  week date not null,
  key text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, week, key)
);
alter table public.guild_claims enable row level security;
drop policy if exists "看自己的公會領獎" on public.guild_claims;
create policy "看自己的公會領獎" on public.guild_claims for select to authenticated using (user_id = auth.uid());

-- 讀書會這週的進度（成員、任務）
create or replace function public.guild_info()
returns json language plpgsql stable security definer set search_path = public as $$
declare cls text; w date := date_trunc('week', public.taipei_today())::date; n int;
  foc int; ans int; mea int; chk int; res json;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select class_code into cls from public.profiles where id = auth.uid();
  if cls is null then return json_build_object('name', null); end if;
  select count(*) into n from public.profiles where class_code = cls;
  select coalesce(sum(f.minutes), 0) into foc from public.focus_sessions f join public.profiles p on p.id = f.user_id where p.class_code = cls and f.day >= w;
  select count(*) into ans from public.answers a join public.profiles p on p.id = a.user_id where p.class_code = cls and a.day >= w;
  select count(*) into mea from public.meals m join public.profiles p on p.id = m.user_id where p.class_code = cls and m.day >= w;
  select count(*) into chk from public.profiles p where p.class_code = cls and (
    exists (select 1 from public.answers a where a.user_id = p.id and a.day >= w)
    or exists (select 1 from public.focus_sessions f where f.user_id = p.id and f.day >= w));
  select json_build_object(
    'name', cls, 'count', n, 'week', w,
    'members', coalesce((select json_agg(x order by x.week_minutes desc) from (
      select p.name, p.tier, p.id = auth.uid() as is_me,
        coalesce((select sum(f.minutes) from public.focus_sessions f where f.user_id = p.id and f.day >= w), 0)::int as week_minutes,
        (select count(*) from public.answers a where a.user_id = p.id and a.day >= w)::int as answers,
        public.current_streak(p.id) as streak
      from public.profiles p where p.class_code = cls limit 60) x), '[]'::json),
    'missions', json_build_array(
      json_build_object('key', 'g_focus', 'title', '大家一起專注', 'unit', '分鐘', 'progress', foc, 'target', 60 * least(n, 30), 'reward', 50,
        'claimed', exists (select 1 from public.guild_claims where user_id = auth.uid() and week = w and key = 'g_focus')),
      json_build_object('key', 'g_answer', 'title', '大家一起答今日一題', 'unit', '次', 'progress', ans, 'target', 3 * least(n, 30), 'reward', 40,
        'claimed', exists (select 1 from public.guild_claims where user_id = auth.uid() and week = w and key = 'g_answer')),
      json_build_object('key', 'g_meal', 'title', '大家一起去餐廳吃飯', 'unit', '次', 'progress', mea, 'target', 4 * least(n, 30), 'reward', 30,
        'claimed', exists (select 1 from public.guild_claims where user_id = auth.uid() and week = w and key = 'g_meal')),
      json_build_object('key', 'g_all', 'title', '每位成員這週都打卡', 'unit', '人', 'progress', chk, 'target', n, 'reward', 60,
        'claimed', exists (select 1 from public.guild_claims where user_id = auth.uid() and week = w and key = 'g_all'))
    )) into res;
  return res;
end $$;

create or replace function public.claim_guild(p_key text)
returns json language plpgsql security definer set search_path = public as $$
declare g json; m json; w date := date_trunc('week', public.taipei_today())::date;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  g := public.guild_info();
  if g->>'name' is null then raise exception '先填班級代碼加入讀書會'; end if;
  select value into m from json_array_elements(g->'missions') where value->>'key' = p_key;
  if m is null then raise exception '沒有這個公會任務'; end if;
  if (m->>'claimed')::boolean then raise exception '這週已經領過了'; end if;
  if (m->>'progress')::int < (m->>'target')::int then raise exception '讀書會還沒完成這個任務'; end if;
  insert into public.guild_claims (user_id, week, key) values (auth.uid(), w, p_key);
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), (m->>'reward')::int, 'guild', p_key);
  return json_build_object('reward', (m->>'reward')::int, 'wallet', public.wallet_balance(auth.uid()));
end $$;

revoke all on function public.grade_board() from public, anon;
grant execute on function public.grade_board() to authenticated;
revoke all on function public.guild_info() from public, anon;
grant execute on function public.guild_info() to authenticated;
revoke all on function public.claim_guild(text) from public, anon;
grant execute on function public.claim_guild(text) to authenticated;
