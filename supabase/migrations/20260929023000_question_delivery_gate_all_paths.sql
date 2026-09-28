-- Every route that issues, answers, finalizes, or schedules a question must
-- consult the same per-item readiness view.  Existing historical rows remain
-- available for teacher audit; no blanket legacy hold is created here.
begin;

do $gate$
declare
  change record;
  definition text;
  match_count integer;
begin
  for change in
    select * from (values
    ('public.chem_junior_issue_step(uuid,uuid,text,smallint,text,text,jsonb)', $find$    raise exception 'junior question is unavailable for issue';
  end if;$find$, $replacement$    raise exception 'junior question is unavailable for issue';
  end if;
  if not exists (select 1 from app_private.chem_teaching_ready_questions ready where ready.id = v_question.id) then
    raise exception 'junior question is not ready for delivery';
  end if;$replacement$),
    ('public.chem_junior_validate_issued_step(uuid,uuid,uuid)', $find$    raise exception 'junior issued question is unavailable';
  end if;$find$, $replacement$    raise exception 'junior issued question is unavailable';
  end if;
  if not exists (select 1 from app_private.chem_teaching_ready_questions ready where ready.id = v_question.id) then
    raise exception 'junior issued question is not ready for delivery';
  end if;$replacement$),
    ('public.chem_junior_record_step(uuid,uuid,uuid,smallint,boolean,integer,text)', $find$    raise exception 'junior source question is unavailable';
  end if;$find$, $replacement$    raise exception 'junior source question is unavailable';
  end if;
  if not exists (select 1 from app_private.chem_teaching_ready_questions ready where ready.id = v_question.id) then
    raise exception 'junior source question is not ready for an answer';
  end if;$replacement$),
    ('public.chem_junior_finalize_session(uuid,uuid)', $find$  into v_current_contract_count
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id$find$, $replacement$  into v_current_contract_count
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id
  join app_private.chem_teaching_ready_questions as ready_question
    on ready_question.id = question.id$replacement$),
    ('public.chem_personalize_next_review_plan(uuid,uuid,timestamptz)', $find$), fresh_question as (
    select question.*
    from public.chem_questions question$find$, $replacement$), fresh_question as (
    select question.*
    from app_private.chem_teaching_ready_questions question$replacement$),
    ('app_private.chem_rebudget_unstarted_review_suffix(uuid,uuid,text[])', $find$join public.chem_questions question on question.source_release_id = release.id$find$, $replacement$join app_private.chem_teaching_ready_questions question on question.source_release_id = release.id$replacement$),
    ('public.chem_lock_question_answer(uuid,uuid,integer,text,integer,boolean,integer,text)', $find$from public.chem_questions question
    join app_private.chem_question_source_releases release$find$, $replacement$from app_private.chem_teaching_ready_questions question
    join app_private.chem_question_source_releases release$replacement$),
    ('public.chem_finalize_learning_attempt(uuid,uuid,uuid,text,integer,text,timestamptz,timestamptz,integer,jsonb,jsonb)', $find$    raise exception 'question was held before finalization';
  end if;$find$, $replacement$    raise exception 'question was held before finalization';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_answers) answer
    where not exists (
      select 1 from app_private.chem_teaching_ready_questions ready
      where ready.id = answer->>'question_id'
    )
  ) then
    raise exception 'question is not ready for finalization';
  end if;$replacement$)
    ) as changes(signature, needle, replacement)
  loop
    definition := replace(pg_get_functiondef(change.signature::regprocedure), chr(13), '');
    match_count := (length(definition) - length(replace(definition, change.needle, ''))) / length(change.needle);
    if match_count <> 1 then
      raise exception 'delivery gate patch for % found % anchors instead of one', change.signature, match_count;
    end if;
    execute replace(definition, change.needle, change.replacement);
  end loop;
end;
$gate$;

-- A read-only queue exposes the legacy review debt and likely OCR gaps without
-- asserting that an automated text scan is equivalent to visual verification.
create or replace view app_private.chem_question_quality_audit_queue as
select
  question.id as question_id,
  question.grade_band,
  question.source_release_id,
  question.source_item_key,
  (not app_private.chem_question_item_delivery_review_ready(question.id)) as needs_manual_visual_review,
  (question.stem ~ '(为[，。；]|与通过|和的|[=＝][[:space:]]*[，。；]|[△Δ]H[[:space:]]*=[[:space:]]*[，。；])'
    or question.options::text ~ '(为[，。；]|与通过|和的|[=＝][[:space:]]*[，。；])') as suspected_formula_gap,
  case when review.question_id is null then 'no_item_review'
       else review.review_state end as review_state
from app_private.chem_teaching_ready_questions question
left join app_private.chem_question_item_visual_reviews review
  on review.question_id = question.id
where not app_private.chem_question_item_delivery_review_ready(question.id)
   or question.stem ~ '(为[，。；]|与通过|和的|[=＝][[:space:]]*[，。；]|[△Δ]H[[:space:]]*=[[:space:]]*[，。；])'
   or question.options::text ~ '(为[，。；]|与通过|和的|[=＝][[:space:]]*[，。；])';
revoke all on app_private.chem_question_quality_audit_queue from public, anon, authenticated, service_role;

-- Explicit dated assignments are checked against the exact same ready view.
-- Automatic plans without fixed question IDs are intentionally absent here.
create or replace view app_private.chem_future_plan_question_readiness_audit as
select
  plan.id as plan_id,
  plan.student_id,
  plan.plan_date,
  plan.teaching_managed,
  assigned.question_id,
  plan.question_count,
  case when jsonb_typeof(metadata_assignment.assignment) is distinct from 'array'
         then 'missing_fixed_assignment'
       when jsonb_array_length(case when jsonb_typeof(metadata_assignment.assignment) = 'array'
         then metadata_assignment.assignment else '[]'::jsonb end) is distinct from plan.question_count
         then 'assignment_count_mismatch'
       when original.id is null then 'question_missing'
       when ready.id is null then 'question_not_ready'
       when ready.grade_band is distinct from coalesce(plan.teaching_source_grade, student.grade_band)
         then 'grade_mismatch'
       when plan.self_study_release_id is not null
         and ready.source_release_id is distinct from plan.self_study_release_id
         then 'release_mismatch'
       else null end as issue
from public.chem_learning_plans plan
join public.chem_students_v2 student on student.id = plan.student_id
cross join lateral (
  select student.metadata#>'{reviewProgram,questionAssignments}'->plan.plan_date::text as assignment
) metadata_assignment
left join lateral jsonb_array_elements_text(
  case when jsonb_typeof(metadata_assignment.assignment) = 'array'
       then metadata_assignment.assignment else '[]'::jsonb end
) assigned(question_id) on true
left join public.chem_questions original on original.id = assigned.question_id
left join app_private.chem_teaching_ready_questions ready on ready.id = assigned.question_id
where plan.is_scheduled
  and plan.plan_date >= (now() at time zone 'Asia/Shanghai')::date
  and (plan.teaching_managed or jsonb_typeof(metadata_assignment.assignment) = 'array')
  and (jsonb_typeof(metadata_assignment.assignment) is distinct from 'array'
    or jsonb_array_length(case when jsonb_typeof(metadata_assignment.assignment) = 'array'
      then metadata_assignment.assignment else '[]'::jsonb end) is distinct from plan.question_count
    or original.id is null
    or ready.id is null
    or ready.grade_band is distinct from coalesce(plan.teaching_source_grade, student.grade_band)
    or (plan.self_study_release_id is not null
      and ready.source_release_id is distinct from plan.self_study_release_id));
revoke all on app_private.chem_future_plan_question_readiness_audit from public, anon, authenticated, service_role;

commit;
