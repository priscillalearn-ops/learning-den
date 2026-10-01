
-- =====================================================================
-- 地圖金幣、萬聖節糖果大作戰（2026-10-02 更新；整份重跑即可）
-- =====================================================================
-- 小遊戲領獎：加上萬聖節（每場最多 20），其他遊戲照關卡 15／18／21／24，每種每天最多 40
create or replace function public.claim_game(p_game text, p_score int, p_level int default 1)
returns json language plpgsql security definer set search_path = public as $$
declare got int; r int; cap int; lv int := greatest(1, least(coalesce(p_level, 1), 4));
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_game not in ('match', 'speed', 'granny', 'tower', 'halloween') then raise exception '沒有這個遊戲'; end if;
  if p_game = 'halloween' and not (extract(month from public.taipei_today()) = 10
      or (extract(month from public.taipei_today()) = 11 and extract(day from public.taipei_today()) <= 7)) then
    raise exception '萬聖節活動結束了'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select coalesce(sum(amount), 0) into got from public.coin_tx
    where user_id = auth.uid() and kind = 'game:' || p_game and day = public.taipei_today();
  cap := 15 + 3 * (lv - 1);
  if p_game = 'halloween' then cap := 20; end if;
  r := greatest(0, least(coalesce(p_score, 0), cap, 40 - got));
  if r > 0 then insert into public.coin_tx (user_id, amount, kind) values (auth.uid(), r, 'game:' || p_game); end if;
  return json_build_object('reward', r, 'wallet', public.wallet_balance(auth.uid()));
end $$;
revoke all on function public.claim_game(text, integer, integer) from public, anon;
grant execute on function public.claim_game(text, integer, integer) to authenticated;

-- 地圖金幣：每天 8 枚（編號 0～7），每枚只能撿一次，一枚 2～5 金幣
create or replace function public.claim_map_coin(p_idx int)
returns json language plpgsql security definer set search_path = public as $$
declare amt int;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_idx is null or p_idx < 0 or p_idx > 7 then raise exception '沒有這枚金幣'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  if exists (select 1 from public.coin_tx where user_id = auth.uid() and kind = 'map_coin'
      and ref = p_idx::text and day = public.taipei_today()) then
    return json_build_object('amount', 0, 'wallet', public.wallet_balance(auth.uid())); end if;
  amt := 2 + floor(random() * 4)::int;
  insert into public.coin_tx (user_id, amount, kind, ref) values (auth.uid(), amt, 'map_coin', p_idx::text);
  return json_build_object('amount', amt, 'wallet', public.wallet_balance(auth.uid()));
end $$;
revoke all on function public.claim_map_coin(integer) from public, anon;
grant execute on function public.claim_map_coin(integer) to authenticated;
