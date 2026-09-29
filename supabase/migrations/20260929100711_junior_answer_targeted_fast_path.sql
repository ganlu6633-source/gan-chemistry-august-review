-- Preserve source/rights/revision/snapshot/date/round/budget gates while restricting
-- per-question scans and hashing each required bound card once, after row locks.
-- Adds only service-role RPCs: atomic immutable answer acknowledgement and one
-- shared practice pool/availability read. Existing APIs and other grades unchanged.

CREATE OR REPLACE FUNCTION public.chem_question_delivery_holds_for(p_question_ids text[])
 RETURNS TABLE(question_id text, reason text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
select distinct q.id,h.reason
  from app_private.chem_question_delivery_holds h
  join public.chem_questions anchor on anchor.id=h.anchor_question_id
  join public.chem_questions q on q.id=anchor.id
    or (
      q.content_fingerprint=anchor.content_fingerprint
      and not (
        q.parent_source_item_key=anchor.source_item_key
        and q.id<>anchor.id
        and q.grade_band=anchor.grade_band
        and q.source_release_id is distinct from anchor.source_release_id
        and exists (
          select 1
          from app_private.chem_question_source_release_items child_item
          join app_private.chem_question_source_release_items parent_item
            on parent_item.canonical_source_id=child_item.canonical_source_id
           and parent_item.question_id=anchor.id
           and parent_item.release_id=anchor.source_release_id
          join app_private.chem_question_source_releases child_release
            on child_release.id=q.source_release_id
          where child_item.question_id=q.id
            and child_item.release_id=q.source_release_id
            and child_release.status='active'
            and child_release.verification_status='full_visual_verified'
            and child_release.manifest_sha256=child_release.verification_manifest_sha256
            and app_private.chem_question_item_visual_reviewed(q.id)
        )
      )
    )
  where h.resolved_at is null and q.id=any(p_question_ids)
  union
  select review.question_id,'逐题原题图像、公式和解析待复核'::text
  from app_private.chem_question_item_visual_reviews review
  join public.chem_questions reviewed_question on reviewed_question.id=review.question_id
  join app_private.chem_question_source_releases reviewed_release
    on reviewed_release.id=reviewed_question.source_release_id
  where review.question_id=any(p_question_ids) and reviewed_question.usable_for_review and reviewed_release.status='active'
    and case review.review_state when 'verified' then not app_private.chem_question_item_visual_reviewed(review.question_id) when 'legacy_carried' then not app_private.chem_question_item_legacy_carried(review.question_id) else true end;
$function$;
create function app_private.chem_junior_question_delivery_ready(p_question_id text)
returns boolean language sql stable security definer set search_path='' as $function$
 select exists(
   select 1 from public.chem_questions q
   join app_private.chem_question_source_releases r on r.id=q.source_release_id
   where q.id=p_question_id and q.review_status='approved' and q.scope_status='IN' and q.usable_for_review
     and r.status='active' and r.verification_status='full_visual_verified'
     and r.manifest_sha256=r.verification_manifest_sha256
     and jsonb_typeof(q.options)='array' and jsonb_array_length(q.options)=4
     and q.correct_option between 0 and 3 and length(btrim(q.stem))>0 and length(btrim(q.explanation))>0
     and q.content_fingerprint is not null and q.source_item_key is not null
     and q.grade_band='初三' and q.source_kind='user_provided_local' and q.render_mode='native' and q.textbook_version='科粤版'
     and app_private.chem_question_item_delivery_review_ready(q.id)
     and not exists(select 1 from public.chem_question_delivery_holds_for(array[q.id]) h where h.question_id=q.id)
     and exists(select 1 from public.chem_junior_verified_provenance_rows('科粤版',array[q.knowledge_id]) p
       where p.knowledge_id=q.knowledge_id and p.source_release_id=q.source_release_id
         and p.verification_status='verified' and p.source_release_ready)
 );
$function$;
revoke all on function public.chem_question_delivery_holds_for(text[]) from public,anon,authenticated;
grant execute on function public.chem_question_delivery_holds_for(text[]) to service_role;
revoke all on function app_private.chem_junior_question_delivery_ready(text) from public,anon,authenticated;
grant execute on function app_private.chem_junior_question_delivery_ready(text) to service_role;


CREATE OR REPLACE FUNCTION public.chem_junior_record_step(p_session_id uuid, p_student_id uuid, p_step_id uuid, p_selected_option smallint, p_uncertain boolean, p_duration_sec integer, p_revision_token text)
 RETURNS TABLE(step_id uuid, question_id text, selected_option smallint, uncertain boolean, duration_sec integer, correct boolean, answered_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_required_card_ids text[];
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
  -- Lock all versions for the required skills before checking the bound approved
  -- version once per skill. Approval/content changes cannot race the check.
  perform card.id from public.chem_knowledge_cards card
    join (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids) requested(skill_id)
      union all select st.knowledge_id from public.chem_junior_session_steps st where st.session_id=p_session_id) required_raw) required on required.skill_id=card.skill_id
    order by card.skill_id,card.id for share of card;
  select count(*)::integer,array_agg(app_private.chem_junior_ready_card_id(v_session.textbook_version,required.skill_id) order by required.skill_id)
    into v_required_knowledge_count,v_required_card_ids
  from (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids) requested(skill_id)
      union all select st.knowledge_id from public.chem_junior_session_steps st where st.session_id=p_session_id) required_raw) required;
  select count(*)::integer into v_required_card_count from unnest(v_required_card_ids) id where id is not null;

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
  if not app_private.chem_junior_question_delivery_ready(v_question.id) then
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
CREATE OR REPLACE FUNCTION public.chem_junior_issue_step(p_session_id uuid, p_student_id uuid, p_question_id text, p_sequence smallint, p_route_kind text, p_route_reason text, p_question_snapshot jsonb)
 RETURNS TABLE(step_id uuid, question_id text, sequence smallint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_required_card_ids text[];
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
  if not app_private.chem_junior_question_delivery_ready(v_question.id) then
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
  elsif p_route_kind='foundation_repair' and app_private.chem_junior_frozen_recovery_allows(
    p_student_id,p_session_id,v_question.id,v_question.question_revision_token,null,
    coalesce(nullif(pg_catalog.current_setting('app.chem_junior_practice_round',true),''),'0')::smallint) then
    null; -- Only the exact next frozen wrong-option route may cross today's curriculum.
  elsif not (v_question.knowledge_id = any(v_session.knowledge_skill_ids)) then
    raise exception 'junior non-recovery question is outside the locked curriculum skills';
  end if;

  -- Lock and require exactly one approved knowledge card for every current
  -- curriculum skill and for the selected recovery skill, if it is outside
  -- the current three. This closes the Edge card-read/change race.
  -- Lock all versions for the required skills before checking the bound approved
  -- version once per skill. Approval/content changes cannot race the check.
  perform card.id from public.chem_knowledge_cards card
    join (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) requested(skill_id)) required_raw) required on required.skill_id=card.skill_id
    order by card.skill_id,card.id for share of card;
  select count(*)::integer,array_agg(app_private.chem_junior_ready_card_id(v_session.textbook_version,required.skill_id) order by required.skill_id)
    into v_required_knowledge_count,v_required_card_ids
  from (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) requested(skill_id)) required_raw) required;
  select count(*)::integer into v_required_card_count from unnest(v_required_card_ids) id where id is not null;

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
  v_required_card_ids text[];
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
  if not app_private.chem_junior_question_delivery_ready(v_question.id) then
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
  elsif v_step.route_kind='foundation_repair' and app_private.chem_junior_frozen_recovery_allows(
    p_student_id,p_session_id,v_question.id,v_question.question_revision_token,v_step.id,v_step.practice_round) then
    null;
  elsif not (v_question.knowledge_id = any(v_session.knowledge_skill_ids)) then
    raise exception 'junior issued non-recovery step is outside the locked curriculum skills';
  end if;

  -- Lock all versions for the required skills before checking the bound approved
  -- version once per skill. Approval/content changes cannot race the check.
  perform card.id from public.chem_knowledge_cards card
    join (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) requested(skill_id)) required_raw) required on required.skill_id=card.skill_id
    order by card.skill_id,card.id for share of card;
  select count(*)::integer,array_agg(app_private.chem_junior_ready_card_id(v_session.textbook_version,required.skill_id) order by required.skill_id)
    into v_required_knowledge_count,v_required_card_ids
  from (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) requested(skill_id)) required_raw) required;
  select count(*)::integer into v_required_card_count from unnest(v_required_card_ids) id where id is not null;

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
              and not exists(select 1 from public.chem_question_delivery_holds_for(array[question.id]) h where h.question_id=question.id);
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
        or exists(select 1 from public.chem_question_delivery_holds_for(array[next_id]) h where h.question_id=next_id)
      then branch_status:='reserve_gap'; branch_reason:='reserved_original_unavailable';
      elsif sess.repetition_policy='spaced_review'
        and (app_private.chem_junior_repetition_state(q,repetition_history,p_session_id,sess.repetition_policy,
          (now() at time zone 'Asia/Shanghai')::date)->>'eligible') is distinct from 'true'
        and not exists(select 1 from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id
          where os.branch_id=branch.id and st.session_id=p_session_id and st.question_id=q.id and st.answered_at is null)
      then branch_status:='pending'; branch_reason:='review_interval_not_due';
      elsif not (q.knowledge_id=any(sess.knowledge_skill_ids))
        and not app_private.chem_junior_frozen_recovery_allows(p_student_id,p_session_id,q.id,q.question_revision_token) then branch_status:='pending'; branch_reason:='waiting_for_compatible_curriculum';
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
        and not exists(select 1 from public.chem_question_delivery_holds_for(array[q.id]) h where h.question_id=q.id)) then 'reserve_gap'
      when sess.repetition_policy='spaced_review' and exists(select 1 from public.chem_questions q
        where q.id=candidates->(n::integer)->>'questionId'
          and (app_private.chem_junior_repetition_state(q,repetition_history,p_session_id,sess.repetition_policy,
            (now() at time zone 'Asia/Shanghai')::date)->>'eligible') is distinct from 'true')
        and not exists(select 1 from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id
          where os.branch_id=t.id and st.session_id=p_session_id and st.question_id=candidates->(n::integer)->>'questionId' and st.answered_at is null) then 'pending'
      when not exists(select 1 from public.chem_questions compatible where compatible.id=candidates->(n::integer)->>'questionId'
        and (compatible.knowledge_id=any(sess.knowledge_skill_ids)
          or app_private.chem_junior_frozen_recovery_allows(p_student_id,p_session_id,compatible.id,compatible.question_revision_token))) or sess.status<>'active' or issued_count>=sess.hard_question_cap
        or (sess.recovery_round_limit=3 and ordinary_count<sess.initial_question_target) or (app_private.chem_junior_budget_enabled(p_student_id) and daily_count>=30) then 'pending'
      else 'practicing' end current_status,
      case
      when sess.recovery_round_limit=3 and ordinary_count<sess.initial_question_target and jsonb_array_length(candidates)=0 then 'initial_round_in_progress'
      when jsonb_array_length(candidates)<3 then 'fewer_than_three_verified_fresh_originals'
      when n>=target then case when last_good then '' else 'reviewed_reserves_exhausted_without_three_consecutive_correct' end
      when not exists(select 1 from public.chem_questions q where q.id=candidates->(n::integer)->>'questionId'
        and q.question_revision_token=candidates->(n::integer)->>'revisionToken' and q.usable_for_review
        and not exists(select 1 from public.chem_question_delivery_holds_for(array[q.id]) h where h.question_id=q.id)) then 'reserved_original_unavailable'
      when sess.repetition_policy='spaced_review' and exists(select 1 from public.chem_questions q
        where q.id=candidates->(n::integer)->>'questionId'
          and (app_private.chem_junior_repetition_state(q,repetition_history,p_session_id,sess.repetition_policy,
            (now() at time zone 'Asia/Shanghai')::date)->>'eligible') is distinct from 'true')
        and not exists(select 1 from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id
          where os.branch_id=t.id and st.session_id=p_session_id and st.question_id=candidates->(n::integer)->>'questionId' and st.answered_at is null) then 'review_interval_not_due'
      when not exists(select 1 from public.chem_questions compatible where compatible.id=candidates->(n::integer)->>'questionId'
        and (compatible.knowledge_id=any(sess.knowledge_skill_ids)
          or app_private.chem_junior_frozen_recovery_allows(p_student_id,p_session_id,compatible.id,compatible.question_revision_token))) then 'waiting_for_compatible_curriculum'
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
CREATE OR REPLACE FUNCTION public.chem_junior_practice_pool(p_student_id uuid, p_plan_id uuid, p_session_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF chem_questions
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare plan public.chem_learning_plans%rowtype; sess public.chem_junior_daily_sessions%rowtype;
begin
 select * into plan from public.chem_learning_plans where id=p_plan_id and student_id=p_student_id
   and delivery_mode='junior_adaptive';
 if not found or not app_private.chem_junior_plan_date_allowed(p_plan_id,p_student_id)
 then raise exception 'junior practice pool plan unavailable'; end if;
 if p_session_id is not null then
   select * into sess from public.chem_junior_daily_sessions
   where id=p_session_id and student_id=p_student_id and plan_day_id=p_plan_id;
   if not found then raise exception 'junior practice pool session ownership mismatch'; end if;
 else
   -- The teacher requests the pool before loading the real session in parallel.
   -- Resolve it by the owned plan so old frozen policies are not reinterpreted.
   select * into sess from public.chem_junior_daily_sessions
   where student_id=p_student_id and plan_day_id=p_plan_id;
   if found then p_session_id:=sess.id; end if;
 end if;
 return query
 with recursive ready_skills as materialized (
   select c.skill_id from public.chem_junior_bound_knowledge_cards('科粤版',null) c
 ), held as materialized (
   select h.question_id from public.chem_question_delivery_holds_for(array(
     select q.id from public.chem_questions q where q.grade_band='初三' and q.textbook_version='科粤版' and q.usable_for_review)) h
 ), eligible as materialized (
   select q.* from public.chem_questions q
   join ready_skills ready on ready.skill_id=q.knowledge_id
   join app_private.chem_junior_knowledge_provenance p
     on p.knowledge_id=q.knowledge_id and p.textbook_version='科粤版'
       and p.source_release_id=q.source_release_id and p.verification_status='verified'
   where q.grade_band='初三' and q.textbook_version='科粤版'
     and q.source_kind='user_provided_local' and q.review_status='approved'
     and q.scope_status='IN' and q.usable_for_review and q.render_mode='native'
     and not exists(select 1 from held where held.question_id=q.id)
 ), seeds as (
   select q.id from eligible q where q.knowledge_id=any(plan.skill_ids)
   union
   select q.id from eligible q join public.chem_junior_session_steps st on st.question_id=q.id
     where st.session_id=p_session_id
   union
   select q.id from eligible q join app_private.chem_junior_option_branches b
     on q.id=b.anchor_question_id where b.student_id=p_student_id
   union
   select q.id from app_private.chem_junior_option_branches b
     cross join lateral jsonb_array_elements(b.candidates) c
     join eligible q on q.id=c->>'questionId' and q.question_revision_token=c->>'revisionToken'
     where b.student_id=p_student_id
 ), reachable(id,depth) as (
   select seeds.id,0 from seeds
   union
   select q.id,path.depth+1 from reachable path
   join eligible anchor on anchor.id=path.id
   join app_private.chem_option_practice_bindings b on b.anchor_question_id=anchor.id
     and b.anchor_revision_token=anchor.question_revision_token and b.review_status='verified'
   cross join lateral jsonb_array_elements(b.candidates) c
   join eligible q on q.id=c->>'questionId' and q.question_revision_token=c->>'revisionToken'
   where path.depth<3 and (case when p_session_id is null then plan.question_count=8 and plan.round_limit=4
     else sess.recovery_round_limit=3 end)
 )
 select q.* from eligible q where exists(select 1 from reachable r where r.id=q.id) order by q.id;
end;$function$;
CREATE OR REPLACE FUNCTION app_private.chem_junior_ready_card_id(p_textbook_version text, p_knowledge_id text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when count(*) = 1 then min(ready_card.card_id) else null end
  from (
      select card.id as card_id
      from app_private.chem_junior_knowledge_provenance as provenance
      join app_private.chem_question_source_releases as release_row
        on release_row.id = provenance.source_release_id
      join app_private.chem_junior_source_release_rights as rights
        on rights.release_id = release_row.id
      join app_private.chem_junior_knowledge_card_bindings as binding
        on binding.release_id = release_row.id
       and binding.textbook_version = provenance.textbook_version
       and binding.knowledge_id = provenance.knowledge_id
      join public.chem_knowledge_cards as card
        on card.id = binding.card_id
       and card.skill_id = binding.knowledge_id
      where p_textbook_version = '科粤版'
        and provenance.textbook_version = p_textbook_version
        and provenance.knowledge_id = p_knowledge_id
        and provenance.verification_status = 'verified'
        and provenance.reviewed_at is not null
        and release_row.grade_band = '初三'
        and release_row.textbook_version = p_textbook_version
        and release_row.status = 'active'
        and release_row.verification_status = 'full_visual_verified'
        and release_row.verification_manifest_sha256 = release_row.manifest_sha256
        and release_row.revision_contract = 'v3_junior_native_text'
        and release_row.verified_at is not null
        and release_row.activated_at is not null
        and app_private.chem_junior_knowledge_card_binding_matches(
          release_row.id,
          p_textbook_version,
          p_knowledge_id
        )
        and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
        and rights.redistribution_allowed = false
        and rights.attested_manifest_sha256 = release_row.manifest_sha256
        and rights.attested_card_manifest_sha256 =
          app_private.chem_junior_knowledge_card_manifest_sha256(release_row.id)
        and rights.attested_at is not null
        and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
        and binding.source_verification_status = 'visually_verified'
        and binding.verified_at is not null
        and binding.verification_actor = 'codex-knowledge-card-source-qa'
        and card.review_status = 'approved'
    ) as ready_card;
$function$;
-- Internal-only answer acknowledgement: no queue preparation or full payload fetch.
create or replace function public.chem_junior_submit_answer(
 p_student_id uuid,p_plan_id uuid,p_step_id uuid,p_selected_option smallint,
 p_uncertain boolean,p_duration_sec integer,p_revision_token text)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare
 learner public.chem_students_v2%rowtype;
 plan public.chem_learning_plans%rowtype;
 sess public.chem_junior_daily_sessions%rowtype;
 st public.chem_junior_session_steps%rowtype;
 program jsonb; unit_id text; replayed boolean;
begin
 if p_student_id is null or p_plan_id is null or p_step_id is null
   or p_selected_option is null or p_selected_option not between 0 and 3
   or p_uncertain is null or p_duration_sec is null or p_duration_sec not between 0 and 3600
   or nullif(btrim(p_revision_token),'') is null
 then raise exception 'junior_answer_unavailable'; end if;
 -- Keep the same lifecycle -> learner -> session order as issue/record.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release',0));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release',0));
 select * into learner from public.chem_students_v2 where id=p_student_id for update;
 if not found or learner.record_status is distinct from 'active'
   or learner.grade_band is distinct from '初三' or learner.textbook_version is distinct from '科粤版'
   or coalesce(learner.metadata->'demo','null'::jsonb) not in ('null'::jsonb,'false'::jsonb,'0'::jsonb,'""'::jsonb)
 then raise exception 'junior_answer_unavailable'; end if;
 select * into sess from public.chem_junior_daily_sessions
   where student_id=p_student_id and plan_day_id=p_plan_id for update;
 if not found then raise exception 'junior_answer_unavailable'; end if;
 select * into plan from public.chem_learning_plans
   where id=p_plan_id and student_id=p_student_id and delivery_mode='junior_adaptive'
     and mode='REVIEW' for share;
 if not found then raise exception 'junior_answer_unavailable'; end if;
 select c.unit_id into unit_id from public.chem_junior_curriculum_days c
   where c.id=plan.junior_curriculum_day_id for share;
 if not found then raise exception 'junior_answer_unavailable'; end if;
 -- Mirror programPlanVisible/readReviewProgram. The PLAN date, not today's
 -- date, defines access: a pupil may catch up after the programme's end.
 program:=learner.metadata->'reviewProgram';
 if coalesce(program,'null'::jsonb) not in ('null'::jsonb,'false'::jsonb,'0'::jsonb,'""'::jsonb) then
   if program->'participating' is distinct from 'true'::jsonb
     or coalesce(program->>'startDate','') !~ '^\d{4}-\d{2}-\d{2}$'
     or coalesce(program->>'endDate','') !~ '^\d{4}-\d{2}-\d{2}$'
     or (program->>'startDate')>(program->>'endDate')
     or plan.plan_date::text not between program->>'startDate' and program->>'endDate'
     or plan.is_scheduled is distinct from true
   then raise exception 'junior_answer_unavailable'; end if;
   if program ? 'juniorUnitIds' then
     if jsonb_typeof(program->'juniorUnitIds') is distinct from 'array' then
       raise exception 'junior_answer_unavailable';
     end if;
     if jsonb_array_length(program->'juniorUnitIds')=0
       or exists(select 1 from jsonb_array_elements(program->'juniorUnitIds') value
         where jsonb_typeof(value) is distinct from 'string' or btrim(value#>>'{}')='')
       or not(program->'juniorUnitIds' ? coalesce(unit_id,''))
     then raise exception 'junior_answer_unavailable'; end if;
   end if;
 end if;
 select * into st from public.chem_junior_session_steps
   where id=p_step_id and session_id=sess.id for update;
 if not found then raise exception 'junior_answer_unavailable'; end if;
 if st.question_snapshot->>'revisionToken' is distinct from p_revision_token
 then raise exception 'junior_answer_changed'; end if;
 replayed:=st.answered_at is not null;
 if replayed then
   -- The stored answer and source snapshot are immutable. Current source
   -- retirement/review changes cannot alter already confirmed feedback.
   if st.selected_option is distinct from p_selected_option or st.uncertain is distinct from p_uncertain
   then raise exception 'junior_answer_locked'; end if;
 else
   if sess.status is distinct from 'active'
     or (select count(*) from public.chem_junior_session_steps
          where session_id=sess.id and answered_at is null)<>1
   then raise exception 'junior_answer_unavailable'; end if;
   perform public.chem_junior_record_step(sess.id,p_student_id,p_step_id,
      p_selected_option,p_uncertain,p_duration_sec,p_revision_token);
   select * into strict st from public.chem_junior_session_steps where id=p_step_id;
 end if;
 return jsonb_build_object('stepId',st.id,'questionId',st.question_id,
   'selectedOption',st.selected_option,'uncertain',st.uncertain,'durationSec',st.duration_sec,
   'correct',st.correct,'answeredAt',st.answered_at,'replayed',replayed,
   'questionSnapshot',st.question_snapshot);
end;
$function$;
revoke all on function public.chem_junior_submit_answer(uuid,uuid,uuid,smallint,boolean,integer,text) from public,anon,authenticated;
grant execute on function public.chem_junior_submit_answer(uuid,uuid,uuid,smallint,boolean,integer,text) to service_role;

-- Build and validate one exact source pool; derive availability from those rows.
create or replace function public.chem_junior_practice_context(
 p_student_id uuid,p_plan_id uuid,p_session_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare plan public.chem_learning_plans%rowtype; sess public.chem_junior_daily_sessions%rowtype;
 pol text; hist jsonb; questions jsonb; availability jsonb;
begin
 select * into plan from public.chem_learning_plans
   where id=p_plan_id and student_id=p_student_id and delivery_mode='junior_adaptive';
 if not found or not app_private.chem_junior_plan_date_allowed(p_plan_id,p_student_id)
 then raise exception 'junior repetition plan unavailable'; end if;
 if p_session_id is not null then
   select * into sess from public.chem_junior_daily_sessions
     where id=p_session_id and student_id=p_student_id and plan_day_id=p_plan_id;
   if not found then raise exception 'junior repetition session ownership mismatch'; end if;
 else
   select * into sess from public.chem_junior_daily_sessions
     where student_id=p_student_id and plan_day_id=p_plan_id;
   if found then p_session_id:=sess.id; end if;
 end if;
 if sess.id is not null then pol:=sess.repetition_policy;
 else
   select case when plan.question_count=8 and plan.round_limit=4 then c.repetition_policy else 'fresh_only' end
     into pol from public.chem_junior_curriculum_days c where c.id=plan.junior_curriculum_day_id;
 end if;
 hist:=app_private.chem_junior_repetition_history(p_student_id);
 select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]'::jsonb),
   coalesce(jsonb_object_agg(q.id,app_private.chem_junior_repetition_state(q,hist,p_session_id,pol,(now() at time zone 'Asia/Shanghai')::date)),'{}'::jsonb)
 into questions,availability from public.chem_junior_practice_pool(p_student_id,p_plan_id,p_session_id) q;
 return jsonb_build_object('questions',questions,'availability',jsonb_build_object('policy',pol,'questions',availability));
end;
$function$;
revoke all on function public.chem_junior_practice_context(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.chem_junior_practice_context(uuid,uuid,uuid) to service_role;
