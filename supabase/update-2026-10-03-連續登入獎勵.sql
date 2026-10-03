
-- =====================================================================
-- 連續登入獎勵（2026-10-03 更新；整份重跑即可）
-- 每天第一次打開 app 領一次；7 天一輪：10／15／20／25／30／40／50 金幣，第 7 天再送盲盒券 1 張。
-- 中間漏一天就從第 1 天重來。
-- =====================================================================
create table if not exists public.login_claims (
  user_id uuid not null references public.profiles on delete cascade,
  day date not null default public.taipei_today(),
  streak int not null,
  created_at timestamptz not null default now(),
  primary key (user_id, day)
);
alter table public.login_claims enable row level security;
drop policy if exists "看自己的登入紀錄" on public.login_claims;
create policy "看自己的登入紀錄" on public.login_claims for select to authenticated using (user_id = auth.uid());

create or replace function public.claim_login()
returns json language plpgsql security definer set search_path = public as $$
declare t date := public.taipei_today(); prev int; st int; d int; amt int; tk int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid()) then raise exception '請先建立角色'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select streak into st from public.login_claims where user_id = auth.uid() and day = t;
  if found then
    return json_build_object('claimed', false, 'streak', st, 'day', (st - 1) % 7 + 1, 'wallet', public.wallet_balance(auth.uid()));
  end if;
  select streak into prev from public.login_claims where user_id = auth.uid() and day = t - 1;
  st := coalesce(prev, 0) + 1;
  d := (st - 1) % 7 + 1;
  amt := (array[10, 15, 20, 25, 30, 40, 50])[d];
  insert into public.login_claims (user_id, day, streak) values (auth.uid(), t, st);
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'login', d::text);
  if d = 7 then
    insert into public.gacha_state (user_id, tickets) values (auth.uid(), 1)
      on conflict (user_id) do update set tickets = public.gacha_state.tickets + 1;
  end if;
  select tickets into tk from public.gacha_state where user_id = auth.uid();
  return json_build_object('claimed', true, 'streak', st, 'day', d, 'coins', amt, 'ticket', d = 7,
    'tickets', coalesce(tk, 0), 'wallet', public.wallet_balance(auth.uid()));
end $$;
revoke all on function public.claim_login() from public, anon;
grant execute on function public.claim_login() to authenticated;
