-- Completion validates only the <=30 locked originals from this session.
-- Exact source/rights/provenance/card/revision/snapshot and immutable ledger
-- checks remain intact. No global ready-view scan and no timeout increase.
CREATE OR REPLACE FUNCTION public.chem_junior_finalize_session(p_session_id uuid, p_student_id uuid)
 RETURNS TABLE(completed boolean, total_questions integer, correct_questions integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_required_card_ids text[];
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
  -- Row locks precede every approval/hash decision, including all actual
  -- recovery skills. Hash the bound version only once per required skill.
  perform card.id from public.chem_knowledge_cards card
    join (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids) requested(skill_id)
      union all select existing.knowledge_id from public.chem_junior_session_steps existing where existing.session_id=p_session_id) raw_required) required on required.skill_id=card.skill_id
    order by card.skill_id,card.id for share of card;
  select count(*)::integer,array_agg(app_private.chem_junior_ready_card_id(v_session.textbook_version,required.skill_id) order by required.skill_id)
    into v_required_skill_count,v_required_card_ids from (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids) requested(skill_id)
      union all select existing.knowledge_id from public.chem_junior_session_steps existing where existing.session_id=p_session_id) raw_required) required;
  select count(*)::integer into v_required_card_count
    from unnest(v_required_card_ids) card_id where card_id is not null;

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
  with session_original_ids as materialized (
    select distinct st.question_id from public.chem_junior_session_steps st
    where st.session_id=p_session_id and st.answered_at is not null
  ), ready_original_ids as materialized (
    select original.question_id from session_original_ids original
    where app_private.chem_junior_question_delivery_ready(original.question_id)
  )
  select count(*)::integer
  into v_current_contract_count
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id
  join ready_original_ids as ready_question
    on ready_question.question_id = question.id
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
  demonstrated as (
    select evidence.*,
      app_private.chem_junior_demonstrated_level(v_session.textbook_version,evidence.skill_id,
        v_session.repetition_policy,evidence.foundation_level,
        least(evidence.foundation_question_count,evidence.foundation_mother_count,
          evidence.foundation_source_count,evidence.foundation_parent_count,evidence.foundation_fingerprint_count),
        evidence.higher_question_count,evidence.achieved_level) as demonstrated_level
    from evidence
  ),
  mastery as (
    select demonstrated.*,
      demonstrated.demonstrated_level > 0
        and not exists (
          select 1 from app_private.chem_junior_option_branches b
          where b.student_id=p_student_id and b.knowledge_id=demonstrated.skill_id
            and b.status <> 'consolidated'
        ) as mastered
    from demonstrated
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
    case when mastery.mastered then mastery.demonstrated_level else 0 end,
    case when mastery.mastered then mastery.demonstrated_level else null end,
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
