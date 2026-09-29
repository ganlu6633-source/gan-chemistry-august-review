-- Run after the oxygen source release, cards, provenance and precise option
-- bindings are active. This is an integration test of real issue/answer RPCs.
-- Only a new QA learner receives test answers; every write is rolled back.
begin;
create temp table perf_fast_answer(stage text,sequence integer,elapsed_ms numeric) on commit drop;
do $test$
declare
  sid uuid:=gen_random_uuid(); pid uuid:=gen_random_uuid(); sessid uuid:=gen_random_uuid();
  curriculum public.chem_junior_curriculum_days%rowtype;
  binding app_private.chem_option_practice_bindings%rowtype;
  q public.chem_questions%rowtype;
  step_result record; answer_result record;
  snap jsonb; state jsonb; branch jsonb; before_rows jsonb;
 ack jsonb; retry jsonb; context jsonb; bad_metadata jsonb; original_metadata jsonb; locked_before jsonb; started timestamptz;
  first_anchor text; first_step uuid; selected smallint;
  route_kind text; route_reason text; chosen boolean:=false; rejected boolean;
  i integer; candidate_parents text[]; total integer;
begin
  -- Use a real, reviewed cross-group binding. A temporary course contains the
  -- anchor group plus two introductory groups, deliberately excluding its reserve group.
  select * into curriculum from public.chem_junior_curriculum_days
    where textbook_version='科粤版' and release_status='ready' order by day_number limit 1;
  for binding in select b.* from app_private.chem_option_practice_bindings b
    join public.chem_questions a on a.id=b.anchor_question_id
    join app_private.chem_question_source_releases r on r.id=a.source_release_id and r.status='active'
    join public.chem_questions first_q on first_q.id=b.candidates->0->>'questionId'
    where a.knowledge_id='J_KY_OXY_H2O2' and first_q.knowledge_id='J_KY_OXY_KMNO4'
      and b.review_status='verified' and b.anchor_revision_token=a.question_revision_token
      and b.option_index<>a.correct_option and not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=a.id)
    order by b.anchor_question_id,b.option_index
  loop
    select array_agg(distinct cq.parent_source_item_key) into candidate_parents
    from jsonb_array_elements(binding.candidates) c join public.chem_questions cq
      on cq.id=c->>'questionId' and cq.question_revision_token=c->>'revisionToken'
    join app_private.chem_question_source_releases r on r.id=cq.source_release_id and r.status='active'
    where cq.review_status='approved' and cq.usable_for_review
      and not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=cq.id);
    if cardinality(candidate_parents)>=3 then chosen:=true;exit;end if;
  end loop;
  if not chosen then raise exception 'QA needs a real active H2O2 wrong-option route with KMnO4 reserves'; end if;
  curriculum:=jsonb_populate_record(curriculum,jsonb_build_object(
    'id','QA-CROSS-SKILL-'||gen_random_uuid(),'day_number',(select max(day_number)+1 from public.chem_junior_curriculum_days),
    'knowledge_skill_ids',array['J_KY_OXY_H2O2','J_KY_1_1_K01','J_KY_1_1_K02'],'repetition_policy','spaced_review'));
  insert into public.chem_junior_curriculum_days select curriculum.*;
  first_anchor:=binding.anchor_question_id;

  insert into public.chem_students_v2(id,display_name,grade_band,textbook_version,metadata)
    values(sid,'QA-junior-cross-skill-rollback','初三','科粤版','{"qaTransactionOnly":true}'::jsonb);
  insert into public.chem_learning_plans(id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,question_count,round_limit,delivery_mode,junior_curriculum_day_id)
    values(pid,sid,(now() at time zone 'Asia/Shanghai')::date,'REVIEW','QA source RPC roundtrip',curriculum.knowledge_skill_ids,30,'course',8,4,'junior_adaptive',curriculum.id);
  insert into public.chem_junior_daily_sessions(id,student_id,plan_day_id,curriculum_day_id,study_date,textbook_version,knowledge_skill_ids,initial_question_target,hard_question_cap,recovery_round_limit,status)
    values(sessid,sid,pid,curriculum.id,(now() at time zone 'Asia/Shanghai')::date,'科粤版',curriculum.knowledge_skill_ids,8,30,3,'active');


  if not exists(select 1 from public.chem_junior_practice_pool(sid,pid,sessid) pool_q
      where pool_q.id=binding.candidates->0->>'questionId')
    or public.chem_junior_practice_availability(sid,pid,sessid)->'questions'->(binding.candidates->0->>'questionId') is null
  then raise exception 'exact cross-skill reserve is missing from pool or review-interval availability'; end if;
  if app_private.chem_junior_frozen_recovery_allows(sid,sessid,binding.candidates->0->>'questionId',
      binding.candidates->0->>'revisionToken')
  then raise exception 'unanswered anchor authorized cross-skill practice'; end if;
  for i in 1..11 loop
    if i=1 then
      select * into q from public.chem_questions where id=first_anchor;
    elsif i<=8 then
      select other.* into q from public.chem_questions other
      join app_private.chem_question_source_releases r on r.id=other.source_release_id and r.status='active'
      where other.knowledge_id=any(curriculum.knowledge_skill_ids) and other.usable_for_review
        and other.review_status='approved' and other.render_mode='native' and other.level=1
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
      if i=9 and q.knowledge_id=any(curriculum.knowledge_skill_ids) then raise exception 'fixture did not exercise cross-skill issue'; end if;
      if not exists(select 1 from jsonb_array_elements(public.chem_junior_option_state_readonly(sid,sessid,pid)->'branches') b
        where b->>'branchId'=branch->>'branchId' and b->>'status'=branch->>'status'
          and b->>'nextQuestionId'=branch->>'nextQuestionId')
      then raise exception 'student/teacher cross-skill next route disagrees'; end if;
      if app_private.chem_junior_frozen_recovery_allows(sid,sessid,q.id,repeat('0',64))
        or app_private.chem_junior_frozen_recovery_allows(sid,sessid,first_anchor,q.question_revision_token)
        or app_private.chem_junior_frozen_recovery_allows(sid,sessid,q.id,q.question_revision_token,null,2::smallint)
      then raise exception 'wrong revision, unbound source or wrong round authorized before issue'; end if;
    end if;
    route_kind:=case when i<=8 then 'new_learning' else 'foundation_repair' end;
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
    if i=9 then
      rejected:=false;
      begin
        perform public.chem_junior_issue_option_step(sid,sessid,(branch->>'branchId')::uuid,
          q.id,i::smallint,route_kind,route_reason,jsonb_set(snap,'{revisionToken}',to_jsonb(repeat('0',64))));
      exception when raise_exception then
        if sqlerrm<>'junior option issue is not the next frozen reserve' then raise; end if; rejected:=true;
      end;
      if not rejected then raise exception 'issue wrapper accepted a stale cross-group revision'; end if;
      rejected:=false;
      begin
        update app_private.chem_junior_option_branches set binding_snapshot=jsonb_set(binding_snapshot,'{review_status}','"pending"'::jsonb)
          where id=(branch->>'branchId')::uuid;
      exception when raise_exception then
        if sqlerrm<>'junior first-option identity and reserved versions are immutable' then raise; end if; rejected:=true;
      end;
      if not rejected then raise exception 'frozen binding audit changed'; end if;
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

    if i>8 then
      perform public.chem_junior_validate_issued_step(sessid,sid,step_result.step_id);
      if not app_private.chem_junior_frozen_recovery_allows(sid,sessid,q.id,q.question_revision_token,step_result.step_id,1::smallint)
        or app_private.chem_junior_frozen_recovery_allows(sid,sessid,q.id,repeat('0',64),step_result.step_id,1::smallint)
        or app_private.chem_junior_frozen_recovery_allows(gen_random_uuid(),sessid,q.id,q.question_revision_token,step_result.step_id,1::smallint)
        or app_private.chem_junior_frozen_recovery_allows(sid,sessid,q.id,q.question_revision_token,step_result.step_id,2::smallint)
        or app_private.chem_junior_frozen_recovery_allows(sid,sessid,first_anchor,q.question_revision_token,step_result.step_id,1::smallint)
      then raise exception 'frozen branch revision/ownership/round/exact-question gate failed'; end if;
    end if;
    selected:=case when i=1 then binding.option_index else q.correct_option end;

    if i=1 then
      select metadata into original_metadata from public.chem_students_v2 where id=sid;
      update public.chem_learning_plans set is_scheduled=true where id=pid;
      for bad_metadata in select value from jsonb_array_elements(jsonb_build_array(
        '{"demo":true}'::jsonb, '{"demo":"true"}'::jsonb,
        '{"reviewProgram":{"participating":false,"startDate":"2020-01-01","endDate":"2099-12-31"}}'::jsonb,
        '{"reviewProgram":{"participating":true,"startDate":"2099-01-01","endDate":"2099-12-31"}}'::jsonb,
        '{"reviewProgram":{"participating":true,"startDate":"2020-01-01","endDate":"2099-12-31","juniorUnitIds":[]}}'::jsonb,
        '{"reviewProgram":{"participating":true,"startDate":"2020-01-01","endDate":"2099-12-31","juniorUnitIds":["wrong"]}}'::jsonb,
        '{"reviewProgram":{"participating":true,"startDate":"invalid","endDate":"2099-12-31"}}'::jsonb
      )) loop
        update public.chem_students_v2 set metadata=bad_metadata where id=sid;
        rejected:=false;
        begin perform public.chem_junior_submit_answer(sid,pid,step_result.step_id,selected,false,10,q.question_revision_token);
        exception when raise_exception then if sqlerrm<>'junior_answer_unavailable' then raise;end if;rejected:=true;end;
        if not rejected then raise exception 'fast answer allowed an excluded/demo programme: %',bad_metadata;end if;
      end loop;
      update public.chem_students_v2 set metadata=jsonb_build_object('reviewProgram',
        jsonb_build_object('participating',true,'startDate','2020-01-01','endDate','2099-12-31','juniorUnitIds',jsonb_build_array(curriculum.unit_id)))
        where id=sid;
      update public.chem_learning_plans set is_scheduled=false where id=pid;
      rejected:=false;
      begin perform public.chem_junior_submit_answer(sid,pid,step_result.step_id,selected,false,10,q.question_revision_token);
      exception when raise_exception then if sqlerrm<>'junior_answer_unavailable' then raise;end if;rejected:=true;end;
      if not rejected then raise exception 'unscheduled programme answer accepted';end if;
      update public.chem_learning_plans set is_scheduled=true where id=pid;
      update public.chem_students_v2 set metadata=original_metadata where id=sid;
      rejected:=false;
      begin perform public.chem_junior_submit_answer(gen_random_uuid(),pid,step_result.step_id,selected,false,10,q.question_revision_token);
      exception when raise_exception then if sqlerrm<>'junior_answer_unavailable' then raise;end if;rejected:=true;end;
      if not rejected then raise exception 'cross-student answer accepted';end if;
      rejected:=false;
      begin perform public.chem_junior_submit_answer(sid,gen_random_uuid(),step_result.step_id,selected,false,10,q.question_revision_token);
      exception when raise_exception then if sqlerrm<>'junior_answer_unavailable' then raise;end if;rejected:=true;end;
      if not rejected then raise exception 'cross-plan answer accepted';end if;
    end if;
    started:=clock_timestamp();
    ack:=public.chem_junior_submit_answer(sid,pid,step_result.step_id,selected,false,10,q.question_revision_token);
    insert into perf_fast_answer values('submit',i,extract(epoch from clock_timestamp()-started)*1000);
    if (ack->>'correct')::boolean is distinct from (i<>1) or ack->'replayed'<>'false'::jsonb
      or ack->'questionSnapshot' is distinct from snap
      or ack->>'stepId'<>step_result.step_id::text or (ack->>'durationSec')::integer<>10
    then raise exception 'atomic answer feedback mismatches locked source at %',i;end if;
    select to_jsonb(st) into locked_before from public.chem_junior_session_steps st where id=step_result.step_id;
    started:=clock_timestamp();
    retry:=public.chem_junior_submit_answer(sid,pid,step_result.step_id,selected,false,200,q.question_revision_token);
    insert into perf_fast_answer values('exact_replay',i,extract(epoch from clock_timestamp()-started)*1000);
    if retry is distinct from jsonb_set(ack,'{replayed}','true') then raise exception 'replay changed confirmed answer';end if;
    if locked_before is distinct from (select to_jsonb(st) from public.chem_junior_session_steps st where id=step_result.step_id)
      then raise exception 'replay modified answer record';end if;
    rejected:=false;
    begin perform public.chem_junior_submit_answer(sid,pid,step_result.step_id,((selected+1)%4)::smallint,false,10,q.question_revision_token);
    exception when raise_exception then if sqlerrm<>'junior_answer_locked' then raise;end if;rejected:=true;end;
    if not rejected then raise exception 'replay changed selected option';end if;
    rejected:=false;
    begin perform public.chem_junior_submit_answer(sid,pid,step_result.step_id,selected,true,10,q.question_revision_token);
    exception when raise_exception then if sqlerrm<>'junior_answer_locked' then raise;end if;rejected:=true;end;
    if not rejected then raise exception 'replay changed certainty';end if;
    rejected:=false;
    begin perform public.chem_junior_submit_answer(sid,pid,step_result.step_id,selected,false,10,repeat('0',64));
    exception when raise_exception then if sqlerrm<>'junior_answer_changed' then raise;end if;rejected:=true;end;
    if not rejected then raise exception 'replay accepted stale revision';end if;
    if i in (1,8,11) then
      started:=clock_timestamp();
      context:=public.chem_junior_practice_context(sid,pid,sessid);
      insert into perf_fast_answer values('practice_context',i,extract(epoch from clock_timestamp()-started)*1000);
      if context->'questions' is distinct from (select jsonb_agg(to_jsonb(pq) order by pq.id) from public.chem_junior_practice_pool(sid,pid,sessid) pq)
        or context->'availability' is distinct from public.chem_junior_practice_availability(sid,pid,sessid)
        or public.chem_junior_practice_context(sid,pid,null) is distinct from context
      then raise exception 'combined context differs from exact pool/availability';end if;
    end if;
    if (select practice_round from public.chem_junior_session_steps where id=step_result.step_id)
      <>(case when i<=8 then 0 else 1 end) then raise exception 'actual issue RPC persisted wrong practice_round at %',i; end if;
    state:=public.chem_junior_option_state(sid,sessid);
    if i<8 and not exists(select 1 from jsonb_array_elements(state->'branches') b
      where b->>'anchorStepId'=first_step::text and b->>'reason'='initial_round_in_progress'
        and b->'candidates'='[]'::jsonb) then raise exception 'recovery consumed initial-round source inventory at %',i; end if;
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
  select jsonb_agg(to_jsonb(b) order by b.id) into before_rows from app_private.chem_junior_option_branches b where b.student_id=sid;
  state:=public.chem_junior_option_state_readonly(sid,sessid,pid);
  if (state->>'dailyIssuedCount')::integer<>11 or not(state->>'dailyBudgetEnabled')::boolean then raise exception 'readonly budget differs after real RPC answers'; end if;
  if before_rows is distinct from (select jsonb_agg(to_jsonb(b) order by b.id) from app_private.chem_junior_option_branches b where b.student_id=sid)
    then raise exception 'readonly RPC mutated actual branch evidence'; end if;

  -- Replays remain immutable when a source is subsequently withheld or the
  -- execution session finishes; new unanswered questions still use full gates.
  insert into app_private.chem_question_delivery_holds(anchor_question_id,reason)
    values(q.id,'QA transaction-only hold after confirmed answer');
  if app_private.chem_junior_question_delivery_ready(q.id) then raise exception 'held source passed targeted ready gate';end if;
  update public.chem_junior_daily_sessions set status='completed',completed_at=now() where id=sessid;
  retry:=public.chem_junior_submit_answer(sid,pid,step_result.step_id,selected,false,400,q.question_revision_token);
  if retry is distinct from jsonb_set(ack,'{replayed}','true') then raise exception 'post-hold completed-session retry lost immutable feedback';end if;
  -- Programme window checks the assigned lesson date. Catch-up/replay after
  -- its window has ended must remain available when the owned lesson is in it.
  update public.chem_learning_plans set plan_date=(now() at time zone 'Asia/Shanghai')::date-1 where id=pid;
  update public.chem_students_v2 set metadata=jsonb_build_object('reviewProgram',jsonb_build_object(
    'participating',true,'startDate',((now() at time zone 'Asia/Shanghai')::date-2)::text,
    'endDate',((now() at time zone 'Asia/Shanghai')::date-1)::text,'juniorUnitIds',jsonb_build_array(curriculum.unit_id))) where id=sid;
  retry:=public.chem_junior_submit_answer(sid,pid,step_result.step_id,selected,false,400,q.question_revision_token);
  if retry is distinct from jsonb_set(ack,'{replayed}','true') then raise exception 'past programme incorrectly blocked owned catch-up feedback';end if;

end;
$test$;
select stage,count(*) as calls,round(avg(elapsed_ms),2) as avg_ms,round(max(elapsed_ms),2) as max_ms from perf_fast_answer group by stage;
rollback;
select 'exact cross-skill frozen recovery, real issue/resume/answer, read-only parity, date/budget gates passed; all QA rolled back' as result,
  count(*) as persisted_qa_students from public.chem_students_v2
  where display_name='QA-junior-cross-skill-rollback';
