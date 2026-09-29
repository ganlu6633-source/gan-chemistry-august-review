-- Explicit calendar opt-in. Old curriculum and already-started sessions retain
-- fresh-only selection; no historical answers or source identities are rewritten.
alter table public.chem_junior_curriculum_days add column repetition_policy text not null default 'fresh_only'
  check (repetition_policy in ('fresh_only','spaced_review'));
alter table public.chem_junior_daily_sessions add column repetition_policy text not null default 'fresh_only'
  check (repetition_policy in ('fresh_only','spaced_review'));
alter table public.chem_junior_session_steps drop constraint chem_junior_session_steps_route_kind_check;
alter table public.chem_junior_session_steps add constraint chem_junior_session_steps_route_kind_check
  check (route_kind in ('new_learning','advance','stability_validation','foundation_repair','prior_error_recovery','spaced_review'));

create or replace function app_private.chem_freeze_junior_repetition_policy() returns trigger
language plpgsql set search_path='' as $function$
begin
  if tg_op='INSERT' then
    select case when new.recovery_round_limit=3 then c.repetition_policy else 'fresh_only' end
      into new.repetition_policy from public.chem_junior_curriculum_days c where c.id=new.curriculum_day_id;
  elsif new.repetition_policy is distinct from old.repetition_policy then
    raise exception 'junior session repetition policy is immutable';
  end if;
  return new;
end; $function$;
create trigger chem_junior_sessions_freeze_repetition before insert or update on public.chem_junior_daily_sessions
for each row execute function app_private.chem_freeze_junior_repetition_policy();

-- A future date is only a label on an explicitly teacher-arranged ready plan.
-- All quota and repeat intervals below use actual Beijing dates.
create or replace function app_private.chem_junior_plan_date_allowed(p_plan_id uuid,p_student_id uuid) returns boolean
language sql stable security definer set search_path='' as $function$
 select exists(select 1 from public.chem_learning_plans p
 join public.chem_students_v2 s on s.id=p.student_id
 join public.chem_junior_curriculum_days c on c.id=p.junior_curriculum_day_id
 where p.id=p_plan_id and p.student_id=p_student_id and p.delivery_mode='junior_adaptive'
   and p.mode='REVIEW' and s.grade_band='初三' and s.textbook_version='科粤版' and s.record_status='active'
   and c.textbook_version=s.textbook_version and c.release_status='ready' and c.knowledge_skill_ids=p.skill_ids
   and (p.plan_date <= (now() at time zone 'Asia/Shanghai')::date
     or (p.is_scheduled=true and coalesce(s.metadata->>'demo','false')<>'true'
       and s.metadata->'reviewProgram'->'allowAdvanceStudy'='true'::jsonb
       and s.metadata->'reviewProgram'->'participating'='true'::jsonb
       and (not (coalesce(s.metadata->'reviewProgram','{}'::jsonb) ? 'juniorUnitIds')
         or (jsonb_typeof(s.metadata->'reviewProgram'->'juniorUnitIds')='array'
           and s.metadata->'reviewProgram'->'juniorUnitIds' @> jsonb_build_array(c.unit_id)))
       and coalesce(s.metadata->'reviewProgram'->>'startDate','') ~ '^\d{4}-\d{2}-\d{2}$'
       and coalesce(s.metadata->'reviewProgram'->>'endDate','') ~ '^\d{4}-\d{2}-\d{2}$'
       and p.plan_date::text between s.metadata->'reviewProgram'->>'startDate' and s.metadata->'reviewProgram'->>'endDate')));
$function$;

-- One history projection covers calendar, free practice and submitted answer
-- locks. Native junior attempts already mirrored into attempts are not doubled.
create or replace function app_private.chem_junior_repetition_history(p_student_id uuid) returns jsonb
language sql stable security definer set search_path='' as $function$
 select coalesce(jsonb_agg(x.row),'[]'::jsonb) from (
 select jsonb_build_object('questionId',st.question_id,'motherId',st.mother_id,
   'sourceItemKey',st.source_item_key,'parentSourceItemKey',st.parent_source_item_key,'contentFingerprint',st.content_fingerprint,
   'sessionId',st.session_id,'createdAt',st.created_at,'answeredAt',st.answered_at,
   'pending',st.answered_at is null and ds.status='active','correct',st.correct,'uncertain',st.uncertain) row
 from public.chem_junior_session_steps st join public.chem_junior_daily_sessions ds on ds.id=st.session_id where ds.student_id=p_student_id
 union all
 select jsonb_build_object('questionId',aa.question_id,'motherId',coalesce(aa.question_snapshot->>'motherId',aa.mother_id),
   'sourceItemKey',coalesce(aa.question_snapshot->>'sourceItemKey',q.source_item_key),
   'parentSourceItemKey',coalesce(aa.question_snapshot->>'parentSourceItemKey',q.parent_source_item_key),
   'contentFingerprint',coalesce(aa.question_snapshot->>'contentFingerprint',q.content_fingerprint),
   'sessionId',null,'createdAt',aa.created_at,'answeredAt',aa.created_at,'pending',false,'correct',aa.correct,'uncertain',aa.uncertain)
 from public.chem_attempt_answers aa join public.chem_learning_attempts a on a.id=aa.attempt_id
 left join public.chem_questions q on q.id=aa.question_id
 where a.student_id=p_student_id and a.junior_session_id is null
 union all
 select jsonb_build_object('questionId',q.id,'motherId',q.mother_id,'sourceItemKey',q.source_item_key,
   'parentSourceItemKey',q.parent_source_item_key,'contentFingerprint',q.content_fingerprint,
   'sessionId',null,'createdAt',l.created_at,'answeredAt',l.created_at,'pending',false,
   'correct',l.selected_option=q.correct_option and l.revision_token=q.question_revision_token,
   'uncertain',l.uncertain or l.revision_token<>q.question_revision_token)
 from app_private.chem_question_answer_locks l join public.chem_questions q on q.id=l.question_id
 where l.student_id=p_student_id and not exists(select 1 from public.chem_learning_attempts a
   join public.chem_attempt_answers aa on aa.attempt_id=a.id and aa.question_id=l.question_id
   where a.student_id=l.student_id and a.plan_day_id=l.plan_day_id and a.sequence=l.attempt_sequence)
 ) x;
$function$;

-- Pure, deterministic interval contract, shared by read-only availability and
-- the atomic issue gate. Interval is based on real answer evidence, never the
-- plan date. Uncertain answers reset the streak even when the choice was right.
create or replace function app_private.chem_junior_repetition_state(
 p_question public.chem_questions,p_history jsonb,p_session_id uuid,p_policy text,p_today date
) returns jsonb language plpgsql immutable set search_path='' as $function$
declare h jsonb; matches jsonb:='[]'; last_day date; last_bad date; streak integer; gap integer; due date;
begin
 for h in select value from jsonb_array_elements(p_history) loop
   if h->>'questionId'=p_question.id or h->>'motherId'=p_question.mother_id
     or h->>'sourceItemKey'=p_question.source_item_key or h->>'parentSourceItemKey'=p_question.parent_source_item_key
     or h->>'contentFingerprint'=p_question.content_fingerprint then
     matches:=matches||jsonb_build_array(h);
     if p_policy<>'spaced_review' then return jsonb_build_object('eligible',false,'kind','used'); end if;
     if h->>'sessionId'=p_session_id::text or h->>'pending'='true'
       or ((h->>'createdAt')::timestamptz at time zone 'Asia/Shanghai')::date=p_today
       or ((h->>'answeredAt')::timestamptz at time zone 'Asia/Shanghai')::date=p_today
     then return jsonb_build_object('eligible',false,'kind','current_or_pending'); end if;
   end if;
 end loop;
 select max(((v->>'answeredAt')::timestamptz at time zone 'Asia/Shanghai')::date),
   max(((v->>'answeredAt')::timestamptz at time zone 'Asia/Shanghai')::date) filter(where v->>'correct' is distinct from 'true' or v->>'uncertain' is distinct from 'false')
 into last_day,last_bad from jsonb_array_elements(matches) v where v->>'answeredAt' is not null;
 if last_day is null then return jsonb_build_object('eligible',true,'kind','fresh'); end if;
 if last_bad=last_day then gap:=1;
 else
   select count(distinct ((v->>'answeredAt')::timestamptz at time zone 'Asia/Shanghai')::date) into streak
   from jsonb_array_elements(matches) v
   where v->>'answeredAt' is not null and v->>'correct'='true' and v->>'uncertain'='false'
     and (last_bad is null or ((v->>'answeredAt')::timestamptz at time zone 'Asia/Shanghai')::date>last_bad);
   gap:=case when streak>=4 then 30 when streak=3 then 14 when streak=2 then 7 else 3 end;
 end if;
 due:=last_day+gap;
 return jsonb_build_object('eligible',p_today>=due,'kind',case when p_today>=due then 'due_review' else 'not_due' end,
   'lastAnsweredDate',last_day,'reviewDueDate',due,'intervalDays',gap);
end; $function$;

create or replace function public.chem_junior_practice_availability(p_student_id uuid,p_plan_id uuid,p_session_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare plan public.chem_learning_plans%rowtype; sess public.chem_junior_daily_sessions%rowtype;
 pol text; hist jsonb; out_rows jsonb;
begin
 select * into plan from public.chem_learning_plans where id=p_plan_id and student_id=p_student_id and delivery_mode='junior_adaptive';
 if not found or not app_private.chem_junior_plan_date_allowed(p_plan_id,p_student_id) then raise exception 'junior repetition plan unavailable'; end if;
 if p_session_id is not null then
   select * into sess from public.chem_junior_daily_sessions where id=p_session_id and student_id=p_student_id and plan_day_id=p_plan_id;
   if not found then raise exception 'junior repetition session ownership mismatch'; end if;
   pol:=sess.repetition_policy;
 else
   select case when plan.question_count=8 and plan.round_limit=4 then c.repetition_policy else 'fresh_only' end
     into pol from public.chem_junior_curriculum_days c where c.id=plan.junior_curriculum_day_id;
 end if;
 hist:=app_private.chem_junior_repetition_history(p_student_id);
 select coalesce(jsonb_object_agg(q.id,app_private.chem_junior_repetition_state(q,hist,p_session_id,pol,(now() at time zone 'Asia/Shanghai')::date)),'{}')
 into out_rows from public.chem_questions q join app_private.chem_question_source_releases r on r.id=q.source_release_id and r.status='active'
 where q.grade_band='初三' and q.textbook_version='科粤版' and q.knowledge_id=any(plan.skill_ids);
 return jsonb_build_object('policy',pol,'questions',out_rows);
end; $function$;

revoke all on function public.chem_junior_practice_availability(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.chem_junior_practice_availability(uuid,uuid,uuid) to service_role;
revoke all on function app_private.chem_freeze_junior_repetition_policy(),
 app_private.chem_junior_plan_date_allowed(uuid,uuid),app_private.chem_junior_repetition_history(uuid),
 app_private.chem_junior_repetition_state(public.chem_questions,jsonb,uuid,text,date) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.chem_junior_issue_step(p_session_id uuid, p_student_id uuid, p_question_id text, p_sequence smallint, p_route_kind text, p_route_reason text, p_question_snapshot jsonb)
 RETURNS TABLE(step_id uuid, question_id text, sequence smallint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.chem_junior_daily_sessions%rowtype;
  v_plan public.chem_learning_plans%rowtype;
  v_curriculum public.chem_junior_curriculum_days%rowtype;
  v_question public.chem_questions%rowtype;
  v_provenance app_private.chem_junior_knowledge_provenance%rowtype;
  v_release app_private.chem_question_source_releases%rowtype;
  v_snapshot jsonb;
  v_step_id uuid;
  v_existing_count integer;
  v_max_sequence integer;
  v_unanswered_count integer;
  v_profile_id uuid;
  v_required_knowledge_count integer;
  v_required_card_count integer;
  repetition_state jsonb;
begin
  if p_session_id is null
    or p_student_id is null
    or length(pg_catalog.btrim(coalesce(p_question_id, ''))) = 0
    or p_sequence is null
    or p_sequence not between 1 and 30
    or p_route_kind is null
    or p_route_kind not in (
      'spaced_review',
      'new_learning',
      'advance',
      'stability_validation',
      'foundation_repair',
      'prior_error_recovery'
    )
    or length(pg_catalog.btrim(coalesce(p_route_reason, ''))) not between 1 and 1000
    or pg_catalog.jsonb_typeof(p_question_snapshot) is distinct from 'object'
  then
    raise exception 'invalid junior step issue request';
  end if;

  -- Use the exact lifecycle lock order before touching a session or source
  -- row. Activation holds these transaction locks while retiring/enabling a
  -- batch, so issue cannot observe or persist a half-swapped release.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  -- The session row is the serialization point for issue, resume, answer and
  -- finalization.  A blocked/completed/future session therefore fails before
  -- any source payload could be returned.
  perform s.id from public.chem_students_v2 s where s.id=p_student_id for update;
  select session.*
  into v_session
  from public.chem_junior_daily_sessions as session
  where session.id = p_session_id
    and session.student_id = p_student_id
    and session.status = 'active'
    and app_private.chem_junior_plan_date_allowed(session.plan_day_id,p_student_id)
  for update;

  if not found
    or length(pg_catalog.btrim(coalesce(v_session.textbook_version, ''))) = 0
    or v_session.textbook_version = '待确认'
  then
    raise exception 'junior session is unavailable for question issue';
  end if;

  -- A session is only an execution snapshot of its immutable daily plan. Lock
  -- and reassert every authorization-bearing plan field before consulting the
  -- profile, curriculum, step history or any question-bearing table.
  select plan.*
  into v_plan
  from public.chem_learning_plans as plan
  where plan.id = v_session.plan_day_id
    and plan.student_id = v_session.student_id
    and plan.student_id = p_student_id
    and plan.delivery_mode = 'junior_adaptive'
    and plan.plan_date = v_session.study_date
    and app_private.chem_junior_plan_date_allowed(plan.id,p_student_id)
    and plan.junior_curriculum_day_id = v_session.curriculum_day_id
    and plan.skill_ids = v_session.knowledge_skill_ids
    and plan.mode = 'REVIEW'
    and plan.question_count = v_session.initial_question_target
    and plan.round_limit = 1 + v_session.recovery_round_limit
  for share;

  if not found then
    raise exception 'junior session plan contract changed before question issue';
  end if;

  select student.id
  into v_profile_id
  from public.chem_students_v2 as student
  where student.id = p_student_id
    and student.grade_band = '初三'
    and student.record_status = 'active'
    and student.textbook_version = v_session.textbook_version
  for share;

  if not found or v_profile_id is null then
    raise exception 'junior student textbook no longer matches the active session';
  end if;

  select curriculum.*
  into v_curriculum
  from public.chem_junior_curriculum_days as curriculum
  where curriculum.id = v_session.curriculum_day_id
    and curriculum.textbook_version = v_session.textbook_version
    and curriculum.release_status = 'ready'
    and curriculum.knowledge_skill_ids = v_session.knowledge_skill_ids
  for share;

  if not found
    or cardinality(v_session.knowledge_skill_ids) <> 3
    or (
      select count(distinct requested.skill_id)
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
    ) <> 3
  then
    raise exception 'junior curriculum day is no longer ready or does not match the session';
  end if;

  -- Lock every existing step after the session serialization lock.  The
  -- count/max/unanswered assertions make a stale concurrent selector retry
  -- through the independently validated resume path.
  perform existing.id
  from public.chem_junior_session_steps as existing
  where existing.session_id = p_session_id
  order by existing.sequence
  for share;

  select
    count(*)::integer,
    coalesce(max(existing.sequence), 0)::integer,
    (count(*) filter (where existing.answered_at is null))::integer
  into v_existing_count, v_max_sequence, v_unanswered_count
  from public.chem_junior_session_steps as existing
  where existing.session_id = p_session_id;

  if v_unanswered_count <> 0
    or p_sequence <> v_existing_count + 1
    or p_sequence <> v_max_sequence + 1
  then
    raise exception using
      errcode = '40001',
      message = 'junior issue sequence is stale';
  end if;
  if p_sequence > v_session.hard_question_cap then
    raise exception 'junior session hard question cap reached';
  end if;

  select question.*
  into v_question
  from public.chem_questions as question
  where question.id = p_question_id
  for share;

  if not found then
    raise exception 'junior question is unavailable for issue';
  end if;
  if not exists (select 1 from app_private.chem_teaching_ready_questions ready where ready.id = v_question.id) then
    raise exception 'junior question is not ready for delivery';
  end if;

  if v_question.grade_band <> '初三'
    or v_question.textbook_version is distinct from v_session.textbook_version
    or v_question.source_kind <> 'user_provided_local'
    or v_question.review_status <> 'approved'
    or v_question.scope_status <> 'IN'
    or not v_question.usable_for_review
    or v_question.render_mode <> 'native'
    or v_question.image_url is not null
    or v_question.asset_refs <> '[]'::jsonb
    or v_question.skill_id is null
    or v_question.knowledge_id is null
    or v_question.skill_id <> v_question.knowledge_id
    or length(pg_catalog.btrim(coalesce(v_question.mother_id, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.same_type_key, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.source_item_key, ''))) < 16
    or length(pg_catalog.btrim(coalesce(v_question.parent_source_item_key, ''))) < 16
    or coalesce(v_question.content_fingerprint, '') !~ '^[0-9a-f]{64}$'
    or coalesce(v_question.question_revision_token, '') !~ '^[0-9a-f]{64}$'
    or v_question.source_release_id is null
    or length(pg_catalog.btrim(coalesce(v_question.stem, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.explanation, ''))) = 0
  then
    raise exception 'junior question no longer satisfies the native source contract';
  end if;

  if pg_catalog.jsonb_typeof(v_question.options) is distinct from 'array' then
    raise exception 'junior question options are not an array';
  end if;
  if pg_catalog.jsonb_array_length(v_question.options) <> 4
    or v_question.correct_option < 0
    or v_question.correct_option > 3
  then
    raise exception 'junior question option contract is invalid';
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
    where pg_catalog.jsonb_typeof(option_value.value) is distinct from 'string'
      or length(pg_catalog.btrim(option_value.value #>> '{}')) = 0
  ) then
    raise exception 'junior question contains a non-text or empty option';
  end if;
  if (
    select count(distinct pg_catalog.btrim(option_value.value #>> '{}'))
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
  ) <> 4 then
    raise exception 'junior question contains duplicated options';
  end if;

  if v_session.repetition_policy='spaced_review' then
    repetition_state:=app_private.chem_junior_repetition_state(v_question,
      app_private.chem_junior_repetition_history(p_student_id),p_session_id,
      v_session.repetition_policy,(now() at time zone 'Asia/Shanghai')::date);
    if repetition_state->>'eligible' is distinct from 'true' then raise exception 'junior_question_not_due'; end if;
    if p_route_kind not in ('foundation_repair','prior_error_recovery') and
      ((repetition_state->>'kind'='due_review') is distinct from (p_route_kind='spaced_review'))
    then raise exception 'junior repeat must be explicitly labelled spaced_review'; end if;
  elsif p_route_kind='spaced_review' then
    raise exception 'junior session has not opted into spaced review';
  end if;

  -- Recompute both native-content digests while the question row is locked.
  -- A matching snapshot is insufficient if a privileged writer corrupted a
  -- revision token together with the content it is meant to bind.
  if v_question.content_fingerprint is distinct from
      app_private.chem_h3_content_fingerprint(v_question.stem, v_question.options)
    or v_question.question_revision_token is distinct from
      app_private.chem_junior_native_revision_sha256(v_question)
  then
    raise exception 'junior question content digest is stale';
  end if;

  select release.*
  into v_release
  from app_private.chem_question_source_releases as release
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  where release.id = v_question.source_release_id
    and release.grade_band = '初三'
    and release.textbook_version = v_session.textbook_version
    and release.status = 'active'
    and release.verification_status = 'full_visual_verified'
    and release.verification_manifest_sha256 = release.manifest_sha256
    and release.revision_contract = 'v3_junior_native_text'
    and release.verified_at is not null
    and length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
    and release.activated_at is not null
  for share of release, rights;

  if not found then
    raise exception 'junior source release is not active and fully verified';
  end if;

  select provenance.*
  into v_provenance
  from app_private.chem_junior_knowledge_provenance as provenance
  where provenance.textbook_version = v_session.textbook_version
    and provenance.knowledge_id = v_question.knowledge_id
    and provenance.source_release_id = v_question.source_release_id
    and provenance.verification_status = 'verified'
    and provenance.reviewed_at is not null
  for share;

  if not found then
    raise exception 'junior textbook knowledge provenance is not verified';
  end if;

  -- Every non-recovery route must stay inside the three locked curriculum
  -- skills. A recovery route, including one for a current-day skill, needs a
  -- real earlier completed error/uncertain answer of the same type and a new
  -- value for all five source identities.
  if p_route_kind = 'prior_error_recovery' then
    perform prior_step.id
    from public.chem_junior_daily_sessions as prior_session
    join public.chem_junior_session_steps as prior_step
      on prior_step.session_id = prior_session.id
    where prior_session.student_id = p_student_id
      and prior_session.id <> p_session_id
      and prior_session.status = 'completed'
      and prior_session.textbook_version = v_session.textbook_version
      and prior_session.completed_at is not null
      and prior_session.completed_at < v_session.started_at
      and prior_step.answered_at is not null
      and (not prior_step.correct or prior_step.uncertain)
      and prior_step.knowledge_id = v_question.knowledge_id
      and prior_step.same_type_key = v_question.same_type_key
      and prior_step.question_id is distinct from v_question.id
      and prior_step.mother_id is distinct from v_question.mother_id
      and prior_step.source_item_key is distinct from v_question.source_item_key
      and prior_step.parent_source_item_key is distinct from v_question.parent_source_item_key
      and prior_step.content_fingerprint is distinct from v_question.content_fingerprint
    order by prior_session.completed_at desc, prior_step.sequence desc
    limit 1
    for share of prior_session, prior_step;

    if not found then
      raise exception 'junior recovery route has no matching prior error evidence';
    end if;
  elsif not (v_question.knowledge_id = any(v_session.knowledge_skill_ids)) then
    raise exception 'junior non-recovery question is outside the locked curriculum skills';
  end if;

  -- Lock and require exactly one approved knowledge card for every current
  -- curriculum skill and for the selected recovery skill, if it is outside
  -- the current three. This closes the Edge card-read/change race.
  perform card.id
  from public.chem_knowledge_cards as card
  where card.review_status = 'approved'
    and card.skill_id = any(v_session.knowledge_skill_ids || array[v_question.knowledge_id])
  order by card.id
  for share;

  select count(*)::integer
  into v_required_knowledge_count
  from (
    select distinct requested.skill_id
    from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) as requested(skill_id)
  ) as required;

  select count(*)::integer
  into v_required_card_count
  from (
    select required.skill_id
    from (
      select distinct requested.skill_id
      from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) as requested(skill_id)
    ) as required
    join public.chem_knowledge_cards as card
      on card.skill_id = required.skill_id
     and card.review_status = 'approved'
     and app_private.chem_junior_knowledge_card_is_ready(
       v_session.textbook_version,
       required.skill_id
     )
    group by required.skill_id
    having count(card.id) = 1
  ) as exactly_one_card;

  if v_required_card_count <> v_required_knowledge_count then
    raise exception 'junior knowledge-card approval contract changed before issue';
  end if;

  v_snapshot := pg_catalog.jsonb_build_object(
    'questionId', v_question.id,
    'motherId', v_question.mother_id,
    'skillId', v_question.skill_id,
    'knowledgeId', v_question.knowledge_id,
    'conceptKey', v_question.concept_key,
    'level', v_question.level,
    'gradeBand', v_question.grade_band,
    'textbookVersion', v_question.textbook_version,
    'stem', v_question.stem,
    'options', v_question.options,
    'correctOption', v_question.correct_option,
    'explanation', v_question.explanation,
    'scaffold', v_question.scaffold,
    'reviewStatus', v_question.review_status,
    'scopeStatus', v_question.scope_status,
    'sourceKind', v_question.source_kind,
    'renderMode', v_question.render_mode,
    'imageUrl', v_question.image_url,
    'assetRefs', v_question.asset_refs,
    'sourceReleaseId', v_question.source_release_id,
    'sourceItemKey', v_question.source_item_key,
    'parentSourceItemKey', v_question.parent_source_item_key,
    'sameTypeKey', v_question.same_type_key,
    'contentFingerprint', v_question.content_fingerprint,
    'revisionToken', v_question.question_revision_token,
    'routeKind', p_route_kind,
    'routeReason', p_route_reason
  );

  if p_question_snapshot is distinct from v_snapshot then
    raise exception 'junior issue snapshot does not match the locked source question';
  end if;

  if exists (
    select 1
    from public.chem_junior_session_steps as existing
    where existing.session_id = p_session_id
      and (
        existing.question_id = v_question.id
        or existing.mother_id = v_question.mother_id
        or existing.source_item_key = v_question.source_item_key
        or existing.parent_source_item_key = v_question.parent_source_item_key
        or existing.content_fingerprint = v_question.content_fingerprint
      )
  ) then
    raise exception 'junior source identity was already issued in this session';
  end if;

  if v_session.recovery_round_limit=3 and p_sequence>v_session.initial_question_target and coalesce(nullif(pg_catalog.current_setting('app.chem_junior_practice_round',true),''),'0')::integer=0 then raise exception 'junior recovery must use the strict option queue'; end if;
  perform app_private.chem_junior_reserve_daily_question(p_student_id,'junior:'||p_session_id::text||':'||p_sequence::text);
  perform pg_catalog.set_config('app.chem_junior_step_issue', 'on', true);
  insert into public.chem_junior_session_steps (
    session_id,
    sequence,
    question_id,
    mother_id,
    skill_id,
    knowledge_id,
    same_type_key,
    source_item_key,
    parent_source_item_key,
    content_fingerprint,
    level,
    route_kind,
    route_reason,
    practice_round,
    question_snapshot
  ) values (
    p_session_id,
    p_sequence,
    v_question.id,
    v_question.mother_id,
    v_question.skill_id,
    v_question.knowledge_id,
    v_question.same_type_key,
    v_question.source_item_key,
    v_question.parent_source_item_key,
    v_question.content_fingerprint,
    v_question.level,
    p_route_kind,
    p_route_reason,
    coalesce(nullif(pg_catalog.current_setting('app.chem_junior_practice_round',true),''),'0')::smallint,
    v_snapshot
  )
  returning id
  into v_step_id;
  perform pg_catalog.set_config('app.chem_junior_step_issue', 'off', true);

  return query select v_step_id, v_question.id, p_sequence;
end;
$function$;

CREATE OR REPLACE FUNCTION public.chem_junior_validate_issued_step(p_session_id uuid, p_student_id uuid, p_step_id uuid)
 RETURNS TABLE(step_id uuid, question_id text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.chem_junior_daily_sessions%rowtype;
  v_plan public.chem_learning_plans%rowtype;
  v_curriculum public.chem_junior_curriculum_days%rowtype;
  v_step public.chem_junior_session_steps%rowtype;
  v_question public.chem_questions%rowtype;
  v_provenance app_private.chem_junior_knowledge_provenance%rowtype;
  v_release app_private.chem_question_source_releases%rowtype;
  v_snapshot jsonb;
  v_profile_id uuid;
  v_unanswered_count integer;
  v_required_knowledge_count integer;
  v_required_card_count integer;
begin
  if p_session_id is null or p_student_id is null or p_step_id is null then
    raise exception 'invalid junior issued-step validation request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  perform s.id from public.chem_students_v2 s where s.id=p_student_id for update;
  select session.*
  into v_session
  from public.chem_junior_daily_sessions as session
  where session.id = p_session_id
    and session.student_id = p_student_id
    and session.status = 'active'
    and app_private.chem_junior_plan_date_allowed(session.plan_day_id,p_student_id)
  for update;

  if not found
    or length(pg_catalog.btrim(coalesce(v_session.textbook_version, ''))) = 0
    or v_session.textbook_version = '待确认'
  then
    raise exception 'junior session is unavailable for resume';
  end if;

  -- Resume is a disclosure path too. A previously issued payload remains
  -- unavailable unless the locked plan is still the exact parent snapshot of
  -- the active session.
  select plan.*
  into v_plan
  from public.chem_learning_plans as plan
  where plan.id = v_session.plan_day_id
    and plan.student_id = v_session.student_id
    and plan.student_id = p_student_id
    and plan.delivery_mode = 'junior_adaptive'
    and plan.plan_date = v_session.study_date
    and app_private.chem_junior_plan_date_allowed(plan.id,p_student_id)
    and plan.junior_curriculum_day_id = v_session.curriculum_day_id
    and plan.skill_ids = v_session.knowledge_skill_ids
    and plan.mode = 'REVIEW'
    and plan.question_count = v_session.initial_question_target
    and plan.round_limit = 1 + v_session.recovery_round_limit
  for share;

  if not found then
    raise exception 'junior session plan contract changed before resume';
  end if;

  select student.id
  into v_profile_id
  from public.chem_students_v2 as student
  where student.id = p_student_id
    and student.grade_band = '初三'
    and student.record_status = 'active'
    and student.textbook_version = v_session.textbook_version
  for share;

  if not found or v_profile_id is null then
    raise exception 'junior student textbook no longer matches the active session';
  end if;

  select curriculum.*
  into v_curriculum
  from public.chem_junior_curriculum_days as curriculum
  where curriculum.id = v_session.curriculum_day_id
    and curriculum.textbook_version = v_session.textbook_version
    and curriculum.release_status = 'ready'
    and curriculum.knowledge_skill_ids = v_session.knowledge_skill_ids
  for share;

  if not found
    or cardinality(v_session.knowledge_skill_ids) <> 3
    or (
      select count(distinct requested.skill_id)
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
    ) <> 3
  then
    raise exception 'junior curriculum day is no longer ready or does not match the session';
  end if;

  select step.*
  into v_step
  from public.chem_junior_session_steps as step
  where step.id = p_step_id
    and step.session_id = p_session_id
  for share;

  if not found
    or v_step.answered_at is not null
    or v_step.selected_option is not null
    or v_step.uncertain is not null
    or v_step.duration_sec is not null
    or v_step.correct is not null
    or v_step.sequence not between 1 and v_session.hard_question_cap
  then
    raise exception 'junior issued step is unavailable for resume';
  end if;

  select (count(*) filter (where step.answered_at is null))::integer
  into v_unanswered_count
  from public.chem_junior_session_steps as step
  where step.session_id = p_session_id;

  if v_unanswered_count <> 1 then
    raise exception 'junior session does not have exactly one resumable step';
  end if;

  select question.*
  into v_question
  from public.chem_questions as question
  where question.id = v_step.question_id
  for share;

  if not found then
    raise exception 'junior issued question is unavailable';
  end if;
  if not exists (select 1 from app_private.chem_teaching_ready_questions ready where ready.id = v_question.id) then
    raise exception 'junior issued question is not ready for delivery';
  end if;

  if v_question.grade_band <> '初三'
    or v_question.textbook_version is distinct from v_session.textbook_version
    or v_question.source_kind <> 'user_provided_local'
    or v_question.review_status <> 'approved'
    or v_question.scope_status <> 'IN'
    or not v_question.usable_for_review
    or v_question.render_mode <> 'native'
    or v_question.image_url is not null
    or v_question.asset_refs <> '[]'::jsonb
    or v_question.skill_id is null
    or v_question.knowledge_id is null
    or v_question.skill_id <> v_question.knowledge_id
    or length(pg_catalog.btrim(coalesce(v_question.mother_id, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.same_type_key, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.source_item_key, ''))) < 16
    or length(pg_catalog.btrim(coalesce(v_question.parent_source_item_key, ''))) < 16
    or coalesce(v_question.content_fingerprint, '') !~ '^[0-9a-f]{64}$'
    or coalesce(v_question.question_revision_token, '') !~ '^[0-9a-f]{64}$'
    or v_question.source_release_id is null
    or length(pg_catalog.btrim(coalesce(v_question.stem, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.explanation, ''))) = 0
  then
    raise exception 'junior issued question no longer satisfies the native source contract';
  end if;

  if pg_catalog.jsonb_typeof(v_question.options) is distinct from 'array' then
    raise exception 'junior issued question options are not an array';
  end if;
  if pg_catalog.jsonb_array_length(v_question.options) <> 4
    or v_question.correct_option < 0
    or v_question.correct_option > 3
  then
    raise exception 'junior issued question option contract is invalid';
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
    where pg_catalog.jsonb_typeof(option_value.value) is distinct from 'string'
      or length(pg_catalog.btrim(option_value.value #>> '{}')) = 0
  ) then
    raise exception 'junior issued question contains a non-text or empty option';
  end if;
  if (
    select count(distinct pg_catalog.btrim(option_value.value #>> '{}'))
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
  ) <> 4 then
    raise exception 'junior issued question contains duplicated options';
  end if;

  if v_question.content_fingerprint is distinct from
      app_private.chem_h3_content_fingerprint(v_question.stem, v_question.options)
    or v_question.question_revision_token is distinct from
      app_private.chem_junior_native_revision_sha256(v_question)
  then
    raise exception 'junior issued question content digest is stale';
  end if;

  select release.*
  into v_release
  from app_private.chem_question_source_releases as release
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  where release.id = v_question.source_release_id
    and release.grade_band = '初三'
    and release.textbook_version = v_session.textbook_version
    and release.status = 'active'
    and release.verification_status = 'full_visual_verified'
    and release.verification_manifest_sha256 = release.manifest_sha256
    and release.revision_contract = 'v3_junior_native_text'
    and release.verified_at is not null
    and length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
    and release.activated_at is not null
  for share of release, rights;

  if not found then
    raise exception 'junior issued source release is no longer active and verified';
  end if;

  select provenance.*
  into v_provenance
  from app_private.chem_junior_knowledge_provenance as provenance
  where provenance.textbook_version = v_session.textbook_version
    and provenance.knowledge_id = v_question.knowledge_id
    and provenance.source_release_id = v_question.source_release_id
    and provenance.verification_status = 'verified'
    and provenance.reviewed_at is not null
  for share;

  if not found then
    raise exception 'junior issued textbook provenance is no longer verified';
  end if;

  if v_step.route_kind = 'prior_error_recovery' then
    perform prior_step.id
    from public.chem_junior_daily_sessions as prior_session
    join public.chem_junior_session_steps as prior_step
      on prior_step.session_id = prior_session.id
    where prior_session.student_id = p_student_id
      and prior_session.id <> p_session_id
      and prior_session.status = 'completed'
      and prior_session.textbook_version = v_session.textbook_version
      and prior_session.completed_at is not null
      and prior_session.completed_at < v_session.started_at
      and prior_step.answered_at is not null
      and (not prior_step.correct or prior_step.uncertain)
      and prior_step.knowledge_id = v_question.knowledge_id
      and prior_step.same_type_key = v_question.same_type_key
      and prior_step.question_id is distinct from v_question.id
      and prior_step.mother_id is distinct from v_question.mother_id
      and prior_step.source_item_key is distinct from v_question.source_item_key
      and prior_step.parent_source_item_key is distinct from v_question.parent_source_item_key
      and prior_step.content_fingerprint is distinct from v_question.content_fingerprint
    order by prior_session.completed_at desc, prior_step.sequence desc
    limit 1
    for share of prior_session, prior_step;

    if not found then
      raise exception 'junior issued recovery step no longer has prior error evidence';
    end if;
  elsif not (v_question.knowledge_id = any(v_session.knowledge_skill_ids)) then
    raise exception 'junior issued non-recovery step is outside the locked curriculum skills';
  end if;

  perform card.id
  from public.chem_knowledge_cards as card
  where card.review_status = 'approved'
    and card.skill_id = any(v_session.knowledge_skill_ids || array[v_question.knowledge_id])
  order by card.id
  for share;

  select count(*)::integer
  into v_required_knowledge_count
  from (
    select distinct requested.skill_id
    from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) as requested(skill_id)
  ) as required;

  select count(*)::integer
  into v_required_card_count
  from (
    select required.skill_id
    from (
      select distinct requested.skill_id
      from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) as requested(skill_id)
    ) as required
    join public.chem_knowledge_cards as card
      on card.skill_id = required.skill_id
     and card.review_status = 'approved'
     and app_private.chem_junior_knowledge_card_is_ready(
       v_session.textbook_version,
       required.skill_id
     )
    group by required.skill_id
    having count(card.id) = 1
  ) as exactly_one_card;

  if v_required_card_count <> v_required_knowledge_count then
    raise exception 'junior knowledge-card approval contract changed before resume';
  end if;

  v_snapshot := pg_catalog.jsonb_build_object(
    'questionId', v_question.id,
    'motherId', v_question.mother_id,
    'skillId', v_question.skill_id,
    'knowledgeId', v_question.knowledge_id,
    'conceptKey', v_question.concept_key,
    'level', v_question.level,
    'gradeBand', v_question.grade_band,
    'textbookVersion', v_question.textbook_version,
    'stem', v_question.stem,
    'options', v_question.options,
    'correctOption', v_question.correct_option,
    'explanation', v_question.explanation,
    'scaffold', v_question.scaffold,
    'reviewStatus', v_question.review_status,
    'scopeStatus', v_question.scope_status,
    'sourceKind', v_question.source_kind,
    'renderMode', v_question.render_mode,
    'imageUrl', v_question.image_url,
    'assetRefs', v_question.asset_refs,
    'sourceReleaseId', v_question.source_release_id,
    'sourceItemKey', v_question.source_item_key,
    'parentSourceItemKey', v_question.parent_source_item_key,
    'sameTypeKey', v_question.same_type_key,
    'contentFingerprint', v_question.content_fingerprint,
    'revisionToken', v_question.question_revision_token,
    'routeKind', v_step.route_kind,
    'routeReason', v_step.route_reason
  );

  if v_step.question_id is distinct from v_question.id
    or v_step.mother_id is distinct from v_question.mother_id
    or v_step.skill_id is distinct from v_question.skill_id
    or v_step.knowledge_id is distinct from v_question.knowledge_id
    or v_step.same_type_key is distinct from v_question.same_type_key
    or v_step.source_item_key is distinct from v_question.source_item_key
    or v_step.parent_source_item_key is distinct from v_question.parent_source_item_key
    or v_step.content_fingerprint is distinct from v_question.content_fingerprint
    or v_step.level is distinct from v_question.level
    or v_step.question_snapshot is distinct from v_snapshot
  then
    raise exception 'junior issued step no longer matches its locked source snapshot';
  end if;

  perform app_private.chem_junior_reserve_daily_question(p_student_id,'junior:'||p_session_id::text||':'||v_step.sequence::text);
  return query select v_step.id, v_question.id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.chem_junior_record_step(p_session_id uuid, p_student_id uuid, p_step_id uuid, p_selected_option smallint, p_uncertain boolean, p_duration_sec integer, p_revision_token text)
 RETURNS TABLE(step_id uuid, question_id text, selected_option smallint, uncertain boolean, duration_sec integer, correct boolean, answered_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.chem_junior_daily_sessions%rowtype;
  v_plan public.chem_learning_plans%rowtype;
  v_curriculum public.chem_junior_curriculum_days%rowtype;
  v_step public.chem_junior_session_steps%rowtype;
  v_question public.chem_questions%rowtype;
  v_provenance app_private.chem_junior_knowledge_provenance%rowtype;
  v_release app_private.chem_question_source_releases%rowtype;
  v_snapshot jsonb;
  v_profile_id uuid;
  v_required_knowledge_count integer;
  v_required_card_count integer;
  v_correct boolean;
  v_duration integer;
begin
  if p_session_id is null
    or p_student_id is null
    or p_step_id is null
    or p_selected_option is null
    or p_uncertain is null
    or p_duration_sec is null
    or p_duration_sec < 0
    or p_duration_sec > 3600 then
    raise exception 'invalid junior step answer';
  end if;

  -- Match activation/issue lock order.  The source locks prevent a release
  -- swap while an answer is being authorized; the session row then
  -- serializes issue, resume, answer and finalization for this learner.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  perform s.id from public.chem_students_v2 s where s.id=p_student_id for update;
  select session.*
  into v_session
  from public.chem_junior_daily_sessions as session
  where session.id = p_session_id
    and session.student_id = p_student_id
    and session.status = 'active'
    and app_private.chem_junior_plan_date_allowed(session.plan_day_id,p_student_id)
  for update;

  if not found
    or pg_catalog.length(pg_catalog.btrim(coalesce(v_session.textbook_version, ''))) = 0
    or v_session.textbook_version = '待确认'
  then
    raise exception 'junior session step is unavailable';
  end if;

  -- The session is only an execution snapshot.  Re-lock and reassert its
  -- complete parent-plan authorization before reading a mutable profile,
  -- curriculum/card approval or any source-bearing row.
  select plan.*
  into v_plan
  from public.chem_learning_plans as plan
  where plan.id = v_session.plan_day_id
    and plan.student_id = v_session.student_id
    and plan.student_id = p_student_id
    and plan.delivery_mode = 'junior_adaptive'
    and plan.plan_date = v_session.study_date
    and app_private.chem_junior_plan_date_allowed(plan.id,p_student_id)
    and plan.junior_curriculum_day_id = v_session.curriculum_day_id
    and plan.skill_ids = v_session.knowledge_skill_ids
    and plan.mode = 'REVIEW'
    and plan.question_count = v_session.initial_question_target
    and plan.round_limit = 1 + v_session.recovery_round_limit
  for share;

  if not found then
    raise exception 'junior session plan contract changed before answer recording';
  end if;

  select student.id
  into v_profile_id
  from public.chem_students_v2 as student
  where student.id = p_student_id
    and student.grade_band = '初三'
    and student.record_status = 'active'
    and student.textbook_version = v_session.textbook_version
  for share;

  if not found or v_profile_id is null then
    raise exception 'junior student textbook no longer matches the active session';
  end if;

  select curriculum.*
  into v_curriculum
  from public.chem_junior_curriculum_days as curriculum
  where curriculum.id = v_session.curriculum_day_id
    and curriculum.textbook_version = v_session.textbook_version
    and curriculum.release_status = 'ready'
    and curriculum.knowledge_skill_ids = v_session.knowledge_skill_ids
  for share;

  if not found
    or cardinality(v_session.knowledge_skill_ids) <> 3
    or (
      select count(distinct requested.skill_id)
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
    ) <> 3
  then
    raise exception 'junior curriculum day is no longer ready or does not match the session';
  end if;

  -- The session lock makes this required-skill set stable even though the
  -- step rows are deliberately not locked until after the cards.  Include
  -- recovery knowledge outside today's three and require one, not merely at
  -- least one, approved card for every required skill.
  perform card.id
  from public.chem_knowledge_cards as card
  join (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required
    on required.skill_id = card.skill_id
  where card.review_status = 'approved'
  order by card.skill_id, card.id
  for share of card;

  select count(*)::integer
  into v_required_knowledge_count
  from (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required_knowledge;

  select count(*)::integer
  into v_required_card_count
  from (
    select required.skill_id
    from (
      select distinct required.skill_id
      from (
        select requested.skill_id
        from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
        union all
        select existing.knowledge_id
        from public.chem_junior_session_steps as existing
        where existing.session_id = p_session_id
      ) as required
    ) as required
    join public.chem_knowledge_cards as card
      on card.skill_id = required.skill_id
     and card.review_status = 'approved'
     and app_private.chem_junior_knowledge_card_is_ready(
       v_session.textbook_version,
       required.skill_id
     )
    group by required.skill_id
    having count(card.id) = 1
  ) as exactly_one_card;

  if v_required_card_count <> v_required_knowledge_count then
    raise exception 'junior knowledge-card approval contract changed before answer recording';
  end if;

  -- Lock source-bearing rows only after all current authorization rows.  The
  -- separate statements make the step -> question -> provenance -> release
  -- order explicit and keep every source/snapshot gate ahead of writes.
  select step.*
  into v_step
  from public.chem_junior_session_steps as step
  where step.id = p_step_id
    and step.session_id = p_session_id
  for update;

  if not found then
    raise exception 'junior session step is unavailable';
  end if;
  if v_step.answered_at is not null then
    raise exception 'junior session step is already locked';
  end if;

  select question.*
  into v_question
  from public.chem_questions as question
  where question.id = v_step.question_id
  for share;

  if not found then
    raise exception 'junior source question is unavailable';
  end if;
  if not exists (select 1 from app_private.chem_teaching_ready_questions ready where ready.id = v_question.id) then
    raise exception 'junior source question is not ready for an answer';
  end if;

  if v_question.grade_band is distinct from '初三'
    or v_question.textbook_version is distinct from v_session.textbook_version
    or v_question.source_kind is distinct from 'user_provided_local'
    or v_question.review_status is distinct from 'approved'
    or v_question.scope_status is distinct from 'IN'
    or v_question.usable_for_review is distinct from true
    or v_question.render_mode is distinct from 'native'
    or v_question.image_url is not null
    or v_question.asset_refs is distinct from '[]'::jsonb
    or v_question.skill_id is distinct from v_step.skill_id
    or v_question.knowledge_id is distinct from v_step.knowledge_id
    or v_question.skill_id is distinct from v_question.knowledge_id
    or v_question.mother_id is distinct from v_step.mother_id
    or v_question.same_type_key is distinct from v_step.same_type_key
    or v_question.source_item_key is distinct from v_step.source_item_key
    or v_question.parent_source_item_key is distinct from v_step.parent_source_item_key
    or v_question.content_fingerprint is distinct from v_step.content_fingerprint
    or v_question.level is distinct from v_step.level
    or v_question.source_release_id is null
    or pg_catalog.length(pg_catalog.btrim(coalesce(v_question.stem, ''))) = 0
    or pg_catalog.length(pg_catalog.btrim(coalesce(v_question.explanation, ''))) = 0
  then
    raise exception 'junior question no longer satisfies the native source contract';
  end if;

  if pg_catalog.jsonb_typeof(v_question.options) is distinct from 'array' then
    raise exception 'junior question options are not an array';
  end if;
  if pg_catalog.jsonb_array_length(v_question.options) <> 4
    or v_question.correct_option not between 0 and 3
  then
    raise exception 'junior question option contract is invalid';
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
    where pg_catalog.jsonb_typeof(option_value.value) is distinct from 'string'
      or pg_catalog.length(pg_catalog.btrim(option_value.value #>> '{}')) = 0
  ) then
    raise exception 'junior question contains a non-text or empty option';
  end if;
  if (
    select count(distinct pg_catalog.btrim(option_value.value #>> '{}'))
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
  ) <> 4 then
    raise exception 'junior question contains duplicated options';
  end if;

  if v_question.content_fingerprint is distinct from
      app_private.chem_h3_content_fingerprint(v_question.stem, v_question.options)
    or v_question.question_revision_token is distinct from
      app_private.chem_junior_native_revision_sha256(v_question)
  then
    raise exception 'junior question content digest is stale';
  end if;

  select provenance.*
  into v_provenance
  from app_private.chem_junior_knowledge_provenance as provenance
  where provenance.textbook_version = v_session.textbook_version
    and provenance.knowledge_id = v_step.knowledge_id
    and provenance.source_release_id = v_question.source_release_id
    and provenance.verification_status = 'verified'
    and provenance.reviewed_at is not null
  for share;

  if not found then
    raise exception 'junior textbook knowledge provenance is not verified';
  end if;

  select release.*
  into v_release
  from app_private.chem_question_source_releases as release
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  where release.id = v_question.source_release_id
    and release.id = v_provenance.source_release_id
    and release.grade_band = '初三'
    and release.textbook_version = v_session.textbook_version
    and release.status = 'active'
    and release.verification_status = 'full_visual_verified'
    and release.verification_manifest_sha256 = release.manifest_sha256
    and release.revision_contract = 'v3_junior_native_text'
    and release.verified_at is not null
    and pg_catalog.length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
    and release.activated_at is not null
  for share of release, rights;

  if not found then
    raise exception 'junior source release is not active and fully verified';
  end if;

  v_snapshot := pg_catalog.jsonb_build_object(
    'questionId', v_question.id,
    'motherId', v_question.mother_id,
    'skillId', v_question.skill_id,
    'knowledgeId', v_question.knowledge_id,
    'conceptKey', v_question.concept_key,
    'level', v_question.level,
    'gradeBand', v_question.grade_band,
    'textbookVersion', v_question.textbook_version,
    'stem', v_question.stem,
    'options', v_question.options,
    'correctOption', v_question.correct_option,
    'explanation', v_question.explanation,
    'scaffold', v_question.scaffold,
    'reviewStatus', v_question.review_status,
    'scopeStatus', v_question.scope_status,
    'sourceKind', v_question.source_kind,
    'renderMode', v_question.render_mode,
    'imageUrl', v_question.image_url,
    'assetRefs', v_question.asset_refs,
    'sourceReleaseId', v_question.source_release_id,
    'sourceItemKey', v_question.source_item_key,
    'parentSourceItemKey', v_question.parent_source_item_key,
    'sameTypeKey', v_question.same_type_key,
    'contentFingerprint', v_question.content_fingerprint,
    'revisionToken', v_question.question_revision_token,
    'routeKind', v_step.route_kind,
    'routeReason', v_step.route_reason
  );

  if v_step.question_snapshot is distinct from v_snapshot
    or coalesce(v_step.question_snapshot ->> 'revisionToken', '')
      <> coalesce(v_question.question_revision_token, '')
  then
    raise exception 'junior immutable question snapshot changed';
  end if;
  if p_selected_option not between 0 and 3 then
    raise exception 'junior selected option is outside the immutable option set';
  end if;
  if v_question.question_revision_token is distinct from p_revision_token then
    raise exception 'junior source question revision changed';
  end if;

  perform app_private.chem_junior_reserve_daily_question(p_student_id,'junior:'||p_session_id::text||':'||v_step.sequence::text);
  v_duration := least(3600, greatest(0, p_duration_sec));
  v_correct := p_selected_option = v_question.correct_option;

  perform pg_catalog.set_config('app.chem_junior_step_answer', 'on', true);
  update public.chem_junior_session_steps as updated
  set selected_option = p_selected_option,
      uncertain = p_uncertain,
      duration_sec = v_duration,
      correct = v_correct,
      answered_at = now(),
      updated_at = now()
  where updated.id = p_step_id
  returning
    updated.id,
    updated.question_id,
    updated.selected_option,
    updated.uncertain,
    updated.duration_sec,
    updated.correct,
    updated.answered_at
  into
    step_id,
    question_id,
    selected_option,
    uncertain,
    duration_sec,
    correct,
    answered_at;
  perform pg_catalog.set_config('app.chem_junior_step_answer', 'off', true);

  insert into public.chem_student_skill_state (
    student_id,
    skill_id,
    stability,
    consecutive_errors,
    next_review_at,
    last_reviewed_at,
    teacher_intervention,
    updated_at
  ) values (
    p_student_id,
    v_step.skill_id,
    'learning',
    case when v_correct and not p_uncertain then 0 else 1 end,
    now() + interval '1 day',
    now(),
    false,
    now()
  )
  on conflict (student_id, skill_id) do update set
    stability = 'learning',
    consecutive_errors = case
      when v_correct and not p_uncertain
        then public.chem_student_skill_state.consecutive_errors
      else public.chem_student_skill_state.consecutive_errors + 1
    end,
    next_review_at = least(
      coalesce(public.chem_student_skill_state.next_review_at, now() + interval '1 day'),
      now() + interval '1 day'
    ),
    last_reviewed_at = now(),
    teacher_intervention = public.chem_student_skill_state.teacher_intervention
      or (
        (not v_correct or p_uncertain)
        and public.chem_student_skill_state.consecutive_errors + 1 >= 3
      ),
    updated_at = now();

  return next;
end;
$function$;

CREATE OR REPLACE FUNCTION public.chem_junior_finalize_session(p_session_id uuid, p_student_id uuid)
 RETURNS TABLE(completed boolean, total_questions integer, correct_questions integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.chem_junior_daily_sessions%rowtype;
  v_plan public.chem_learning_plans%rowtype;
  v_curriculum public.chem_junior_curriculum_days%rowtype;
  v_plan_mode text;
  v_profile_id uuid;
  v_total integer;
  v_answered integer;
  v_correct integer;
  v_attempt_id uuid;
  v_answer_ledger_count integer;
  v_completed_at timestamptz;
  v_required_skill_count integer;
  v_required_card_count integer;
  v_verified_provenance_count integer;
  v_current_contract_count integer;
begin
  if p_session_id is null or p_student_id is null then
    raise exception 'invalid junior session finalization';
  end if;

  -- Use the same global lifecycle locks as activation, issue, validation and
  -- answer recording before taking the per-session serialization lock.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  -- Reconcile the private first-option queue before deriving mastery. The
  -- original 12/15, source-rights and exact-snapshot checks below are unchanged.
  perform public.chem_junior_option_state(p_student_id,p_session_id);

  perform s.id from public.chem_students_v2 s where s.id=p_student_id for update;
  select session.*
  into v_session
  from public.chem_junior_daily_sessions as session
  where session.id = p_session_id
    and session.student_id = p_student_id
    and session.status in ('active', 'completed')
    and app_private.chem_junior_plan_date_allowed(session.plan_day_id,p_student_id)
  for update;

  if not found
    or pg_catalog.length(pg_catalog.btrim(coalesce(v_session.textbook_version, ''))) = 0
    or v_session.textbook_version = '待确认'
  then
    raise exception 'junior session is unavailable';
  end if;

  -- Re-lock the complete authorization snapshot before touching steps or an
  -- existing attempt.  Even an idempotent retry must prove that the current
  -- plan/profile/curriculum/card contract still authorizes this student.
  select plan.*
  into v_plan
  from public.chem_learning_plans as plan
  where plan.id = v_session.plan_day_id
    and plan.student_id = v_session.student_id
    and plan.student_id = p_student_id
    and plan.delivery_mode = 'junior_adaptive'
    and plan.plan_date = v_session.study_date
    and app_private.chem_junior_plan_date_allowed(plan.id,p_student_id)
    and plan.junior_curriculum_day_id = v_session.curriculum_day_id
    and plan.skill_ids = v_session.knowledge_skill_ids
    and plan.mode = 'REVIEW'
    and plan.question_count = v_session.initial_question_target
    and plan.round_limit = 1 + v_session.recovery_round_limit
  for share;

  if not found then
    raise exception 'junior session plan contract changed before finalization';
  end if;
  v_plan_mode := v_plan.mode;

  select student.id
  into v_profile_id
  from public.chem_students_v2 as student
  where student.id = p_student_id
    and student.grade_band = '初三'
    and student.record_status = 'active'
    and student.textbook_version = v_session.textbook_version
  for share;

  if not found or v_profile_id is null then
    raise exception 'junior student textbook no longer matches the session';
  end if;

  select curriculum.*
  into v_curriculum
  from public.chem_junior_curriculum_days as curriculum
  where curriculum.id = v_session.curriculum_day_id
    and curriculum.textbook_version = v_session.textbook_version
    and curriculum.release_status = 'ready'
    and curriculum.knowledge_skill_ids = v_session.knowledge_skill_ids
  for share;

  if not found
    or cardinality(v_session.knowledge_skill_ids) <> 3
    or (
      select count(distinct requested.skill_id)
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
    ) <> 3
  then
    raise exception 'junior curriculum day is no longer ready or does not match the session';
  end if;

  -- The locked session makes the union stable before step locks are taken.
  -- It includes the current three skills plus every actual recovery skill.
  perform card.id
  from public.chem_knowledge_cards as card
  join (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required
    on required.skill_id = card.skill_id
  where card.review_status = 'approved'
  order by card.skill_id, card.id
  for share of card;

  select count(*)::integer
  into v_required_skill_count
  from (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required_knowledge;

  select count(*)::integer
  into v_required_card_count
  from (
    select required.skill_id
    from (
      select distinct required.skill_id
      from (
        select requested.skill_id
        from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
        union all
        select existing.knowledge_id
        from public.chem_junior_session_steps as existing
        where existing.session_id = p_session_id
      ) as required
    ) as required
    join public.chem_knowledge_cards as card
      on card.skill_id = required.skill_id
     and card.review_status = 'approved'
     and app_private.chem_junior_knowledge_card_is_ready(
       v_session.textbook_version,
       required.skill_id
     )
    group by required.skill_id
    having count(card.id) = 1
  ) as exactly_one_card;

  if v_required_card_count <> v_required_skill_count then
    raise exception 'junior knowledge-card approval contract changed before finalization';
  end if;

  -- Lock all issued steps, then their question, provenance and release rows in
  -- that order.  The following validation reads only rows held by these locks.
  perform step.id
  from public.chem_junior_session_steps as step
  where step.session_id = p_session_id
  order by step.sequence
  for update;

  select
    count(*)::integer,
    (count(*) filter (where step.answered_at is not null))::integer,
    (count(*) filter (where step.correct))::integer
  into v_total, v_answered, v_correct
  from public.chem_junior_session_steps as step
  where step.session_id = p_session_id;

  if v_total not between v_session.initial_question_target and v_session.hard_question_cap
    or v_answered <> v_total then
    raise exception 'junior session is not ready to finalize';
  end if;

  perform question.id
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id
  where step.session_id = p_session_id
  order by question.id
  for share of question;

  perform provenance.knowledge_id
  from app_private.chem_junior_knowledge_provenance as provenance
  join (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required
    on required.skill_id = provenance.knowledge_id
  where provenance.textbook_version = v_session.textbook_version
  order by provenance.knowledge_id
  for share of provenance;

  perform release.id
  from app_private.chem_question_source_releases as release
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  where release.id in (
    select provenance.source_release_id
    from app_private.chem_junior_knowledge_provenance as provenance
    where provenance.textbook_version = v_session.textbook_version
      and provenance.knowledge_id in (
        select required.skill_id
        from (
          select requested.skill_id
          from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
          union
          select existing.knowledge_id
          from public.chem_junior_session_steps as existing
          where existing.session_id = p_session_id
        ) as required
      )
    union
    select question.source_release_id
    from public.chem_junior_session_steps as step
    join public.chem_questions as question
      on question.id = step.question_id
    where step.session_id = p_session_id
  )
  order by release.id
  for share of release, rights;

  -- Every current or recovery knowledge route must still resolve to one
  -- verified provenance row on an active, fully verified native release.
  perform provenance.knowledge_id
  from (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required
  join app_private.chem_junior_knowledge_provenance as provenance
    on provenance.textbook_version = v_session.textbook_version
   and provenance.knowledge_id = required.skill_id
   and provenance.verification_status = 'verified'
   and provenance.reviewed_at is not null
  join app_private.chem_question_source_releases as release
    on release.id = provenance.source_release_id
   and release.grade_band = '初三'
   and release.textbook_version = v_session.textbook_version
   and release.status = 'active'
   and release.verification_status = 'full_visual_verified'
   and release.verification_manifest_sha256 = release.manifest_sha256
   and release.revision_contract = 'v3_junior_native_text'
   and release.verified_at is not null
   and pg_catalog.length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
   and release.activated_at is not null
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0;
  get diagnostics v_verified_provenance_count = row_count;
  if v_verified_provenance_count <> v_required_skill_count then
    raise exception 'junior verified provenance is no longer active';
  end if;

  -- Revalidate every original and its exact issue snapshot while all source
  -- rows remain locked.  The CASE wrappers keep malformed JSON fail-closed
  -- without invoking array functions on a non-array value.
  select count(*)::integer
  into v_current_contract_count
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id
  join app_private.chem_teaching_ready_questions as ready_question
    on ready_question.id = question.id
  join app_private.chem_junior_knowledge_provenance as provenance
    on provenance.textbook_version = v_session.textbook_version
   and provenance.knowledge_id = step.knowledge_id
   and provenance.source_release_id = question.source_release_id
   and provenance.verification_status = 'verified'
  join app_private.chem_question_source_releases as release
    on release.id = provenance.source_release_id
   and release.grade_band = '初三'
   and release.textbook_version = v_session.textbook_version
   and release.status = 'active'
   and release.verification_status = 'full_visual_verified'
   and release.verification_manifest_sha256 = release.manifest_sha256
   and release.revision_contract = 'v3_junior_native_text'
   and release.verified_at is not null
   and pg_catalog.length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
   and release.activated_at is not null
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  where step.session_id = p_session_id
    and step.answered_at is not null
    and question.grade_band = '初三'
    and question.textbook_version = v_session.textbook_version
    and question.source_kind = 'user_provided_local'
    and question.review_status = 'approved'
    and question.scope_status = 'IN'
    and question.usable_for_review
    and question.render_mode = 'native'
    and question.image_url is null
    and question.asset_refs = '[]'::jsonb
    and question.skill_id = step.skill_id
    and question.knowledge_id = step.knowledge_id
    and question.skill_id = question.knowledge_id
    and question.mother_id = step.mother_id
    and question.same_type_key = step.same_type_key
    and question.source_item_key = step.source_item_key
    and question.parent_source_item_key = step.parent_source_item_key
    and question.content_fingerprint = step.content_fingerprint
    and question.level = step.level
    and question.source_release_id is not null
    and pg_catalog.length(pg_catalog.btrim(coalesce(question.stem, ''))) > 0
    and pg_catalog.length(pg_catalog.btrim(coalesce(question.explanation, ''))) > 0
    and pg_catalog.jsonb_typeof(question.options) = 'array'
    and case
      when pg_catalog.jsonb_typeof(question.options) = 'array'
        then pg_catalog.jsonb_array_length(question.options)
      else -1
    end = 4
    and question.correct_option between 0 and 3
    and not exists (
      select 1
      from pg_catalog.jsonb_array_elements(
        case
          when pg_catalog.jsonb_typeof(question.options) = 'array' then question.options
          else '[]'::jsonb
        end
      ) as option_value(value)
      where pg_catalog.jsonb_typeof(option_value.value) is distinct from 'string'
        or pg_catalog.length(pg_catalog.btrim(option_value.value #>> '{}')) = 0
    )
    and (
      select count(distinct pg_catalog.btrim(option_value.value #>> '{}'))
      from pg_catalog.jsonb_array_elements(
        case
          when pg_catalog.jsonb_typeof(question.options) = 'array' then question.options
          else '[]'::jsonb
        end
      ) as option_value(value)
    ) = 4
    and question.content_fingerprint =
      app_private.chem_h3_content_fingerprint(question.stem, question.options)
    and question.question_revision_token =
      app_private.chem_junior_native_revision_sha256(question)
    and step.question_snapshot = pg_catalog.jsonb_build_object(
      'questionId', question.id,
      'motherId', question.mother_id,
      'skillId', question.skill_id,
      'knowledgeId', question.knowledge_id,
      'conceptKey', question.concept_key,
      'level', question.level,
      'gradeBand', question.grade_band,
      'textbookVersion', question.textbook_version,
      'stem', question.stem,
      'options', question.options,
      'correctOption', question.correct_option,
      'explanation', question.explanation,
      'scaffold', question.scaffold,
      'reviewStatus', question.review_status,
      'scopeStatus', question.scope_status,
      'sourceKind', question.source_kind,
      'renderMode', question.render_mode,
      'imageUrl', question.image_url,
      'assetRefs', question.asset_refs,
      'sourceReleaseId', question.source_release_id,
      'sourceItemKey', question.source_item_key,
      'parentSourceItemKey', question.parent_source_item_key,
      'sameTypeKey', question.same_type_key,
      'contentFingerprint', question.content_fingerprint,
      'revisionToken', question.question_revision_token,
      'routeKind', step.route_kind,
      'routeReason', step.route_reason
    )
    and coalesce(step.question_snapshot ->> 'revisionToken', '') =
      coalesce(question.question_revision_token, '');

  if v_current_contract_count <> v_total then
    raise exception 'junior source evidence contract changed before finalization';
  end if;

  -- Only now may a completed retry return.  The existing attempt lookup is
  -- intentionally after all present-tense authorization and source locks so
  -- completion never bypasses a revoked plan/profile/curriculum/card/release.
  select attempt.id
  into v_attempt_id
  from public.chem_learning_attempts as attempt
  where attempt.junior_session_id = p_session_id
    and attempt.student_id = p_student_id
    and attempt.plan_day_id = v_session.plan_day_id
  for share;

  if v_attempt_id is not null then
    if v_session.status <> 'completed' then
      raise exception 'junior attempt exists for a session that is not completed';
    end if;
    select count(*)::integer
    into v_answer_ledger_count
    from public.chem_attempt_answers as answer
    where answer.attempt_id = v_attempt_id;
    if v_answer_ledger_count <> v_total then
      raise exception 'junior immutable answer ledger is incomplete';
    end if;
    return query select true, v_total, v_correct;
    return;
  end if;

  if v_session.status = 'completed' then
    raise exception 'completed junior session has no immutable attempt ledger';
  end if;

  v_completed_at := coalesce(v_session.completed_at, now());
  v_attempt_id := gen_random_uuid();

  insert into public.chem_learning_attempts (
    id,
    student_id,
    plan_day_id,
    attempt_kind,
    sequence,
    mode,
    started_at,
    completed_at,
    first_score,
    junior_session_id
  ) values (
    v_attempt_id,
    p_student_id,
    v_session.plan_day_id,
    'scheduled',
    0,
    v_plan_mode,
    v_session.started_at,
    v_completed_at,
    v_correct,
    p_session_id
  );

  insert into public.chem_attempt_answers (
    attempt_id,
    question_id,
    mother_id,
    skill_id,
    concept_key,
    level,
    correct,
    uncertain,
    duration_sec,
    selected_option,
    question_snapshot,
    created_at
  )
  select
    v_attempt_id,
    step.question_id,
    step.mother_id,
    step.skill_id,
    coalesce(nullif(step.question_snapshot ->> 'conceptKey', ''), question.concept_key),
    step.level,
    step.correct,
    step.uncertain,
    step.duration_sec,
    step.selected_option,
    coalesce(step.question_snapshot, '{}'::jsonb)
      || jsonb_build_object(
        'version', 2,
        'source', 'junior_adaptive_session',
        'capturedAt', step.created_at,
        'answeredAt', step.answered_at,
        'questionId', step.question_id,
        'motherId', step.mother_id,
        'skillId', step.skill_id,
        'knowledgeId', step.knowledge_id,
        'level', step.level,
        'gradeBand', coalesce(nullif(step.question_snapshot ->> 'gradeBand', ''), question.grade_band),
        'textbookVersion', v_session.textbook_version,
        'stem', coalesce(nullif(step.question_snapshot ->> 'stem', ''), question.stem),
        'options', case
          when jsonb_typeof(step.question_snapshot -> 'options') = 'array'
            then step.question_snapshot -> 'options'
          else question.options
        end,
        'correctOption', case
          when jsonb_typeof(step.question_snapshot -> 'correctOption') = 'number'
            then (step.question_snapshot ->> 'correctOption')::smallint
          else question.correct_option
        end,
        'explanation', coalesce(nullif(step.question_snapshot ->> 'explanation', ''), question.explanation),
        'scaffold', coalesce(step.question_snapshot ->> 'scaffold', question.scaffold),
        'sourceKind', 'user_provided_local',
        'sourceReleaseId', coalesce(
          nullif(step.question_snapshot ->> 'sourceReleaseId', ''),
          question.source_release_id::text
        ),
        'sameTypeKey', step.same_type_key,
        'sourceItemKey', step.source_item_key,
        'parentSourceItemKey', step.parent_source_item_key,
        'contentFingerprint', step.content_fingerprint,
        'revisionToken', coalesce(
          nullif(step.question_snapshot ->> 'revisionToken', ''),
          question.question_revision_token
        ),
        'renderMode', coalesce(nullif(step.question_snapshot ->> 'renderMode', ''), question.render_mode),
        'routeKind', step.route_kind,
        'routeReason', step.route_reason,
        'sequence', step.sequence
      ),
    step.answered_at
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id
  where step.session_id = p_session_id
  order by step.sequence;

  select count(*)::integer
  into v_answer_ledger_count
  from public.chem_attempt_answers as answer
  where answer.attempt_id = v_attempt_id;

  if v_answer_ledger_count <> v_total then
    raise exception 'junior immutable answer ledger is incomplete';
  end if;

  with requested_skills as (
    select distinct unnest(v_session.knowledge_skill_ids) as skill_id
  ),
  verified_provenance as (
    select requested.skill_id, provenance.source_release_id
    from requested_skills as requested
    join app_private.chem_junior_knowledge_provenance as provenance
      on provenance.textbook_version = v_session.textbook_version
      and provenance.knowledge_id = requested.skill_id
      and provenance.verification_status = 'verified'
    join app_private.chem_question_source_releases as release
      on release.id = provenance.source_release_id
      and release.grade_band = '初三'
      and release.textbook_version = v_session.textbook_version
      and release.status = 'active'
      and release.verification_status = 'full_visual_verified'
      and release.verification_manifest_sha256 = release.manifest_sha256
      and release.revision_contract = 'v3_junior_native_text'
      and release.verified_at is not null
      and pg_catalog.length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
      and release.activated_at is not null
    join app_private.chem_junior_source_release_rights as rights
      on rights.release_id = release.id
      and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
      and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
      and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  ),
  foundation_levels as (
    select provenance.skill_id, min(question.level)::smallint as foundation_level
    from verified_provenance as provenance
    join public.chem_questions as question
      on question.source_release_id = provenance.source_release_id
      and question.skill_id = provenance.skill_id
      and question.knowledge_id = provenance.skill_id
      and question.grade_band = '初三'
      and question.textbook_version = v_session.textbook_version
      and question.source_kind = 'user_provided_local'
      and question.review_status = 'approved'
      and question.scope_status = 'IN'
      and question.usable_for_review
      and question.render_mode = 'native'
      and coalesce(btrim(question.image_url), '') = ''
      and question.asset_refs = '[]'::jsonb
    group by provenance.skill_id
  ),
  original_evidence as (
    select step.*
    from public.chem_junior_session_steps as step
    join verified_provenance as provenance
      on provenance.skill_id = step.skill_id
    join public.chem_questions as question
      on question.id = step.question_id
      and question.source_release_id = provenance.source_release_id
      and question.skill_id = step.skill_id
      and question.knowledge_id = step.knowledge_id
      and question.grade_band = '初三'
      and question.textbook_version = v_session.textbook_version
      and question.source_kind = 'user_provided_local'
      and question.review_status = 'approved'
      and question.scope_status = 'IN'
      and question.usable_for_review
      and question.render_mode = 'native'
      and coalesce(btrim(question.image_url), '') = ''
      and question.asset_refs = '[]'::jsonb
      and question.mother_id = step.mother_id
      and question.source_item_key = step.source_item_key
      and question.parent_source_item_key = step.parent_source_item_key
      and question.content_fingerprint = step.content_fingerprint
      and question.question_revision_token is not distinct from nullif(step.question_snapshot ->> 'revisionToken', '')
    where step.session_id = p_session_id
  ),
  evidence as (
    select
      requested.skill_id,
      foundation.foundation_level,
      count(distinct original.question_id) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_question_count,
      count(distinct original.mother_id) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_mother_count,
      count(distinct original.source_item_key) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_source_count,
      count(distinct original.parent_source_item_key) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_parent_count,
      count(distinct original.content_fingerprint) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_fingerprint_count,
      count(distinct original.question_id) filter (
        where original.correct
          and not original.uncertain
          and original.level > foundation.foundation_level
      ) as higher_question_count,
      max(original.level) filter (
        where original.correct
          and not original.uncertain
          and original.level > foundation.foundation_level
      )::smallint as achieved_level,
      (
        select count(*)::integer
        from public.chem_junior_session_steps as all_step
        where all_step.session_id = p_session_id
          and all_step.skill_id = requested.skill_id
          and (not all_step.correct or all_step.uncertain)
      ) as error_or_uncertain_count
    from requested_skills as requested
    left join foundation_levels as foundation
      on foundation.skill_id = requested.skill_id
    left join original_evidence as original
      on original.skill_id = requested.skill_id
    group by requested.skill_id, foundation.foundation_level
  ),
  mastery as (
    select
      evidence.*,
      evidence.foundation_level is not null
        and evidence.foundation_question_count >= 2
        and evidence.foundation_mother_count >= 2
        and evidence.foundation_source_count >= 2
        and evidence.foundation_parent_count >= 2
        and evidence.foundation_fingerprint_count >= 2
        and evidence.higher_question_count >= 1
        and evidence.achieved_level > evidence.foundation_level
        and not exists (
          select 1 from app_private.chem_junior_option_branches b
          where b.student_id=p_student_id and b.knowledge_id=evidence.skill_id
            and b.status <> 'consolidated'
        )
        as mastered
    from evidence
  )
  insert into public.chem_student_skill_state (
    student_id,
    skill_id,
    verified_level,
    candidate_level,
    stability,
    consecutive_errors,
    next_review_at,
    review_interval_index,
    last_reviewed_at,
    teacher_intervention,
    updated_at
  )
  select
    p_student_id,
    mastery.skill_id,
    case when mastery.mastered then mastery.achieved_level else 0 end,
    case when mastery.mastered then mastery.achieved_level else null end,
    case when mastery.mastered then 'verified' else 'learning' end,
    mastery.error_or_uncertain_count,
    now() + case when mastery.mastered then interval '3 days' else interval '1 day' end,
    case when mastery.mastered then 1 else 0 end,
    now(),
    not mastery.mastered and mastery.error_or_uncertain_count >= 3,
    now()
  from mastery
  on conflict (student_id, skill_id) do update set
    verified_level = case
      when excluded.stability = 'verified'
        then greatest(public.chem_student_skill_state.verified_level, excluded.verified_level)
      else public.chem_student_skill_state.verified_level
    end,
    candidate_level = case
      when excluded.stability = 'verified' then excluded.candidate_level
      else null
    end,
    stability = case
      when excluded.stability = 'verified' then 'verified'
      when public.chem_student_skill_state.verified_level > 0
        and excluded.consecutive_errors > 0 then 'forgotten'
      else 'learning'
    end,
    consecutive_errors = case
      when excluded.stability = 'verified' then 0
      else greatest(
        public.chem_student_skill_state.consecutive_errors,
        excluded.consecutive_errors
      )
    end,
    next_review_at = excluded.next_review_at,
    review_interval_index = case
      when excluded.stability = 'verified'
        then least(4, public.chem_student_skill_state.review_interval_index + 1)
      else 0
    end,
    last_reviewed_at = now(),
    teacher_intervention = public.chem_student_skill_state.teacher_intervention
      or excluded.teacher_intervention,
    updated_at = now();

  update public.chem_junior_daily_sessions
  set status = 'completed',
      completed_at = v_completed_at,
      blocked_reason_code = null,
      blocked_reason_detail = null,
      blocked_at = null,
      updated_at = now()
  where id = p_session_id;

  return query select true, v_total, v_correct;
end;
$function$;

CREATE OR REPLACE FUNCTION public.chem_junior_option_state_readonly(p_student_id uuid, p_session_id uuid, p_plan_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare sess public.chem_junior_daily_sessions%rowtype; plan public.chem_learning_plans%rowtype;
  result jsonb; daily_count integer; ordinary_count integer; issued_count integer; repetition_history jsonb;
begin
  if p_session_id is null then
    select p.* into plan from public.chem_learning_plans p join public.chem_students_v2 s on s.id=p.student_id
      where p.id=p_plan_id and p.student_id=p_student_id and p.delivery_mode='junior_adaptive'
        and app_private.chem_junior_plan_date_allowed(p.id,p_student_id) and p.mode='REVIEW'
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
    select case when sess.recovery_round_limit=3 then c.repetition_policy else 'fresh_only' end into sess.repetition_policy from public.chem_junior_curriculum_days c where c.id=plan.junior_curriculum_day_id;
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
  repetition_history:=app_private.chem_junior_repetition_history(p_student_id);
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
      when sess.repetition_policy='spaced_review' and exists(select 1 from public.chem_questions q
        where q.id=candidates->(n::integer)->>'questionId'
          and (app_private.chem_junior_repetition_state(q,repetition_history,p_session_id,sess.repetition_policy,
            (now() at time zone 'Asia/Shanghai')::date)->>'eligible') is distinct from 'true')
        and not exists(select 1 from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id
          where os.branch_id=t.id and st.session_id=p_session_id and st.question_id=candidates->(n::integer)->>'questionId' and st.answered_at is null) then 'pending'
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
      when sess.repetition_policy='spaced_review' and exists(select 1 from public.chem_questions q
        where q.id=candidates->(n::integer)->>'questionId'
          and (app_private.chem_junior_repetition_state(q,repetition_history,p_session_id,sess.repetition_policy,
            (now() at time zone 'Asia/Shanghai')::date)->>'eligible') is distinct from 'true')
        and not exists(select 1 from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id
          where os.branch_id=t.id and st.session_id=p_session_id and st.question_id=candidates->(n::integer)->>'questionId' and st.answered_at is null) then 'review_interval_not_due'
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
$function$;

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
    if p_route_kind not in ('new_learning','stability_validation','spaced_review')
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
end; $function$;

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
  repetition_history jsonb;
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
  repetition_history:=app_private.chem_junior_repetition_history(p_student_id);

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
          if (app_private.chem_junior_repetition_state(q,repetition_history,p_session_id,sess.repetition_policy,
              (now() at time zone 'Asia/Shanghai')::date)->>'eligible') is distinct from 'true'
            or exists(select 1 from public.chem_questions a where a.id=branch.anchor_question_id
              and (a.id=q.id or a.mother_id=q.mother_id or a.source_item_key=q.source_item_key
                or a.parent_source_item_key=q.parent_source_item_key or a.content_fingerprint=q.content_fingerprint))
            or exists(select 1 from public.chem_junior_session_steps st where st.session_id=branch.anchor_session_id
              and (st.question_id=q.id or st.mother_id=q.mother_id or st.source_item_key=q.source_item_key or st.parent_source_item_key=q.parent_source_item_key or st.content_fingerprint=q.content_fingerprint))
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
      elsif sess.repetition_policy='spaced_review'
        and (app_private.chem_junior_repetition_state(q,repetition_history,p_session_id,sess.repetition_policy,
          (now() at time zone 'Asia/Shanghai')::date)->>'eligible') is distinct from 'true'
        and not exists(select 1 from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id
          where os.branch_id=branch.id and st.session_id=p_session_id and st.question_id=q.id and st.answered_at is null)
      then branch_status:='pending'; branch_reason:='review_interval_not_due';
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
end; $function$;
