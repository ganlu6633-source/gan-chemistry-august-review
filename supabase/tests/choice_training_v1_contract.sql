-- Run only inside a transaction with the candidate migration; ROLLBACK after.
-- Isolated random fixture IDs, real current reviewed source questions only.
create temporary table choice_qa_results(grade text,initial_count integer,recovery_count integer,final_count integer) on commit drop;
create temporary table choice_qa_ready on commit drop as
 select * from app_private.chem_teaching_ready_questions where grade_band in ('高一','高二','高三') and app_private.chem_choice_parent_identity(to_jsonb(chem_teaching_ready_questions)) is not null;
do $test$
declare
 grade text; sid uuid; pid uuid; aid uuid; rids uuid[]; ids text[]; skills text[]; preferred text[];
 anchor text; reserve_ids text[]; anchor_option integer; ctx jsonb; before_ctx jsonb; virtual jsonb:='[]';
 preview_ctx jsonb; q jsonb; response jsonb; selected integer; count_before integer; count_after integer;
 rows_before integer; rows_after integer; states jsonb; result jsonb; rejected boolean; total integer; current_item jsonb;
begin
 for grade in select unnest(array['高一','高二','高三']) loop
   sid:=gen_random_uuid(); pid:=gen_random_uuid(); aid:=gen_random_uuid(); anchor:=null; virtual:='[]';
   select array_agg(distinct source_release_id),array_agg(id order by id),array_agg(distinct skill_id) into rids,ids,skills
     from choice_qa_ready where grade_band=grade;
   select b.anchor_question_id,b.option_index,array(select v->>'questionId' from jsonb_array_elements(b.candidates) v)
   into anchor,anchor_option,reserve_ids
   from app_private.chem_option_practice_bindings b join choice_qa_ready r on r.id=b.anchor_question_id
   where r.grade_band=grade and b.review_status='verified' and b.anchor_revision_token=r.question_revision_token
     and (select count(distinct app_private.chem_choice_parent_identity(to_jsonb(c))) from jsonb_array_elements(b.candidates) v
       join choice_qa_ready c on c.id=v->>'questionId' and c.question_revision_token=v->>'revisionToken'
       where c.grade_band=grade and c.mother_id<>r.mother_id and app_private.chem_choice_parent_identity(to_jsonb(c))<>app_private.chem_choice_parent_identity(to_jsonb(r)))>=3
     and b.option_index<>r.correct_option
   order by b.anchor_question_id,b.option_index limit 1;
   select array_agg(id order by n) into preferred from (
     select id,row_number() over(order by case when id=anchor then 0 else 1 end,id) n
     from (select distinct on(app_private.chem_choice_parent_identity(to_jsonb(choice_qa_ready))) id,app_private.chem_choice_parent_identity(to_jsonb(choice_qa_ready)) parent_source_item_key
       from choice_qa_ready where grade_band=grade and (id=anchor or not id=any(coalesce(reserve_ids,'{}')))
       order by app_private.chem_choice_parent_identity(to_jsonb(choice_qa_ready)),case when id=anchor then 0 else 1 end,id) unique_parent
   ) x where n<=8;
   insert into public.chem_students_v2(id,display_name,grade_band,record_status,textbook_version,metadata)
   values(sid,'ROLLBACK choice policy QA',grade,'active','苏教版',jsonb_build_object('demo',false,'reviewProgram',
     jsonb_build_object('participating',true,'startDate','2026-09-01','endDate','2026-10-31')));
   insert into public.chem_learning_plans(id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,is_scheduled,
     question_count,round_limit,max_question_level,delivery_mode,teaching_managed)
   values(pid,sid,(now() at time zone 'Asia/Shanghai')::date,'REVIEW','ROLLBACK QA',skills,20,'course',true,8,1,8,'legacy_round',false);
   insert into app_private.chem_choice_training_policy(plan_id,grade_band,source_release_ids,preferred_base_ids,authorized_base_pool_ids,
     focus_skill_ids,authorized_skill_ids,source_note) values(pid,grade,rids,preferred,ids,skills,skills,'Isolated rollback contract test; real verified originals');
   select count(*) into rows_before from app_private.chem_choice_training_issued;
   before_ctx:=public.chem_choice_training_context(sid,pid,'[]');
   select count(*) into rows_after from app_private.chem_choice_training_issued;
   if rows_before<>rows_after or jsonb_array_length(before_ctx->'questions')<>8 then raise exception 'preview wrote or did not issue eight'; end if;
   ctx:=public.chem_choice_training_open(sid,pid);
   if ctx->'baseQuestionIds' is distinct from before_ctx->'baseQuestionIds' or (ctx->>'dailyUsed')::integer<>8 then
     raise exception 'initial preview/open/budget mismatch'; end if;
   ctx:=public.chem_choice_training_open(sid,pid);
   if (ctx->>'dailyUsed')::integer<>8 then raise exception 'open retry double budget'; end if;
   rejected:=false;
   begin perform public.chem_choice_training_context(gen_random_uuid(),pid,null);
   exception when others then if sqlerrm='choice_plan_not_available' then rejected:=true; else raise; end if; end;
   if not rejected then raise exception 'cross-student context accepted'; end if;
   q:=ctx->'questions'->0; rejected:=false;
   begin perform public.chem_choice_training_lock_answer(sid,pid,q->>'id',repeat('0',64),(q->>'correct_option')::integer,false,2);
   exception when others then if sqlerrm='choice_revision_changed' then rejected:=true; else raise; end if; end;
   if not rejected then raise exception 'wrong revision accepted'; end if;
   q:=ctx->'questions'->1; rejected:=false;
   begin
     perform public.chem_choice_training_lock_answer(sid,pid,q->>'id',q->>'question_revision_token',(q->>'correct_option')::integer,false,2);
   exception when others then if sqlerrm='choice_answer_out_of_order' then rejected:=true; else raise; end if; end;
   if not rejected then raise exception 'out of order answer accepted'; end if;
   total:=0;
   loop
     select value into q from jsonb_array_elements(ctx->'questions') with ordinality x(value,n)
       where not exists(select 1 from jsonb_array_elements(ctx->'lockedAnswers') a where a->>'question_id'=x.value->>'id') order by n limit 1;
     exit when q is null;
     total:=total+1; if total>30 then raise exception 'session exceeded 30'; end if;
     selected:=case when q->>'id'=anchor then anchor_option else (q->>'correct_option')::integer end;
     virtual:=virtual||jsonb_build_array(jsonb_build_object('questionId',q->>'id','selectedOption',selected,
       'revisionToken',q->>'question_revision_token','uncertain',false,'durationSec',2));
     preview_ctx:=public.chem_choice_training_context(sid,pid,virtual);
     response:=public.chem_choice_training_lock_answer(sid,pid,q->>'id',q->>'question_revision_token',selected,false,2);
     ctx:=response->'context';
     if (select jsonb_agg(v->>'id') from jsonb_array_elements(ctx->'questions') v)
       is distinct from (select jsonb_agg(v->>'id') from jsonb_array_elements(preview_ctx->'questions') v) then
       raise exception 'teacher/student next question mismatch'; end if;
     if total<8 and jsonb_array_length(ctx->'questions')<>8 then raise exception 'recovery before all eight'; end if;
     if total=8 and anchor is not null then
       begin
         update app_private.chem_option_practice_bindings set review_status='retired'
           where anchor_question_id=anchor and option_index=anchor_option;
         before_ctx:=public.chem_choice_training_context(sid,pid,null);
         if before_ctx->>'pendingReason'<>'source_changed' then raise exception 'withdrawn binding still deliverable'; end if;
         current_item:=ctx->'questions'->8; rejected:=false;
         begin perform public.chem_choice_training_context(sid,pid,jsonb_build_array(jsonb_build_object(
           'questionId',current_item->>'id','revisionToken',current_item->>'question_revision_token',
           'selectedOption',(current_item->>'correct_option')::integer,'uncertain',false,'durationSec',2)));
         exception when others then if sqlerrm='choice_binding_changed' then rejected:=true; else raise; end if; end;
         if not rejected then raise exception 'withdrawn binding accepted simulated answer'; end if;
         rejected:=false;
         begin perform public.chem_choice_training_lock_answer(sid,pid,current_item->>'id',current_item->>'question_revision_token',
           (current_item->>'correct_option')::integer,false,2);
         exception when others then if sqlerrm='choice_binding_changed' then rejected:=true; else raise; end if; end;
         if not rejected then raise exception 'withdrawn binding accepted an answer'; end if;
         raise exception 'qa_restore_binding';
       exception when others then if sqlerrm<>'qa_restore_binding' then raise; end if; end;
     end if;
     response:=public.chem_choice_training_lock_answer(sid,pid,q->>'id',q->>'question_revision_token',selected,false,2);
     if response->>'replayed'<>'true' then raise exception 'answer retry not replayed'; end if;
   end loop;
   if ctx->>'complete'<>'true' then raise exception 'all answered session not finishable: %',ctx->>'pendingReason'; end if;
   if anchor is not null and total<11 then raise exception 'real exact branch not exercised for %',grade; end if;
   select jsonb_agg(jsonb_build_object('student_id',sid,'skill_id',skill,'_expected_updated_at',null,'verified_level',0,'candidate_level',null,
     'stability','learning','consecutive_errors',1,'next_review_at',now()+interval '1 day','review_interval_index',0,
     'last_reviewed_at',now(),'teacher_intervention',false,'updated_at',now())) into states
     from (select distinct v->>'skill_id' skill from jsonb_array_elements(ctx->'questions') v) x;
   rejected:=false;
   begin perform public.chem_choice_training_finalize(sid,pid,aid,(select jsonb_agg(v||jsonb_build_object('_expected_updated_at',now())) from jsonb_array_elements(states) v));
   exception when others then if sqlerrm='choice_mastery_changed' then rejected:=true; else raise; end if; end;
   if not rejected then raise exception 'stale mastery version accepted'; end if;
   result:=public.chem_choice_training_finalize(sid,pid,aid,states);
   if result->>'completed'<>'true' or (select count(*) from public.chem_attempt_answers where attempt_id=aid)<>total then
     raise exception 'final attempt is incomplete'; end if;
   if exists(select 1 from public.chem_attempt_answers where attempt_id=aid and question_snapshot->'choiceContext' is null) then
     raise exception 'round evidence missing from snapshot'; end if;
   result:=public.chem_choice_training_finalize(sid,pid,aid,states);
   if result->>'replayed'<>'true' then raise exception 'finalization retry was not idempotent'; end if;
   if jsonb_array_length(result#>'{context,lockedAnswers}')<>total or result#>>'{context,complete}'<>'true' then
     raise exception 'completed context lost immutable answers'; end if;
   q:=ctx->'questions'->0;
   selected:=case when q->>'id'=anchor then anchor_option else (q->>'correct_option')::integer end;
   response:=public.chem_choice_training_lock_answer(sid,pid,q->>'id',q->>'question_revision_token',selected,false,2);
   if response->>'replayed'<>'true' then raise exception 'completed answer retry not immutable'; end if;
   insert into choice_qa_results values(grade,8,total-8,total);
 end loop;
end;
$test$;
select * from choice_qa_results order by grade;
