-- =====================================================================
-- 大魔導師加「大學」年級（2026-11-23；整份重跑即可）
-- 高中生、大學生是主要客群：大魔導師（高中・大學）可以選 高一／高二／高三／大學。
-- 選「大學」的人有自己的「大學 讀書房」和年級排行榜（grade_board 本來就照 grade 分，不用改）。
-- 只改 profiles 的年級檢查，不會動到任何人的資料。
-- =====================================================================
alter table public.profiles drop constraint if exists profiles_grade_ok;
alter table public.profiles add constraint profiles_grade_ok check (
  grade is null
  or (tier = 'kid' and grade = '國小')
  or (tier = 'teen' and grade in ('國一', '國二', '國三'))
  or (tier = 'sage' and grade in ('高一', '高二', '高三', '大學')));

-- 檢查：跑完應該看到一行 profiles_grade_ok，內容有「大學」
select conname, pg_get_constraintdef(oid) from pg_constraint where conname = 'profiles_grade_ok';
