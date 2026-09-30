-- Run with the candidate migration inside BEGIN ... ROLLBACK.
-- All changed source holds and QA identities disappear on rollback.
create temporary table teacher_choice_refresh_results(check_name text,passed boolean) on commit drop;
create temporary table teacher_choice_refresh_ready on commit drop as
 select q.*,app_private.chem_choice_identities(to_jsonb(q)) source_identities
 from app_private.chem_teaching_ready_questions q
 where grade_band='高三' and level<=3 and skill_id in('H3_AQ','H3_STOICH')
 and app_private.chem_choice_parent_identity(to_jsonb(q)) is not null;
do $test$
declare
 donor uuid:=gen_random_uuid(); target uuid; donor_plan uuid:=gen_random_uuid(); target_plan uuid;
 today date:=(now() at time zone 'Asia/Shanghai')::date;
 ids text[]:='{}'; preferred text[]; identities text[]:='{}'; releases uuid[]; q record;
 focus_id text; focus_backup text; other_focus text; focus_concept text; held_id text; second_hold text; third_hold text; result jsonb; policy_before jsonb; context jsonb;
 target_name text; rejected boolean; new_policy app_private.chem_choice_training_policy; fixture_definition text;
begin
 -- Nine quantitative originals and three aqueous originals: two exact target
 -- concepts plus another concept in the same skill, all independent originals.
 for q in select * from teacher_choice_refresh_ready where skill_id='H3_STOICH' order by id loop
  if q.source_identities&&identities then continue; end if;
  ids:=array_append(ids,q.id);identities:=identities||q.source_identities;
  exit when cardinality(ids)=9;
 end loop;
 select id into focus_id from teacher_choice_refresh_ready where skill_id='H3_AQ' and not(source_identities&&identities) order by id limit 1;
 if cardinality(ids)<>9 or focus_id is null then raise exception 'QA needs independent current sources'; end if;
 select concept_key,source_identities into focus_concept,identities from teacher_choice_refresh_ready where id=focus_id;
 identities:=identities||array(select unnest(source_identities) from teacher_choice_refresh_ready where id=any(ids));
 select id into focus_backup from teacher_choice_refresh_ready where skill_id='H3_AQ' and concept_key=focus_concept and not(source_identities&&identities) order by id limit 1;
 if focus_backup is null then raise exception 'QA needs another independent exact target original'; end if;
 identities:=identities||(select source_identities from teacher_choice_refresh_ready where id=focus_backup);
 select id into other_focus from teacher_choice_refresh_ready where skill_id='H3_AQ' and concept_key<>focus_concept and not(source_identities&&identities) order by id limit 1;
 if other_focus is null then raise exception 'QA needs an independent different-concept original'; end if;
 preferred:=ids[1:7]||array[focus_id];held_id:=ids[1];second_hold:=ids[2];third_hold:=ids[3];ids:=ids||array[focus_id,focus_backup,other_focus];
 select array_agg(distinct source_release_id) into releases from teacher_choice_refresh_ready where id=any(ids);
 insert into public.chem_students_v2(id,display_name,grade_band,textbook_version,record_status,metadata)
 values(donor,'ROLLBACK-source-reference-'||left(donor::text,8),'高三','苏教版','active',
 jsonb_build_object('qaTransactionOnly',true,'teacherSchedulingManaged',true,'reviewProgram',
 jsonb_build_object('participating',true,'startDate',today,'endDate',today+10,'allowAdvanceStudy',true,'allowedSkillIds',jsonb_build_array('H3_AQ','H3_STOICH'))));
 insert into public.chem_learning_plans(id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,is_scheduled,
 question_count,round_limit,max_question_level,delivery_mode,teaching_managed,target_concept_keys)
 values(donor_plan,donor,today,'REVIEW','ROLLBACK focus and current-source refresh',array['H3_AQ'],20,'course',true,8,1,3,'legacy_round',false,array[focus_concept]);
 insert into app_private.chem_choice_training_policy(plan_id,grade_band,source_release_ids,preferred_base_ids,authorized_base_pool_ids,
 focus_skill_ids,authorized_skill_ids,allow_advance_study,source_note)
 values(donor_plan,'高三',releases,preferred,ids,array['H3_AQ'],array['H3_AQ','H3_STOICH'],true,'Rollback-only current source cloning');
 select to_jsonb(c) into policy_before from app_private.chem_choice_training_policy c where plan_id=donor_plan;
 insert into app_private.chem_question_delivery_holds(anchor_question_id,reason) values(held_id,'ROLLBACK teacher clone source withdrawn');
 target_name:='ROLLBACK-source-target-'||left(donor::text,8);
 result:=public.chem_teacher_management('manage_student',jsonb_build_object('operation','create','displayName',target_name,'gradeBand','高三','referenceStudentId',donor),repeat('c',64),'Rollback source clone QA');
 target:=(result->>'studentId')::uuid;
 select p.id into strict target_plan from public.chem_learning_plans p where student_id=target and plan_date=today;
 select * into strict new_policy from app_private.chem_choice_training_policy where plan_id=target_plan;
 if held_id=any(new_policy.authorized_base_pool_ids) or held_id=any(new_policy.preferred_base_ids)
  or cardinality(new_policy.authorized_base_pool_ids)<>11 or cardinality(new_policy.preferred_base_ids)<>8
  or not(new_policy.authorized_base_pool_ids<@ids) or not(focus_id=any(new_policy.preferred_base_ids))
 then raise exception 'Current subset/focus/independent replacement failed'; end if;
 identities:='{}';
 for q in select * from teacher_choice_refresh_ready where id=any(new_policy.preferred_base_ids) loop
  if identities&&q.source_identities then raise exception 'Cloned independent source collision'; end if;
  identities:=identities||q.source_identities;
 end loop;
 if (select to_jsonb(c) from app_private.chem_choice_training_policy c where plan_id=donor_plan) is distinct from policy_before then
 raise exception 'Reference configuration was altered'; end if;
 if exists(select 1 from public.chem_learning_attempts where student_id=target)
 or exists(select 1 from app_private.chem_choice_training_sessions where student_id=target)
 or exists(select 1 from app_private.chem_question_answer_locks where student_id=target)
 or exists(select 1 from public.chem_student_skill_state where student_id=target) then raise exception 'New student inherited learning evidence'; end if;
 context:=public.chem_choice_training_context(target,target_plan,'[]');
 if jsonb_array_length(context->'baseQuestionIds')<>8 or context->>'pendingReason' is not null then raise exception 'Refreshed clone cannot issue eight'; end if;
 insert into teacher_choice_refresh_results values('withdrawn_preferred_excluded_exact_original_pool_used_eight_independent_and_real_focus',true);
 insert into teacher_choice_refresh_results values('reference_policy_and_learning_evidence_unchanged',true);
 -- Activated originals are immutable, so fault-inject NULL only into this
 -- rollback-local helper's JSON read projection, without editing a real source,
 -- weakening its delivery gate, or committing the instrumented helper.
 begin
  fixture_definition:=pg_get_functiondef('app_private.chem_clone_choice_policy(uuid,uuid)'::regprocedure);
  if strpos(fixture_definition,'jsonb_agg(to_jsonb(source_q) order by original.ordinality)')=0 then raise exception 'NULL fixture projection anchor changed';end if;
  execute replace(fixture_definition,'jsonb_agg(to_jsonb(source_q) order by original.ordinality)',
   format('jsonb_agg(case when source_q.id=%L then to_jsonb(source_q)-''concept_key'' else to_jsonb(source_q) end order by original.ordinality)',focus_id));
  insert into app_private.chem_question_delivery_holds(anchor_question_id,reason) values(focus_backup,'ROLLBACK NULL concept exact alternate unavailable');
  target_name:='ROLLBACK-null-focus-'||left(donor::text,8);rejected:=false;
  begin
   perform public.chem_teacher_management('manage_student',jsonb_build_object('operation','create','displayName',target_name,'gradeBand','高三','referenceStudentId',donor),repeat('c',64),'Rollback unknown focus QA');
  exception when others then if sqlerrm='参照进度的这个细知识点暂缺可用原题，请先补齐题源再同步进度' then rejected:=true;else raise;end if;end;
  if not rejected or exists(select 1 from public.chem_students_v2 where display_name=target_name) then raise exception 'NULL source concept was accepted as actual focus evidence';end if;
  raise exception 'qa_restore_null_concept';
 exception when others then if sqlerrm<>'qa_restore_null_concept' then raise;end if;end;
 insert into teacher_choice_refresh_results values('null_source_concept_does_not_bypass_exact_focus_guard_or_create_partial_student',true);
 -- A current original for the exact target can replace a withdrawn target.
 insert into app_private.chem_question_delivery_holds(anchor_question_id,reason) values(focus_id,'ROLLBACK only focus original withdrawn');
 result:=public.chem_teacher_management('manage_student',jsonb_build_object('operation','create','displayName','ROLLBACK-exact-focus-'||left(donor::text,8),'gradeBand','高三','referenceStudentId',donor),repeat('c',64),'Rollback exact focus replacement');
 if not exists(select 1 from app_private.chem_choice_training_policy c join public.chem_learning_plans p on p.id=c.plan_id
  where p.student_id=(result->>'studentId')::uuid and focus_backup=any(c.preferred_base_ids) and not(focus_id=any(c.authorized_base_pool_ids))) then
  raise exception 'Exact target replacement failed'; end if;
 insert into teacher_choice_refresh_results values('withdrawn_target_replaced_by_same_concept_from_original_pool',true);
 -- A ready question in another concept of the same skill is NOT the target.
 insert into app_private.chem_question_delivery_holds(anchor_question_id,reason) values(focus_backup,'ROLLBACK exact target exhausted');
 target_name:='ROLLBACK-focus-gap-'||left(donor::text,8);rejected:=false;
 begin
  perform public.chem_teacher_management('manage_student',jsonb_build_object('operation','create','displayName',target_name,'gradeBand','高三','referenceStudentId',donor),repeat('c',64),'Rollback focus gap QA');
 exception when others then if sqlerrm='参照进度的这个细知识点暂缺可用原题，请先补齐题源再同步进度' then rejected:=true;else raise;end if;end;
 if not rejected or exists(select 1 from public.chem_students_v2 where display_name=target_name) then raise exception 'Focus shortage did not fail atomically'; end if;
 insert into teacher_choice_refresh_results values('same_skill_other_concept_does_not_hide_target_gap_or_create_partial_student',true);
 insert into app_private.chem_question_delivery_holds(anchor_question_id,reason) values(second_hold,'ROLLBACK pool shortage'),(third_hold,'ROLLBACK pool shortage');
 target_name:='ROLLBACK-pool-gap-'||left(donor::text,8);rejected:=false;
 begin
  perform public.chem_teacher_management('manage_student',jsonb_build_object('operation','create','displayName',target_name,'gradeBand','高三','referenceStudentId',donor),repeat('c',64),'Rollback pool gap QA');
 exception when others then if sqlerrm='参照进度中的可用原题不足八道，请先补齐题源再同步进度' then rejected:=true;else raise;end if;end;
 if not rejected or exists(select 1 from public.chem_students_v2 where display_name=target_name) then raise exception 'Source shortage did not fail atomically'; end if;
 insert into teacher_choice_refresh_results values('pool_shortage_is_explicit_and_creates_no_partial_student',true);
 -- The normal policy guard still rejects a stale configuration even after the
 -- new helper exists; no readiness exception has been added to the guard.
 rejected:=false;
 begin
  update app_private.chem_choice_training_policy set authorized_base_pool_ids=ids where plan_id=target_plan;
 exception when others then if sqlerrm='choice_policy_source_not_ready' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'Existing live source guard weakened'; end if;
 insert into teacher_choice_refresh_results values('existing_policy_guard_still_rejects_withdrawn_sources',true);
 if has_function_privilege('anon','app_private.chem_clone_choice_policy(uuid,uuid)','execute')
 or has_function_privilege('authenticated','app_private.chem_clone_choice_policy(uuid,uuid)','execute')
 or has_function_privilege('service_role','app_private.chem_clone_choice_policy(uuid,uuid)','execute')
 or (select prosecdef from pg_proc where oid='app_private.chem_clone_choice_policy(uuid,uuid)'::regprocedure)
 or not exists(select 1 from pg_proc where oid='app_private.chem_clone_choice_policy(uuid,uuid)'::regprocedure and proconfig @> array['search_path=""']) then
  raise exception 'Private clone helper privilege boundary changed'; end if;
 insert into teacher_choice_refresh_results values('private_invoker_helper_has_empty_search_path_and_no_client_execute',true);
end $test$;
select * from teacher_choice_refresh_results order by check_name;
