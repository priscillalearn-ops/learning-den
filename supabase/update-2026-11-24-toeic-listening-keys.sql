-- 多益聽力 Part 2～4 的答案表（2026-11-24；整份重跑即可）
-- 新增 TL 共 61 題答案到 question_keys（原本就有的表），只新增／更新 TL 開頭的題目。
-- 每一串數字是該分類每一題的正解位置（0=A、1=B、2=C、3=D）。
insert into public.question_keys (qid, tier, unit, a)
select x.u || ':' || x.t || ':' || (i - 1), 'sage', x.u, substr(x.k, i, 1)::int
from (values
  ('TL','v','2002320230202033110012303'),
  ('TL','g','101313231103311012'),
  ('TL','c','113102000103333231')
) as x(u, t, k)
cross join lateral generate_series(1, length(x.k)) as i
on conflict (qid) do update set tier = excluded.tier, unit = excluded.unit, a = excluded.a;

-- 檢查：應該看到 TL 61
select unit, count(*) from public.question_keys where unit = 'TL' group by unit;
