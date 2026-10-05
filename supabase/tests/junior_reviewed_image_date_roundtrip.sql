-- Apply the candidate migration inside this transaction before running this test.
-- Real reviewed Anhui source questions and ordinary native questions are used.
-- The only learner/plan/session created is temporary QA data; ROLLBACK is required.
create temp table junior_image_roundtrip_checks(check_name text,details jsonb) on commit drop;
do $test$
declare
 sid uuid:=gen_random_uuid(); other_sid uuid:=gen_random_uuid(); pid uuid:=gen_random_uuid(); sessid uuid:=gen_random_uuid();
 c public.chem_junior_curriculum_days%rowtype; q public.chem_questions%rowtype;
 issued record; first_step uuid; first_q public.chem_questions%rowtype; snap jsonb; ack jsonb; replay jsonb;
 image_path text; analysis_path text; rejected boolean; i integer; source_before integer;
begin
 select * into c from public.chem_junior_curriculum_days where textbook_version='科粤版' and release_status='ready' order by day_number limit 1;
 c:=jsonb_populate_record(c,jsonb_build_object('id','QA-IMAGE-DATE-'||gen_random_uuid(),
  'day_number',(select max(day_number)+1 from public.chem_junior_curriculum_days),
  'knowledge_skill_ids',array['J_KY_CHANGE_PROPERTY','J_KY_ELEMENTS','J_KY_FORMULA'],'repetition_policy','spaced_review'));
 insert into public.chem_junior_curriculum_days select c.*;
 insert into public.chem_students_v2(id,display_name,grade_band,textbook_version,record_status,metadata)
 values(sid,'QA-reviewed-junior-image-rollback','初三','科粤版','active','{"qaTransactionOnly":true}'::jsonb);
 insert into public.chem_learning_plans(id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,question_count,round_limit,delivery_mode,junior_curriculum_day_id)
 values(pid,sid,(now() at time zone 'Asia/Shanghai')::date,'REVIEW','QA mixed real-source date session',c.knowledge_skill_ids,30,'course',8,4,'junior_adaptive',c.id);
 insert into public.chem_junior_daily_sessions(id,student_id,plan_day_id,curriculum_day_id,study_date,textbook_version,knowledge_skill_ids,initial_question_target,hard_question_cap,recovery_round_limit,status)
 values(sessid,sid,pid,c.id,(now() at time zone 'Asia/Shanghai')::date,'科粤版',c.knowledge_skill_ids,8,30,3,'active');
 if not exists(select 1 from public.chem_junior_practice_pool(sid,pid,sessid) where id='JLOCAL-20261002-ANHUI2018-Q01')
 then raise exception 'reviewed original image missing from real date pool'; end if;
 if exists(select 1 from public.chem_junior_practice_pool(other_sid,pid,null)) then raise exception 'foreign plan leaked'; end if;
exception when raise_exception then
 if sqlerrm<>'junior practice pool plan unavailable' then raise; end if;
 -- The foreign ownership check is an independent subtransaction; create the
 -- working fixture below after that expected rejection rolled it back.
end;
$test$;

do $test$
declare
 sid uuid:=gen_random_uuid(); other_sid uuid:=gen_random_uuid(); pid uuid:=gen_random_uuid(); sessid uuid:=gen_random_uuid();
 c public.chem_junior_curriculum_days%rowtype; q public.chem_questions%rowtype;
 issued record; first_step uuid; first_q public.chem_questions%rowtype; snap jsonb; ack jsonb; replay jsonb;
 image_path text; analysis_path text; rejected boolean; i integer; finalized jsonb;
begin
 select * into c from public.chem_junior_curriculum_days where textbook_version='科粤版' and release_status='ready' order by day_number limit 1;
 c:=jsonb_populate_record(c,jsonb_build_object('id','QA-IMAGE-DATE-'||gen_random_uuid(),
  'day_number',(select max(day_number)+1 from public.chem_junior_curriculum_days),
  'knowledge_skill_ids',array['J_KY_CHANGE_PROPERTY','J_KY_ELEMENTS','J_KY_FORMULA'],'repetition_policy','spaced_review'));
 insert into public.chem_junior_curriculum_days select c.*;
 insert into public.chem_students_v2(id,display_name,grade_band,textbook_version,record_status,metadata)
 values(sid,'QA-reviewed-junior-image-rollback','初三','科粤版','active','{"qaTransactionOnly":true}'::jsonb);
 insert into public.chem_learning_plans(id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,question_count,round_limit,delivery_mode,junior_curriculum_day_id)
 values(pid,sid,(now() at time zone 'Asia/Shanghai')::date,'REVIEW','QA mixed real-source date session',c.knowledge_skill_ids,30,'course',8,4,'junior_adaptive',c.id);
 insert into public.chem_junior_daily_sessions(id,student_id,plan_day_id,curriculum_day_id,study_date,textbook_version,knowledge_skill_ids,initial_question_target,hard_question_cap,recovery_round_limit,status)
 values(sessid,sid,pid,c.id,(now() at time zone 'Asia/Shanghai')::date,'科粤版',c.knowledge_skill_ids,8,30,3,'active');
 for i in 1..8 loop
  if i=1 then select * into q from public.chem_questions where id='JLOCAL-20261002-ANHUI2018-Q01';
  elsif i=2 then select * into q from public.chem_questions where id='JLOCAL-20261002-ANHUI2018-Q03';
  else
   select other.* into q from public.chem_questions other
    where other.knowledge_id=any(c.knowledge_skill_ids) and other.source_kind='user_provided_local'
     and app_private.chem_junior_question_delivery_ready(other.id)
     and not exists(select 1 from public.chem_junior_session_steps used where used.session_id=sessid
      and (used.question_id=other.id or used.mother_id=other.mother_id or used.source_item_key=other.source_item_key
        or used.parent_source_item_key=other.parent_source_item_key or used.content_fingerprint=other.content_fingerprint))
    order by other.id limit 1;
  end if;
  if q.id is null then raise exception 'real reviewed QA question is unavailable at %',i; end if;
  snap:=jsonb_build_object('questionId',q.id,'motherId',q.mother_id,'skillId',q.skill_id,'knowledgeId',q.knowledge_id,
   'conceptKey',q.concept_key,'level',q.level,'gradeBand',q.grade_band,'textbookVersion',q.textbook_version,
   'stem',q.stem,'options',q.options,'correctOption',q.correct_option,'explanation',q.explanation,'scaffold',q.scaffold,
   'reviewStatus',q.review_status,'scopeStatus',q.scope_status,'sourceKind',q.source_kind,'renderMode',q.render_mode,
   'imageUrl',q.image_url,'assetRefs',q.asset_refs,'sourceReleaseId',q.source_release_id,'sourceItemKey',q.source_item_key,
   'parentSourceItemKey',q.parent_source_item_key,'sameTypeKey',q.same_type_key,'contentFingerprint',q.content_fingerprint,
   'revisionToken',q.question_revision_token,'routeKind','new_learning','routeReason','QA original-source image/native session');
  if i=1 then
   rejected:=false;
   begin
    perform public.chem_junior_issue_option_step(sid,sessid,null,q.id,1::smallint,'new_learning',
      'QA original-source image/native session',jsonb_set(snap,'{assetRefs}','[]'::jsonb));
   exception when raise_exception then rejected:=true; end;
   if not rejected then raise exception 'issue accepted a changed question-image snapshot'; end if;
  end if;
  select * into issued from public.chem_junior_issue_option_step(sid,sessid,null,q.id,i::smallint,
    'new_learning','QA original-source image/native session',snap);
  perform * from public.chem_junior_validate_issued_step(sessid,sid,issued.step_id);
  if i=1 then
   first_step:=issued.step_id; first_q:=q;
   select asset_path into image_path from app_private.chem_question_assets where question_id=q.id and asset_kind='question_image';
   select asset_path into analysis_path from app_private.chem_question_assets where question_id=q.id and asset_kind='analysis_image';
   if not exists(select 1 from public.chem_junior_step_question_asset_context(sid,pid,first_step,image_path,q.question_revision_token))
     or exists(select 1 from public.chem_junior_step_question_asset_context(other_sid,pid,first_step,image_path,q.question_revision_token))
     or exists(select 1 from public.chem_junior_step_question_asset_context(sid,pid,first_step,image_path,repeat('0',64)))
     or exists(select 1 from public.chem_junior_step_question_asset_context(sid,pid,first_step,analysis_path,q.question_revision_token))
   then raise exception 'image capability failed ownership/version/solution protection'; end if;
   rejected:=false;
   begin
    update app_private.chem_question_item_visual_reviews set review_state='pending' where question_id=q.id;
    if app_private.chem_junior_image_question_delivery_ready(q.id) then raise exception 'QA invalid visual review still ready'; end if;
    perform * from public.chem_junior_validate_issued_step(sessid,sid,first_step);
   exception when raise_exception then
    if sqlerrm='QA invalid visual review still ready' then raise; end if; rejected:=true;
   end;
   if not rejected then raise exception 'resume accepted an unreviewed source'; end if;
   rejected:=false;
   begin
    perform public.chem_junior_submit_answer(sid,pid,first_step,q.correct_option,false,5,repeat('0',64));
   exception when raise_exception then rejected:=true; end;
   if not rejected then raise exception 'stale revision got a first-answer lock'; end if;
  end if;
  ack:=public.chem_junior_submit_answer(sid,pid,issued.step_id,q.correct_option,false,5,q.question_revision_token);
  if ack->>'correct'<>'true' or ack->'questionSnapshot'->'assetRefs' is distinct from q.asset_refs
    or ack->'questionSnapshot'->>'sourceKind' is distinct from q.source_kind then raise exception 'first answer changed immutable source snapshot'; end if;
  if i=1 then
   replay:=public.chem_junior_submit_answer(sid,pid,first_step,q.correct_option,false,5,q.question_revision_token);
   if replay->>'replayed'<>'true' or replay->'questionSnapshot' is distinct from ack->'questionSnapshot' then raise exception 'confirmed feedback retry changed first evidence'; end if;
   rejected:=false;
   begin perform public.chem_junior_submit_answer(sid,pid,first_step,((q.correct_option+1)%4)::smallint,false,5,q.question_revision_token);
   exception when raise_exception then rejected:=true; end;
   if not rejected then raise exception 'first selected option was overwritten'; end if;
  end if;
 end loop;
 perform * from public.chem_junior_finalize_session(sessid,sid);
 if not exists(select 1 from public.chem_junior_daily_sessions where id=sessid and status='completed')
   or (select count(*) from public.chem_attempt_answers a join public.chem_learning_attempts t on t.id=a.attempt_id where t.junior_session_id=sessid)<>8
   or not exists(select 1 from public.chem_attempt_answers a join public.chem_learning_attempts t on t.id=a.attempt_id
      where t.junior_session_id=sessid and a.question_id=first_q.id and a.question_snapshot->>'sourceKind'='licensed_local'
       and a.question_snapshot->>'renderMode'='image_primary' and a.question_snapshot->'assetRefs'=first_q.asset_refs)
 then raise exception 'mixed source session did not complete with exact image history'; end if;
 -- A held completed version remains historical evidence, never a new issue.
 update app_private.chem_question_item_visual_reviews set review_state='pending' where question_id=first_q.id;
 if app_private.chem_junior_image_question_delivery_ready(first_q.id)
   or not exists(select 1 from public.chem_junior_step_question_asset_context(sid,pid,first_step,image_path,first_q.question_revision_token) where answered)
 then raise exception 'held version was deliverable or historical source evidence disappeared'; end if;
 insert into junior_image_roundtrip_checks values('real mixed date issue/resume/first-answer/finalize/history',jsonb_build_object('answered',8,'images',2,'staleSnapshotRejected',true,'foreignOwnerRejected',true,'analysisImageHidden',true,'unreviewedSourceRejected',true,'firstAnswerImmutable',true,'exactAssetsSaved',true,'heldHistoryReadable',true));
end;
$test$;
select * from junior_image_roundtrip_checks;
