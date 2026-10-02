-- A diagnostic can exist without a verified three-question practice pool.
-- The private lookup changes only the empty reserve-gap knowledgePoint.
do $guard$ begin
 if md5(pg_get_functiondef('app_private.chem_choice_projection(uuid,uuid,jsonb)'::regprocedure))<>'fcbadceebdc2f7381af5340f2ea0da2c' then
   raise exception 'Choice projection changed since exact diagnostic baseline; review new function before deployment'; end if;
 if to_regclass('app_private.chem_option_knowledge_diagnostics') is not null then
   raise exception 'Option diagnostic table already exists; inspect rather than silently replacing'; end if;
end $guard$;
create table app_private.chem_option_knowledge_diagnostics (
 anchor_question_id text not null references public.chem_questions(id),
 anchor_revision_token text not null check(anchor_revision_token ~ '^[0-9a-f]{64}$'),
 option_index smallint not null check(option_index between 0 and 3),
 knowledge_card_id text not null references public.chem_knowledge_cards(id),
 section_index integer not null check(section_index>=0),
 item_index integer not null check(item_index>=0),
 review_point_index integer not null check(review_point_index>=0),
 knowledge_point_id text not null,
 knowledge_point text not null check(length(btrim(knowledge_point))>0),
 source_option_text text not null check(length(btrim(source_option_text))>0),
 evidence jsonb not null check(jsonb_typeof(evidence)='object'),
 review_status text not null check(review_status in ('pending','verified')),
 reviewed_by text not null check(length(btrim(reviewed_by))>0),
 reviewed_at timestamptz not null default now(),
 review_note text not null,
 primary key(anchor_question_id,option_index),
 check(knowledge_point_id=knowledge_card_id||':s'||section_index::text||':i'||item_index::text||':p'||review_point_index::text)
);
alter table app_private.chem_option_knowledge_diagnostics enable row level security;
revoke all on table app_private.chem_option_knowledge_diagnostics from public,anon,authenticated,service_role;

create function app_private.chem_option_diagnostic_point(p_question_id text,p_revision_token text,p_option_index integer)
returns text language sql stable security invoker set search_path='' as $lookup$
 with recursive selected as (
   select d.*,k.structured_content #> array['sections',d.section_index::text,'items',d.item_index::text] as item
   from app_private.chem_option_knowledge_diagnostics d
   join public.chem_questions q on q.id=d.anchor_question_id and q.question_revision_token=d.anchor_revision_token
   join public.chem_knowledge_cards k on k.id=d.knowledge_card_id and k.review_status='approved'
   where d.anchor_question_id=p_question_id and d.anchor_revision_token=p_revision_token
     and d.option_index=p_option_index and d.review_status='verified'
     and q.review_status='approved' and q.usable_for_review
     and q.options->>p_option_index=d.source_option_text
 ), nodes(node) as (
   select item from selected
   union all
   select child.value from nodes n cross join lateral jsonb_array_elements(
     case when jsonb_typeof(n.node->'children')='array' then n.node->'children' else '[]'::jsonb end) child
 )
 select d.knowledge_point from selected d where exists(
   select 1 from nodes n where n.node->>'label'=d.knowledge_point
     and coalesce(n.node->>'reviewPointIndex','0')=d.review_point_index::text
     and jsonb_array_length(case when jsonb_typeof(n.node->'children')='array' then n.node->'children' else '[]'::jsonb end)=0
 );
$lookup$;
revoke all on function app_private.chem_option_diagnostic_point(text,text,integer) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION app_private.chem_choice_projection(p_student_id uuid, p_plan_id uuid, p_preview_answers jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 c app_private.chem_choice_training_policy; sess app_private.chem_choice_training_sessions;
 p public.chem_learning_plans; today date:=(now() at time zone 'Asia/Shanghai')::date;
 history jsonb; pool jsonb; issued jsonb; answers jsonb:='{}'; questions jsonb:='[]'; branches jsonb:='[]';
 ready_ids text[]; budget_keys text[]; real_answer_ids text[]; base_ids text[]:='{}'; used_ids text[]:='{}'; branch_ids text[];
 q jsonb; a jsonb; candidate jsonb; anchor jsonb; binding jsonb; frozen jsonb; prior_branch jsonb;
 qid text; key text; pending_reason text; source_changed boolean:=false;
 repetition jsonb; branch_questions jsonb; emitted jsonb; contexts jsonb;
 current_round integer; position integer; target integer; answered integer; correct_count integer; persisted_target integer; branch_gap text;
 daily_used integer; projected_cost integer:=0; cost integer; first_pending boolean:=false;
 all_confident boolean; any_wrong boolean; has_gap boolean; finished boolean; current_anchor text;
begin
 c:=app_private.chem_choice_assert_plan(p_student_id,p_plan_id);
 select * into p from public.chem_learning_plans where id=p_plan_id;
 select * into sess from app_private.chem_choice_training_sessions where plan_id=p_plan_id and student_id=p_student_id;
 if p_preview_answers is not null and (jsonb_typeof(p_preview_answers)<>'array' or jsonb_array_length(p_preview_answers)>30) then
   raise exception 'choice_preview_answers_invalid'; end if;
 select coalesce(array_agg(event_key),'{}'),count(*) into budget_keys,daily_used
   from app_private.chem_junior_daily_budget_keys(p_student_id);
 history:=app_private.chem_choice_history(p_student_id,p_plan_id);
 select coalesce(jsonb_object_agg(i.question_id,i.question_snapshot),'{}') into issued
   from app_private.chem_choice_training_issued i where i.plan_id=p_plan_id;
 select coalesce(jsonb_object_agg(l.question_id,jsonb_build_object('question_id',l.question_id,
   'selected_option',l.selected_option,'uncertain',l.uncertain,'duration_sec',l.duration_sec,
   'revision_token',l.revision_token,'created_at',l.created_at)),'{}') into answers
   from app_private.chem_question_answer_locks l where l.student_id=p_student_id and l.plan_day_id=p_plan_id and l.attempt_sequence=0;
 if sess.status='completed' then
   select coalesce(jsonb_object_agg(a.question_id,jsonb_build_object('question_id',a.question_id,
     'selected_option',a.selected_option,'uncertain',a.uncertain,'duration_sec',a.duration_sec,
     'revision_token',a.question_snapshot->>'revisionToken','created_at',a.created_at)),'{}') into answers
   from public.chem_attempt_answers a where a.attempt_id=sess.attempt_id;
 end if;
 real_answer_ids:=array(select jsonb_object_keys(answers));
 for a in select value from jsonb_array_elements(coalesce(p_preview_answers,'[]')) loop
   qid:=a->>'questionId';
   if coalesce(qid,'')='' or jsonb_typeof(a->'selectedOption')<>'number' or (a->>'selectedOption')::numeric not between 0 and 3
     or trunc((a->>'selectedOption')::numeric)<>(a->>'selectedOption')::numeric
     or coalesce(a->>'revisionToken','')='' or (a ? 'uncertain' and jsonb_typeof(a->'uncertain')<>'boolean')
     or exists(select 1 from jsonb_array_elements(p_preview_answers) v where v->>'questionId'=qid group by v->>'questionId' having count(*)>1)
   then raise exception 'choice_preview_answers_invalid'; end if;
   if answers ? qid and ((answers->qid->>'selected_option')::integer<>(a->>'selectedOption')::integer
     or answers->qid->>'revision_token'<>a->>'revisionToken'
     or (answers->qid->>'uncertain')::boolean is distinct from coalesce((a->>'uncertain')::boolean,false)) then
     raise exception 'choice_first_answer_immutable'; end if;
   if answers ? qid then continue; end if;
   answers:=answers||jsonb_build_object(qid,jsonb_build_object('question_id',qid,'selected_option',(a->>'selectedOption')::integer,
     'uncertain',coalesce((a->>'uncertain')::boolean,false),'duration_sec',least(3600,greatest(0,coalesce((a->>'durationSec')::integer,0))),
     'revision_token',a->>'revisionToken','created_at',now()));
 end loop;
 -- Candidate discovery is constrained by the explicit stage, release and grade.
 -- Readiness still applies to every candidate, not just the eight preferred IDs.
 select coalesce(array_agg(pool_q.id),'{}') into ready_ids from public.chem_questions pool_q
   where pool_q.source_release_id=any(c.source_release_ids) and pool_q.grade_band=c.grade_band
     and pool_q.skill_id=any(c.authorized_skill_ids) and pool_q.source_kind='licensed_local' and pool_q.render_mode='image_primary'
     and pool_q.review_status='approved' and pool_q.scope_status='IN' and pool_q.usable_for_review
     and nullif(pool_q.mother_id,'') is not null and app_private.chem_choice_parent_identity(to_jsonb(pool_q)) is not null
     and (p.max_question_level is null or pool_q.level<=p.max_question_level);
 if cardinality(ready_ids)>1000 then raise exception 'choice_stage_pool_too_large'; end if;
 select coalesce(jsonb_object_agg(pool_q.id,to_jsonb(pool_q)),'{}') into pool from public.chem_questions pool_q
   join public.chem_teaching_ready_question_ids(c.grade_band,ready_ids) r on r.question_id=pool_q.id;
 -- Virtual answers cannot turn an unready, withdrawn or changed question into
 -- an already-answered historical row. Only server-persisted locks/attempts
 -- qualify for that replay exception.
 if exists(select 1 from jsonb_each(answers) virtual_answer
   where not virtual_answer.key=any(real_answer_ids) and
     (pool->virtual_answer.key is null or
      pool->virtual_answer.key->>'question_revision_token' is distinct from virtual_answer.value->>'revision_token')) then
   raise exception 'choice_source_changed';
 end if;
 if sess.plan_id is not null then
   base_ids:=sess.base_question_ids;
   for qid in select unnest(base_ids) loop
     q:=issued->qid;
     if q is null then raise exception 'choice_frozen_base_incomplete'; end if;
     questions:=questions||jsonb_build_array(q);
     used_ids:=used_ids||app_private.chem_choice_identities(q);
   end loop;
 else
   if daily_used+8>30 then pending_reason:='daily_limit';
   else
     for q in select value from jsonb_each(pool) e
       where e.key=any(c.authorized_base_pool_ids)
       order by case when e.value->>'skill_id'=any(c.focus_skill_ids)
           and (cardinality(coalesce(p.target_concept_keys,'{}'))=0
             or e.value->>'concept_key'=any(p.target_concept_keys)) then 0 else 1 end,
         coalesce(array_position(c.preferred_base_ids,e.key),1001),
         case when e.value->>'skill_id'=any(c.focus_skill_ids) then 0 else 1 end,
         (e.value->>'level')::integer,e.key loop
       repetition:=app_private.chem_choice_repetition_state(q,history,today);
       if repetition->>'eligible'<>'true' or used_ids && app_private.chem_choice_identities(q) then continue; end if;
       q:=q||jsonb_build_object('choiceContext',jsonb_build_object('recoveryRound',0,'anchorId',null,'knowledgePoint',null,
         'position',cardinality(base_ids)+1,'total',8,'learningPurpose',case when repetition->>'kind'='due_review' then 'spaced_review' else 'first_learning' end,
         'lastAnsweredDate',repetition->'lastAnsweredDate','reviewDueDate',repetition->'reviewDueDate'));
       base_ids:=array_append(base_ids,q->>'id'); questions:=questions||jsonb_build_array(q);
       used_ids:=used_ids||app_private.chem_choice_identities(q);
       exit when cardinality(base_ids)=8;
     end loop;
     if cardinality(base_ids)<>8 or not exists(
       select 1 from jsonb_array_elements(questions) selected_question
       where selected_question->>'skill_id'=any(c.focus_skill_ids)
        and (cardinality(coalesce(p.target_concept_keys,'{}'))=0
          or selected_question->>'concept_key'=any(p.target_concept_keys))
     ) then pending_reason:='base_source_gap'; questions:='[]'; base_ids:='{}'; end if;
   end if;
 end if;
 -- Answers must remain a prefix of issued questions; saving a forged future
 -- answer must not unlock its descendants in teacher simulation either.
 for q in select value from jsonb_array_elements(questions) loop
   qid:=q->>'id'; a:=answers->qid;
   key:='answer:'||p_plan_id::text||':0:'||qid;
   if not key=any(budget_keys) and not qid=any(real_answer_ids) then projected_cost:=projected_cost+1; end if;
   if a is null then
     first_pending:=true;
     if pool->qid is null or pool->qid->>'question_revision_token' is distinct from q->>'question_revision_token' then source_changed:=true; end if;
     if qid=any(real_answer_ids) and not key=any(budget_keys) then projected_cost:=projected_cost+1; end if;
   elsif first_pending or a->>'revision_token' is distinct from q->>'question_revision_token' then
     raise exception 'choice_answer_order_or_revision';
   end if;
 end loop;
 if source_changed then pending_reason:='source_changed'; end if;
 if daily_used+projected_cost>30 then pending_reason:='daily_limit'; end if;
 if cardinality(base_ids)=8 and not first_pending and pending_reason is null then
   <<rounds>> for current_round in 1..3 loop
     for anchor in select value from jsonb_array_elements(questions)
       where (value#>>'{choiceContext,recoveryRound}')::integer=current_round-1 loop
       current_anchor:=anchor->>'id'; a:=answers->current_anchor;
       if current_round>1 and exists(select 1 from jsonb_array_elements(branches) old_branch
         where old_branch->>'status'='consolidated' and old_branch->'questionIds' ? current_anchor) then continue; end if;
       if a is null then exit rounds; end if;
       if (a->>'selected_option')::integer=(anchor->>'correct_option')::integer and a->>'uncertain'='false' then continue; end if;
       select to_jsonb(b) into prior_branch from app_private.chem_choice_training_branches b
         where b.plan_id=p_plan_id and b.anchor_question_id=current_anchor;
       frozen:='[]'; binding:=null; branch_questions:='[]'; branch_ids:='{}';
       if prior_branch is not null then
         if prior_branch->>'anchor_revision_token'<>anchor->>'question_revision_token'
           or (prior_branch->>'option_index')::integer<>(a->>'selected_option')::integer then raise exception 'choice_frozen_binding_changed'; end if;
         binding:=prior_branch->'binding_snapshot'; frozen:=prior_branch->'candidates';
         if sess.status<>'completed' and exists(select 1 from jsonb_array_elements(frozen) candidate_entry
           where not(candidate_entry->>'questionId')=any(real_answer_ids)) and not exists(
             select 1 from app_private.chem_option_practice_bindings current_binding
             where current_binding.anchor_question_id=current_anchor and current_binding.option_index=(a->>'selected_option')::integer
               and current_binding.review_status='verified' and to_jsonb(current_binding)=binding) then
           if exists(select 1 from jsonb_array_elements(frozen) newly_simulated
             where answers ? (newly_simulated->>'questionId') and not(newly_simulated->>'questionId')=any(real_answer_ids)) then
             raise exception 'choice_binding_changed'; end if;
           pending_reason:='source_changed'; exit rounds;
         end if;
       else
         select to_jsonb(b) into binding from app_private.chem_option_practice_bindings b
           where b.anchor_question_id=current_anchor and b.option_index=(a->>'selected_option')::integer
             and b.anchor_revision_token=anchor->>'question_revision_token' and b.review_status='verified';
         if binding is not null then
           for candidate in select value from jsonb_array_elements(binding->'candidates') loop
             q:=pool->(candidate->>'questionId');
             if q is null or q->>'question_revision_token' is distinct from candidate->>'revisionToken'
               or app_private.chem_choice_identities(q) && (used_ids||branch_ids)
             then continue; end if;
             repetition:=app_private.chem_choice_repetition_state(q,history,today);
             if repetition->>'eligible'<>'true' then continue; end if;
             frozen:=frozen||jsonb_build_array(candidate);
             branch_ids:=branch_ids||app_private.chem_choice_identities(q);
           end loop;
         end if;
       end if;
       if jsonb_array_length(frozen)<3 or jsonb_array_length(frozen)>5 or coalesce(binding->>'knowledge_point','')='' then
         branches:=branches||jsonb_build_array(jsonb_build_object('anchorQuestionId',current_anchor,
           'anchorOptionIndex',(a->>'selected_option')::integer,'recoveryRound',current_round,
           'knowledgePoint',coalesce(nullif(binding->>'knowledge_point',''),app_private.chem_option_diagnostic_point(current_anchor,anchor->>'question_revision_token',(a->>'selected_option')::integer),''),'skillId',anchor->>'skill_id','conceptKey',anchor->>'concept_key',
           'questionIds','[]'::jsonb,'status','reserve_gap','gap','exact_reserve_unavailable'));
         continue;
       end if;
       target:=3; any_wrong:=false; branch_gap:=null;
       select count(*) into persisted_target from app_private.chem_choice_training_issued i
         where i.plan_id=p_plan_id and i.anchor_question_id=current_anchor;
       for candidate in select value from jsonb_array_elements(frozen) with ordinality x(value,n) where n<=3 loop
         q:=coalesce(issued->(candidate->>'questionId'),pool->(candidate->>'questionId'));
         a:=answers->(candidate->>'questionId');
         if a is not null and ((a->>'selected_option')::integer<>(q->>'correct_option')::integer or a->>'uncertain'<>'false') then any_wrong:=true; end if;
       end loop;
       if any_wrong then target:=jsonb_array_length(frozen); end if;
       -- A frozen reserve that has not been issued yet can have been used in
       -- another date's session. It does not gain permission to bypass spacing
       -- or the same-day parent rule merely because the binding was frozen.
       if prior_branch is not null and exists(select 1 from jsonb_array_elements(frozen) with ordinality f(v,n)
         where n<=target and not issued ? (v->>'questionId') and
           app_private.chem_choice_repetition_state(pool->(v->>'questionId'),history,today)->>'eligible' is distinct from 'true') then
         if persisted_target>=3 then target:=persisted_target; branch_gap:='reserved_question_not_due';
         else pending_reason:='reserve_not_due'; exit rounds; end if;
       end if;
       if jsonb_array_length(questions)+target>30 and persisted_target>=3 then target:=persisted_target; branch_gap:='session_limit'; end if;
       -- Never make fewer than three questions look like a full diagnostic set.
       if jsonb_array_length(questions)+target>30 then
         branches:=branches||jsonb_build_array(jsonb_build_object('anchorQuestionId',current_anchor,
           'anchorOptionIndex',(answers->current_anchor->>'selected_option')::integer,'recoveryRound',current_round,
           'knowledgePoint',binding->>'knowledge_point','skillId',anchor->>'skill_id','conceptKey',anchor->>'concept_key',
           'questionIds','[]'::jsonb,'status','needs_practice','gap','session_limit'));
         continue;
       end if;
       cost:=0;
       for candidate in select value from jsonb_array_elements(frozen) with ordinality x(value,n) where n<=target loop
         qid:=candidate->>'questionId'; key:='answer:'||p_plan_id::text||':0:'||qid;
         if not qid=any(real_answer_ids) and not key=any(budget_keys) then cost:=cost+1; end if;
       end loop;
       if daily_used+projected_cost+cost>30 then
         pending_reason:='daily_limit';
         if persisted_target<3 then exit rounds; end if;
         target:=persisted_target; branch_gap:='daily_limit';
         select count(*) into cost from jsonb_array_elements(frozen) with ordinality x(v,n)
           where n<=target and not(v->>'questionId')=any(real_answer_ids)
             and not('answer:'||p_plan_id::text||':0:'||(v->>'questionId'))=any(budget_keys);
       end if;
       projected_cost:=projected_cost+cost;
       answered:=0; correct_count:=0; all_confident:=true; position:=0; first_pending:=false;
       for candidate in select value from jsonb_array_elements(frozen) with ordinality x(value,n) where n<=target order by n loop
         qid:=candidate->>'questionId'; position:=position+1;
         q:=coalesce(issued->qid,pool->qid);
         if q is null or q->>'question_revision_token' is distinct from candidate->>'revisionToken' then pending_reason:='source_changed'; exit rounds; end if;
         a:=answers->qid;
         if a is null then
           first_pending:=true;
           if pool->qid is null or pool->qid->>'question_revision_token' is distinct from q->>'question_revision_token' then pending_reason:='source_changed'; exit rounds; end if;
         else
           if first_pending or a->>'revision_token' is distinct from q->>'question_revision_token' then raise exception 'choice_answer_order_or_revision'; end if;
           answered:=answered+1;
           if (a->>'selected_option')::integer=(q->>'correct_option')::integer then correct_count:=correct_count+1; end if;
           if (a->>'selected_option')::integer<>(q->>'correct_option')::integer or a->>'uncertain'<>'false' then all_confident:=false; end if;
         end if;
         q:=q||jsonb_build_object('choiceContext',jsonb_build_object('recoveryRound',current_round,'anchorId',current_anchor,
           'knowledgePoint',binding->>'knowledge_point','position',position,'total',target,'learningPurpose','targeted_practice'),
           'reviewRequiredNode',jsonb_build_object('knowledgePoint',binding->>'knowledge_point','skillId',anchor->>'skill_id','conceptKey',anchor->>'concept_key'));
         branch_questions:=branch_questions||jsonb_build_array(q);
       end loop;
       questions:=questions||branch_questions;
       if answered=target then
         select bool_and((answers->(v->>'id')->>'selected_option')::integer=(v->>'correct_option')::integer
           and answers->(v->>'id')->>'uncertain'='false') into all_confident
         from jsonb_array_elements(branch_questions) with ordinality x(v,n) where n>target-3;
       end if;
       used_ids:=used_ids||array(select unnest(app_private.chem_choice_identities(coalesce(issued->(v->>'questionId'),pool->(v->>'questionId')))) from jsonb_array_elements(frozen) v);
       branches:=branches||jsonb_build_array(jsonb_build_object('anchorQuestionId',current_anchor,
         'anchorOptionIndex',(answers->current_anchor->>'selected_option')::integer,'recoveryRound',current_round,
         'knowledgePoint',binding->>'knowledge_point','skillId',anchor->>'skill_id','conceptKey',anchor->>'concept_key',
         'questionIds',(select jsonb_agg(v->>'id') from jsonb_array_elements(branch_questions) v),'answered',answered,'correct',correct_count,
         'status',case when answered<target then 'practicing' when all_confident then 'consolidated' else 'needs_practice' end,
         'gap',branch_gap,'_binding',binding,'_candidates',frozen));
       if answered<target or pending_reason is not null then exit rounds; end if;
     end loop;
   end loop rounds;
 end if;
 -- No submitted virtual answer may have opened an unissued branch, and a live
 -- source/binding update must never silently remove a previously issued row.
 if pending_reason='source_changed' and sess.plan_id is not null then
   select coalesce(jsonb_agg(i.question_snapshot order by i.sequence),'[]') into questions
   from app_private.chem_choice_training_issued i where i.plan_id=p_plan_id;
 end if;
 if exists(select 1 from jsonb_each(answers) answer_entry where not exists(select 1 from jsonb_array_elements(questions) question_entry where question_entry->>'id'=answer_entry.key)) then
   raise exception 'choice_answer_not_issued'; end if;
 if exists(select 1 from app_private.chem_choice_training_issued i where i.plan_id=p_plan_id
   and not exists(select 1 from jsonb_array_elements(questions) with ordinality q(value,n) where q.value->>'id'=i.question_id and q.n=i.sequence)) then
   raise exception 'choice_frozen_issuance_changed'; end if;
 emitted:='[]';
 for q in select value from jsonb_array_elements(questions) loop
   a:=answers->(q->>'id');
   if a is not null then emitted:=emitted||jsonb_build_array(a||jsonb_build_object('correct',(a->>'selected_option')::integer=(q->>'correct_option')::integer)); end if;
 end loop;
 finished:=cardinality(base_ids)=8 and jsonb_array_length(emitted)=jsonb_array_length(questions) and pending_reason is null;
 return jsonb_build_object('policyVersion',c.policy_version,'planId',p_plan_id,'baseQuestionIds',to_jsonb(base_ids),
   'questions',questions,'lockedAnswers',emitted,'branches',branches,'dailyUsed',daily_used,
   'dailyRemaining',greatest(0,30-daily_used-projected_cost),'projectedAdditionalCost',projected_cost,
   'complete',finished,'pendingReason',pending_reason,'startedAt',sess.started_at,'persisted',sess.plan_id is not null,
   'status',coalesce(sess.status,'not_started'));
end;
$function$
