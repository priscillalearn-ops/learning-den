-- =====================================================================
-- 學生自己刪除帳號（2026-10-20 更新；整份重跑即可）
-- App Store 和 Google Play 都規定 app 裡要能自己刪除帳號。
-- 刪除後：角色、作答、專注、單字卡、房間、花園、好友、私訊、留言、金幣紀錄全部一起刪掉，無法復原。
-- =====================================================================
create or replace function public.delete_my_account(p_confirm text)
returns void language plpgsql security definer set search_path = public, auth as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception '請先登入'; end if;
  if coalesce(p_confirm, '') <> '刪除' then raise exception '請輸入「刪除」確認'; end if;
  -- 沒有外鍵連到帳號的紀錄先手動清掉
  delete from public.friend_point_log where a = u or b = u or actor = u;
  delete from public.friend_points where a = u or b = u;
  -- 刪掉登入帳號；角色和所有學習紀錄會跟著一起刪除（on delete cascade）
  delete from auth.users where id = u;
end $$;
revoke all on function public.delete_my_account(text) from public, anon;
grant execute on function public.delete_my_account(text) to authenticated;

-- =====================================================================
-- 上架建議箱（2026-10-20 第二次更新；整份重跑即可）
-- 學生寫建議（每天最多 3 則）；老師看建議、給 100～1000 金幣或只說謝謝、可以回覆；學生下次打開會收到通知。
-- =====================================================================
create table if not exists public.suggestions (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles on delete cascade,
  category text not null check (category in ('feature', 'question', 'bug', 'other')),
  body text not null check (char_length(body) between 5 and 300),
  status text not null default 'new' check (status in ('new', 'rewarded', 'thanked')),
  reward int not null default 0,
  reply text check (char_length(reply) <= 100),
  notified boolean not null default false,
  created_at timestamptz not null default now(),
  handled_at timestamptz
);
create index if not exists suggestions_user on public.suggestions (user_id, created_at desc);
create index if not exists suggestions_status on public.suggestions (status, created_at desc);
alter table public.suggestions enable row level security;
drop policy if exists "看自己的建議" on public.suggestions;
create policy "看自己的建議" on public.suggestions for select to authenticated using (user_id = auth.uid());

create or replace function public.submit_suggestion(p_category text, p_body text)
returns json language plpgsql security definer set search_path = public as $$
declare b text := trim(coalesce(p_body, ''));
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid()) then raise exception '請先建立角色'; end if;
  if char_length(b) < 5 then raise exception '建議至少寫 5 個字'; end if;
  if char_length(b) > 300 then raise exception '建議最多 300 字'; end if;
  if p_category not in ('feature', 'question', 'bug', 'other') then raise exception '類型不對'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if (select count(*) from public.suggestions where user_id = auth.uid() and created_at > now() - interval '1 day') >= 3 then
    raise exception '今天已經寫 3 則了，明天再來'; end if;
  insert into public.suggestions (user_id, category, body) values (auth.uid(), p_category, b);
  return json_build_object('ok', true);
end $$;

create or replace function public.my_suggestions()
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', id, 'category', category, 'body', body, 'status', status, 'reward', reward,
    'reply', reply, 'notified', notified, 'created_at', created_at) order by created_at desc), '[]'::json)
  from public.suggestions where user_id = auth.uid();
$$;
create or replace function public.suggestions_seen()
returns void language sql security definer set search_path = public as $$
  update public.suggestions set notified = true where user_id = auth.uid() and status <> 'new' and not notified;
$$;

-- 老師：看建議（還沒處理的排前面）
create or replace function public.teacher_suggestions()
returns table (id bigint, name text, tier text, class_code text, category text, body text, status text, reward int, reply text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select s.id, p.name, p.tier, p.class_code, s.category, s.body, s.status, s.reward, s.reply, s.created_at
  from public.suggestions s join public.profiles p on p.id = s.user_id
  where public.is_teacher() and (public.teacher_can_see(p.class_code)
    or exists (select 1 from public.teachers x where x.user_id = auth.uid() and x.classes is null))
  order by (s.status = 'new') desc, s.created_at desc limit 200;
$$;

-- 老師：給獎勵（0 = 只說謝謝；100～1000 金幣），每則只能處理一次
create or replace function public.teacher_reward_suggestion(p_id bigint, p_coins int, p_reply text)
returns json language plpgsql security definer set search_path = public as $$
declare sg public.suggestions; cls text;
begin
  if not public.is_teacher() then raise exception '只有老師可以處理建議'; end if;
  select * into sg from public.suggestions where id = p_id for update;
  if not found then raise exception '找不到這則建議'; end if;
  select class_code into cls from public.profiles where id = sg.user_id;
  if not (public.teacher_can_see(cls) or exists (select 1 from public.teachers x where x.user_id = auth.uid() and x.classes is null)) then
    raise exception '你沒有這位學生的權限'; end if;
  if sg.status <> 'new' then raise exception '這則已經處理過了'; end if;
  if p_coins is null or not (p_coins = 0 or p_coins between 100 and 1000) then raise exception '金幣要是 0（只說謝謝）或 100～1000'; end if;
  update public.suggestions set status = case when p_coins > 0 then 'rewarded' else 'thanked' end, reward = p_coins,
    reply = left(nullif(trim(coalesce(p_reply, '')), ''), 100), handled_at = now(), notified = false where id = p_id;
  if p_coins > 0 then insert into public.coin_tx (user_id, amount, kind, ref) values (sg.user_id, p_coins, 'suggestion', p_id::text); end if;
  return json_build_object('ok', true);
end $$;

revoke all on function public.submit_suggestion(text, text) from public, anon;
grant execute on function public.submit_suggestion(text, text) to authenticated;
revoke all on function public.my_suggestions() from public, anon;
grant execute on function public.my_suggestions() to authenticated;
revoke all on function public.suggestions_seen() from public, anon;
grant execute on function public.suggestions_seen() to authenticated;
revoke all on function public.teacher_suggestions() from public, anon;
grant execute on function public.teacher_suggestions() to authenticated;
revoke all on function public.teacher_reward_suggestion(bigint, integer, text) from public, anon;
grant execute on function public.teacher_reward_suggestion(bigint, integer, text) to authenticated;
