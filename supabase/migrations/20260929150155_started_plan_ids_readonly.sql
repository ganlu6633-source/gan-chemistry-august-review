-- A saved first answer is learning activity even before an attempt is finalized.
-- This lookup never manufactures progress and never exposes answers or options.
create function public.chem_started_plan_ids(p_student_id uuid)
returns table(plan_id uuid)
language sql
stable
security definer
set search_path = ''
as $function$
  select p.id
  from public.chem_learning_plans p
  join public.chem_students_v2 s on s.id = p.student_id
  where p_student_id is not null
    and s.id = p_student_id
    and s.record_status = 'active'
    and (
      exists (
        select 1 from public.chem_learning_attempts a
        where a.student_id = p_student_id and a.plan_day_id = p.id
      )
      or exists (
        select 1 from app_private.chem_question_answer_locks l
        where l.student_id = p_student_id and l.plan_day_id = p.id
      )
    )
  order by p.id;
$function$;

revoke all on function public.chem_started_plan_ids(uuid) from public, anon, authenticated;
grant execute on function public.chem_started_plan_ids(uuid) to service_role;

comment on function public.chem_started_plan_ids(uuid) is
  'Service-only readonly set of owned plans with a persisted attempt or first-answer lock; used for hasStarted, never completion or mastery.';
