-- 2026-11-26 多益補題 117 題（聽力 61、Part 6 26、Part 7 30）的答案，給雙倍挑戰、競技場用。
-- 舊題目編號和答案都沒變，只新增；重跑也沒關係。
insert into public.question_keys (qid, tier, unit, a)
select x.u || ':' || x.t || ':' || (x.s + i - 1), 'sage', x.u, substr(x.k, i, 1)::int
from (values
  ('TL','v',25,'1321301031133213030000023'),
  ('TL','g',18,'130033333331033013'),
  ('TL','c',18,'010211202011113202'),
  ('TP6','v',24,'3023021033'),
  ('TP6','g',24,'11030301'),
  ('TP6','c',21,'20001012'),
  ('TP7','v',21,'0133200330'),
  ('TP7','g',20,'2210003102'),
  ('TP7','c',20,'1203000003')
) as x(u, t, s, k)
cross join lateral generate_series(1, length(x.k)) as i
on conflict (qid) do update set tier = excluded.tier, unit = excluded.unit, a = excluded.a;
-- 檢查：TL 應該 122、TP6 95、TP7 91
select unit, count(*) from public.question_keys where unit in ('TL','TP6','TP7') group by unit order by unit;
