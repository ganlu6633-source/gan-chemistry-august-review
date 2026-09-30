-- Run with the candidate migration inside BEGIN ... ROLLBACK.
create temporary table exact_focus_runtime_results(check_name text,passed boolean) on commit drop;
create temporary table exact_focus_runtime_ready on commit drop as
 select source_q.*,app_private.chem_choice_identities(to_jsonb(source_q)) source_identities
 from app_private.chem_teaching_ready_questions source_q
 where grade_band='高三' and app_private.chem_choice_parent_identity(to_jsonb(source_q)) is not null;
do $test$
declare
 sid uuid:=gen_random_uuid(); pid uuid:=gen_random_uuid(); next_pid uuid:=gen_random_uuid(); skill_pid uuid:=gen_random_uuid();
 today date:=(now() at time zone 'Asia/Shanghai')::date; ids text[]:='{}'; preferred text[]; identities text[]:='{}'; releases uuid[];
 focus_id text; focus_concept text; q record; focus_question jsonb; ctx jsonb; preview jsonb; frozen jsonb; response jsonb; rejected boolean;
begin
 -- More than eight non-target questions remain after the first real opening,
 -- so the due-interval test cannot pass merely through overall pool exhaustion.
 for q in select * from exact_focus_runtime_ready where skill_id='H3_STOICH' order by id loop
  if identities&&q.source_identities then continue;end if;
  ids:=array_append(ids,q.id);identities:=identities||q.source_identities;
  exit when cardinality(ids)=18;
 end loop;
 select id,concept_key into focus_id,focus_concept from exact_focus_runtime_ready
 where skill_id='H3_AQ' and not(source_identities&&identities) order by id limit 1;
 if cardinality(ids)<>18 or focus_id is null then raise exception 'QA needs 19 independent current originals';end if;
 preferred:=ids[1:8];ids:=ids||array[focus_id];
 select array_agg(distinct source_release_id) into releases from exact_focus_runtime_ready where id=any(ids);
 insert into public.chem_students_v2(id,display_name,grade_band,textbook_version,record_status,metadata)
 values(sid,'ROLLBACK-exact-runtime-'||left(sid::text,8),'高三','苏教版','active',jsonb_build_object('qaTransactionOnly',true,
 'reviewProgram',jsonb_build_object('participating',true,'startDate',today,'endDate',today+10,'allowAdvanceStudy',true)));
 insert into public.chem_learning_plans(id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,is_scheduled,
 question_count,round_limit,max_question_level,delivery_mode,teaching_managed,target_concept_keys)
 select p,sid,today+n,'REVIEW','ROLLBACK exact small point',array['H3_AQ'],20,'course',true,8,1,8,'legacy_round',false,targets
 from(values(pid,0,array[focus_concept]),(next_pid,1,array[focus_concept]),(skill_pid,2,'{}'::text[])) v(p,n,targets);
 insert into app_private.chem_choice_training_policy(plan_id,grade_band,source_release_ids,preferred_base_ids,authorized_base_pool_ids,
 focus_skill_ids,authorized_skill_ids,allow_advance_study,source_note)
 select p,'高三',releases,preferred,ids,array['H3_AQ'],array['H3_AQ','H3_STOICH'],true,'Rollback-only exact focus runtime test'
 from unnest(array[pid,next_pid,skill_pid]) p;
 preview:=public.chem_choice_training_context(sid,pid,'[]');
 if jsonb_array_length(preview->'baseQuestionIds')<>8 or preview->'baseQuestionIds'->>0<>focus_id
  or preview->>'pendingReason' is not null then raise exception 'Preferred review questions displaced exact target';end if;
 if exists(select 1 from app_private.chem_choice_training_sessions where student_id=sid)
  or exists(select 1 from app_private.chem_choice_training_issued i join public.chem_learning_plans p on p.id=i.plan_id where p.student_id=sid) then
  raise exception 'Read-only exact target preview wrote learning state';end if;
 insert into exact_focus_runtime_results values('eligible_exact_target_outranks_eight_review_preferreds_without_preview_writes',true);
 -- Empty concept list still requires and prioritizes a real focus-skill question.
 ctx:=public.chem_choice_training_context(sid,skill_pid,'[]');
 if ctx->'baseQuestionIds'->>0<>focus_id then raise exception 'Skill-only plan lost actual focus';end if;
 insert into exact_focus_runtime_results values('empty_concept_list_uses_actual_focus_skill',true);
 -- A held target cannot be replaced with unrelated ready questions or become
 -- an issued session/ledger merely by pressing the real start button.
 begin
  insert into app_private.chem_question_delivery_holds(anchor_question_id,reason) values(focus_id,'ROLLBACK exact point unavailable');
  ctx:=public.chem_choice_training_context(sid,pid,'[]');
  if ctx->>'pendingReason'<>'base_source_gap' or jsonb_array_length(ctx->'baseQuestionIds')<>0 then raise exception 'Missing target concealed by same pool review';end if;
  ctx:=public.chem_choice_training_open(sid,pid);
  if ctx->>'pendingReason'<>'base_source_gap'
   or exists(select 1 from app_private.chem_choice_training_sessions where student_id=sid) then raise exception 'Missing-target opening created session';end if;
  raise exception 'qa_restore_focus_source';
 exception when others then if sqlerrm<>'qa_restore_focus_source' then raise;end if;end;
 insert into exact_focus_runtime_results values('missing_target_fails_closed_without_session_or_budget_issue',true);
 ctx:=public.chem_choice_training_open(sid,pid);
 if ctx->'baseQuestionIds' is distinct from preview->'baseQuestionIds' then raise exception 'Teacher and real opening differ';end if;
 frozen:=ctx->'baseQuestionIds';focus_question:=ctx->'questions'->0;
 response:=public.chem_choice_training_lock_answer(sid,pid,focus_id,focus_question->>'question_revision_token',(focus_question->>'correct_option')::integer,false,2);
 -- Exactly one real first answer is saved; it is not due again in another date.
 ctx:=public.chem_choice_training_context(sid,next_pid,'[]');
 if ctx->>'pendingReason'<>'base_source_gap' or jsonb_array_length(ctx->'baseQuestionIds')<>0 then raise exception 'Not-yet-due target pretended to be eligible';end if;
 insert into exact_focus_runtime_results values('recent_target_not_yet_due_cannot_be_replaced_by_review_only_eight',true);
 -- A teacher cannot use a virtual answer to override the immutable first answer.
 rejected:=false;
 begin
  perform public.chem_choice_training_context(sid,pid,jsonb_build_array(jsonb_build_object('questionId',focus_id,
  'revisionToken',focus_question->>'question_revision_token','selectedOption',((focus_question->>'correct_option')::integer+1)%4,'uncertain',false)));
 exception when others then if sqlerrm='choice_first_answer_immutable' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'Target prioritization weakened first answer lock';end if;
 -- The new selection rule must never rewrite a previously frozen session.
 update public.chem_learning_plans set target_concept_keys=array['ROLLBACK-new-unavailable-target'] where id=pid;
 ctx:=public.chem_choice_training_context(sid,pid,null);
 if ctx->'baseQuestionIds' is distinct from frozen or jsonb_array_length(ctx->'lockedAnswers')<>1 then
  raise exception 'Frozen original session or actual answer was replaced';end if;
 insert into exact_focus_runtime_results values('frozen_source_order_and_saved_first_answer_are_unchanged',true);
end $test$;
select * from exact_focus_runtime_results order by check_name;
