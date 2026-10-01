
-- =====================================================================
-- 讀書房聊天室、萬聖節商品（2026-10-01 第三次更新；整份重跑即可）
-- 聊天室跟讀書房同一間（年級房 g-國三 或自由房 free），只看得到最近 24 小時。
-- 國小只能送貼圖、國中 30 字、高中 60 字；3 秒一則、每天 100 則；被禁言不能聊；3 人檢舉自動隱藏。
-- =====================================================================
create table if not exists public.room_chat (
  id bigint generated always as identity primary key,
  room text not null,
  user_id uuid not null references public.profiles on delete cascade,
  name text not null,
  tier text not null,
  body text not null check (char_length(body) between 1 and 60),
  hidden boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists room_chat_room_id on public.room_chat (room, id desc);
alter table public.room_chat enable row level security;

-- 我能進的聊天室：自由房＋自己的年級房（還沒選年級就是等級房）
create or replace function public.my_rooms()
returns text[] language sql stable security definer set search_path = public as $$
  select array['free', case when p.grade is not null then 'g-' || p.grade else 't-' || p.tier end]
  from public.profiles p where p.id = auth.uid();
$$;

drop policy if exists "看自己房間的聊天" on public.room_chat;
create policy "看自己房間的聊天" on public.room_chat for select to authenticated
  using ((room = any (public.my_rooms()) and not hidden and created_at > now() - interval '1 day') or public.is_teacher());

create table if not exists public.room_chat_reports (
  chat_id bigint not null references public.room_chat on delete cascade,
  reporter uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (chat_id, reporter)
);
alter table public.room_chat_reports enable row level security;

create or replace function public.send_room_chat(p_room text, p_body text)
returns void language plpgsql security definer set search_path = public as $$
declare me public.profiles; b text := trim(coalesce(p_body, ''));
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select * into me from public.profiles where id = auth.uid();
  if not found then raise exception '請先建立角色'; end if;
  if not (p_room = any (public.my_rooms())) then raise exception '你不在這間讀書房'; end if;
  if public.is_muted(auth.uid()) then raise exception '你被老師暫停發言了'; end if;
  if b = '' then raise exception '先寫點什麼'; end if;
  if me.tier = 'kid' and b not in ('讚', '好難', '我答對', '加油', '好好玩') then raise exception '見習魔法師用貼圖聊天喔'; end if;
  if char_length(b) > case me.tier when 'teen' then 30 else 60 end then raise exception '太長了'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if exists (select 1 from public.room_chat where user_id = auth.uid() and created_at > now() - interval '3 seconds') then
    raise exception '慢一點，3 秒後再送'; end if;
  if (select count(*) from public.room_chat where user_id = auth.uid() and created_at > now() - interval '1 day') >= 100 then
    raise exception '今天聊太多了，明天再來'; end if;
  insert into public.room_chat (room, user_id, name, tier, body) values (p_room, auth.uid(), me.name, me.tier, b);
end $$;

create or replace function public.report_room_chat(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if not exists (select 1 from public.room_chat where id = p_id and room = any (public.my_rooms())) then raise exception '找不到這則訊息'; end if;
  insert into public.room_chat_reports (chat_id, reporter) values (p_id, auth.uid()) on conflict do nothing;
  if (select count(*) from public.room_chat_reports where chat_id = p_id) >= 3 then
    update public.room_chat set hidden = true where id = p_id; end if;
end $$;

create or replace function public.teacher_chat_reports()
returns table (chat_id bigint, room text, body text, created_at timestamptz, hidden boolean, author_id uuid, author text, reports int)
language sql stable security definer set search_path = public as $$
  select c.id, c.room, c.body, c.created_at, c.hidden, c.user_id, c.name, count(r.chat_id)::int
  from public.room_chat_reports r join public.room_chat c on c.id = r.chat_id
  where public.is_teacher()
  group by c.id order by max(r.created_at) desc limit 100;
$$;

create or replace function public.teacher_hide_chat(p_id bigint, p_hidden boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_teacher() then raise exception '只有老師可以操作'; end if;
  update public.room_chat set hidden = p_hidden where id = p_id;
end $$;

create or replace function public.teacher_dismiss_chat(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_teacher() then raise exception '只有老師可以操作'; end if;
  delete from public.room_chat_reports where chat_id = p_id;
  update public.room_chat set hidden = false where id = p_id;
end $$;

revoke all on function public.my_rooms() from public, anon;
grant execute on function public.my_rooms() to authenticated;
revoke all on function public.send_room_chat(text, text) from public, anon;
grant execute on function public.send_room_chat(text, text) to authenticated;
revoke all on function public.report_room_chat(bigint) from public, anon;
grant execute on function public.report_room_chat(bigint) to authenticated;
revoke all on function public.teacher_chat_reports() from public, anon;
grant execute on function public.teacher_chat_reports() to authenticated;
revoke all on function public.teacher_hide_chat(bigint, boolean) from public, anon;
grant execute on function public.teacher_hide_chat(bigint, boolean) to authenticated;
revoke all on function public.teacher_dismiss_chat(bigint) from public, anon;
grant execute on function public.teacher_dismiss_chat(bigint) to authenticated;

-- 新聊天即時推播
do $$ begin
  alter publication supabase_realtime add table public.room_chat;
exception when duplicate_object then null; end $$;

-- 萬聖節商品（10/1～11/7 限定）
insert into public.shop_items (id, slot, price, unlock_cards, avail_from, avail_until, gacha, bundle) values
  ('hat_pumpkin', 'hat', 150, null, '10-01', '11-07', null, null),
  ('pet_bat', 'pet', 350, null, '10-01', '11-07', null, null),
  ('wall_halloween', 'wall', 200, null, '10-01', '11-07', null, null),
  ('floor_halloween', 'floor', 150, null, '10-01', '11-07', null, null),
  ('win_hallow', 'window', 150, null, '10-01', '11-07', null, null),
  ('poster_ghost', 'poster', 100, null, '10-01', '11-07', null, null),
  ('poster_bat', 'poster', 100, null, '10-01', '11-07', null, null),
  ('bed_coffin', 'bed', 350, null, '10-01', '11-07', null, null),
  ('lamp_ghost', 'lamp', 120, null, '10-01', '11-07', null, null),
  ('plant_jack', 'plant', 100, null, '10-01', '11-07', null, null),
  ('rug_web', 'rug', 120, null, '10-01', '11-07', null, null),
  ('pet_ghost', 'pet', 350, null, '10-01', '11-07', null, null),
  ('pet_pumpkin', 'pet', 400, null, '10-01', '11-07', null, null),
  ('pet_spider', 'pet', 250, null, '10-01', '11-07', null, null),
  ('hat_witch_purple', 'hat', 200, null, '10-01', '11-07', null, null),
  ('hat_horns', 'hat', 180, null, '10-01', '11-07', null, null),
  ('hat_mummy', 'hat', 180, null, '10-01', '11-07', null, null),
  ('top_vampire', 'top', 150, null, '10-01', '11-07', null, null),
  ('top_pumpkin', 'top', 120, null, '10-01', '11-07', null, null),
  ('acc_fangs', 'acc', 100, null, '10-01', '11-07', null, null),
  ('acc_mask', 'acc', 120, null, '10-01', '11-07', null, null)
on conflict (id) do update set slot = excluded.slot, price = excluded.price, unlock_cards = excluded.unlock_cards, avail_from = excluded.avail_from, avail_until = excluded.avail_until, gacha = excluded.gacha, bundle = excluded.bundle;
