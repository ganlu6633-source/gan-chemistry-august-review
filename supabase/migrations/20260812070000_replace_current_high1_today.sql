-- Replace the pre-existing 2026-08-12 redox plan for the currently taught high-one cohort.
-- An audit immediately before this migration confirmed zero attempts on those legacy plans.
begin;

delete from public.chem_learning_plans p
using public.chem_students_v2 s
where p.student_id = s.id
  and p.plan_date = date '2026-08-12'
  and s.metadata->>'curriculumCohort' = 'high1_current';

insert into public.chem_learning_plans(
  student_id, plan_date, mode, title, skill_ids,
  estimated_minutes, source, is_scheduled
)
select
  s.id,
  date '2026-08-12',
  'REVIEW',
  '物质的量、阿伏加德罗常数与摩尔质量当天回收',
  array['H1_MOLE_INTRO']::text[],
  18,
  'course',
  true
from public.chem_students_v2 s
where s.record_status <> 'legacy'
  and s.metadata->>'curriculumCohort' = 'high1_current';

commit;
