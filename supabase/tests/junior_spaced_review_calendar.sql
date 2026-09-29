-- Run after the oxygen source release, cards, provenance and precise option
-- bindings are active. This is an integration test of real issue/answer RPCs.
-- Only a new QA learner receives test answers; every write is rolled back.
begin;
do $interval_test$
declare q public.chem_questions%rowtype; h jsonb; evidence jsonb:='[]'; state jsonb;
 sid uuid:=gen_random_uuid(); today date:='2026-09-29'; i integer; expected integer;
begin
 select * into q from public.chem_questions where grade_band='初三' and usable_for_review and level=1 and parent_source_item_key is not null limit 1;
 if not found then raise exception 'an original L1 fixture is required for interval testing'; end if;
 h:=jsonb_build_object('questionId','reissued-id','parentSourceItemKey',q.parent_source_item_key,
   'createdAt','2026-09-01T02:00:00+08:00','answeredAt','2026-09-01T03:00:00+08:00',
   'correct',true,'uncertain',false,'pending',false,'sessionId',gen_random_uuid());
 for i in 1..4 loop
   h:=jsonb_set(h,'{answeredAt}',to_jsonb(((today-i)::text||'T03:00:00+08:00')));
   h:=jsonb_set(h,'{createdAt}',to_jsonb(((today-i)::text||'T02:00:00+08:00')));
   evidence:=evidence||jsonb_build_array(h);
   state:=app_private.chem_junior_repetition_state(q,evidence,sid,'spaced_review',today);
   expected:=case i when 1 then 3 when 2 then 7 when 3 then 14 else 30 end;
   if (state->>'intervalDays')::integer is distinct from expected or state->>'eligible' is distinct from 'false' then raise exception 'correct streak interval mismatch: %',state; end if;
 end loop;
 h:=jsonb_set(h,'{answeredAt}','"2026-09-28T04:00:00+08:00"');
 h:=jsonb_set(h,'{uncertain}','true');
 state:=app_private.chem_junior_repetition_state(q,evidence||jsonb_build_array(h),sid,'spaced_review',today);
 if state->>'kind'<>'due_review' or (state->>'intervalDays')::integer<>1 then raise exception 'uncertain correct did not reset to next-day review: %',state; end if;
 h:=jsonb_set(h,'{correct}','false'); h:=jsonb_set(h,'{uncertain}','false');
 state:=app_private.chem_junior_repetition_state(q,jsonb_build_array(h),sid,'spaced_review',today);
 if state->>'kind'<>'due_review' then raise exception 'wrong-answer next-day review unavailable'; end if;
 state:=app_private.chem_junior_repetition_state(q,jsonb_build_array(h),sid,'fresh_only',today);
 if state->>'eligible'<>'false' then raise exception 'legacy lifetime policy changed'; end if;
 h:=jsonb_set(h,'{sessionId}',to_jsonb(sid));
 state:=app_private.chem_junior_repetition_state(q,jsonb_build_array(h),sid,'spaced_review',today);
 if state->>'eligible'<>'false' then raise exception 'same-session parent reused after midnight'; end if;
 h:=jsonb_set(h,'{sessionId}',to_jsonb(gen_random_uuid()));
 h:=jsonb_set(h,'{answeredAt}','"2026-09-28T16:00:00Z"');
 state:=app_private.chem_junior_repetition_state(q,jsonb_build_array(h),sid,'spaced_review',today);
 if state->>'eligible'<>'false' then raise exception 'Beijing midnight was treated as prior UTC day'; end if;
 h:=jsonb_set(h,'{answeredAt}','null'); h:=jsonb_set(h,'{pending}','true');
 state:=app_private.chem_junior_repetition_state(q,jsonb_build_array(h),sid,'spaced_review',today);
 if state->>'eligible'<>'false' then raise exception 'unanswered active exposure became a review'; end if;
 if has_function_privilege('anon','public.chem_junior_practice_availability(uuid,uuid,uuid)','execute')
   or has_function_privilege('authenticated','app_private.chem_junior_repetition_history(uuid)','execute')
 then raise exception 'private repetition evidence exposed'; end if;
end; $interval_test$;
do $test$
declare
  sid uuid:=gen_random_uuid(); pid uuid:=gen_random_uuid(); sessid uuid:=gen_random_uuid();
  curriculum public.chem_junior_curriculum_days%rowtype;
  binding app_private.chem_option_practice_bindings%rowtype;
  q public.chem_questions%rowtype;
  step_result record; answer_result record;
  snap jsonb; state jsonb; branch jsonb; before_rows jsonb;
  first_anchor text; first_step uuid; selected smallint;
  route_kind text; route_reason text; chosen boolean:=false; rejected boolean;
  i integer; candidate_parents text[]; total integer;
  old_pid uuid:=gen_random_uuid(); old_session uuid:=gen_random_uuid(); original_curriculum text; future_date date:=(now() at time zone 'Asia/Shanghai')::date+2;
begin
  -- Choose an actual audited wrong-option route that leaves seven independent
  -- first-round parents outside its reserved pool. No source content or binding
  -- is manufactured to make the exercise pass.
  for curriculum in select * from public.chem_junior_curriculum_days
    where textbook_version='科粤版' and release_status='ready'
      and 'J_KY_OXY_H2O2'=any(knowledge_skill_ids) order by day_number
  loop
    for binding in select b.* from app_private.chem_option_practice_bindings b
      join public.chem_questions anchor on anchor.id=b.anchor_question_id
      join app_private.chem_question_source_releases r on r.id=anchor.source_release_id
      where b.review_status='verified' and b.anchor_revision_token=anchor.question_revision_token
        and b.option_index<>anchor.correct_option and anchor.knowledge_id=any(curriculum.knowledge_skill_ids)
        and anchor.review_status='approved' and anchor.usable_for_review and r.status='active'
        and r.verification_status='full_visual_verified'
        and not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=anchor.id)
      order by b.anchor_question_id,b.option_index
    loop
      select array_agg(distinct cq.parent_source_item_key) into candidate_parents
      from jsonb_array_elements(binding.candidates) candidate
      join public.chem_questions cq on cq.id=candidate->>'questionId'
      join app_private.chem_question_source_releases cr on cr.id=cq.source_release_id and cr.status='active'
      where cq.question_revision_token=candidate->>'revisionToken' and cq.usable_for_review
        and cq.review_status='approved' and cq.knowledge_id=any(curriculum.knowledge_skill_ids)
        and not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=cq.id);
      if coalesce(cardinality(candidate_parents),0)<3 then continue; end if;
      select * into q from public.chem_questions where id=binding.anchor_question_id;
      select count(distinct other.parent_source_item_key) into total from public.chem_questions other
      join app_private.chem_question_source_releases r on r.id=other.source_release_id and r.status='active'
      where other.knowledge_id=any(curriculum.knowledge_skill_ids) and other.usable_for_review
        and other.review_status='approved' and other.render_mode='native'
        and other.parent_source_item_key<>q.parent_source_item_key
        and not(other.parent_source_item_key=any(candidate_parents))
        and not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=other.id);
      if total>=7 then chosen:=true; exit; end if;
    end loop;
    exit when chosen;
  end loop;
  if not chosen then raise exception 'active oxygen inventory lacks an audited test route with three reserves and eight independent initial parents'; end if;
  first_anchor:=binding.anchor_question_id;
  original_curriculum:=curriculum.id;
  insert into public.chem_junior_curriculum_days(id,textbook_version,day_number,unit_id,unit_title,title,knowledge_skill_ids,knowledge_summaries,estimated_minutes,release_status,repetition_policy)
    values('QA-SPACED-'||sid::text,'科粤版',(select max(day_number)+1 from public.chem_junior_curriculum_days),curriculum.unit_id,curriculum.unit_title,'间隔复习事务测试',curriculum.knowledge_skill_ids,curriculum.knowledge_summaries,30,'ready','spaced_review') returning * into curriculum;

  insert into public.chem_students_v2(id,display_name,grade_band,textbook_version,metadata)
    values(sid,'QA-junior-spaced-rpc-rollback','初三','科粤版','{"qaTransactionOnly":true}'::jsonb);
  insert into public.chem_learning_plans(id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,question_count,round_limit,delivery_mode,junior_curriculum_day_id)
    values(pid,sid,future_date,'REVIEW','QA source RPC roundtrip',curriculum.knowledge_skill_ids,30,'course',8,4,'junior_adaptive',curriculum.id);
  insert into public.chem_junior_daily_sessions(id,student_id,plan_day_id,curriculum_day_id,study_date,textbook_version,knowledge_skill_ids,initial_question_target,hard_question_cap,recovery_round_limit,status)
    values(sessid,sid,pid,curriculum.id,future_date,'科粤版',curriculum.knowledge_skill_ids,8,30,3,'active');


  if (select repetition_policy from public.chem_junior_daily_sessions where id=sessid)<>'spaced_review' then raise exception 'session did not freeze opted-in repetition policy'; end if;
  if app_private.chem_junior_plan_date_allowed(pid,sid) then raise exception 'future plan opened without explicit authorization'; end if;
  update public.chem_students_v2 set metadata=metadata||jsonb_build_object('reviewProgram',jsonb_build_object(
    'participating',true,'allowAdvanceStudy',true,'startDate',future_date-2,'endDate',future_date)) where id=sid;
  if not app_private.chem_junior_plan_date_allowed(pid,sid) then raise exception 'authorized ready future plan remains closed'; end if;
  update public.chem_students_v2 set metadata=jsonb_set(metadata,'{reviewProgram,endDate}',to_jsonb((future_date-1)::text)) where id=sid;
  if app_private.chem_junior_plan_date_allowed(pid,sid) then raise exception 'future plan outside enrolled range opened'; end if;
  update public.chem_students_v2 set metadata=jsonb_set(metadata,'{reviewProgram,endDate}',to_jsonb(future_date::text)) where id=sid;
  insert into public.chem_learning_plans(id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,question_count,round_limit,delivery_mode,junior_curriculum_day_id)
    values(old_pid,sid,(now() at time zone 'Asia/Shanghai')::date-4,'REVIEW','QA old learning evidence',curriculum.knowledge_skill_ids,30,'course',12,1,'junior_adaptive',original_curriculum);
  insert into public.chem_junior_daily_sessions(id,student_id,plan_day_id,curriculum_day_id,study_date,textbook_version,knowledge_skill_ids,initial_question_target,hard_question_cap,recovery_round_limit,status)
    values(old_session,sid,old_pid,original_curriculum,(now() at time zone 'Asia/Shanghai')::date-4,'科粤版',curriculum.knowledge_skill_ids,12,15,0,'abandoned');
  -- Historical timestamps are seeded only for this rollback QA learner. The
  -- new question deliveries and answers below use the actual gated RPCs.
  perform set_config('app.chem_junior_step_issue','on',true);
  for i in 1..2 loop
    select * into q from public.chem_questions where id=case when i=1 then first_anchor else binding.candidates->0->>'questionId' end;
    snap:=jsonb_build_object('questionId',q.id,'motherId',q.mother_id,'skillId',q.skill_id,'knowledgeId',q.knowledge_id,
      'level',q.level,'stem',q.stem,'options',q.options,'correctOption',q.correct_option,'explanation',q.explanation,
      'sourceReleaseId',q.source_release_id,'sameTypeKey',q.same_type_key,'sourceItemKey',q.source_item_key,
      'parentSourceItemKey',q.parent_source_item_key,'contentFingerprint',q.content_fingerprint,'revisionToken',q.question_revision_token,
      'renderMode',q.render_mode,'routeKind','new_learning','routeReason','QA prior real-source identity');
    insert into public.chem_junior_session_steps(session_id,sequence,question_id,mother_id,skill_id,knowledge_id,same_type_key,source_item_key,parent_source_item_key,content_fingerprint,level,route_kind,route_reason,question_snapshot,practice_round,selected_option,uncertain,duration_sec,correct,answered_at,created_at)
    values(old_session,i,q.id,q.mother_id,q.skill_id,q.knowledge_id,q.same_type_key,q.source_item_key,q.parent_source_item_key,q.content_fingerprint,q.level,
      'new_learning','QA prior real-source identity',snap,0,q.correct_option,false,10,true,now()-interval '4 days',now()-interval '4 days');
  end loop;
  perform set_config('app.chem_junior_step_issue','off',true);
  state:=public.chem_junior_practice_availability(sid,pid,sessid);
  if state->'questions'->first_anchor->>'kind'<>'due_review' then raise exception 'genuine prior identity did not become due'; end if;
  if (select count(*) from app_private.chem_junior_daily_budget_keys(sid))<>0 then raise exception 'old evidence consumed today budget'; end if;
  rejected:=false;
  begin update public.chem_junior_daily_sessions set repetition_policy='fresh_only' where id=sessid;
  exception when raise_exception then rejected:=true; end;
  if not rejected then raise exception 'started session repetition policy was mutable'; end if;

  for i in 1..11 loop
    if i=1 then
      select * into q from public.chem_questions where id=first_anchor;
    elsif i<=8 then
      select other.* into q from public.chem_questions other
      join app_private.chem_question_source_releases r on r.id=other.source_release_id and r.status='active'
      where other.knowledge_id=any(curriculum.knowledge_skill_ids) and other.usable_for_review
        and other.review_status='approved' and other.render_mode='native'
        and not(other.parent_source_item_key=any(candidate_parents))
        and not exists(select 1 from public.chem_junior_session_steps used where used.session_id=sessid
          and (used.question_id=other.id or used.mother_id=other.mother_id or used.source_item_key=other.source_item_key
            or used.parent_source_item_key=other.parent_source_item_key or used.content_fingerprint=other.content_fingerprint))
        and not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=other.id)
      order by other.id limit 1;
      if not found then raise exception 'test exhausted independent initial questions at %',i; end if;
    else
      state:=public.chem_junior_option_state(sid,sessid);
      select value into branch from jsonb_array_elements(state->'branches') with ordinality t(value,n)
        where value->>'status'='practicing' order by n limit 1;
      if branch is null or (branch->>'recoveryRound')::integer<>1
        or branch->>'anchorStepId'<>first_step::text then raise exception 'wrong option did not enter its real first recovery queue: %',state; end if;
      select * into q from public.chem_questions where id=branch->>'nextQuestionId';
      if not found then raise exception 'frozen recovery source question missing'; end if;
    end if;
    route_kind:=case when i=1 then 'spaced_review' when i<=8 then 'new_learning' else 'foundation_repair' end;
    if i=9 then
      -- A submitted answer in another entry may consume a frozen reserve.
      -- Both states defer it. This nested QA transaction then rolls back.
      begin
        insert into app_private.chem_question_answer_locks(student_id,plan_day_id,attempt_sequence,question_id,selected_option,uncertain,duration_sec,revision_token)
          values(sid,pid,0,q.id,q.correct_option,false,10,q.question_revision_token);
        state:=public.chem_junior_option_state(sid,sessid);
        if not exists(select 1 from jsonb_array_elements(state->'branches') b where b->>'branchId'=branch->>'branchId' and b->>'reason'='review_interval_not_due') then raise exception 'real state reused consumed frozen reserve'; end if;
        state:=public.chem_junior_option_state_readonly(sid,sessid,pid);
        if not exists(select 1 from jsonb_array_elements(state->'branches') b where b->>'branchId'=branch->>'branchId' and b->>'reason'='review_interval_not_due') then raise exception 'preview state reused consumed frozen reserve'; end if;
        raise exception 'rollback simulated concurrent entry' using errcode='P0002';
      exception when no_data_found then null; end;
    end if;
    route_reason:=case when i<=8 then 'QA real-source transaction' else '针对该选项考点的已审核原题补练：'||(branch->>'knowledgePoint') end;
    snap:=jsonb_build_object(
      'questionId',q.id,'motherId',q.mother_id,'skillId',q.skill_id,'knowledgeId',q.knowledge_id,
      'conceptKey',q.concept_key,'level',q.level,'gradeBand',q.grade_band,'textbookVersion',q.textbook_version,
      'stem',q.stem,'options',q.options,'correctOption',q.correct_option,'explanation',q.explanation,
      'scaffold',q.scaffold,'reviewStatus',q.review_status,'scopeStatus',q.scope_status,'sourceKind',q.source_kind,
      'renderMode',q.render_mode,'imageUrl',q.image_url,'assetRefs',q.asset_refs,'sourceReleaseId',q.source_release_id,
      'sourceItemKey',q.source_item_key,'parentSourceItemKey',q.parent_source_item_key,'sameTypeKey',q.same_type_key,
      'contentFingerprint',q.content_fingerprint,'revisionToken',q.question_revision_token,
      'routeKind',route_kind,'routeReason',route_reason);
    if i=1 then
      rejected:=false;
      begin
        perform public.chem_junior_issue_option_step(sid,sessid,null,q.id,1::smallint,'new_learning',route_reason,
          jsonb_set(snap,'{routeKind}','"new_learning"'));
      exception when raise_exception then
        if sqlerrm<>'junior repeat must be explicitly labelled spaced_review' then raise; end if;
        rejected:=true;
      end;
      if not rejected then raise exception 'a repeated source was mislabelled as new'; end if;
    end if;
    -- This calls the strict queue wrapper and, internally, the real source-gated
    -- chem_junior_issue_step. No direct step inserts or guard bypasses are used.
    select * into step_result from public.chem_junior_issue_option_step(sid,sessid,
      case when i<=8 then null::uuid else (branch->>'branchId')::uuid end,
      q.id,i::smallint,route_kind,route_reason,snap);
    if step_result.step_id is null then raise exception 'real issue RPC returned no step'; end if;
    if i=1 then
      first_step:=step_result.step_id;
      rejected:=false;
      begin
        perform public.chem_junior_record_step(sessid,sid,first_step,binding.option_index,false,10,repeat('0',64));
      exception when raise_exception then
        if sqlerrm<>'junior source question revision changed' then raise; end if;
        rejected:=true;
      end;
      if not rejected then raise exception 'wrong revision answered a real source question'; end if;
    end if;
    selected:=case when i=1 then binding.option_index else q.correct_option end;
    select * into answer_result from public.chem_junior_record_step(sessid,sid,step_result.step_id,selected,false,10,q.question_revision_token);
    if answer_result.correct is distinct from (i<>1) then raise exception 'record RPC returned incorrect correctness at %',i; end if;
    if (select practice_round from public.chem_junior_session_steps where id=step_result.step_id)
      <>(case when i<=8 then 0 else 1 end) then raise exception 'actual issue RPC persisted wrong practice_round at %',i; end if;
    state:=public.chem_junior_option_state(sid,sessid);
    if i<8 and not exists(select 1 from jsonb_array_elements(state->'branches') b
      where b->>'anchorStepId'=first_step::text and b->>'reason'='initial_round_in_progress'
        and b->'candidates'='[]'::jsonb) then raise exception 'recovery consumed initial-round source inventory at %',i; end if;
    if i=1 then
      rejected:=false;
      begin perform public.chem_junior_issue_option_step(sid,sessid,null,q.id,2::smallint,'spaced_review',route_reason,snap);
      exception when raise_exception then
        if sqlerrm<>'junior_question_not_due' then raise; end if;
        rejected:=true;
      end;
      if not rejected then raise exception 'same actual-day source repetition was accepted'; end if;
    end if;
    if (state->>'dailyIssuedCount')::integer<>i then raise exception 'issue+answer double-counted the day budget at %',i; end if;
  end loop;

  if not exists(select 1 from jsonb_array_elements(state->'branches') b
    where b->>'anchorStepId'=first_step::text and b->>'status'='consolidated'
      and (b->>'answered')::integer=3 and (b->>'correct')::integer=3)
    then raise exception 'three actual correct recovery answers did not consolidate the audited branch'; end if;
  if (select count(*) from public.chem_junior_session_steps where session_id=sessid and answered_at is not null)<>11
    or (select count(*) from public.chem_junior_session_steps where session_id=sessid and practice_round=0)<>8
    or (select count(*) from public.chem_junior_session_steps where session_id=sessid and practice_round=1)<>3
    then raise exception '8 initial +3 recovery real RPC evidence mismatch'; end if;
  -- A submitted self-study answer lock participates in both identity and day budget.
  select other.* into q from public.chem_questions other
    join app_private.chem_question_source_releases r on r.id=other.source_release_id and r.status='active'
    where other.knowledge_id=any(curriculum.knowledge_skill_ids)
      and not exists(select 1 from public.chem_junior_session_steps used where used.session_id=sessid and used.parent_source_item_key=other.parent_source_item_key)
    order by other.id limit 1;
  insert into app_private.chem_question_answer_locks(student_id,plan_day_id,attempt_sequence,question_id,selected_option,uncertain,duration_sec,revision_token)
    values(sid,pid,0,q.id,q.correct_option,false,10,q.question_revision_token);
  state:=public.chem_junior_practice_availability(sid,pid,sessid);
  if state->'questions'->q.id->>'eligible'<>'false' then raise exception 'other entry answer bypassed actual-day identity exclusion'; end if;
  for i in 13..30 loop perform app_private.chem_junior_reserve_daily_question(sid,'QA-spaced-extra:'||i); end loop;
  rejected:=false;
  begin perform app_private.chem_junior_reserve_daily_question(sid,'QA-spaced-extra:31');
  exception when raise_exception then if sqlerrm<>'junior_daily_question_limit' then raise; end if; rejected:=true; end;
  if not rejected then raise exception 'future plan bypassed all-entry actual-day 30 cap'; end if;
  select jsonb_agg(to_jsonb(b) order by b.id) into before_rows from app_private.chem_junior_option_branches b where b.student_id=sid;
  state:=public.chem_junior_option_state_readonly(sid,sessid,pid);
  if (state->>'dailyIssuedCount')::integer<>30 or not(state->>'dailyBudgetEnabled')::boolean then raise exception 'readonly budget differs after real RPC answers'; end if;
  if before_rows is distinct from (select jsonb_agg(to_jsonb(b) order by b.id) from app_private.chem_junior_option_branches b where b.student_id=sid)
    then raise exception 'readonly RPC mutated actual branch evidence'; end if;
  perform public.chem_junior_finalize_session(sessid,sid);
  if not exists(select 1 from public.chem_junior_daily_sessions where id=sessid and status='completed') then
    raise exception 'authorized future spaced-review session could not finalize';
  end if;
  if (select count(*) from app_private.chem_junior_daily_budget_keys(sid))<>30 then
    raise exception 'finalizing a future review double-counted actual-day answers';
  end if;
end;
$test$;
rollback;
select 'spaced review / future / cross-entry RPC integration passed; all QA writes rolled back' as result,
  count(*) as persisted_qa_students from public.chem_students_v2
  where display_name='QA-junior-spaced-rpc-rollback';
