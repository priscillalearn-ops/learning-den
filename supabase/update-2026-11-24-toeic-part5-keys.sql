-- 多益 Part 5 新題目的答案表（2026-11-24；整份重跑即可）
-- 新增 TP5A～TP5D 共 300 題答案到 question_keys（原本就有的表），只新增／更新 TP5 開頭的題目。
-- 每一串數字是該分類 25 題的正解位置（0=A、1=B、2=C、3=D）。
insert into public.question_keys (qid, tier, unit, a)
select x.u || ':' || x.t || ':' || (i - 1), 'sage', x.u, substr(x.k, i, 1)::int
from (values
  ('TP5A','v','1323233323321202133331221'),
  ('TP5A','g','2123213200130002001000330'),
  ('TP5A','c','0103111002021301231000323'),
  ('TP5B','v','0221330020033232232111010'),
  ('TP5B','g','2312222211232012030330122'),
  ('TP5B','c','0012213330033232010230020'),
  ('TP5C','v','1203101122301232010033133'),
  ('TP5C','g','3030113310121002333310231'),
  ('TP5C','c','1210031022013103132003122'),
  ('TP5D','v','0231122311121001331330331'),
  ('TP5D','g','3012103113203021121120032'),
  ('TP5D','c','1131201133030003322233200')
) as x(u, t, k)
cross join lateral generate_series(1, length(x.k)) as i
on conflict (qid) do update set tier = excluded.tier, unit = excluded.unit, a = excluded.a;

-- 檢查：應該看到 TP5A～TP5D 各 75
select unit, count(*) from public.question_keys where unit like 'TP5%' group by unit order by unit;
