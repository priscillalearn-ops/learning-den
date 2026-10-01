
-- =====================================================================
-- 年級大群（2026-10-01 更新；整份重跑即可）
-- 讀書房照年級分：國小／國一～國三／高一～高三。班級代碼還是可以自己打，不受影響。
-- 舊學生會用班級代碼猜年級（國中 7xx→國一、8xx→國二、9xx→國三；高中 1xx→高一…；國小全部→國小），
-- 猜不到的留空，學生下次登入會被請去選年級。
-- =====================================================================
alter table public.profiles add column if not exists grade text;
alter table public.profiles drop constraint if exists profiles_grade_ok;

update public.profiles set grade = case
    when tier = 'kid' then '國小'
    when tier = 'teen' and class_code ~ '^\s*(7|七|國一)' then '國一'
    when tier = 'teen' and class_code ~ '^\s*(8|八|國二)' then '國二'
    when tier = 'teen' and class_code ~ '^\s*(9|九|國三)' then '國三'
    when tier = 'sage' and class_code ~ '^\s*(1|一|高一)' then '高一'
    when tier = 'sage' and class_code ~ '^\s*(2|二|高二)' then '高二'
    when tier = 'sage' and class_code ~ '^\s*(3|三|高三)' then '高三'
  end
  where grade is null;

alter table public.profiles add constraint profiles_grade_ok check (
  grade is null
  or (tier = 'kid' and grade = '國小')
  or (tier = 'teen' and grade in ('國一', '國二', '國三'))
  or (tier = 'sage' and grade in ('高一', '高二', '高三')));
