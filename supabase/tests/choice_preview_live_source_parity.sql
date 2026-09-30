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
 for grade in select unnest(array['高二']) loop
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

   q:=ctx->'questions'->0;
   begin
     insert into app_private.chem_question_delivery_holds(anchor_question_id,reason)
     values(q->>'id','Rollback-only parity audit hold') on conflict(anchor_question_id) do update set resolved_at=null,reason=excluded.reason;
     rejected:=false;
     begin perform public.chem_choice_training_lock_answer(sid,pid,q->>'id',q->>'question_revision_token',(q->>'correct_option')::integer,false,2);
     exception when others then
       if sqlerrm like '%held%' or sqlerrm like '%not ready%' or sqlerrm like '%source%' or sqlerrm like '%not eligible%' then rejected:=true; else raise; end if;
     end;
     if not rejected then raise exception 'real held source accepted'; end if;
     rejected:=false;
     begin perform public.chem_choice_training_context(sid,pid,jsonb_build_array(jsonb_build_object('questionId',q->>'id','revisionToken',q->>'question_revision_token','selectedOption',(q->>'correct_option')::integer,'uncertain',false,'durationSec',2)));
     exception when others then if sqlerrm='choice_source_changed' then rejected:=true; else raise; end if; end;
     if not rejected then raise exception 'new simulated held source accepted'; end if;
     if exists(select 1 from app_private.chem_question_answer_locks where plan_day_id=pid) then raise exception 'hold rejection wrote lock'; end if;
     raise exception 'qa_restore_hold';
   exception when others then if sqlerrm<>'qa_restore_hold' then raise; end if; end;
   response:=public.chem_choice_training_lock_answer(sid,pid,q->>'id',q->>'question_revision_token',(q->>'correct_option')::integer,false,2);
   begin
     insert into app_private.chem_question_delivery_holds(anchor_question_id,reason)
     values(q->>'id','Rollback-only saved-history replay hold') on conflict(anchor_question_id) do update set resolved_at=null,reason=excluded.reason;
     response:=public.chem_choice_training_lock_answer(sid,pid,q->>'id',q->>'question_revision_token',(q->>'correct_option')::integer,false,2);
     if response->>'replayed'<>'true' then raise exception 'saved real answer replay lost'; end if;
     preview_ctx:=public.chem_choice_training_context(sid,pid,jsonb_build_array(jsonb_build_object('questionId',q->>'id','revisionToken',q->>'question_revision_token','selectedOption',(q->>'correct_option')::integer,'uncertain',false,'durationSec',2)));
     if jsonb_array_length(preview_ctx->'lockedAnswers')<>1 then raise exception 'saved answer not visible to teacher'; end if;
     raise exception 'qa_restore_hold';
   exception when others then if sqlerrm<>'qa_restore_hold' then raise; end if; end;
   insert into choice_qa_results values(grade,8,0,1);
 end loop;
end;
$test$;
select * from choice_qa_results;
