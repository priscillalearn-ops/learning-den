-- 多益 Part 6 段落填空的答案表（2026-11-24；整份重跑即可）
-- 新增 TP6 共 69 題答案到 question_keys（原本就有的表），只新增／更新 TP6 開頭的題目。
-- 每一串數字是該分類每一題的正解位置（0=A、1=B、2=C、3=D）。
insert into public.question_keys (qid, tier, unit, a)
select x.u || ':' || x.t || ':' || (i - 1), 'sage', x.u, substr(x.k, i, 1)::int
from (values
  ('TP6','v','001311331202301103013323'),
  ('TP6','g','113131211303210131232303'),
  ('TP6','c','232131230111323123320')
) as x(u, t, k)
cross join lateral generate_series(1, length(x.k)) as i
on conflict (qid) do update set tier = excluded.tier, unit = excluded.unit, a = excluded.a;

-- 檢查：應該看到 TP6 69
select unit, count(*) from public.question_keys where unit = 'TP6' group by unit;
