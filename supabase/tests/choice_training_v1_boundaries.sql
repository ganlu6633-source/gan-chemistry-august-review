-- Candidate schema + this test must be run inside BEGIN / ROLLBACK.
-- No existing student or learning history is modified.
do $test$
declare q jsonb:='{"id":"qa","mother_id":"m","parent_source_item_key":"p"}'; h jsonb:='[]'; r jsonb;
 day date:='2026-09-01'; n integer; expected integer;
begin
 if app_private.chem_choice_repetition_state(q,h,day)->>'kind'<>'fresh' then raise exception 'fresh is not fresh'; end if;
 for n in 1..5 loop
   h:=h||jsonb_build_array(q||jsonb_build_object('study_date',day,'answered_at',day::timestamptz,'correct',true,'uncertain',false));
   expected:=case n when 1 then 1 when 2 then 3 when 3 then 7 when 4 then 14 else 30 end;
   if app_private.chem_choice_repetition_state(q,h,day)->>'eligible'<>'false' then raise exception 'same day allowed'; end if;
   r:=app_private.chem_choice_repetition_state(q,h,day+expected);
   if r->>'kind'<>'due_review' or (r->>'intervalDays')::integer<>expected then raise exception 'wrong spacing %',r; end if;
   if expected>1 and app_private.chem_choice_repetition_state(q,h,day+expected-1)->>'eligible'<>'false' then raise exception 'early review allowed'; end if;
   day:=day+expected;
 end loop;
 h:=h||jsonb_build_array(q||jsonb_build_object('study_date',day,'answered_at',day::timestamptz,'correct',true,'uncertain',true));
 if (app_private.chem_choice_repetition_state(q,h,day+1)->>'intervalDays')::integer<>1 then raise exception 'uncertainty did not reset review'; end if;
 h:=h||jsonb_build_array(q||jsonb_build_object('study_date',day,'pending',true));
 if app_private.chem_choice_repetition_state(q,h,day+20)->>'eligible'<>'false' then raise exception 'pending issue reused'; end if;
 if app_private.chem_choice_parent_identity('{"source_info":{"exam":"real exam","year":"2026","questionNo":"11(1)"}}') is distinct from
    app_private.chem_choice_parent_identity('{"source_info":{"exam":"real exam","year":"2026","questionNo":"11(2)"}}') then raise exception 'subquestions became independent'; end if;
 if app_private.chem_choice_parent_identity('{"mother_id":"fake-only"}') is not null then raise exception 'unlocated source accepted as parent'; end if;
end;
$test$;

create temporary table choice_boundary_result(payload jsonb) on commit drop;
create temporary table choice_boundary_ready on commit drop as
 select * from app_private.chem_teaching_ready_questions where grade_band='高二'
 and app_private.chem_choice_parent_identity(to_jsonb(chem_teaching_ready_questions)) is not null;
do $test$
declare sid uuid:=gen_random_uuid(); pid uuid; oldpid uuid:=gen_random_uuid(); firstpid uuid; current_pid uuid;
 rids uuid[]; ids text[]; skills text[]; preferred text[]; ctx jsonb; q public.chem_questions;
 i integer; j integer; count_before integer; bad boolean; used text[]:='{}'; wrong_point jsonb;
begin
 select array_agg(distinct source_release_id),array_agg(id order by id),array_agg(distinct skill_id) into rids,ids,skills from choice_boundary_ready;
 select array_agg(id order by id) into preferred from (select distinct on(app_private.chem_choice_parent_identity(to_jsonb(r))) id
   from choice_boundary_ready r order by app_private.chem_choice_parent_identity(to_jsonb(r)),id limit 8) x;
 insert into public.chem_students_v2(id,display_name,grade_band,record_status,textbook_version,metadata)
 values(sid,'ROLLBACK boundary policy QA','高二','active','苏教版',jsonb_build_object('demo',false,'reviewProgram',
   jsonb_build_object('participating',true,'startDate','2026-09-01','endDate','2026-10-31')));
 for i in 1..4 loop
   pid:=gen_random_uuid(); if i=1 then firstpid:=pid; end if;
   insert into public.chem_learning_plans(id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,is_scheduled,
     question_count,round_limit,max_question_level,delivery_mode,teaching_managed)
   values(pid,sid,(now() at time zone 'Asia/Shanghai')::date-i,'REVIEW','ROLLBACK boundary QA',skills,20,'course',true,8,1,8,'legacy_round',false);
   insert into app_private.chem_choice_training_policy(plan_id,grade_band,source_release_ids,preferred_base_ids,authorized_base_pool_ids,
     focus_skill_ids,authorized_skill_ids,source_note) values(pid,'高二',rids,preferred,ids,skills,skills,'Rollback source boundary fixture');
   ctx:=public.chem_choice_training_open(sid,pid);
   if i<=3 then
     if jsonb_array_length(ctx->'questions')<>8 or (ctx->>'dailyUsed')::integer<>i*8 then raise exception 'cross-plan budget wrong'; end if;
     if exists(select 1 from jsonb_array_elements(ctx->'questions') current_q where app_private.chem_choice_identities(current_q)&&used) then
       raise exception 'same day repeated source parent'; end if;
     used:=used||array(select unnest(app_private.chem_choice_identities(v)) from jsonb_array_elements(ctx->'questions') v);
   elsif ctx->>'pendingReason'<>'daily_limit' or jsonb_array_length(ctx->'questions')<>0 then
     raise exception 'fourth eight-question opening exceeded day cap';
   end if;
 end loop;
 if (select count(*) from app_private.chem_choice_training_issued where plan_id in(select id from public.chem_learning_plans where student_id=sid))<>24 then raise exception 'gap created fake issued rows'; end if;
 -- Six real legacy answers share the same 30-question day budget. The seventh
 -- must fail even though it enters through the pre-existing answer-lock RPC.
 insert into public.chem_learning_plans(id,student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,is_scheduled,
   question_count,round_limit,max_question_level,delivery_mode,teaching_managed)
 values(oldpid,sid,(now() at time zone 'Asia/Shanghai')::date,'REVIEW','ROLLBACK legacy entry',skills,20,'course',true,7,1,8,'legacy_round',false);
 j:=0;
 for q in select r.* from choice_boundary_ready r where not(app_private.chem_choice_identities(to_jsonb(r))&&used) order by r.id loop
   j:=j+1;
   if j<=6 then
     perform public.chem_lock_question_answer(sid,oldpid,0,q.id,q.correct_option,false,2,q.question_revision_token);
   else
     bad:=false;
     begin perform public.chem_lock_question_answer(sid,oldpid,0,q.id,q.correct_option,false,2,q.question_revision_token);
     exception when others then if sqlerrm='junior_daily_question_limit' then bad:=true; else raise; end if; end;
     if not bad then raise exception '31st real legacy answer bypassed day cap'; end if;
     exit;
   end if;
 end loop;
 if j<>7 or (select count(*) from app_private.chem_junior_daily_budget_keys(sid))<>30 then raise exception '30 budget fixture incomplete'; end if;
 -- Opening, retrying, and a readonly teacher context cannot consume it again.
 ctx:=public.chem_choice_training_open(sid,firstpid);
 if (ctx->>'dailyUsed')::integer<>30 or (select count(*) from app_private.chem_choice_training_issued where plan_id=firstpid)<>8 then raise exception 'retry changed issued or day count'; end if;
 ctx:=public.chem_choice_training_context(sid,firstpid,'[]');
 if (select count(*) from app_private.chem_junior_daily_budget_keys(sid))<>30 then raise exception 'preview wrote day count'; end if;
 -- Retrofitting a started legacy plan is prohibited even if its plan metadata
 -- is changed to eight: old immutable locks remain under the old contract.
 bad:=false;
 begin
   update public.chem_learning_plans set question_count=8 where id=oldpid;
   insert into app_private.chem_choice_training_policy(plan_id,grade_band,source_release_ids,preferred_base_ids,authorized_base_pool_ids,
     focus_skill_ids,authorized_skill_ids,source_note) values(oldpid,'高二',rids,preferred,ids,skills,skills,'must reject started legacy');
 exception when others then if sqlerrm='choice_policy_invalid_or_legacy_started' then bad:=true; else raise; end if; end;
 if not bad then raise exception 'legacy started contract migrated'; end if;
 -- Program revocation and demo state are evaluated on each locked entry.
 begin
   update public.chem_students_v2 set metadata=jsonb_set(metadata,'{reviewProgram,participating}','false') where id=sid;
   bad:=false;
   begin perform public.chem_choice_training_open(sid,firstpid);
   exception when others then if sqlerrm='choice_outside_program' then bad:=true; else raise; end if; end;
   if not bad then raise exception 'revoked program accepted'; end if;
   raise exception 'qa_restore_program';
 exception when others then if sqlerrm<>'qa_restore_program' then raise; end if; end;
 begin
   update public.chem_students_v2 set metadata=jsonb_set(metadata,'{demo}','true') where id=sid;
   bad:=false;
   begin perform public.chem_choice_training_open(sid,firstpid);
   exception when others then if sqlerrm='choice_plan_not_available' then bad:=true; else raise; end if; end;
   if not bad then raise exception 'demo accepted'; end if;
   raise exception 'qa_restore_program';
 exception when others then if sqlerrm<>'qa_restore_program' then raise; end if; end;
 -- PUBLIC/browser roles have no RPC or private table privilege.
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'chem_choice_training_%'
   and (has_function_privilege('anon',p.oid,'EXECUTE') or has_function_privilege('authenticated',p.oid,'EXECUTE') or not has_function_privilege('service_role',p.oid,'EXECUTE'))) then
   raise exception 'choice RPC ACL leaked'; end if;
 insert into choice_boundary_result values(jsonb_build_object('crossPlanIssued',24,'legacyLocked',6,'dailyUsed',30,'checks','passed'));
end;
$test$;
select * from choice_boundary_result;
