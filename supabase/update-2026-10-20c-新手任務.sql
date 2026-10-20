-- =====================================================================
-- 新手任務（2026-10-20 第三次更新；整份重跑即可）
-- 給 10/20 以後加入的新同學：吃第一餐、答第一題、專注一次、種第一顆菜、買第一件東西，每個 +30 金幣；
-- 全部完成再 +100 金幣和 2 張盲盒券。由資料庫確認真的做到了才發。
-- =====================================================================
create table if not exists public.newbie_claims (
  user_id uuid not null references public.profiles on delete cascade,
  step text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, step)
);
alter table public.newbie_claims enable row level security;
drop policy if exists "看自己的新手任務" on public.newbie_claims;
create policy "看自己的新手任務" on public.newbie_claims for select to authenticated using (user_id = auth.uid());

create or replace function public.newbie_done(u uuid, p_step text)
returns boolean language sql stable security definer set search_path = public as $$
  select case p_step
    when 'meal' then exists (select 1 from public.meals where user_id = u)
    when 'answer' then exists (select 1 from public.answers where user_id = u)
    when 'focus' then exists (select 1 from public.focus_sessions where user_id = u)
    when 'plant' then exists (select 1 from public.garden_plots where user_id = u)
    when 'buy' then exists (select 1 from public.purchases where user_id = u and price > 0)
    when 'all' then (select count(*) from public.newbie_claims where user_id = u and step in ('meal', 'answer', 'focus', 'plant', 'buy')) = 5
    else false end;
$$;

create or replace function public.newbie_status()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'eligible', coalesce((select created_at >= '2026-10-20' from public.profiles where id = auth.uid()), false),
    'done', (select json_object_agg(s, public.newbie_done(auth.uid(), s)) from unnest(array['meal','answer','focus','plant','buy','all']) s),
    'claimed', coalesce((select json_agg(step) from public.newbie_claims where user_id = auth.uid()), '[]'::json));
$$;

create or replace function public.claim_newbie(p_step text)
returns json language plpgsql security definer set search_path = public as $$
declare amt int; tk int := 0;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if not coalesce((select created_at >= '2026-10-20' from public.profiles where id = auth.uid()), false) then
    raise exception '新手任務只給新加入的同學'; end if;
  if p_step not in ('meal', 'answer', 'focus', 'plant', 'buy', 'all') then raise exception '沒有這個任務'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if exists (select 1 from public.newbie_claims where user_id = auth.uid() and step = p_step) then raise exception '已經領過了'; end if;
  if not public.newbie_done(auth.uid(), p_step) then raise exception '還沒完成這個任務'; end if;
  amt := case when p_step = 'all' then 100 else 30 end;
  insert into public.newbie_claims (user_id, step) values (auth.uid(), p_step);
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'newbie', p_step);
  if p_step = 'all' then
    insert into public.gacha_state (user_id, tickets) values (auth.uid(), 2)
      on conflict (user_id) do update set tickets = public.gacha_state.tickets + 2;
    select tickets into tk from public.gacha_state where user_id = auth.uid();
  end if;
  return json_build_object('coins', amt, 'tickets', tk, 'wallet', public.wallet_balance(auth.uid()));
end $$;

revoke all on function public.newbie_status() from public, anon;
grant execute on function public.newbie_status() to authenticated;
revoke all on function public.claim_newbie(text) from public, anon;
grant execute on function public.claim_newbie(text) to authenticated;
