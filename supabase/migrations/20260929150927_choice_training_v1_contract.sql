-- CANDIDATE: explicit, opt-in high-school policy; no student/plan is enrolled here.
-- Legacy plans, snapshots, first answers and the junior contract are untouched.
create table app_private.chem_choice_training_policy (
  plan_id uuid primary key references public.chem_learning_plans(id) on delete cascade,
  policy_version text not null default 'choice_8_3_30_v1' check(policy_version='choice_8_3_30_v1'),
  grade_band text not null check(grade_band in ('高一','高二','高三')),
  source_release_ids uuid[] not null check(cardinality(source_release_ids)>0),
  preferred_base_ids text[] not null check(cardinality(preferred_base_ids)=8),
  authorized_base_pool_ids text[] not null check(cardinality(authorized_base_pool_ids) between 8 and 1000),
  focus_skill_ids text[] not null check(cardinality(focus_skill_ids)>0),
  authorized_skill_ids text[] not null check(cardinality(authorized_skill_ids)>0),
  repetition_policy text not null default 'spaced_review' check(repetition_policy='spaced_review'),
  allow_advance_study boolean not null default false,
  source_note text not null check(length(btrim(source_note))>0),
  created_at timestamptz not null default now()
);
create table app_private.chem_choice_training_sessions (
  plan_id uuid primary key references app_private.chem_choice_training_policy(plan_id),
  student_id uuid not null references public.chem_students_v2(id),
  status text not null default 'active' check(status in ('active','completed')),
  base_question_ids text[] not null check(cardinality(base_question_ids)=8),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  attempt_id uuid references public.chem_learning_attempts(id)
);
create table app_private.chem_choice_training_branches (
  plan_id uuid not null references app_private.chem_choice_training_sessions(plan_id),
  anchor_question_id text not null,
  recovery_round smallint not null check(recovery_round between 1 and 3),
  anchor_revision_token text not null,
  option_index smallint not null check(option_index between 0 and 3),
  knowledge_point text not null,
  binding_snapshot jsonb not null,
  candidates jsonb not null check(jsonb_typeof(candidates)='array' and jsonb_array_length(candidates) between 3 and 5),
  created_at timestamptz not null default now(),
  primary key(plan_id,anchor_question_id)
);
create table app_private.chem_choice_training_issued (
  plan_id uuid not null references app_private.chem_choice_training_sessions(plan_id),
  question_id text not null,
  sequence smallint not null check(sequence between 1 and 30),
  recovery_round smallint not null check(recovery_round between 0 and 3),
  anchor_question_id text,
  question_snapshot jsonb not null,
  learning_purpose text not null check(learning_purpose in ('first_learning','spaced_review','targeted_practice')),
  repetition_evidence jsonb not null default '{}',
  created_at timestamptz not null default now(),
  primary key(plan_id,question_id), unique(plan_id,sequence)
);
create index chem_choice_training_sessions_student_idx on app_private.chem_choice_training_sessions(student_id);
alter table app_private.chem_choice_training_policy enable row level security;
alter table app_private.chem_choice_training_sessions enable row level security;
alter table app_private.chem_choice_training_branches enable row level security;
alter table app_private.chem_choice_training_issued enable row level security;
revoke all on app_private.chem_choice_training_policy,app_private.chem_choice_training_sessions,
  app_private.chem_choice_training_branches,app_private.chem_choice_training_issued from public,anon,authenticated,service_role;

-- Same source identities are retained, including the independent parent.
-- Legacy rows without a canonical parent are conservatively grouped by their
-- reviewed exam/year + original top-level question number. This deduplication
-- key is not written back or represented as a new source identity. Generic old
-- titles can merge more than one book; that reduces supply rather than inventing
-- independent parents. Subquestions such as 11(1)/11(2) stay together.
create function app_private.chem_choice_parent_identity(p_question jsonb)
returns text language sql immutable set search_path='' as $fn$
 select coalesce(nullif(p_question->>'parent_source_item_key',''),case
   when coalesce(p_question#>>'{source_info,sourceSha256}',p_question#>>'{source_info,sourceFileHash}','') ~ '^[0-9a-fA-F]{64}$'
    and p_question#>>'{source_info,questionNo}' ~ '^[0-9]+'
   then 'legacy-file:'||lower(coalesce(p_question#>>'{source_info,sourceSha256}',p_question#>>'{source_info,sourceFileHash}'))||':'||
     substring(p_question#>>'{source_info,questionNo}' from '^[0-9]+')
   when nullif(p_question#>>'{source_info,exam}','') is not null
    and p_question#>>'{source_info,questionNo}' ~ '^[0-9]+'
   then 'legacy:'||(p_question#>>'{source_info,exam}')||':'||coalesce(p_question#>>'{source_info,year}','')||':'||
     substring(p_question#>>'{source_info,questionNo}' from '^[0-9]+') end);
$fn$;
create function app_private.chem_choice_identities(p_question jsonb)
returns text[] language sql immutable set search_path='' as $fn$
 select array_remove(array[
   case when nullif(p_question->>'id','') is not null then 'id:'||(p_question->>'id') end,
   case when nullif(p_question->>'mother_id','') is not null then 'mother:'||(p_question->>'mother_id') end,
   case when nullif(p_question->>'source_item_key','') is not null then 'source:'||(p_question->>'source_item_key') end,
   case when app_private.chem_choice_parent_identity(p_question) is not null then 'parent:'||app_private.chem_choice_parent_identity(p_question) end,
   case when nullif(p_question->>'content_fingerprint','') is not null then 'fingerprint:'||(p_question->>'content_fingerprint') end
 ],null);
$fn$;

create function app_private.chem_choice_repetition_state(p_question jsonb,p_history jsonb,p_today date)
returns jsonb language plpgsql immutable set search_path='' as $fn$
declare h jsonb; matches jsonb:='[]'; last_day date; last_bad date; streak integer; gap integer; due date;
begin
 for h in select value from jsonb_array_elements(p_history) loop
   if app_private.chem_choice_identities(p_question) && app_private.chem_choice_identities(h) then
     if h->>'pending'='true' or (h->>'study_date')::date=p_today then
       return jsonb_build_object('eligible',false,'kind','same_day_or_pending');
     end if;
     if h->>'answered_at' is not null then matches:=matches||jsonb_build_array(h); end if;
   end if;
 end loop;
 select max((v->>'study_date')::date),max((v->>'study_date')::date)
   filter(where v->>'correct' is distinct from 'true' or v->>'uncertain' is distinct from 'false')
 into last_day,last_bad from jsonb_array_elements(matches) v;
 if last_day is null then return jsonb_build_object('eligible',true,'kind','fresh'); end if;
 if last_bad=last_day then gap:=1;
 else
   select count(distinct (v->>'study_date')::date) into streak from jsonb_array_elements(matches) v
   where v->>'correct'='true' and v->>'uncertain'='false'
     and (last_bad is null or (v->>'study_date')::date>last_bad);
   gap:=case when streak>=5 then 30 when streak=4 then 14 when streak=3 then 7 when streak=2 then 3 else 1 end;
 end if;
 due:=last_day+gap;
 return jsonb_build_object('eligible',p_today>=due,'kind',case when p_today>=due then 'due_review' else 'not_due' end,
   'lastAnsweredDate',last_day,'reviewDueDate',due,'intervalDays',gap);
end;
$fn$;

-- Completed attempts plus unfinished immutable first-answer locks, deduplicated.
-- Excluding this plan is solely for resuming its already-frozen issuance.
create function app_private.chem_choice_history(p_student_id uuid,p_exclude_plan_id uuid)
returns jsonb language sql stable security definer set search_path='' as $fn$
 select coalesce(jsonb_agg(x.row),'[]') from (
   select jsonb_build_object('id',aa.question_id,'mother_id',coalesce(aa.question_snapshot->>'motherId',aa.mother_id),
     'source_item_key',coalesce(aa.question_snapshot->>'sourceItemKey',q.source_item_key),
     'parent_source_item_key',coalesce(aa.question_snapshot->>'parentSourceItemKey',q.parent_source_item_key),
     'content_fingerprint',coalesce(aa.question_snapshot->>'contentFingerprint',q.content_fingerprint),
     'source_info',coalesce(aa.question_snapshot->'sourceInfo',q.source_info),
     'study_date',(aa.created_at at time zone 'Asia/Shanghai')::date,'answered_at',aa.created_at,
     'correct',aa.correct,'uncertain',aa.uncertain,'pending',false) row
   from public.chem_attempt_answers aa join public.chem_learning_attempts a on a.id=aa.attempt_id
   left join public.chem_questions q on q.id=aa.question_id
   where a.student_id=p_student_id and a.plan_day_id is distinct from p_exclude_plan_id
   union all
   select coalesce(i.question_snapshot,to_jsonb(q)) || jsonb_build_object(
     'study_date',(l.created_at at time zone 'Asia/Shanghai')::date,'answered_at',l.created_at,'pending',false,
     'correct',l.selected_option=coalesce((i.question_snapshot->>'correct_option')::integer,q.correct_option)
       and l.revision_token=coalesce(i.question_snapshot->>'question_revision_token',q.question_revision_token),
     'uncertain',l.uncertain or l.revision_token is distinct from coalesce(i.question_snapshot->>'question_revision_token',q.question_revision_token))
   from app_private.chem_question_answer_locks l join public.chem_questions q on q.id=l.question_id
   left join app_private.chem_choice_training_issued i on i.plan_id=l.plan_day_id and i.question_id=l.question_id
   where l.student_id=p_student_id and l.plan_day_id is distinct from p_exclude_plan_id
     and not exists(select 1 from public.chem_learning_attempts a join public.chem_attempt_answers aa on aa.attempt_id=a.id
       and aa.question_id=l.question_id where a.student_id=l.student_id and a.plan_day_id=l.plan_day_id and a.sequence=l.attempt_sequence)
   union all
   select i.question_snapshot || jsonb_build_object('study_date',(i.created_at at time zone 'Asia/Shanghai')::date,
     'answered_at',null,'pending',true)
   from app_private.chem_choice_training_issued i join app_private.chem_choice_training_sessions s on s.plan_id=i.plan_id
   where s.student_id=p_student_id and s.status='active' and i.plan_id is distinct from p_exclude_plan_id
     and not exists(select 1 from app_private.chem_question_answer_locks l where l.student_id=s.student_id
       and l.plan_day_id=i.plan_id and l.attempt_sequence=0 and l.question_id=i.question_id)
 ) x;
$fn$;

create function app_private.chem_choice_assert_plan(p_student_id uuid,p_plan_id uuid)
returns app_private.chem_choice_training_policy language plpgsql stable security definer set search_path='' as $fn$
declare p public.chem_learning_plans; s public.chem_students_v2; c app_private.chem_choice_training_policy; program jsonb;
begin
 select * into c from app_private.chem_choice_training_policy where plan_id=p_plan_id;
 if not found then raise exception 'choice_policy_not_found'; end if;
 select * into p from public.chem_learning_plans where id=p_plan_id and student_id=p_student_id;
 select * into s from public.chem_students_v2 where id=p_student_id and record_status='active';
 if p.id is null or s.id is null or s.grade_band<>c.grade_band or s.metadata->'demo'='true'::jsonb
   or p.mode<>'REVIEW' or p.delivery_mode<>'legacy_round' or not p.is_scheduled or p.teaching_managed
   or p.question_count<>8 or p.round_limit<>1 or not(p.skill_ids<@c.authorized_skill_ids)
 then raise exception 'choice_plan_not_available'; end if;
 program:=s.metadata->'reviewProgram';
 if jsonb_typeof(program)<>'object' or program->'participating' is distinct from 'true'::jsonb
   or coalesce(program->>'startDate','') !~ '^\d{4}-\d{2}-\d{2}$'
   or coalesce(program->>'endDate','') !~ '^\d{4}-\d{2}-\d{2}$'
   or p.plan_date::text<program->>'startDate' or p.plan_date::text>program->>'endDate'
 then raise exception 'choice_outside_program'; end if;
 if p.plan_date>(now() at time zone 'Asia/Shanghai')::date and not c.allow_advance_study then
   raise exception 'choice_future_plan_not_open'; end if;
 return c;
end;
$fn$;

create function app_private.chem_choice_policy_guard()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare p public.chem_learning_plans; s public.chem_students_v2; n integer;
begin
 if tg_op<>'INSERT' and (exists(select 1 from app_private.chem_choice_training_sessions where plan_id=old.plan_id)
   or exists(select 1 from public.chem_learning_attempts where plan_day_id=old.plan_id)
   or exists(select 1 from app_private.chem_question_answer_locks where plan_day_id=old.plan_id)) then
   raise exception 'choice_started_policy_immutable';
 end if;
 if tg_op='DELETE' then return old; end if;
 select * into p from public.chem_learning_plans where id=new.plan_id;
 select * into s from public.chem_students_v2 where id=p.student_id;
 if p.id is null or s.record_status<>'active' or s.grade_band<>new.grade_band or s.metadata->'demo'='true'::jsonb
   or p.mode<>'REVIEW' or p.delivery_mode<>'legacy_round' or p.question_count<>8 or p.round_limit<>1 or p.teaching_managed
   or exists(select 1 from public.chem_learning_attempts where plan_day_id=p.id)
   or exists(select 1 from app_private.chem_question_answer_locks where plan_day_id=p.id)
   or not(new.preferred_base_ids<@new.authorized_base_pool_ids)
   or not(new.focus_skill_ids<@new.authorized_skill_ids)
   or not(p.skill_ids<@new.authorized_skill_ids)
   or cardinality(new.source_release_ids)<>(select count(distinct v) from unnest(new.source_release_ids) v)
   or cardinality(new.preferred_base_ids)<>(select count(distinct v) from unnest(new.preferred_base_ids) v)
   or cardinality(new.authorized_base_pool_ids)<>(select count(distinct v) from unnest(new.authorized_base_pool_ids) v)
 then raise exception 'choice_policy_invalid_or_legacy_started'; end if;
 select count(*) into n from public.chem_questions q
   join public.chem_teaching_ready_question_ids(new.grade_band,new.authorized_base_pool_ids) ready on ready.question_id=q.id
   where q.id=any(new.authorized_base_pool_ids) and q.grade_band=new.grade_band
     and q.source_release_id=any(new.source_release_ids) and q.skill_id=any(new.authorized_skill_ids)
     and q.source_kind='licensed_local' and q.render_mode='image_primary'
     and nullif(q.mother_id,'') is not null and app_private.chem_choice_parent_identity(to_jsonb(q)) is not null
     and (p.max_question_level is null or q.level<=p.max_question_level);
 if n<>cardinality(new.authorized_base_pool_ids) then raise exception 'choice_policy_source_not_ready'; end if;
 return new;
end;
$fn$;
create trigger chem_choice_policy_guard before insert or update or delete on app_private.chem_choice_training_policy
for each row execute function app_private.chem_choice_policy_guard();

-- Reuse the existing unified reservation ledger and student row lock. Its event
-- key is identical to first-answer locks/finalized answers, so retries cost zero.
create or replace function app_private.chem_junior_budget_enabled(p_student_id uuid)
returns boolean language sql stable set search_path='' as $fn$
 select exists(select 1 from public.chem_students_v2 s where s.id=p_student_id and s.record_status='active'
   and ((s.grade_band='初三' and exists(select 1 from public.chem_learning_plans p where p.student_id=s.id
     and p.delivery_mode='junior_adaptive' and p.question_count=8 and p.round_limit=4))
   or exists(select 1 from app_private.chem_choice_training_policy c join public.chem_learning_plans p on p.id=c.plan_id
     where p.student_id=s.id and c.grade_band=s.grade_band)));
$fn$;

-- One read-only projection powers real issuance and teacher simulation. It
-- accepts virtual first answers but can neither update the ledger nor save them.
create function app_private.chem_choice_projection(p_student_id uuid,p_plan_id uuid,p_preview_answers jsonb default null)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
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
       order by coalesce(array_position(c.preferred_base_ids,e.key),1001),
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
     if cardinality(base_ids)<>8 then pending_reason:='base_source_gap'; questions:='[]'; base_ids:='{}'; end if;
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
           where not answers ? (candidate_entry->>'questionId')) and not exists(
             select 1 from app_private.chem_option_practice_bindings current_binding
             where current_binding.anchor_question_id=current_anchor and current_binding.option_index=(a->>'selected_option')::integer
               and current_binding.review_status='verified' and to_jsonb(current_binding)=binding) then
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
           'knowledgePoint',coalesce(binding->>'knowledge_point',''),'skillId',anchor->>'skill_id','conceptKey',anchor->>'concept_key',
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
$fn$;

create function app_private.chem_choice_write_locks(p_student_id uuid,p_plan_id uuid)
returns void language plpgsql security definer set search_path='' as $fn$
begin
 perform pg_advisory_xact_lock(hashtextextended('chem-source-original-release',0));
 perform pg_advisory_xact_lock(hashtextextended('chem-h3-original-release',0));
 perform pg_advisory_xact_lock(hashtextextended('chem-review-suffix:'||p_student_id::text,0));
 perform id from public.chem_students_v2 where id=p_student_id for update;
 perform id from public.chem_learning_plans where id=p_plan_id and student_id=p_student_id for update;
 perform app_private.chem_choice_assert_plan(p_student_id,p_plan_id);
end;
$fn$;

create function public.chem_choice_training_policy(p_plan_id uuid)
returns jsonb language sql stable security definer set search_path='' as $fn$
 select to_jsonb(c) from app_private.chem_choice_training_policy c where c.plan_id=p_plan_id;
$fn$;
create function public.chem_choice_training_policies(p_student_id uuid)
returns table(plan_id uuid,policy_version text,allow_advance_study boolean)
language sql stable security definer set search_path='' as $fn$
 select c.plan_id,c.policy_version,c.allow_advance_study
 from app_private.chem_choice_training_policy c join public.chem_learning_plans p on p.id=c.plan_id
 join public.chem_students_v2 s on s.id=p.student_id
 where s.id=p_student_id and s.record_status='active' order by p.plan_date,p.id;
$fn$;
create function public.chem_choice_training_context(p_student_id uuid,p_plan_id uuid,p_preview_answers jsonb default null)
returns jsonb language sql stable security definer set search_path='' as $fn$
 select app_private.chem_choice_projection(p_student_id,p_plan_id,p_preview_answers);
$fn$;

create function app_private.chem_choice_sync(p_student_id uuid,p_plan_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare ctx jsonb; q jsonb; b jsonb; current_binding jsonb; n integer:=0; used_count integer; started timestamptz;
begin
 -- Caller already owns source -> suffix -> student -> plan locks.
 ctx:=app_private.chem_choice_projection(p_student_id,p_plan_id,null);
 if ctx->>'status'='completed' then return ctx; end if;
 if jsonb_array_length(ctx->'baseQuestionIds')<>8 then return ctx; end if;
 if ctx->>'pendingReason'='source_changed' then return ctx; end if;
 if ctx->>'pendingReason'='daily_limit' and coalesce((ctx->>'projectedAdditionalCost')::integer,0)>
     greatest(0,30-(ctx->>'dailyUsed')::integer) then return ctx; end if;
 insert into app_private.chem_choice_training_sessions(plan_id,student_id,base_question_ids)
 values(p_plan_id,p_student_id,array(select jsonb_array_elements_text(ctx->'baseQuestionIds')))
 on conflict(plan_id) do nothing;
 for b in select value from jsonb_array_elements(ctx->'branches') where value ? '_binding' loop
   select to_jsonb(binding) into current_binding from app_private.chem_option_practice_bindings binding
   where binding.anchor_question_id=b->>'anchorQuestionId' and binding.option_index=(b->>'anchorOptionIndex')::integer
   for share;
   if not exists(select 1 from app_private.chem_choice_training_branches old
       where old.plan_id=p_plan_id and old.anchor_question_id=b->>'anchorQuestionId') then
     if current_binding is distinct from b->'_binding' or current_binding->>'review_status'<>'verified' then
       raise exception 'choice_binding_changed'; end if;
     insert into app_private.chem_choice_training_branches(plan_id,anchor_question_id,recovery_round,
       anchor_revision_token,option_index,knowledge_point,binding_snapshot,candidates)
     values(p_plan_id,b->>'anchorQuestionId',(b->>'recoveryRound')::smallint,
       current_binding->>'anchor_revision_token',(b->>'anchorOptionIndex')::smallint,b->>'knowledgePoint',current_binding,b->'_candidates');
   end if;
 end loop;
 for q in select value from jsonb_array_elements(ctx->'questions') loop
   n:=n+1;
   if not exists(select 1 from app_private.chem_question_answer_locks l where l.student_id=p_student_id
     and l.plan_day_id=p_plan_id and l.attempt_sequence=0 and l.question_id=q->>'id') then
     perform app_private.chem_junior_reserve_daily_question(p_student_id,'answer:'||p_plan_id::text||':0:'||(q->>'id'));
   end if;
   insert into app_private.chem_choice_training_issued(plan_id,question_id,sequence,recovery_round,anchor_question_id,
     question_snapshot,learning_purpose,repetition_evidence)
   values(p_plan_id,q->>'id',n,(q#>>'{choiceContext,recoveryRound}')::smallint,q#>>'{choiceContext,anchorId}',q,
     q#>>'{choiceContext,learningPurpose}',q->'choiceContext') on conflict(plan_id,question_id) do nothing;
 end loop;
 select count(*) into used_count from app_private.chem_junior_daily_budget_keys(p_student_id);
 select started_at into started from app_private.chem_choice_training_sessions where plan_id=p_plan_id;
 return ctx||jsonb_build_object('dailyUsed',used_count,'dailyRemaining',greatest(0,30-used_count),
   'projectedAdditionalCost',0,'persisted',true,'status','active','startedAt',started);
end;
$fn$;

create function public.chem_choice_training_open(p_student_id uuid,p_plan_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $fn$
begin
 perform app_private.chem_choice_write_locks(p_student_id,p_plan_id);
 return app_private.chem_choice_sync(p_student_id,p_plan_id);
end;
$fn$;

-- Existing service RPCs remain valid for legacy plans; new-policy writes must
-- pass the ordered frozen-issuance wrapper, including retry/first-answer rules.
create function app_private.chem_choice_answer_guard()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare expected text;
begin
 if not exists(select 1 from app_private.chem_choice_training_policy where plan_id=new.plan_day_id) then return new; end if;
 if current_setting('app.choice_answer_plan',true) is distinct from new.plan_day_id::text or new.attempt_sequence<>0 then
   raise exception 'choice_answer_requires_training_rpc'; end if;
 select i.question_id into expected from app_private.chem_choice_training_issued i
 where i.plan_id=new.plan_day_id and not exists(select 1 from app_private.chem_question_answer_locks l
   where l.student_id=new.student_id and l.plan_day_id=new.plan_day_id and l.attempt_sequence=0 and l.question_id=i.question_id)
 order by i.sequence limit 1;
 if expected is distinct from new.question_id then raise exception 'choice_answer_out_of_order'; end if;
 return new;
end;
$fn$;
create trigger chem_choice_answer_guard before insert on app_private.chem_question_answer_locks
for each row execute function app_private.chem_choice_answer_guard();

create function public.chem_choice_training_lock_answer(p_student_id uuid,p_plan_id uuid,p_question_id text,
 p_revision_token text,p_selected_option integer,p_uncertain boolean,p_duration_sec integer)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare ctx jsonb; q jsonb; locked app_private.chem_question_answer_locks; expected text; replayed boolean:=false;
begin
 if p_selected_option not between 0 and 3 or p_selected_option is null or p_uncertain is null
   or p_duration_sec not between 0 and 3600 or p_duration_sec is null or coalesce(p_revision_token,'')='' then
   raise exception 'choice_answer_invalid'; end if;
 perform app_private.chem_choice_write_locks(p_student_id,p_plan_id);
 select * into locked from app_private.chem_question_answer_locks l where l.student_id=p_student_id
   and l.plan_day_id=p_plan_id and l.attempt_sequence=0 and l.question_id=p_question_id;
 if locked.question_id is null then
   select a.question_id,a.selected_option,a.uncertain,a.duration_sec,a.question_snapshot->>'revisionToken'
   into locked.question_id,locked.selected_option,locked.uncertain,locked.duration_sec,locked.revision_token
   from app_private.chem_choice_training_sessions s join public.chem_attempt_answers a on a.attempt_id=s.attempt_id
   where s.plan_id=p_plan_id and s.student_id=p_student_id and s.status='completed' and a.question_id=p_question_id;
 end if;
 select question_snapshot into q from app_private.chem_choice_training_issued where plan_id=p_plan_id and question_id=p_question_id;
 if locked.question_id is not null then
   if q is null or locked.selected_option<>p_selected_option or locked.uncertain<>p_uncertain
     or locked.revision_token is distinct from p_revision_token then raise exception 'choice_first_answer_immutable'; end if;
   replayed:=true;
 else
   if exists(select 1 from app_private.chem_choice_training_sessions where plan_id=p_plan_id and status='completed') then
     raise exception 'choice_session_completed'; end if;
   select i.question_id into expected from app_private.chem_choice_training_issued i
   where i.plan_id=p_plan_id and not exists(select 1 from app_private.chem_question_answer_locks l
     where l.student_id=p_student_id and l.plan_day_id=p_plan_id and l.attempt_sequence=0 and l.question_id=i.question_id)
   order by i.sequence limit 1;
   if expected is distinct from p_question_id then raise exception 'choice_answer_out_of_order'; end if;
   select question_snapshot into q from app_private.chem_choice_training_issued where plan_id=p_plan_id and question_id=p_question_id;
   if q->>'question_revision_token' is distinct from p_revision_token then raise exception 'choice_revision_changed'; end if;
   if q#>>'{choiceContext,anchorId}' is not null and not exists(
     select 1 from app_private.chem_choice_training_branches b
     join app_private.chem_option_practice_bindings current_binding on current_binding.anchor_question_id=b.anchor_question_id
       and current_binding.option_index=b.option_index and current_binding.review_status='verified'
       and to_jsonb(current_binding)=b.binding_snapshot
     where b.plan_id=p_plan_id and b.anchor_question_id=q#>>'{choiceContext,anchorId}') then
     raise exception 'choice_binding_changed'; end if;
   perform set_config('app.choice_answer_plan',p_plan_id::text,true);
   perform public.chem_lock_question_answer(p_student_id,p_plan_id,0,p_question_id,p_selected_option,p_uncertain,p_duration_sec,p_revision_token);
   perform set_config('app.choice_answer_plan','',true);
   select * into locked from app_private.chem_question_answer_locks l where l.student_id=p_student_id
     and l.plan_day_id=p_plan_id and l.attempt_sequence=0 and l.question_id=p_question_id;
 end if;
 ctx:=app_private.chem_choice_sync(p_student_id,p_plan_id);
 return jsonb_build_object('feedback',jsonb_build_object('questionId',p_question_id,'selectedOption',locked.selected_option,
   'correctOption',(q->>'correct_option')::integer,'correct',locked.selected_option=(q->>'correct_option')::integer,
   'uncertain',locked.uncertain,'durationSec',locked.duration_sec,'revisionToken',locked.revision_token,
   'explanation',q->'explanation','scaffold',q->'scaffold','assetRefs',q->'asset_refs'),
   'context',ctx,'replayed',replayed);
end;
$fn$;

create function app_private.chem_choice_attempt_guard()
returns trigger language plpgsql security definer set search_path='' as $fn$
begin
 if exists(select 1 from app_private.chem_choice_training_policy where plan_id=new.plan_day_id)
   and current_setting('app.choice_finish_plan',true) is distinct from new.plan_day_id::text then
   raise exception 'choice_finish_requires_training_rpc'; end if;
 return new;
end;
$fn$;
create trigger chem_choice_attempt_guard before insert on public.chem_learning_attempts
for each row execute function app_private.chem_choice_attempt_guard();

create function public.chem_choice_training_finalize(p_student_id uuid,p_plan_id uuid,p_attempt_id uuid,p_skill_states jsonb)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare ctx jsonb; sess app_private.chem_choice_training_sessions; canonical jsonb:='[]';
 q jsonb; a jsonb; score integer:=0; snapshot jsonb; completed timestamptz:=clock_timestamp();
begin
 perform app_private.chem_choice_write_locks(p_student_id,p_plan_id);
 select * into sess from app_private.chem_choice_training_sessions where plan_id=p_plan_id;
 if sess.status='completed' then
   return jsonb_build_object('attemptId',sess.attempt_id,'completed',true,'replayed',true,
     'context',app_private.chem_choice_projection(p_student_id,p_plan_id,null));
 end if;
 ctx:=app_private.chem_choice_sync(p_student_id,p_plan_id);
 if ctx->>'complete' is distinct from 'true' then raise exception 'choice_training_not_finished'; end if;
 select * into sess from app_private.chem_choice_training_sessions where plan_id=p_plan_id;
 if jsonb_typeof(p_skill_states)<>'array' or jsonb_array_length(p_skill_states)<1
   or exists(select 1 from jsonb_array_elements(p_skill_states) s where s->>'student_id' is distinct from p_student_id::text
     or not exists(select 1 from jsonb_array_elements(ctx->'questions') question_entry where question_entry->>'skill_id'=s->>'skill_id')) then
   raise exception 'choice_skill_states_invalid'; end if;
 if exists(select 1 from jsonb_array_elements(p_skill_states) requested
   left join public.chem_student_skill_state current_state on current_state.student_id=p_student_id
     and current_state.skill_id=requested->>'skill_id'
   where not requested ? '_expected_updated_at'
     or (requested->>'_expected_updated_at')::timestamptz is distinct from current_state.updated_at) then
   raise exception 'choice_mastery_changed';
 end if;
 for q in select value from jsonb_array_elements(ctx->'questions') loop
   select value into a from jsonb_array_elements(ctx->'lockedAnswers') where value->>'question_id'=q->>'id';
   if a is null or a->>'revision_token' is distinct from q->>'question_revision_token' then raise exception 'choice_answer_snapshot_mismatch'; end if;
   snapshot:=jsonb_build_object('version',3,'source','submission','capturedAt',completed,'questionId',q->'id','motherId',q->'mother_id',
     'skillId',q->'skill_id','conceptKey',q->'concept_key','level',q->'level','gradeBand',q->'grade_band','stem',q->'stem',
     'options',q->'options','correctOption',q->'correct_option','explanation',q->'explanation','imageUrl',null,
     'sourceKind',q->'source_kind','sourceInfo',q->'source_info','assetRefs',q->'asset_refs','renderMode',q->'render_mode',
     'sourceItemKey',q->'source_item_key','parentSourceItemKey',q->'parent_source_item_key','contentFingerprint',q->'content_fingerprint',
     'revisionToken',q->'question_revision_token','reviewStatus',q->'review_status','scopeStatus',q->'scope_status',
     'optionPractice',q->'choiceContext','choiceContext',q->'choiceContext','choiceTrainingPolicy','choice_8_3_30_v1');
   canonical:=canonical||jsonb_build_array(jsonb_build_object('question_id',q->'id','mother_id',q->'mother_id','skill_id',q->'skill_id',
     'concept_key',q->'concept_key','level',q->'level','correct',a->'correct','uncertain',a->'uncertain','duration_sec',a->'duration_sec',
     'selected_option',a->'selected_option','revision_token',a->'revision_token','question_snapshot',snapshot));
   if a->>'correct'='true' then score:=score+1; end if;
 end loop;
 perform set_config('app.choice_finish_plan',p_plan_id::text,true);
 perform public.chem_finalize_learning_attempt(p_attempt_id,p_student_id,p_plan_id,'scheduled',0,'REVIEW',
   sess.started_at,completed,score,canonical,p_skill_states);
 perform set_config('app.choice_finish_plan','',true);
 update app_private.chem_choice_training_sessions set status='completed',completed_at=completed,attempt_id=p_attempt_id where plan_id=p_plan_id;
 return jsonb_build_object('attemptId',p_attempt_id,'completed',true,'replayed',false,
   'context',app_private.chem_choice_projection(p_student_id,p_plan_id,null));
end;
$fn$;

-- No browser role can invoke or mutate privileged training internals.
revoke all on function app_private.chem_choice_parent_identity(jsonb),app_private.chem_choice_identities(jsonb),
 app_private.chem_choice_repetition_state(jsonb,jsonb,date),app_private.chem_choice_history(uuid,uuid),
 app_private.chem_choice_assert_plan(uuid,uuid),app_private.chem_choice_policy_guard(),
 app_private.chem_choice_projection(uuid,uuid,jsonb),app_private.chem_choice_write_locks(uuid,uuid),
 app_private.chem_choice_sync(uuid,uuid),app_private.chem_choice_answer_guard(),app_private.chem_choice_attempt_guard()
 from public,anon,authenticated,service_role;
revoke all on function public.chem_choice_training_policy(uuid),public.chem_choice_training_context(uuid,uuid,jsonb),
 public.chem_choice_training_policies(uuid),
 public.chem_choice_training_open(uuid,uuid),public.chem_choice_training_lock_answer(uuid,uuid,text,text,integer,boolean,integer),
 public.chem_choice_training_finalize(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.chem_choice_training_policy(uuid),public.chem_choice_training_context(uuid,uuid,jsonb),
 public.chem_choice_training_policies(uuid),
 public.chem_choice_training_open(uuid,uuid),public.chem_choice_training_lock_answer(uuid,uuid,text,text,integer,boolean,integer),
 public.chem_choice_training_finalize(uuid,uuid,uuid,jsonb) to service_role;
