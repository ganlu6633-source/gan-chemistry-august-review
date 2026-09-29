-- Run after the migration, or BEGIN + migration + this file, then ROLLBACK.
-- All assertions are read-only; no QA/student record is inserted or modified.
do $test$
declare
  student record;
  expected uuid[];
  actual uuid[];
  tested integer := 0;
  partial_count integer := 0;
begin
  for student in select id from public.chem_students_v2 loop
    select coalesce(array_agg(x.id order by x.id), '{}'::uuid[]) into expected
    from (
      select p.id
      from public.chem_learning_plans p
      join public.chem_students_v2 s on s.id=p.student_id
      where s.id=student.id and s.record_status='active'
        and (exists(select 1 from public.chem_learning_attempts a where a.student_id=s.id and a.plan_day_id=p.id)
          or exists(select 1 from app_private.chem_question_answer_locks l where l.student_id=s.id and l.plan_day_id=p.id))
    ) x;
    select coalesce(array_agg(plan_id order by plan_id), '{}'::uuid[]) into actual
      from public.chem_started_plan_ids(student.id);
    if actual is distinct from expected then raise exception 'started plan set differs for %',student.id; end if;
    if exists(select 1 from public.chem_started_plan_ids(student.id) x
      left join public.chem_learning_plans p on p.id=x.plan_id
      where p.student_id is distinct from student.id) then
      raise exception 'cross-student plan disclosure';
    end if;
    tested := tested+1;
  end loop;
  if tested=0 then raise exception 'no student fixtures available'; end if;
  select count(*) into partial_count
    from public.chem_learning_plans p join public.chem_students_v2 s on s.id=p.student_id
    where s.record_status='active'
      and exists(select 1 from app_private.chem_question_answer_locks l where l.student_id=s.id and l.plan_day_id=p.id)
      and not exists(select 1 from public.chem_learning_attempts a where a.student_id=s.id and a.plan_day_id=p.id)
      and exists(select 1 from public.chem_started_plan_ids(s.id) x where x.plan_id=p.id);
  if partial_count=0 then raise exception 'no partial-answer fixture exercised'; end if;
  if exists(select 1 from public.chem_started_plan_ids(null)) or
     exists(select 1 from public.chem_started_plan_ids('ffffffff-ffff-4fff-8fff-ffffffffffff')) then
    raise exception 'null or unknown student disclosed plans';
  end if;
  if has_function_privilege('anon','public.chem_started_plan_ids(uuid)','EXECUTE')
    or has_function_privilege('authenticated','public.chem_started_plan_ids(uuid)','EXECUTE')
    or not has_function_privilege('service_role','public.chem_started_plan_ids(uuid)','EXECUTE') then
    raise exception 'started plan ACL mismatch';
  end if;
  if exists(select 1 from pg_proc p, lateral aclexplode(p.proacl) a
    where p.oid='public.chem_started_plan_ids(uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE') then
    raise exception 'PUBLIC execute grant';
  end if;
  if not exists(select 1 from pg_proc where oid='public.chem_started_plan_ids(uuid)'::regprocedure
    and provolatile='s' and prosecdef and proconfig=array['search_path=""']) then
    raise exception 'function volatility or search_path changed';
  end if;
end;
$test$;
