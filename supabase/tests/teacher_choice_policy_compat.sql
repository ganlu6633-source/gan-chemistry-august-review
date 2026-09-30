-- Candidate migration + this file must run inside BEGIN ... ROLLBACK.
-- No real learner is updated. All identities and plans below are random QA rows.
create temporary table teacher_choice_qa_results(check_name text,passed boolean) on commit drop;
create temporary table teacher_choice_qa_ready on commit drop as
 select * from app_private.chem_teaching_ready_questions where grade_band='高一' and level<=3
 and app_private.chem_choice_parent_identity(to_jsonb(chem_teaching_ready_questions)) is not null;
do $test$
declare
 donor uuid:=gen_random_uuid(); empty_reference uuid:=gen_random_uuid(); target uuid;
 today date:=(now() at time zone 'Asia/Shanghai')::date;
 plan_today uuid:=gen_random_uuid(); plan_future uuid:=gen_random_uuid(); plan_closed_future uuid:=gen_random_uuid();
 plan_legacy uuid:=gen_random_uuid(); target_today uuid; target_future uuid; target_closed_future uuid;
 all_ids text[]; preferred text[]; skills text[]; releases uuid[];
 response jsonb; context jsonb; frozen jsonb; copied jsonb; original jsonb;
 rejected boolean; n integer; donor_name text:='ROLLBACK-teacher-choice-'||left(donor::text,8);
 target_name text:='ROLLBACK-teacher-follow-'||left(donor::text,8);
begin
 select array_agg(id order by id),array_agg(distinct skill_id),array_agg(distinct source_release_id)
 into all_ids,skills,releases from teacher_choice_qa_ready;
 select array_agg(id order by id) into preferred from (
  select distinct on(app_private.chem_choice_parent_identity(to_jsonb(q))) id from teacher_choice_qa_ready q
  order by app_private.chem_choice_parent_identity(to_jsonb(q)),id limit 8
 ) unique_parents;
 if cardinality(preferred)<>8 then raise exception 'QA needs eight real independent source questions';end if;
 insert into public.chem_students_v2(id,display_name,grade_band,textbook_version,record_status,metadata)
 values(donor,donor_name,'高一','苏教版','active',jsonb_build_object('qaTransactionOnly',true,
  'teacherSchedulingManaged',true,'reviewProgram',jsonb_build_object('participating',true,
  'startDate',today,'endDate',today+10,'allowAdvanceStudy',true,'allowedSkillIds',skills))),
 (empty_reference,'ROLLBACK-empty-reference-'||left(donor::text,8),'高一','苏教版','active',jsonb_build_object(
  'qaTransactionOnly',true,'reviewProgram',jsonb_build_object('participating',true,'startDate',today,'endDate',today+10)));
 insert into public.chem_learning_plans(id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,
  is_scheduled,question_count,round_limit,max_question_level,delivery_mode,teaching_managed)
 values(plan_today,donor,today,'REVIEW','ROLLBACK opened choice',skills,20,'course',true,8,1,3,'legacy_round',false),
 (plan_future,donor,today+1,'REVIEW','ROLLBACK authorized future',skills,20,'course',true,8,1,3,'legacy_round',false),
 (plan_closed_future,donor,today+2,'REVIEW','ROLLBACK unauthorized future',skills,20,'course',true,8,1,3,'legacy_round',false),
 (plan_legacy,donor,today+3,'REVIEW','ROLLBACK legacy stays legacy',skills,15,'course',true,4,1,3,'legacy_round',false);
 insert into app_private.chem_choice_training_policy(plan_id,grade_band,source_release_ids,preferred_base_ids,
  authorized_base_pool_ids,focus_skill_ids,authorized_skill_ids,allow_advance_study,source_note)
 select pid,'高一',releases,preferred,all_ids,skills,skills,advance,'Rollback-only teacher reference test'
 from (values(plan_today,true),(plan_future,true),(plan_closed_future,false)) x(pid,advance);
 if app_private.chem_teaching_plan_started(plan_today) then raise exception 'Unopened plan reported started';end if;
 context:=public.chem_choice_training_context(donor,plan_today,'[]');
 if app_private.chem_teaching_plan_started(plan_today) then raise exception 'Read-only preview reported started';end if;
 insert into teacher_choice_qa_results values('unopened_and_readonly_preview_remain_not_started',true);
 context:=public.chem_choice_training_open(donor,plan_today);
 if jsonb_array_length(context->'questions')<>8 or jsonb_array_length(context->'lockedAnswers')<>0
  or not app_private.chem_teaching_plan_started(plan_today)
  or exists(select 1 from app_private.chem_question_answer_locks where student_id=donor)
  or exists(select 1 from public.chem_learning_attempts where student_id=donor)
 then raise exception 'Real issued unanswered choice plan is not protected';end if;
 frozen:=context->'questions';
 insert into teacher_choice_qa_results values('issued_unanswered_choice_counts_as_started',true);
 -- A teacher reference change must fail at the normal friendly started check,
 -- before DELETE cascades encounter the private immutable policy guard.
 rejected:=false;
 begin
  perform public.chem_teacher_management('manage_student',jsonb_build_object('operation','update',
   'studentId',donor,'displayName',donor_name,'gradeBand','高一','referenceStudentId',empty_reference),
   repeat('c',64),'Rollback choice teacher QA');
 exception when others then
  if sqlerrm='已有进行中的题组，不能覆盖起始进度' then rejected:=true;else raise;end if;
 end;
 if not rejected or not exists(select 1 from public.chem_learning_plans where id=plan_today) then
  raise exception 'Started reference replacement was not protected';end if;
 insert into teacher_choice_qa_results values('teacher_reference_update_rejects_started_before_delete',true);
 -- Clone through the actual teacher-management function, not handwritten DML.
 response:=public.chem_teacher_management('manage_student',jsonb_build_object('operation','create',
  'displayName',target_name,'gradeBand','高一','referenceStudentId',donor),repeat('c',64),'Rollback choice teacher QA');
 target:=(response->>'studentId')::uuid;
 if(select count(*) from public.chem_learning_plans where student_id=target)<>4 then raise exception 'Expected four cloned future plans';end if;
 select id into target_today from public.chem_learning_plans where student_id=target and plan_date=today;
 select id into target_future from public.chem_learning_plans where student_id=target and plan_date=today+1;
 select id into target_closed_future from public.chem_learning_plans where student_id=target and plan_date=today+2;
 if(select count(*) from app_private.chem_choice_training_policy c join public.chem_learning_plans p on p.id=c.plan_id where p.student_id=target)<>3
  or exists(select 1 from app_private.chem_choice_training_policy c join public.chem_learning_plans p on p.id=c.plan_id where p.student_id=target and p.plan_date=today+3)
 then raise exception 'Choice strategy lost or fabricated for legacy plan';end if;
 for n in 0..2 loop
  select to_jsonb(c)-'plan_id'-'created_at'-'source_note' into original from app_private.chem_choice_training_policy c
   join public.chem_learning_plans p on p.id=c.plan_id where p.student_id=donor and p.plan_date=today+n;
  select to_jsonb(c)-'plan_id'-'created_at'-'source_note' into copied from app_private.chem_choice_training_policy c
   join public.chem_learning_plans p on p.id=c.plan_id where p.student_id=target and p.plan_date=today+n;
  if original is distinct from copied then raise exception 'Cloned policy does not preserve exact configuration';end if;
 end loop;
 if (select metadata#>'{reviewProgram,allowAdvanceStudy}' from public.chem_students_v2 where id=target) is distinct from 'true'::jsonb then
  raise exception 'Explicit reference advance-study authorization lost';end if;
 insert into teacher_choice_qa_results values('same_grade_copies_exact_three_policies_and_leaves_legacy_unchanged',true);
 if app_private.chem_teaching_plan_started(target_today)
  or exists(select 1 from app_private.chem_choice_training_sessions where student_id=target)
  or exists(select 1 from public.chem_learning_attempts where student_id=target)
  or exists(select 1 from app_private.chem_question_answer_locks where student_id=target)
  or exists(select 1 from public.chem_student_skill_state where student_id=target)
 then raise exception 'Reference learner evidence was copied';end if;
 insert into teacher_choice_qa_results values('reference_configuration_does_not_copy_learning_evidence',true);
 context:=public.chem_choice_training_context(target,target_future,'[]');
 if jsonb_array_length(context->'questions')<>8 then raise exception 'Authorized future clone cannot issue eight';end if;
 rejected:=false;
 begin perform public.chem_choice_training_context(target,target_closed_future,'[]');
 exception when others then if sqlerrm='choice_future_plan_not_open' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'Unauthorised future clone was opened';end if;
 insert into teacher_choice_qa_results values('future_policy_true_and_false_preserved_and_enforced',true);
 context:=public.chem_choice_training_open(target,target_today);
 if context->'baseQuestionIds' is distinct from (select to_jsonb(base_question_ids) from app_private.chem_choice_training_sessions where plan_id=plan_today)
  or not app_private.chem_teaching_plan_started(target_today) then raise exception 'Cloned choice policy cannot open identical initial questions';end if;
 context:=public.chem_choice_training_context(donor,plan_today,null);
 if context->'questions' is distinct from frozen then raise exception 'Reference frozen questions changed';end if;
 insert into teacher_choice_qa_results values('cloned_plan_opens_and_reference_pending_questions_unchanged',true);
 -- Reference grade validation must still reject mismatched grades atomically.
 rejected:=false;
 begin
  perform public.chem_teacher_management('manage_student',jsonb_build_object('operation','create',
   'displayName','ROLLBACK-cross-grade-'||left(donor::text,8),'gradeBand','高二','referenceStudentId',donor),
   repeat('c',64),'Rollback choice teacher QA');
 exception when no_data_found then rejected:=true;end;
 if not rejected or exists(select 1 from public.chem_students_v2 where display_name='ROLLBACK-cross-grade-'||left(donor::text,8)) then
  raise exception 'Cross-grade reference incorrectly accepted';end if;
 insert into teacher_choice_qa_results values('cross_grade_reference_still_rejected_without_partial_profile',true);
 -- Missing advance-study authorization is copied as false, not inferred true.
 response:=public.chem_teacher_management('manage_student',jsonb_build_object('operation','create',
  'displayName','ROLLBACK-no-advance-'||left(donor::text,8),'gradeBand','高一','referenceStudentId',empty_reference),
  repeat('c',64),'Rollback choice teacher QA');
 if (select metadata#>'{reviewProgram,allowAdvanceStudy}' from public.chem_students_v2 where id=(response->>'studentId')::uuid) is distinct from 'false'::jsonb then
  raise exception 'Missing authorization was broadened';end if;
 insert into teacher_choice_qa_results values('missing_reference_future_authorization_defaults_false',true);
end $test$;
select * from teacher_choice_qa_results order by check_name;
