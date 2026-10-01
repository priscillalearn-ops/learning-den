
-- =====================================================================
-- 年級分群（2026-10-01 更新；整份重跑即可）
-- 班級代碼不能自己亂打了，只能是：國小／國一／國二／國三／高一／高二／高三，而且要跟等級對得上。
-- 以前填的代碼會盡量猜成年級（7xx→國一、8xx→國二、9xx→國三；高中 1xx→高一…），猜不到的清空，學生下次登入會被請去選年級。
-- =====================================================================
create or replace function public.grade_guess(p_code text, p_tier text)
returns text language sql immutable as $$
  select case
    when p_code is null then case when p_tier = 'kid' then '國小' end
    when p_tier = 'kid' then '國小'
    when p_code in ('國小', '國一', '國二', '國三', '高一', '高二', '高三') then
      case when (p_tier = 'teen' and p_code like '國_' and p_code <> '國小')
             or (p_tier = 'sage' and p_code like '高_')
             or p_tier is null then p_code end
    when p_tier = 'teen' then case
      when p_code ~ '^\s*(7|七|國一|國1|一年)' then '國一'
      when p_code ~ '^\s*(8|八|國二|國2|二年)' then '國二'
      when p_code ~ '^\s*(9|九|國三|國3|三年)' then '國三' end
    when p_tier = 'sage' then case
      when p_code ~ '^\s*(1|10|一|高一|高1)' then '高一'
      when p_code ~ '^\s*(2|11|二|高二|高2)' then '高二'
      when p_code ~ '^\s*(3|12|三|高三|高3)' then '高三' end
  end;
$$;

alter table public.profiles drop constraint if exists profiles_grade_ok;
update public.profiles set class_code = public.grade_guess(class_code, tier)
  where class_code is distinct from public.grade_guess(class_code, tier);
alter table public.profiles add constraint profiles_grade_ok check (
  class_code is null
  or (tier = 'kid' and class_code = '國小')
  or (tier = 'teen' and class_code in ('國一', '國二', '國三'))
  or (tier = 'sage' and class_code in ('高一', '高二', '高三')));

-- 公告和任務也換成年級；猜不到的改成發給全部年級
update public.announcements set class_code = public.grade_guess(class_code, null)
  where class_code is not null and class_code not in ('國小', '國一', '國二', '國三', '高一', '高二', '高三');
update public.missions set class_code = public.grade_guess(class_code, null)
  where class_code is not null and class_code not in ('國小', '國一', '國二', '國三', '高一', '高二', '高三');
-- 只看得到特定班級的老師，改成看全部（班級代碼已經換成年級了）
update public.teachers set classes = null where classes is not null;
