begin;

-- Opt-in policy; old session/plan contracts and immutable answer history survive.
alter table public.chem_junior_daily_sessions add column recovery_round_limit smallint not null default 0;
alter table public.chem_junior_daily_sessions
  drop constraint chem_junior_daily_sessions_initial_question_target_check,
  drop constraint chem_junior_daily_sessions_hard_question_cap_check,
  add constraint chem_junior_daily_sessions_practice_policy_check check (
    (initial_question_target=12 and hard_question_cap=15 and recovery_round_limit=0)
    or (initial_question_target=8 and hard_question_cap=30 and recovery_round_limit=3)
  );
alter table public.chem_learning_plans drop constraint chem_learning_plans_question_count_check;
alter table public.chem_learning_plans add constraint chem_learning_plans_question_count_check check (
  (delivery_mode in ('legacy_round','self_study') and question_count between 1 and 10)
  or (delivery_mode='junior_adaptive' and ((question_count=12 and round_limit=1) or (question_count=8 and round_limit=4)))
);
alter table public.chem_junior_session_steps
  add column practice_round smallint not null default 0 check(practice_round between 0 and 3),
  drop constraint chem_junior_session_steps_sequence_check,
  add constraint chem_junior_session_steps_sequence_check check(sequence between 1 and 30);
alter table app_private.chem_junior_option_branches add column recovery_round smallint not null default 1 check(recovery_round between 1 and 3);

-- Budget entries survive first-answer-lock cleanup. Reserving a question and
-- persisting its step/answer share the same transaction, so failed RPCs cost zero.
create table app_private.chem_junior_daily_question_budget (
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  budget_date date not null,
  event_key text not null,
  created_at timestamptz not null default now(),
  primary key(student_id,budget_date,event_key)
);
alter table app_private.chem_junior_daily_question_budget enable row level security;
revoke all on app_private.chem_junior_daily_question_budget from public,anon,authenticated,service_role;

create function app_private.chem_junior_budget_enabled(p_student_id uuid)
returns boolean language sql stable set search_path='' as $fn$
  select exists(select 1 from public.chem_students_v2 s
    join public.chem_learning_plans p on p.student_id=s.id
    where s.id=p_student_id and s.grade_band='初三' and s.record_status='active'
      and p.delivery_mode='junior_adaptive' and p.question_count=8 and p.round_limit=4);
$fn$;

create function app_private.chem_junior_daily_budget_keys(p_student_id uuid)
returns table(event_key text) language sql volatile set search_path='' as $fn$
  select b.event_key from app_private.chem_junior_daily_question_budget b
    where b.student_id=p_student_id and b.budget_date=(now() at time zone 'Asia/Shanghai')::date
  union
  select 'junior:'||st.session_id::text||':'||st.sequence::text
    from public.chem_junior_session_steps st join public.chem_junior_daily_sessions s on s.id=st.session_id
    where s.student_id=p_student_id and ((st.created_at at time zone 'Asia/Shanghai')::date=(now() at time zone 'Asia/Shanghai')::date
      or (st.answered_at at time zone 'Asia/Shanghai')::date=(now() at time zone 'Asia/Shanghai')::date)
  union
  select 'answer:'||l.plan_day_id::text||':'||l.attempt_sequence::text||':'||l.question_id
    from app_private.chem_question_answer_locks l where l.student_id=p_student_id
      and (l.created_at at time zone 'Asia/Shanghai')::date=(now() at time zone 'Asia/Shanghai')::date
  union
  select 'answer:'||a.plan_day_id::text||':'||a.sequence::text||':'||aa.question_id
    from public.chem_attempt_answers aa join public.chem_learning_attempts a on a.id=aa.attempt_id
    where a.student_id=p_student_id and a.junior_session_id is null
      and (aa.created_at at time zone 'Asia/Shanghai')::date=(now() at time zone 'Asia/Shanghai')::date;
$fn$;

create function app_private.chem_junior_reserve_daily_question(p_student_id uuid,p_event_key text)
returns void language plpgsql set search_path='' as $fn$
begin
  if not app_private.chem_junior_budget_enabled(p_student_id) then return; end if;
  -- Same row lock order for all sessions and every answer path.
  perform id from public.chem_students_v2 where id=p_student_id for update;
  if not exists(select 1 from app_private.chem_junior_daily_budget_keys(p_student_id) b where b.event_key=p_event_key)
    and (select count(*) from app_private.chem_junior_daily_budget_keys(p_student_id))>=30 then
    raise exception 'junior_daily_question_limit' using errcode='P0001';
  end if;
  insert into app_private.chem_junior_daily_question_budget(student_id,budget_date,event_key)
    values(p_student_id,(now() at time zone 'Asia/Shanghai')::date,p_event_key) on conflict do nothing;
end;
$fn$;

-- Existing normal/self-study answers participate in the same budget.
create function app_private.chem_junior_answer_budget_guard()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare a public.chem_learning_attempts%rowtype;
begin
  if tg_table_name='chem_question_answer_locks' then
    perform app_private.chem_junior_reserve_daily_question(new.student_id,
      'answer:'||new.plan_day_id::text||':'||new.attempt_sequence::text||':'||new.question_id);
  else
    select * into a from public.chem_learning_attempts where id=new.attempt_id;
    if a.junior_session_id is null then
      perform app_private.chem_junior_reserve_daily_question(a.student_id,
        'answer:'||a.plan_day_id::text||':'||a.sequence::text||':'||new.question_id);
    end if;
  end if;
  return new;
end;
$fn$;
create trigger chem_junior_answer_budget_guard before insert on app_private.chem_question_answer_locks
  for each row execute function app_private.chem_junior_answer_budget_guard();
create trigger chem_junior_answer_budget_guard before insert on public.chem_attempt_answers
  for each row execute function app_private.chem_junior_answer_budget_guard();
revoke all on function app_private.chem_junior_budget_enabled(uuid),
  app_private.chem_junior_daily_budget_keys(uuid),
  app_private.chem_junior_reserve_daily_question(uuid,text),
  app_private.chem_junior_answer_budget_guard() from public,anon,authenticated,service_role;

-- Keep every existing source-rights, provenance, card and exact-snapshot guard.
-- The substitutions are checked against the live function text, failing closed
-- if another migration changed a contract before this one is applied.
do $patch$
declare fn text; nm text; before_text text;
begin
  foreach nm in array array['chem_junior_issue_step','chem_junior_record_step','chem_junior_validate_issued_step','chem_junior_finalize_session'] loop
    select pg_get_functiondef(p.oid) into fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=nm;
    if fn is null or position('and plan.round_limit = 1' in fn)=0 then raise exception 'junior policy patch: unexpected % definition',nm; end if;
    fn:=replace(fn,E'\r\n',E'\n');
    fn:=replace(fn,'and plan.round_limit = 1','and plan.round_limit = 1 + v_session.recovery_round_limit');
    if nm='chem_junior_issue_step' then
      if position('p_sequence not between 1 and 15' in fn)=0 then raise exception 'junior sequence patch point missing'; end if;
      fn:=replace(fn,'p_sequence not between 1 and 15','p_sequence not between 1 and 30');
      fn:=replace(fn,'    question_snapshot'||chr(10),'    practice_round,'||chr(10)||'    question_snapshot'||chr(10));
      fn:=replace(fn,'    v_snapshot'||chr(10),'    coalesce(nullif(pg_catalog.current_setting(''app.chem_junior_practice_round'',true),''''),''0'')::smallint,'||chr(10)||'    v_snapshot'||chr(10));
      before_text:='  perform pg_catalog.set_config(''app.chem_junior_step_issue'', ''on'', true);';
      if position(before_text in fn)=0 then raise exception 'junior issue patch point missing'; end if;
      fn:=replace(fn,before_text,
        '  if v_session.recovery_round_limit=3 and p_sequence>v_session.initial_question_target and coalesce(nullif(pg_catalog.current_setting(''app.chem_junior_practice_round'',true),''''),''0'')::integer=0 then raise exception ''junior recovery must use the strict option queue''; end if;'||chr(10)||
        '  perform app_private.chem_junior_reserve_daily_question(p_student_id,''junior:''||p_session_id::text||'':''||p_sequence::text);'||chr(10)||before_text);
    end if;
    -- Source locks precede student lock, which precedes session/plan locks.
    before_text:='  select session.*';
    if position(before_text in fn)=0 then raise exception 'junior serialization patch point missing: %',nm; end if;
    fn:=replace(fn,before_text,'  perform s.id from public.chem_students_v2 s where s.id=p_student_id for update;'||chr(10)||before_text);
    if nm='chem_junior_record_step' then
      before_text:='  v_duration := least(3600, greatest(0, p_duration_sec));';
      if position(before_text in fn)=0 then raise exception 'junior answer budget patch point missing'; end if;
      fn:=replace(fn,before_text,'  perform app_private.chem_junior_reserve_daily_question(p_student_id,''junior:''||p_session_id::text||'':''||v_step.sequence::text);'||chr(10)||before_text);
    end if;
    if nm='chem_junior_validate_issued_step' then
      before_text:='  return query select v_step.id, v_question.id;';
      if position(before_text in fn)=0 then raise exception 'junior resume budget patch point missing'; end if;
      fn:=replace(fn,before_text,'  perform app_private.chem_junior_reserve_daily_question(p_student_id,''junior:''||p_session_id::text||'':''||v_step.sequence::text);'||chr(10)||before_text);
    end if;
    execute fn;
  end loop;

  select pg_get_functiondef('app_private.chem_guard_junior_session_step_mutation()'::regprocedure) into fn;
  fn:=replace(fn,'or new.sequence is distinct from old.sequence','or new.sequence is distinct from old.sequence'||chr(10)||'      or new.practice_round is distinct from old.practice_round');
  execute fn;

  -- Align the ordinary answer path before it obtains a plan row lock.
  select pg_get_functiondef('public.chem_lock_question_answer(uuid,uuid,integer,text,integer,boolean,integer,text)'::regprocedure) into fn;
  before_text:='  select * into v_plan from public.chem_learning_plans';
  if position(before_text in fn)=0 then raise exception 'normal answer budget serialization patch point missing'; end if;
  fn:=replace(fn,before_text,'  perform s.id from public.chem_students_v2 s where s.id=p_student_id for update;'||chr(10)||before_text);
  execute fn;

  select pg_get_functiondef('public.chem_finalize_learning_attempt(uuid,uuid,uuid,text,integer,text,timestamp with time zone,timestamp with time zone,integer,jsonb,jsonb)'::regprocedure) into fn;
  before_text:='  select teaching_managed,teaching_source_grade into v_managed,v_source_grade from public.chem_learning_plans';
  if position(before_text in fn)=0 then raise exception 'normal finalize budget serialization patch point missing'; end if;
  fn:=replace(fn,before_text,'  perform s.id from public.chem_students_v2 s where s.id=p_student_id for update;'||chr(10)||before_text);
  execute fn;
end;
$patch$;

CREATE OR REPLACE FUNCTION public.chem_junior_option_state(p_student_id uuid, p_session_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  sess public.chem_junior_daily_sessions%rowtype;
  anchor record; branch app_private.chem_junior_option_branches%rowtype;
  binding app_private.chem_option_practice_bindings%rowtype;
  candidate jsonb; q public.chem_questions%rowtype;
  chosen jsonb; n integer; good integer; has_error boolean; last_three_good boolean;
  target integer; issued_count integer; next_id text; next_revision text;
  result jsonb := '[]'; branch_status text; branch_reason text;
  daily_issued integer; ordinary_answered integer; new_policy boolean;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release',0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release',0));
  -- A student row serializes queue allocation across days/tabs before sessions.
  perform s.id from public.chem_students_v2 s where s.id=p_student_id and s.grade_band='初三'
    and s.record_status='active' and coalesce((s.metadata->>'demo')::boolean,false)=false for update;
  if not found then raise exception 'junior option student is not eligible'; end if;
  select * into sess from public.chem_junior_daily_sessions s where s.id=p_session_id and s.student_id=p_student_id for update;
  if not found then raise exception 'junior option session ownership mismatch'; end if;
  select count(*) into issued_count from public.chem_junior_session_steps s where s.session_id=p_session_id;

  select count(*) into daily_issued from app_private.chem_junior_daily_budget_keys(p_student_id);
  select count(*) into ordinary_answered from public.chem_junior_session_steps where session_id=p_session_id and practice_round=0 and answered_at is not null;
  new_policy:=sess.recovery_round_limit=3;

  -- Legacy reserves never recurse. New sessions recurse only through round 3.
  for anchor in select st.*,ds.recovery_round_limit from public.chem_junior_session_steps st
    join public.chem_junior_daily_sessions ds on ds.id=st.session_id
    where ds.student_id=p_student_id and ds.textbook_version=sess.textbook_version
      and st.answered_at is not null and (st.correct=false or (ds.recovery_round_limit=3 and st.uncertain))
      and ((ds.recovery_round_limit=0 and not exists(select 1 from app_private.chem_junior_option_steps os where os.step_id=st.id))
        or (ds.recovery_round_limit=3 and st.practice_round<3))
      and (new_policy or st.practice_round=0)
      and not exists(select 1 from app_private.chem_junior_option_branches b where b.anchor_step_id=st.id)
    order by st.answered_at,st.id
  loop
    insert into app_private.chem_junior_option_branches(student_id,anchor_step_id,anchor_session_id,anchor_question_id,anchor_revision_token,selected_option,knowledge_id,recovery_round)
    values(p_student_id,anchor.id,anchor.session_id,anchor.question_id,coalesce(anchor.question_snapshot->>'revisionToken',''),anchor.selected_option,anchor.knowledge_id,case when anchor.recovery_round_limit=3 then anchor.practice_round+1 else 1 end);
  end loop;

  for branch in select * from app_private.chem_junior_option_branches b where b.student_id=p_student_id order by case when new_policy then b.recovery_round else 1 end,b.created_at,b.id for update
  loop
    -- An empty gap may acquire a newly reviewed pool, but a nonempty pool is
    -- frozen for the lifetime of this first-option branch, including next day.
    if jsonb_array_length(branch.candidates)=0 and (not new_policy or ordinary_answered>=sess.initial_question_target) then
      select * into binding from app_private.chem_option_practice_bindings b
        where b.anchor_question_id=branch.anchor_question_id and b.option_index=branch.selected_option
          and b.anchor_revision_token=branch.anchor_revision_token and b.review_status='verified';
      chosen := '[]';
      if found then
        for candidate in select value from jsonb_array_elements(binding.candidates)
        loop
          select question.* into q from public.chem_questions question
            join app_private.chem_question_source_releases r on r.id=question.source_release_id and r.status='active'
              and r.verification_status='full_visual_verified' and r.revision_contract='v3_junior_native_text'
            join app_private.chem_junior_knowledge_provenance p on p.knowledge_id=question.knowledge_id
              and p.textbook_version=sess.textbook_version and p.source_release_id=r.id and p.verification_status='verified'
            where question.id=candidate->>'questionId' and question.question_revision_token=candidate->>'revisionToken'
              and question.grade_band='初三' and question.textbook_version=sess.textbook_version
              and question.source_kind='user_provided_local' and question.review_status='approved'
              and question.scope_status='IN' and question.usable_for_review and question.render_mode='native'
              and not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=question.id);
          if not found then continue; end if;
          if exists(select 1 from public.chem_junior_session_steps st join public.chem_junior_daily_sessions ds on ds.id=st.session_id
              where ds.student_id=p_student_id and (st.question_id=q.id or st.mother_id=q.mother_id or st.source_item_key=q.source_item_key or st.parent_source_item_key=q.parent_source_item_key or st.content_fingerprint=q.content_fingerprint))
            or exists(select 1 from jsonb_array_elements(chosen) c join public.chem_questions prior on prior.id=c->>'questionId'
              where prior.id=q.id or prior.mother_id=q.mother_id or prior.source_item_key=q.source_item_key or prior.parent_source_item_key=q.parent_source_item_key or prior.content_fingerprint=q.content_fingerprint)
            or exists(select 1 from app_private.chem_junior_option_branches other cross join lateral jsonb_array_elements(other.candidates) c
              join public.chem_questions reserved on reserved.id=c->>'questionId'
              where other.student_id=p_student_id and other.id<>branch.id and other.status in ('practicing','pending','reserve_gap')
                and (reserved.id=q.id or reserved.mother_id=q.mother_id or reserved.source_item_key=q.source_item_key or reserved.parent_source_item_key=q.parent_source_item_key or reserved.content_fingerprint=q.content_fingerprint))
          then continue; end if;
          chosen := chosen || jsonb_build_array(candidate);
        end loop;
        if jsonb_array_length(chosen)>=3 then
          update app_private.chem_junior_option_branches set candidates=chosen,binding_snapshot=to_jsonb(binding),knowledge_point=binding.knowledge_point,updated_at=now() where id=branch.id returning * into branch;
        end if;
      end if;
    end if;

    select count(*) filter(where st.answered_at is not null),count(*) filter(where st.correct=true and (not new_policy or not st.uncertain)),coalesce(bool_or((st.correct=false or (new_policy and st.uncertain)) and os.position<=3),false)
      into n,good,has_error from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id where os.branch_id=branch.id;
    select count(*)=3 and bool_and(t.correct) into last_three_good from (
      select st.correct and (not new_policy or not st.uncertain) as correct from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id
      where os.branch_id=branch.id and st.answered_at is not null order by os.position desc limit 3
    ) t;
    target := case when has_error then greatest(3,least(5,jsonb_array_length(branch.candidates))) else 3 end;
    next_id := null; next_revision := null;
    branch_status := 'practicing'; branch_reason := '';
    if new_policy and ordinary_answered<sess.initial_question_target and jsonb_array_length(branch.candidates)=0
      then branch_status:='pending'; branch_reason:='initial_round_in_progress';
    elsif jsonb_array_length(branch.candidates)<3 then branch_status:='reserve_gap'; branch_reason:='fewer_than_three_verified_fresh_originals';
    elsif n>=target then
      if last_three_good then branch_status:='consolidated';
      else branch_status:='needs_practice'; branch_reason:='reviewed_reserves_exhausted_without_three_consecutive_correct'; end if;
    else
      next_id:=branch.candidates->n->>'questionId'; next_revision:=branch.candidates->n->>'revisionToken';
      select * into q from public.chem_questions question where question.id=next_id;
      if not found or q.question_revision_token is distinct from next_revision or not q.usable_for_review
        or exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=next_id)
      then branch_status:='reserve_gap'; branch_reason:='reserved_original_unavailable';
      elsif not (q.knowledge_id=any(sess.knowledge_skill_ids)) then branch_status:='pending'; branch_reason:='waiting_for_compatible_curriculum';
      elsif new_policy and ordinary_answered<sess.initial_question_target then branch_status:='pending'; branch_reason:='initial_round_in_progress';
      elsif new_policy and exists(select 1 from jsonb_array_elements(result) prior where prior->>'status'='practicing' and (prior->>'recoveryRound')::integer<branch.recovery_round)
        then branch_status:='pending'; branch_reason:='waiting_for_previous_recovery_round';
      elsif sess.status<>'active' or issued_count>=sess.hard_question_cap or (app_private.chem_junior_budget_enabled(p_student_id) and daily_issued>=30) then branch_status:='pending'; branch_reason:='daily_limit_carry_forward';
      end if;
    end if;
    update app_private.chem_junior_option_branches set status=branch_status,reason=branch_reason,target_count=target,updated_at=now() where id=branch.id;
    result:=result||jsonb_build_array(jsonb_build_object('branchId',branch.id,'anchorStepId',branch.anchor_step_id,'anchorSessionId',branch.anchor_session_id,
      'recoveryRound',branch.recovery_round,'knowledgeId',branch.knowledge_id,'knowledgePoint',branch.knowledge_point,'optionIndex',branch.selected_option,
      'status',branch_status,'reason',branch_reason,'answered',n,'correct',good,'total',target,
      'candidates',branch.candidates,'nextQuestionId',next_id,'nextRevisionToken',next_revision));
  end loop;
  return jsonb_build_object('branches',result,'dailyIssuedCount',daily_issued,'dailyBudgetEnabled',app_private.chem_junior_budget_enabled(p_student_id),'pendingStepCountedToday',exists(select 1 from public.chem_junior_session_steps st join app_private.chem_junior_daily_budget_keys(p_student_id) k on k.event_key='junior:'||st.session_id::text||':'||st.sequence::text where st.session_id=p_session_id and st.answered_at is null),'stepContexts',coalesce((select jsonb_agg(jsonb_build_object('stepId',os.step_id,'branchId',os.branch_id,'position',os.position,'recoveryRound',st.practice_round)) from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id where st.session_id=p_session_id),'[]'::jsonb));
end; $function$
;

CREATE OR REPLACE FUNCTION public.chem_junior_issue_option_step(p_student_id uuid, p_session_id uuid, p_branch_id uuid, p_question_id text, p_sequence smallint, p_route_kind text, p_route_reason text, p_question_snapshot jsonb)
 RETURNS TABLE(step_id uuid, question_id text, sequence smallint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare state jsonb; branch jsonb; issued record; position integer; sess public.chem_junior_daily_sessions%rowtype; practice_round integer;
begin
  state:=public.chem_junior_option_state(p_student_id,p_session_id);
  select * into sess from public.chem_junior_daily_sessions where id=p_session_id and student_id=p_student_id;
  if app_private.chem_junior_budget_enabled(p_student_id) and (state->>'dailyIssuedCount')::integer>=30 then raise exception 'junior_daily_question_limit'; end if;
  -- Array order is the persistent oldest-first queue order, not a caller choice.
  select b into branch from jsonb_array_elements(state->'branches') with ordinality t(b,n) where b->>'status'='practicing' order by n limit 1;
  if p_branch_id is null then
    if sess.recovery_round_limit=3 and p_sequence>sess.initial_question_target then raise exception 'junior initial round is complete'; end if;
    perform pg_catalog.set_config('app.chem_junior_practice_round','0',true);
    if branch is not null then raise exception 'junior option queue advanced' using errcode='40001'; end if;
    if p_route_kind not in ('new_learning','stability_validation')
      or exists(select 1 from jsonb_array_elements(state->'branches') b cross join lateral jsonb_array_elements(b->'candidates') c
        join public.chem_questions reserved on reserved.id=c->>'questionId'
        join public.chem_questions requested on requested.id=p_question_id
        where b->>'status' in ('practicing','pending','reserve_gap') and (reserved.id=requested.id or reserved.mother_id=requested.mother_id
          or reserved.source_item_key=requested.source_item_key or reserved.parent_source_item_key=requested.parent_source_item_key or reserved.content_fingerprint=requested.content_fingerprint))
      or exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=p_question_id)
    then raise exception 'ordinary junior practice cannot substitute or consume a strict reserve'; end if;
    return query select * from public.chem_junior_issue_step(p_session_id,p_student_id,p_question_id,p_sequence,p_route_kind,p_route_reason,p_question_snapshot);
    return;
  end if;
  if branch is null or branch->>'branchId' is distinct from p_branch_id::text or branch->>'nextQuestionId' is distinct from p_question_id
    or branch->>'nextRevisionToken' is distinct from p_question_snapshot->>'revisionToken'
    or p_route_kind<>'foundation_repair' or p_route_reason is distinct from ('针对该选项考点的已审核原题补练：'||(branch->>'knowledgePoint'))
  then raise exception 'junior option issue is not the next frozen reserve'; end if;
  position:=(branch->>'answered')::integer+1;
  practice_round:=case when sess.recovery_round_limit=3 then (branch->>'recoveryRound')::integer else 0 end;
  if practice_round>sess.recovery_round_limit then raise exception 'junior recovery round limit reached'; end if;
  perform pg_catalog.set_config('app.chem_junior_practice_round',practice_round::text,true);
  select * into issued from public.chem_junior_issue_step(p_session_id,p_student_id,p_question_id,p_sequence,p_route_kind,p_route_reason,p_question_snapshot);
  perform pg_catalog.set_config('app.chem_junior_practice_round','0',true);
  insert into app_private.chem_junior_option_steps(step_id,branch_id,position) values(issued.step_id,p_branch_id,position);
  return query select issued.step_id,issued.question_id,issued.sequence;
end; $function$
;

-- Preview reads the stored queue and recomputes progress without creating a
-- branch, changing timestamps, or writing a practice/mastery record.
create function public.chem_junior_option_state_readonly(p_student_id uuid,p_session_id uuid,p_plan_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare sess public.chem_junior_daily_sessions%rowtype; plan public.chem_learning_plans%rowtype;
  result jsonb; daily_count integer; ordinary_count integer; issued_count integer;
begin
  if p_session_id is null then
    select p.* into plan from public.chem_learning_plans p join public.chem_students_v2 s on s.id=p.student_id
      where p.id=p_plan_id and p.student_id=p_student_id and p.delivery_mode='junior_adaptive'
        and p.plan_date<=(now() at time zone 'Asia/Shanghai')::date and p.mode='REVIEW'
        and ((p.question_count=8 and p.round_limit=4) or (p.question_count=12 and p.round_limit=1))
        and s.grade_band='初三' and s.record_status='active' and s.textbook_version='科粤版'
        and coalesce((s.metadata->>'demo')::boolean,false)=false;
    if not found then raise exception 'junior option preview plan ownership mismatch'; end if;
    -- This row exists only in memory. Previewing an unstarted plan never
    -- inserts a session or allocates question budget in the student's record.
    sess.id:=plan.id; sess.student_id:=p_student_id; sess.plan_day_id:=plan.id;
    sess.curriculum_day_id:=plan.junior_curriculum_day_id; sess.study_date:=plan.plan_date;
    sess.textbook_version:='科粤版'; sess.knowledge_skill_ids:=plan.skill_ids; sess.status:='active';
    sess.initial_question_target:=plan.question_count;
    sess.hard_question_cap:=case when plan.question_count=8 then 30 else 15 end;
    sess.recovery_round_limit:=case when plan.question_count=8 then 3 else 0 end;
  else
    select ds.* into sess from public.chem_junior_daily_sessions ds
      join public.chem_students_v2 s on s.id=ds.student_id
      where ds.id=p_session_id and ds.student_id=p_student_id and s.grade_band='初三' and s.record_status='active'
        and coalesce((s.metadata->>'demo')::boolean,false)=false;
    if not found then raise exception 'junior option preview ownership mismatch'; end if;
  end if;
  select count(*) into daily_count from app_private.chem_junior_daily_budget_keys(p_student_id);
  select count(*) into ordinary_count from public.chem_junior_session_steps where session_id=p_session_id and practice_round=0 and answered_at is not null;
  select count(*) into issued_count from public.chem_junior_session_steps where session_id=p_session_id;
  with facts as (
    select b.*,coalesce(x.n,0) n,coalesce(x.good,0) good,coalesce(x.has_error,false) has_error,
      coalesce(last_three.good,false) last_good
    from app_private.chem_junior_option_branches b
    left join lateral (select count(*) filter(where st.answered_at is not null) n,
      count(*) filter(where st.correct and (sess.recovery_round_limit=0 or not st.uncertain)) good,
      bool_or((not st.correct or (sess.recovery_round_limit=3 and st.uncertain)) and os.position<=3) has_error
      from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id where os.branch_id=b.id) x on true
    left join lateral (select count(*)=3 and bool_and(t.correct) good from (
      select st.correct and (sess.recovery_round_limit=0 or not st.uncertain) correct
      from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id
      where os.branch_id=b.id and st.answered_at is not null order by os.position desc limit 3) t) last_three on true
    where b.student_id=p_student_id
  ), targets as (
    select f.*,case when has_error then greatest(3,least(5,jsonb_array_length(candidates))) else 3 end target from facts f
  ), states as (
    select t.*,case
      when sess.recovery_round_limit=3 and ordinary_count<sess.initial_question_target and jsonb_array_length(candidates)=0 then 'pending'
      when jsonb_array_length(candidates)<3 then 'reserve_gap'
      when n>=target then case when last_good then 'consolidated' else 'needs_practice' end
      when not exists(select 1 from public.chem_questions q where q.id=candidates->(n::integer)->>'questionId'
        and q.question_revision_token=candidates->(n::integer)->>'revisionToken' and q.usable_for_review
        and not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=q.id)) then 'reserve_gap'
      when not (knowledge_id=any(sess.knowledge_skill_ids)) or sess.status<>'active' or issued_count>=sess.hard_question_cap
        or (sess.recovery_round_limit=3 and ordinary_count<sess.initial_question_target) or (app_private.chem_junior_budget_enabled(p_student_id) and daily_count>=30) then 'pending'
      else 'practicing' end current_status,
      case
      when sess.recovery_round_limit=3 and ordinary_count<sess.initial_question_target and jsonb_array_length(candidates)=0 then 'initial_round_in_progress'
      when jsonb_array_length(candidates)<3 then 'fewer_than_three_verified_fresh_originals'
      when n>=target then case when last_good then '' else 'reviewed_reserves_exhausted_without_three_consecutive_correct' end
      when not exists(select 1 from public.chem_questions q where q.id=candidates->(n::integer)->>'questionId'
        and q.question_revision_token=candidates->(n::integer)->>'revisionToken' and q.usable_for_review
        and not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=q.id)) then 'reserved_original_unavailable'
      when not (knowledge_id=any(sess.knowledge_skill_ids)) then 'waiting_for_compatible_curriculum'
      when sess.recovery_round_limit=3 and ordinary_count<sess.initial_question_target then 'initial_round_in_progress'
      when sess.status<>'active' or issued_count>=sess.hard_question_cap or (app_private.chem_junior_budget_enabled(p_student_id) and daily_count>=30) then 'daily_limit_carry_forward'
      else '' end current_reason
      from targets t
  )
  select coalesce(jsonb_agg(jsonb_build_object('branchId',id,'anchorStepId',anchor_step_id,'anchorSessionId',anchor_session_id,
    'anchorQuestionId',anchor_question_id,'anchorRevisionToken',anchor_revision_token,
    'knowledgeId',knowledge_id,'knowledgePoint',knowledge_point,'optionIndex',selected_option,'recoveryRound',recovery_round,
    'status',current_status,'reason',current_reason,'answered',n,'correct',good,'total',target,'candidates',candidates,
    'nextQuestionId',case when n<target then candidates->(n::integer)->>'questionId' end,
    'nextRevisionToken',case when n<target then candidates->(n::integer)->>'revisionToken' end)
    order by case when sess.recovery_round_limit=3 then recovery_round else 1 end,created_at,id),'[]') into result from states;
  return jsonb_build_object('branches',result,'dailyIssuedCount',daily_count,'dailyBudgetEnabled',app_private.chem_junior_budget_enabled(p_student_id),
    'branchAnswerHistory',coalesce((select jsonb_agg(jsonb_build_object('branchId',os.branch_id,'position',os.position,'correct',st.correct,'uncertain',st.uncertain)
      order by os.branch_id,os.position) from app_private.chem_junior_option_steps os
      join app_private.chem_junior_option_branches b on b.id=os.branch_id
      join public.chem_junior_session_steps st on st.id=os.step_id where b.student_id=p_student_id and st.answered_at is not null),'[]'),
    'pendingStepCountedToday',exists(select 1 from public.chem_junior_session_steps st join app_private.chem_junior_daily_budget_keys(p_student_id) k on k.event_key='junior:'||st.session_id::text||':'||st.sequence::text where st.session_id=p_session_id and st.answered_at is null),
    'stepContexts',coalesce((select jsonb_agg(jsonb_build_object('stepId',os.step_id,'branchId',os.branch_id,'position',os.position,'recoveryRound',st.practice_round))
      from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id where st.session_id=p_session_id),'[]'),
    'unbranchedAnchors',coalesce((select jsonb_agg(to_jsonb(st)||jsonb_build_object('stepId',st.id,'questionId',st.question_id,'selectedOption',st.selected_option,
      'practiceRound',st.practice_round,'revisionToken',st.question_snapshot->>'revisionToken') order by st.answered_at,st.id)
      from public.chem_junior_session_steps st join public.chem_junior_daily_sessions ds on ds.id=st.session_id
      where ds.student_id=p_student_id and ds.textbook_version=sess.textbook_version and st.answered_at is not null
        and (not st.correct or (ds.recovery_round_limit=3 and st.uncertain))
        and ((ds.recovery_round_limit=0 and not exists(select 1 from app_private.chem_junior_option_steps os where os.step_id=st.id))
          or (ds.recovery_round_limit=3 and st.practice_round<3))
        and not exists(select 1 from app_private.chem_junior_option_branches b where b.anchor_step_id=st.id)),'[]'));
end;
$fn$;
revoke all on function public.chem_junior_option_state_readonly(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.chem_junior_option_state_readonly(uuid,uuid,uuid) to service_role;

commit;
