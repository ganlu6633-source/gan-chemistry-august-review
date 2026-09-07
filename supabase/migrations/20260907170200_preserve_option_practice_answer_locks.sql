begin;
create or replace function public.chem_current_plan_answer_locks(p_student_id uuid,p_plan_day_id uuid,p_attempt_sequence integer)
returns table(question_id text,selected_option integer,uncertain boolean,duration_sec integer,revision_token text,created_at timestamptz)
language sql stable security definer set search_path=''
as $$
 select l.question_id,l.selected_option::integer,l.uncertain,l.duration_sec::integer,l.revision_token,l.created_at
 from app_private.chem_question_answer_locks l
 join public.chem_learning_plans p on p.id=l.plan_day_id and p.student_id=l.student_id
 where p_student_id is not null and p_plan_day_id is not null and p_attempt_sequence between 0 and 7
 and l.student_id=p_student_id and l.plan_day_id=p_plan_day_id and l.attempt_sequence=p_attempt_sequence
 order by l.created_at,l.question_id;
$$;
revoke all on function public.chem_current_plan_answer_locks(uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.chem_current_plan_answer_locks(uuid,uuid,integer) to service_role;
commit;
