-- Run against a database with question_delivery_gate_all_paths applied.
-- Every fixture write is rolled back, including simulated pending reviews.
begin;

do $test$
declare
  junior public.chem_questions%rowtype;
  curriculum public.chem_junior_curriculum_days%rowtype;
  student_one uuid := gen_random_uuid();
  student_two uuid := gen_random_uuid();
  plan_one uuid := gen_random_uuid();
  plan_two uuid := gen_random_uuid();
  session_one uuid := gen_random_uuid();
  session_two uuid := gen_random_uuid();
  issued record;
  snapshot jsonb;
  rejected boolean;
  name text;
  definition text;
  grade text;
  high_school public.chem_questions%rowtype;
  high_student uuid;
  high_plan uuid;
begin
  -- Inspect every direct database route; Edge selection is validated by
  -- validate:edge and the shared ready-id RPC exercised below.
  definition := pg_get_functiondef(
    'app_private.chem_junior_question_delivery_ready(text)'::regprocedure
  );
  if position('app_private.chem_question_item_delivery_review_ready' in definition)=0 then
    raise exception 'junior delivery helper bypasses the per-item review';
  end if;
  definition := pg_get_functiondef(
    'app_private.chem_question_item_delivery_review_ready(text)'::regprocedure
  );
  if position('app_private.chem_question_item_visual_reviewed' in definition)=0 then
    raise exception 'per-item delivery helper bypasses the exact visual review';
  end if;
  for name in select unnest(array[
    'public.chem_junior_issue_step(uuid,uuid,text,smallint,text,text,jsonb)',
    'public.chem_junior_validate_issued_step(uuid,uuid,uuid)',
    'public.chem_junior_record_step(uuid,uuid,uuid,smallint,boolean,integer,text)',
    'public.chem_junior_finalize_session(uuid,uuid)',
    'public.chem_personalize_next_review_plan(uuid,uuid,timestamptz)',
    'app_private.chem_rebudget_unstarted_review_suffix(uuid,uuid,text[])',
    'public.chem_lock_question_answer(uuid,uuid,integer,text,integer,boolean,integer,text)',
    'public.chem_finalize_learning_attempt(uuid,uuid,uuid,text,integer,text,timestamptz,timestamptz,integer,jsonb,jsonb)'
  ]) loop
    definition := pg_get_functiondef(name::regprocedure);
    if position('app_private.chem_teaching_ready_questions' in definition) = 0
      and position('app_private.chem_junior_question_delivery_ready' in definition) = 0 then
      raise exception '% bypasses per-item readiness', name;
    end if;
  end loop;

  select original.* into junior
  from app_private.chem_teaching_ready_questions ready
  join public.chem_questions original on original.id=ready.id
  join public.chem_junior_curriculum_days day
    on day.textbook_version=ready.textbook_version
   and ready.knowledge_id=any(day.knowledge_skill_ids)
   and day.release_status='ready'
  where ready.grade_band='初三'
  order by ready.id
  limit 1;
  if not found then raise exception 'test requires one ready junior question'; end if;
  select * into curriculum from public.chem_junior_curriculum_days day
    where day.textbook_version=junior.textbook_version
      and junior.knowledge_id=any(day.knowledge_skill_ids)
      and day.release_status='ready'
    order by day.day_number limit 1;

  insert into public.chem_students_v2(id,display_name,grade_band,textbook_version,metadata)
  values
    (student_one,'QA-delivery-ready-one','初三','科粤版','{"qaTransactionOnly":true}'::jsonb),
    (student_two,'QA-delivery-ready-two','初三','科粤版','{"qaTransactionOnly":true}'::jsonb);
  insert into public.chem_learning_plans(
    id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,
    question_count,round_limit,delivery_mode,junior_curriculum_day_id
  ) values
    (plan_one,student_one,(now() at time zone 'Asia/Shanghai')::date,'REVIEW',
     'QA per-item ready one',curriculum.knowledge_skill_ids,30,'course',8,4,'junior_adaptive',curriculum.id),
    (plan_two,student_two,(now() at time zone 'Asia/Shanghai')::date,'REVIEW',
     'QA per-item ready two',curriculum.knowledge_skill_ids,30,'course',8,4,'junior_adaptive',curriculum.id);
  insert into public.chem_junior_daily_sessions(
    id,student_id,plan_day_id,curriculum_day_id,study_date,textbook_version,
    knowledge_skill_ids,initial_question_target,hard_question_cap,recovery_round_limit,status
  ) values
    (session_one,student_one,plan_one,curriculum.id,(now() at time zone 'Asia/Shanghai')::date,
     '科粤版',curriculum.knowledge_skill_ids,8,30,3,'active'),
    (session_two,student_two,plan_two,curriculum.id,(now() at time zone 'Asia/Shanghai')::date,
     '科粤版',curriculum.knowledge_skill_ids,8,30,3,'active');

  snapshot := jsonb_build_object(
    'questionId',junior.id,'motherId',junior.mother_id,'skillId',junior.skill_id,
    'knowledgeId',junior.knowledge_id,'conceptKey',junior.concept_key,
    'level',junior.level,'gradeBand',junior.grade_band,
    'textbookVersion',junior.textbook_version,'stem',junior.stem,
    'options',junior.options,'correctOption',junior.correct_option,
    'explanation',junior.explanation,'scaffold',junior.scaffold,
    'reviewStatus',junior.review_status,'scopeStatus',junior.scope_status,
    'sourceKind',junior.source_kind,'renderMode',junior.render_mode,
    'imageUrl',junior.image_url,'assetRefs',junior.asset_refs,
    'sourceReleaseId',junior.source_release_id,'sourceItemKey',junior.source_item_key,
    'parentSourceItemKey',junior.parent_source_item_key,
    'sameTypeKey',junior.same_type_key,
    'contentFingerprint',junior.content_fingerprint,
    'revisionToken',junior.question_revision_token,
    'routeKind','new_learning','routeReason','QA per-item ready transaction'
  );
  select * into issued from public.chem_junior_issue_step(
    session_one,student_one,junior.id,1::smallint,
    'new_learning','QA per-item ready transaction',snapshot
  );
  if issued.step_id is null then raise exception 'ready junior issue failed'; end if;

  perform public.chem_queue_question_item_visual_recheck(
    junior.id,'回归测试：模拟原题公式丢失，暂停下发和作答','quality-gate-test'
  );
  if exists(select 1 from app_private.chem_teaching_ready_questions where id=junior.id)
    or exists(select 1 from public.chem_teaching_ready_question_ids('初三',array[junior.id]))
  then raise exception 'pending junior item is still ready'; end if;

  rejected:=false;
  begin
    perform public.chem_junior_issue_step(
      session_two,student_two,junior.id,1::smallint,
      'new_learning','QA per-item ready transaction',snapshot
    );
  exception when raise_exception then
    if sqlerrm <> 'junior question is not ready for delivery' then raise; end if;
    rejected:=true;
  end;
  if not rejected then raise exception 'direct junior issue bypassed item hold'; end if;

  rejected:=false;
  begin
    perform public.chem_junior_validate_issued_step(session_one,student_one,issued.step_id);
  exception when raise_exception then
    if sqlerrm <> 'junior issued question is not ready for delivery' then raise; end if;
    rejected:=true;
  end;
  if not rejected then raise exception 'resumed junior step bypassed item hold'; end if;

  rejected:=false;
  begin
    perform public.chem_junior_record_step(
      session_one,student_one,issued.step_id,junior.correct_option::smallint,
      false,10,junior.question_revision_token
    );
  exception when raise_exception then
    if sqlerrm <> 'junior source question is not ready for an answer' then raise; end if;
    rejected:=true;
  end;
  if not rejected then raise exception 'junior answer bypassed item hold'; end if;

  -- All three high-school grades must accept a current original and then
  -- reject the very same ID once its visual review is queued again.
  for grade in select unnest(array['高一','高二','高三']) loop
    select original.* into high_school
    from app_private.chem_teaching_ready_questions ready
    join public.chem_questions original on original.id=ready.id
    where ready.grade_band=grade
      and exists(select 1 from jsonb_array_elements(ready.asset_refs) asset
        where asset->>'kind'='question_image')
      and exists(select 1 from jsonb_array_elements(ready.asset_refs) asset
        where asset->>'kind'='analysis_image')
    order by ready.id limit 1;
    if not found then raise exception 'test requires one image-ready question for %',grade; end if;
    high_student:=gen_random_uuid();
    high_plan:=gen_random_uuid();
    insert into public.chem_students_v2(id,display_name,grade_band,metadata)
      values(high_student,'QA-high-school-delivery-'||grade,grade,
        jsonb_build_object('qaTransactionOnly',true,'reviewProgram',
          jsonb_build_object('questionAssignments',jsonb_build_object(
            (now() at time zone 'Asia/Shanghai')::date::text,jsonb_build_array(high_school.id)))));
    insert into public.chem_learning_plans(
      id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,
      question_count,round_limit
    ) values (
      high_plan,high_student,(now() at time zone 'Asia/Shanghai')::date,
      'REVIEW','QA per-item readiness '||grade,array[high_school.skill_id],10,'course',1,1
    );
    perform public.chem_lock_question_answer(
      high_student,high_plan,0,high_school.id,high_school.correct_option,
      false,10,high_school.question_revision_token
    );
    perform public.chem_queue_question_item_visual_recheck(
      high_school.id,'回归测试：模拟公式与题图待逐题复核，阻断锁答案','quality-gate-test'
    );
    if not exists(select 1 from app_private.chem_future_plan_question_readiness_audit audit
      where audit.plan_id=high_plan and audit.question_id=high_school.id
        and audit.issue='question_not_ready')
    then raise exception '% future assigned question was not flagged',grade; end if;
    rejected:=false;
    begin
      perform public.chem_lock_question_answer(
        high_student,high_plan,1,high_school.id,high_school.correct_option,
        false,10,high_school.question_revision_token
      );
    exception when raise_exception then
      if sqlerrm <> 'question revision is stale or not eligible for an answer lock' then raise; end if;
      rejected:=true;
    end;
    if not rejected then raise exception '% answer lock bypassed item hold',grade; end if;
    rejected:=false;
    begin
      perform public.chem_finalize_learning_attempt(
        gen_random_uuid(),high_student,high_plan,'scheduled',0,'REVIEW',
        now()-interval '1 minute',now(),0,
        jsonb_build_array(jsonb_build_object('question_id',high_school.id)),
        jsonb_build_array('{}'::jsonb)
      );
    exception when raise_exception then
      if sqlerrm <> 'question was held before finalization' then raise; end if;
      rejected:=true;
    end;
    if not rejected then raise exception '% finalization bypassed item hold',grade; end if;
  end loop;

  if to_regclass('app_private.chem_question_quality_audit_queue') is null
    or to_regclass('app_private.chem_future_plan_question_readiness_audit') is null
  then raise exception 'persistent quality audit views are missing'; end if;
end;
$test$;

rollback;
