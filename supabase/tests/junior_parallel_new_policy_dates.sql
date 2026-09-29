begin;
create function pg_temp.qa_snapshot(q public.chem_questions,p_route_kind text,p_route_reason text) returns jsonb language sql as $snap$ select jsonb_build_object(
      'questionId',q.id,'motherId',q.mother_id,'skillId',q.skill_id,'knowledgeId',q.knowledge_id,
      'conceptKey',q.concept_key,'level',q.level,'gradeBand',q.grade_band,'textbookVersion',q.textbook_version,
      'stem',q.stem,'options',q.options,'correctOption',q.correct_option,'explanation',q.explanation,
      'scaffold',q.scaffold,'reviewStatus',q.review_status,'scopeStatus',q.scope_status,'sourceKind',q.source_kind,
      'renderMode',q.render_mode,'imageUrl',q.image_url,'assetRefs',q.asset_refs,'sourceReleaseId',q.source_release_id,
      'sourceItemKey',q.source_item_key,'parentSourceItemKey',q.parent_source_item_key,'sameTypeKey',q.same_type_key,
      'contentFingerprint',q.content_fingerprint,'revisionToken',q.question_revision_token,
      'routeKind',p_route_kind,'routeReason',p_route_reason); $snap$;

do $test$
declare
 sid uuid:=gen_random_uuid(); oldsid uuid:=gen_random_uuid();
 p1 uuid:=gen_random_uuid();p2 uuid:=gen_random_uuid();p3 uuid:=gen_random_uuid();
 x1 uuid:=gen_random_uuid();x2 uuid:=gen_random_uuid();x3 uuid:=gen_random_uuid();
 c1 public.chem_junior_curriculum_days%rowtype;c2 public.chem_junior_curriculum_days%rowtype;c3 public.chem_junior_curriculum_days%rowtype;
 q1 public.chem_questions%rowtype;q2 public.chem_questions%rowtype;q3 public.chem_questions%rowtype;
 issued1 record;issued2 record; before_step jsonb; after_step jsonb; rejected boolean; i integer; expected integer; acknowledged jsonb;
begin
 select * into strict c1 from public.chem_junior_curriculum_days where id='J-KY-2026-0929' and release_status='ready';
 c2:=jsonb_populate_record(c1,jsonb_build_object('id','QA-MULTIDAY-'||gen_random_uuid(),'day_number',(select max(day_number)+1 from public.chem_junior_curriculum_days)));
 insert into public.chem_junior_curriculum_days select c2.*;
 c3:=jsonb_populate_record(c2,jsonb_build_object('id','QA-MULTIDAY-'||gen_random_uuid(),'day_number',c2.day_number+1));
 insert into public.chem_junior_curriculum_days select c3.*;
 insert into public.chem_students_v2(id,display_name,grade_band,textbook_version,metadata) values
 (sid,'QA-junior-multiple-days-rollback','初三','科粤版','{"qaTransactionOnly":true}'),
 (oldsid,'QA-junior-legacy-exclusive-rollback','初三','科粤版','{"qaTransactionOnly":true}');
 insert into public.chem_learning_plans(id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,question_count,round_limit,delivery_mode,junior_curriculum_day_id)
 values
 (p1,sid,(now() at time zone 'Asia/Shanghai')::date-8,'REVIEW','QA catch-up',c1.knowledge_skill_ids,30,'course',8,4,'junior_adaptive',c1.id),
 (p2,sid,(now() at time zone 'Asia/Shanghai')::date,'REVIEW','QA today',c2.knowledge_skill_ids,30,'course',8,4,'junior_adaptive',c2.id),
 (p3,sid,(now() at time zone 'Asia/Shanghai')::date-1,'REVIEW','QA legacy',c3.knowledge_skill_ids,30,'course',12,1,'junior_adaptive',c3.id);
 insert into public.chem_junior_daily_sessions(id,student_id,plan_day_id,curriculum_day_id,study_date,textbook_version,knowledge_skill_ids,initial_question_target,hard_question_cap,recovery_round_limit)
 values(x1,sid,p1,c1.id,(now() at time zone 'Asia/Shanghai')::date-8,'科粤版',c1.knowledge_skill_ids,8,30,3);
 select * into strict q1 from public.chem_junior_practice_pool(sid,p1,x1) q
   where q.knowledge_id=any(c1.knowledge_skill_ids) and q.level=1 order by q.id limit 1;
 select * into issued1 from public.chem_junior_issue_option_step(sid,x1,null,q1.id,1::smallint,
 'new_learning','QA date switch',pg_temp.qa_snapshot(q1,'new_learning','QA date switch'));
 select to_jsonb(st) into before_step from public.chem_junior_session_steps st where id=issued1.step_id;
 insert into public.chem_junior_daily_sessions(id,student_id,plan_day_id,curriculum_day_id,study_date,textbook_version,knowledge_skill_ids,initial_question_target,hard_question_cap,recovery_round_limit)
 values(x2,sid,p2,c2.id,(now() at time zone 'Asia/Shanghai')::date,'科粤版',c2.knowledge_skill_ids,8,30,3);
 if (select count(*) from public.chem_junior_daily_sessions where student_id=sid and status='active')<>2 then raise exception 'new-policy dates cannot coexist';end if;
rejected:=false;
 begin insert into public.chem_junior_daily_sessions(student_id,plan_day_id,curriculum_day_id,study_date,textbook_version,knowledge_skill_ids,initial_question_target,hard_question_cap,recovery_round_limit)
 values(sid,p2,c2.id,(now() at time zone 'Asia/Shanghai')::date,'科粤版',c2.knowledge_skill_ids,8,30,3);
 exception when unique_violation then rejected:=true;end;
 if not rejected or (select count(*) from public.chem_junior_daily_sessions where student_id=sid)<>2
 then raise exception 'same plan created a second session';end if;
 rejected:=false;
 begin
  perform public.chem_junior_issue_option_step(sid,x2,null,q1.id,1::smallint,
   'new_learning','QA date switch',pg_temp.qa_snapshot(q1,'new_learning','QA date switch'));
 exception when raise_exception then if sqlerrm<>'junior_question_not_due' then raise;end if;rejected:=true;end;
 if not rejected then raise exception 'same pending source issued into two dates';end if;
 select * into strict q2 from public.chem_junior_practice_pool(sid,p2,x2) q
 where q.knowledge_id=any(c2.knowledge_skill_ids) and q.level=1 and q.parent_source_item_key<>q1.parent_source_item_key
 and q.content_fingerprint<>q1.content_fingerprint and q.mother_id<>q1.mother_id order by q.id limit 1;
 select * into issued2 from public.chem_junior_issue_option_step(sid,x2,null,q2.id,1::smallint,
 'new_learning','QA date switch',pg_temp.qa_snapshot(q2,'new_learning','QA date switch'));
 perform public.chem_junior_validate_issued_step(x1,sid,issued1.step_id);
 select to_jsonb(st) into after_step from public.chem_junior_session_steps st where id=issued1.step_id;
 if after_step is distinct from before_step then raise exception 'switching dates rewrote previous pending original';end if;
 acknowledged:=public.chem_junior_submit_answer(sid,p1,issued1.step_id,q1.correct_option,false,7,q1.question_revision_token);
 if acknowledged->'correct'<>'true'::jsonb or acknowledged->'replayed'<>'false'::jsonb then raise exception 'old date cannot be resumed and answered';end if;
 if (select count(*) from app_private.chem_junior_daily_budget_keys(sid))<>2 then raise exception 'two dates did not share actual-day budget';end if;
 -- Legacy cannot be inserted alongside active new-policy dates.
 rejected:=false;
 begin insert into public.chem_junior_daily_sessions(id,student_id,plan_day_id,curriculum_day_id,study_date,textbook_version,knowledge_skill_ids,initial_question_target,hard_question_cap,recovery_round_limit)
 values(x3,sid,p3,c3.id,(now() at time zone 'Asia/Shanghai')::date-1,'科粤版',c3.knowledge_skill_ids,12,15,0);
 exception when unique_violation then if sqlerrm<>'junior_session_legacy_active_conflict' then raise;end if;rejected:=true;end;
 if not rejected then raise exception 'legacy/new mixed activation accepted';end if;
 -- Re-activating an old abandoned legacy session must use the same exclusion.
 insert into public.chem_junior_daily_sessions(id,student_id,plan_day_id,curriculum_day_id,study_date,textbook_version,knowledge_skill_ids,initial_question_target,hard_question_cap,recovery_round_limit,status)
 values(x3,sid,p3,c3.id,(now() at time zone 'Asia/Shanghai')::date-1,'科粤版',c3.knowledge_skill_ids,12,15,0,'abandoned');
 rejected:=false;
 begin update public.chem_junior_daily_sessions set status='active' where id=x3;
 exception when unique_violation then if sqlerrm<>'junior_session_legacy_active_conflict' then raise;end if;rejected:=true;end;
 if not rejected then raise exception 'legacy reactivation bypassed mixed-policy gate';end if;
 -- An already active legacy learner cannot start a new-policy date either.
 insert into public.chem_learning_plans(id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,question_count,round_limit,delivery_mode,junior_curriculum_day_id)
 select gen_random_uuid(),oldsid,plan_date,mode,title,skill_ids,estimated_minutes,source,question_count,round_limit,delivery_mode,junior_curriculum_day_id
 from public.chem_learning_plans where id in(p2,p3);
 insert into public.chem_junior_daily_sessions(student_id,plan_day_id,curriculum_day_id,study_date,textbook_version,knowledge_skill_ids,initial_question_target,hard_question_cap,recovery_round_limit)
 select oldsid,id,junior_curriculum_day_id,plan_date,'科粤版',skill_ids,12,15,0 from public.chem_learning_plans where student_id=oldsid and question_count=12;
 rejected:=false;
 begin insert into public.chem_junior_daily_sessions(student_id,plan_day_id,curriculum_day_id,study_date,textbook_version,knowledge_skill_ids,initial_question_target,hard_question_cap,recovery_round_limit)
 select oldsid,id,junior_curriculum_day_id,plan_date,'科粤版',skill_ids,8,30,3 from public.chem_learning_plans where student_id=oldsid and question_count=8;
 exception when unique_violation then if sqlerrm<>'junior_session_legacy_active_conflict' then raise;end if;rejected:=true;end;
 if not rejected then raise exception 'new/legacy mixed activation accepted';end if;
 -- Exercise the same row-locked reservation function used by every entry.
 -- These reservation-only events create no fictitious answers or mastery.
 for i in 3..30 loop
  perform app_private.chem_junior_reserve_daily_question(sid,'QA-budget:'||i::text);
 end loop;
 perform app_private.chem_junior_reserve_daily_question(sid,'junior:'||x1::text||':1');
 if (select count(*) from app_private.chem_junior_daily_budget_keys(sid))<>30 then raise exception 'shared reservations exceed or double-count day cap';end if;
 select * into strict q3 from public.chem_junior_practice_pool(sid,p1,x1) q
 where q.knowledge_id=any(c1.knowledge_skill_ids) and q.level=1 and q.parent_source_item_key<>all(array[q1.parent_source_item_key,q2.parent_source_item_key])
 and q.content_fingerprint<>all(array[q1.content_fingerprint,q2.content_fingerprint]) and q.mother_id<>all(array[q1.mother_id,q2.mother_id]) order by q.id limit 1;
 rejected:=false;
 begin perform public.chem_junior_issue_option_step(sid,x1,null,q3.id,2::smallint,
 'new_learning','QA date switch',pg_temp.qa_snapshot(q3,'new_learning','QA date switch'));
 exception when raise_exception then if sqlerrm<>'junior_daily_question_limit' then raise;end if;rejected:=true;end;
 if not rejected then raise exception 'old-date issue bypassed aggregate daily 30';end if;
 rejected:=false;
 begin perform app_private.chem_junior_reserve_daily_question(sid,'QA-another-entry:31');
 exception when raise_exception then if sqlerrm<>'junior_daily_question_limit' then raise;end if;rejected:=true;end;
 if not rejected then raise exception 'other-entry reservation bypassed aggregate daily 30';end if;
 -- A question already reserved in the other date can still be answered at cap.
 acknowledged:=public.chem_junior_submit_answer(sid,p2,issued2.step_id,q2.correct_option,false,9,q2.question_revision_token);
 if acknowledged->'correct'<>'true'::jsonb or (select count(*) from app_private.chem_junior_daily_budget_keys(sid))<>30
 then raise exception 'already counted pending answer was blocked or double-counted at cap';end if;
 if (select count(*) from public.chem_junior_session_steps where session_id in(x1,x2))<>2
 then raise exception 'failed cross-date issue left an extra step';end if;
end;
$test$;
rollback;
select 'new dates coexist and resume exact originals; legacy mixed activation blocked; actual-day shared 30 and existing answer at cap passed' as result,
 count(*) as remaining_qa from public.chem_students_v2 where display_name in('QA-junior-multiple-days-rollback','QA-junior-legacy-exclusive-rollback');
