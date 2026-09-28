-- Transactional acceptance: fixtures are temporary and every write rolls back.
-- Apply the migration first; execute this file as the database owner.
begin;
do $test$
declare
  sid uuid:=gen_random_uuid(); pnew uuid:=gen_random_uuid(); pold uuid:=gen_random_uuid();
  snew uuid:=gen_random_uuid(); sold uuid:=gen_random_uuid();
  c public.chem_junior_curriculum_days%rowtype; c2 public.chem_junior_curriculum_days%rowtype;
  q public.chem_questions%rowtype; stid uuid; anchor0 uuid; anchor1 uuid; anchor2 uuid; anchor3 uuid;
  snap jsonb; state jsonb; before_state jsonb; failed boolean; i integer:=0; used integer;
begin
  select * into c from public.chem_junior_curriculum_days where textbook_version='科粤版' order by day_number limit 1;
  if c.id is null then raise exception 'test requires one seeded curriculum day'; end if;
  insert into public.chem_junior_curriculum_days(id,textbook_version,day_number,unit_id,unit_title,title,knowledge_skill_ids,knowledge_summaries,estimated_minutes,release_status)
    values('TEST-'||sid::text,'科粤版',(select max(day_number)+1 from public.chem_junior_curriculum_days where textbook_version='科粤版'),
      c.unit_id,c.unit_title,'事务测试课程',c.knowledge_skill_ids,c.knowledge_summaries,c.estimated_minutes,'draft') returning * into c2;
  insert into public.chem_students_v2(id,display_name,grade_band,textbook_version)
    values(sid,'事务回滚测试学生','初三','科粤版');
  insert into public.chem_learning_plans(id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,question_count,round_limit,delivery_mode,junior_curriculum_day_id)
    values(pnew,sid,(now() at time zone 'Asia/Shanghai')::date,'REVIEW','new8',c.knowledge_skill_ids,30,'course',8,4,'junior_adaptive',c.id),
          (pold,sid,(now() at time zone 'Asia/Shanghai')::date-1,'REVIEW','legacy12',c2.knowledge_skill_ids,30,'course',12,1,'junior_adaptive',c2.id);
  insert into public.chem_junior_daily_sessions(id,student_id,plan_day_id,curriculum_day_id,study_date,textbook_version,knowledge_skill_ids,initial_question_target,hard_question_cap,recovery_round_limit,status)
    values(snew,sid,pnew,c.id,(now() at time zone 'Asia/Shanghai')::date,'科粤版',c.knowledge_skill_ids,8,30,3,'active'),
          (sold,sid,pold,c2.id,(now() at time zone 'Asia/Shanghai')::date-1,'科粤版',c2.knowledge_skill_ids,12,15,0,'abandoned');
  failed:=false;
  begin
    update public.chem_junior_daily_sessions set initial_question_target=9 where id=snew;
  exception when check_violation then failed:=true;
  end;
  if not failed then raise exception 'invalid mixed policy was accepted'; end if;
  if not exists(select 1 from public.chem_junior_daily_sessions where id=sold and initial_question_target=12 and hard_question_cap=15 and recovery_round_limit=0) then
    raise exception 'legacy session contract changed';
  end if;

  -- Synthetic answer evidence uses existing FK identities, without editing any
  -- source question/card or pretending to exercise the audited source gate.
  perform set_config('app.chem_junior_step_issue','on',true);
  for q in select * from public.chem_questions where grade_band='初三' and source_kind='user_provided_local' order by id limit 12 loop
    i:=i+1; stid:=gen_random_uuid();
    snap:=jsonb_build_object('questionId',q.id,'motherId',q.mother_id,'skillId',q.skill_id,'knowledgeId',q.knowledge_id,
      'level',q.level,'stem',q.stem,'options',q.options,'correctOption',q.correct_option,'explanation',q.explanation,
      'sourceReleaseId',q.source_release_id,'sameTypeKey',q.same_type_key,'sourceItemKey',q.source_item_key,
      'parentSourceItemKey',q.parent_source_item_key,'contentFingerprint',q.content_fingerprint,'revisionToken',q.question_revision_token,
      'renderMode',q.render_mode,'routeKind','new_learning','routeReason','transaction test');
    insert into public.chem_junior_session_steps(id,session_id,sequence,question_id,mother_id,skill_id,knowledge_id,same_type_key,source_item_key,parent_source_item_key,content_fingerprint,level,route_kind,route_reason,question_snapshot,practice_round,selected_option,uncertain,duration_sec,correct,answered_at,created_at)
      values(stid,case when i=12 then sold else snew end,case when i=12 then 1 else i end,q.id,q.mother_id,q.skill_id,q.knowledge_id,q.same_type_key,q.source_item_key,q.parent_source_item_key,q.content_fingerprint,q.level,
        'new_learning','transaction test',snap,case when i between 9 and 11 then i-8 else 0 end,
        case when i=12 then null else 0 end,case when i=12 then null else i=10 end,
        case when i=12 then null else 1 end,case when i=12 then null else i between 2 and 8 end,
        case when i=12 then null else now() end,case when i=12 then now()-interval '2 days' else now() end);
    if i=1 then anchor0:=stid; elsif i=9 then anchor1:=stid; elsif i=10 then anchor2:=stid; elsif i=11 then anchor3:=stid; end if;
    if i=7 then
      state:=public.chem_junior_option_state(sid,snew);
      if not exists(select 1 from app_private.chem_junior_option_branches where anchor_step_id=anchor0
        and candidates='[]'::jsonb and status='pending' and reason='initial_round_in_progress') then
        raise exception 'reserves must not consume the unfinished first-eight inventory';
      end if;
    end if;
  end loop;
  perform set_config('app.chem_junior_step_issue','off',true);
  if i<>12 then raise exception 'test requires 12 junior source identities'; end if;
  select count(*) into used from app_private.chem_junior_daily_budget_keys(sid);
  if used<>11 then raise exception 'previous-day unviewed question must not consume today budget: %',used; end if;

  state:=public.chem_junior_option_state_readonly(sid,snew);
  if jsonb_array_length(state->'unbranchedAnchors')<>2 then
    raise exception 'preview expected exactly two unbranched eligible child wrong/uncertain anchors: %',state;
  end if;
  if (select count(*) from app_private.chem_junior_option_branches where student_id=sid)<>1 then raise exception 'read-only preview wrote child branches'; end if;
  state:=public.chem_junior_option_state(sid,snew);
  if not exists(select 1 from app_private.chem_junior_option_branches where anchor_step_id=anchor0 and recovery_round=1)
    or not exists(select 1 from app_private.chem_junior_option_branches where anchor_step_id=anchor1 and recovery_round=2)
    or not exists(select 1 from app_private.chem_junior_option_branches where anchor_step_id=anchor2 and recovery_round=3)
    or exists(select 1 from app_private.chem_junior_option_branches where anchor_step_id=anchor3)
  then raise exception 'three recovery rounds were not derived correctly'; end if;
  select jsonb_agg(to_jsonb(b) order by b.id) into before_state from app_private.chem_junior_option_branches b where student_id=sid;
  perform public.chem_junior_option_state_readonly(sid,snew);
  if before_state is distinct from (select jsonb_agg(to_jsonb(b) order by b.id) from app_private.chem_junior_option_branches b where student_id=sid) then
    raise exception 'preview mutated stored branch status/timestamps';
  end if;

  failed:=false;
  begin
    perform set_config('app.chem_junior_step_answer','on',true);
    update public.chem_junior_session_steps set practice_round=2 where id=anchor1;
  exception when raise_exception then failed:=true;
  end;
  perform set_config('app.chem_junior_step_answer','off',true);
  if not failed then raise exception 'issued recovery round must be immutable'; end if;

  for i in 12..30 loop
    perform app_private.chem_junior_reserve_daily_question(sid,'transaction-budget:'||i::text);
  end loop;
  select count(*) into used from app_private.chem_junior_daily_budget_keys(sid);
  if used<>30 then raise exception 'budget did not reach exactly30: %',used; end if;
  perform app_private.chem_junior_reserve_daily_question(sid,'transaction-budget:30');
  if (select count(*) from app_private.chem_junior_daily_budget_keys(sid))<>30 then raise exception 'idempotent retry consumed budget twice'; end if;
  failed:=false;
  begin perform app_private.chem_junior_reserve_daily_question(sid,'transaction-budget:31');
  exception when raise_exception then
    if sqlerrm<>'junior_daily_question_limit' then raise; end if;
    failed:=true;
  end;
  if not failed then raise exception '31st question bypassed cross-session budget'; end if;
  failed:=false;
  begin
    insert into app_private.chem_question_answer_locks(student_id,plan_day_id,attempt_sequence,question_id,selected_option,uncertain,duration_sec,revision_token)
      values(sid,pnew,0,q.id,0,false,1,q.question_revision_token);
  exception when raise_exception then
    if sqlerrm<>'junior_daily_question_limit' then raise; end if;
    failed:=true;
  end;
  if not failed then raise exception 'ordinary/self-study path bypassed junior budget'; end if;
  state:=public.chem_junior_option_state_readonly(sid,snew);
  if (state->>'dailyIssuedCount')::integer<>30 then raise exception 'preview daily budget count differs'; end if;
  state:=public.chem_junior_option_state_readonly(sid,null,pnew);
  if (state->>'dailyIssuedCount')::integer<>30 or not (state->>'dailyBudgetEnabled')::boolean then
    raise exception 'unstarted-plan preview missed shared daily budget';
  end if;
  if (select count(*) from public.chem_junior_daily_sessions where student_id=sid)<>2 then
    raise exception 'unstarted-plan preview created a session';
  end if;
  state:=public.chem_junior_option_state_readonly(sid,sold);
  if not (state->>'dailyBudgetEnabled')::boolean or (state->>'dailyIssuedCount')::integer<>30 then
    raise exception 'legacy session ignored the enrolled students shared daily budget';
  end if;

  if has_function_privilege('anon','public.chem_junior_option_state_readonly(uuid,uuid,uuid)','execute')
    or has_function_privilege('authenticated','app_private.chem_junior_reserve_daily_question(uuid,text)','execute') then
    raise exception 'private budget or preview is publicly executable';
  end if;
end;
$test$;
rollback;
