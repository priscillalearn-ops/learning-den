-- 2026-11-26 新單元 TV「多益高頻單字（進階）」126 題的答案，給雙倍挑戰、競技場用。重跑也沒關係。
insert into public.question_keys (qid, tier, unit, a)
select x.u || ':' || x.t || ':' || (i - 1), 'sage', x.u, substr(x.k, i, 1)::int
from (values
  ('TV','v','31312221021232032301121132303220203313023103210300120022112221102111313200202321010130131102131101133'),
  ('TV','c','2131320012130122103201202')
) as x(u, t, k)
cross join lateral generate_series(1, length(x.k)) as i
on conflict (qid) do update set tier = excluded.tier, unit = excluded.unit, a = excluded.a;
-- 檢查：應該是 TV 126
select unit, count(*) from public.question_keys where unit = 'TV' group by unit;
