-- Only the three reviewed first-lesson routes use a foundation-only inventory.
-- No question, student history, source review, rights, or reserve binding is changed.
create or replace function app_private.chem_junior_route_is_foundation_only(
 p_textbook_version text, p_knowledge_id text
) returns boolean language sql immutable set search_path='' as $function$
 select coalesce(p_textbook_version='科粤版' and p_knowledge_id in
   ('J_KY_1_1_K01','J_KY_1_1_K02','J_KY_1_1_K03'),false);
$function$;
create or replace function app_private.chem_junior_route_inventory_valid(
 p_textbook_version text, p_knowledge_id text, p_total bigint, p_foundation bigint,
 p_higher bigint, p_foundation_level smallint
) returns boolean language sql immutable set search_path='' as $function$
 select coalesce(p_total>=7 and case
   when app_private.chem_junior_route_is_foundation_only(p_textbook_version,p_knowledge_id)
   then p_foundation_level=1 and p_foundation>=7
   else p_foundation>=5 and p_higher>=2 end,false);
$function$;
-- Return the actually demonstrated tier. Three independent L1 successes are
-- the introductory analogue of two foundation plus one higher-level success.
-- Callers pass the minimum of five distinct-source identity counts.
create or replace function app_private.chem_junior_demonstrated_level(
 p_textbook_version text,p_knowledge_id text,p_repetition_policy text,
 p_foundation_level smallint,p_foundation_identities bigint,p_higher bigint,p_achieved_level smallint
) returns smallint language sql immutable set search_path='' as $function$
 select case
 when p_repetition_policy='spaced_review'
   and app_private.chem_junior_route_is_foundation_only(p_textbook_version,p_knowledge_id)
 then case when p_foundation_level=1 and p_foundation_identities>=3 then 1 else 0 end
 else case when p_foundation_identities>=2 and p_higher>=1
   and p_achieved_level>p_foundation_level then p_achieved_level else 0 end
 end::smallint;
$function$;
revoke all on function app_private.chem_junior_route_is_foundation_only(text,text) from public,anon,authenticated;
revoke all on function app_private.chem_junior_route_inventory_valid(text,text,bigint,bigint,bigint,smallint) from public,anon,authenticated;
revoke all on function app_private.chem_junior_demonstrated_level(text,text,text,smallint,bigint,bigint,smallint) from public,anon,authenticated;
grant execute on function app_private.chem_junior_route_is_foundation_only(text,text) to service_role;
grant execute on function app_private.chem_junior_route_inventory_valid(text,text,bigint,bigint,bigint,smallint) to service_role;
grant execute on function app_private.chem_junior_demonstrated_level(text,text,text,smallint,bigint,bigint,smallint) to service_role;

CREATE OR REPLACE FUNCTION app_private.chem_assert_junior_source_release(p_release_id uuid, p_manifest_sha256 text, p_require_full_visual_verified boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_textbook_version text;
  v_knowledge_ids text[];
  v_expected integer;
  v_status text;
  v_verification_status text;
  v_verification_manifest text;
  v_verification_actor text;
  v_verified_at timestamptz;
  v_question_count integer;
  v_item_count integer;
  v_provenance_count integer;
  v_distinct_count integer;
  v_computed_manifest text;
  v_empty_asset_sha256 constant text :=
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
begin
  if p_release_id is null
    or coalesce(p_manifest_sha256, '') !~ '^[0-9a-f]{64}$'
    or p_require_full_visual_verified is null
  then
    raise exception 'invalid junior release preflight identity';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  select
    release_row.textbook_version,
    spec.knowledge_ids,
    release_row.expected_question_count,
    release_row.status,
    release_row.verification_status,
    release_row.verification_manifest_sha256,
    release_row.verification_actor,
    release_row.verified_at
  into
    v_textbook_version,
    v_knowledge_ids,
    v_expected,
    v_status,
    v_verification_status,
    v_verification_manifest,
    v_verification_actor,
    v_verified_at
  from app_private.chem_question_source_releases as release_row
  join app_private.chem_junior_source_release_specs as spec
    on spec.release_id = release_row.id
   and spec.textbook_version = release_row.textbook_version
  where release_row.id = p_release_id
    and release_row.manifest_sha256 = p_manifest_sha256
    and release_row.grade_band = '初三'
    and release_row.revision_contract = 'v3_junior_native_text'
  for update of release_row, spec;

  if not found
    or v_textbook_version is distinct from '科粤版'
    or v_status <> 'staged'
    or v_expected not between 21 and 2000
    or cardinality(v_knowledge_ids) not between 3 and 200
    or v_expected < 7 * cardinality(v_knowledge_ids)
    or (
      p_require_full_visual_verified
      and (
        v_verification_status <> 'full_visual_verified'
        or v_verification_manifest is distinct from p_manifest_sha256
        or v_verification_actor is distinct from 'codex-full-visual-qa'
        or v_verified_at is null
      )
    )
  then
    raise exception 'junior release is missing, not staged, or not bound to its verified manifest';
  end if;

  perform rights.release_id
  from app_private.chem_junior_source_release_rights as rights
  where rights.release_id = p_release_id
  for update;

  perform source_provenance.knowledge_id
  from app_private.chem_junior_source_release_provenance as source_provenance
  where source_provenance.release_id = p_release_id
  order by source_provenance.knowledge_id
  for update;

  perform binding.knowledge_id
  from app_private.chem_junior_knowledge_card_bindings as binding
  where binding.release_id = p_release_id
  order by binding.knowledge_id
  for update;

  perform card.id
  from app_private.chem_junior_knowledge_card_bindings as binding
  join public.chem_knowledge_cards as card on card.id = binding.card_id
  where binding.release_id = p_release_id
  order by card.id
  for update of card;

  if (
    select count(*)
    from app_private.chem_junior_knowledge_card_bindings as binding
    where binding.release_id = p_release_id
  ) <> cardinality(v_knowledge_ids)
    or exists (
      select 1
      from app_private.chem_junior_knowledge_card_bindings as binding
      where binding.release_id = p_release_id
        and (
          binding.textbook_version is distinct from v_textbook_version
          or not (binding.knowledge_id = any(v_knowledge_ids))
        )
    )
    or exists (
      select 1
      from pg_catalog.unnest(v_knowledge_ids) as required(knowledge_id)
      where not app_private.chem_junior_knowledge_card_binding_matches(
        p_release_id,
        v_textbook_version,
        required.knowledge_id
      )
    )
  then
    raise exception 'junior release knowledge cards no longer match the exact source-verified binding contract';
  end if;

  if not exists (
    select 1
    from app_private.chem_junior_source_release_rights as rights
    where rights.release_id = p_release_id
      and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
      and rights.redistribution_allowed = false
      and rights.attested_manifest_sha256 = p_manifest_sha256
      and rights.attested_card_manifest_sha256 =
        app_private.chem_junior_knowledge_card_manifest_sha256(p_release_id)
      and rights.attested_at is not null
      and length(btrim(rights.attestation_actor)) > 0
  ) then
    raise exception 'junior release is missing the private-use, no-redistribution rights contract';
  end if;

  -- The parent row lock blocks new FK children.  Deterministic child locks
  -- close update/delete races before any count, digest or provenance check.
  perform question.id
  from public.chem_questions as question
  where question.source_release_id = p_release_id
  order by question.id
  for update;

  perform item.question_id
  from app_private.chem_question_source_release_items as item
  where item.release_id = p_release_id
  order by item.question_id
  for update;

  perform provenance.knowledge_id
  from app_private.chem_junior_source_release_provenance as provenance
  where provenance.release_id = p_release_id
  order by provenance.knowledge_id
  for update;

  perform asset.asset_path
  from app_private.chem_question_assets as asset
  join public.chem_questions as question on question.id = asset.question_id
  where question.source_release_id = p_release_id
  order by asset.asset_path
  for update of asset;

  -- Curriculum publication is rare and must not race a source activation.
  -- SHARE blocks concurrent ready-day INSERT/UPDATE until this transaction's
  -- full subset check and atomic release switch have completed.
  lock table public.chem_junior_curriculum_days in share mode;

  if exists (
    select 1
    from public.chem_junior_curriculum_days as curriculum
    cross join lateral pg_catalog.unnest(curriculum.knowledge_skill_ids)
      as requested(knowledge_id)
    where curriculum.textbook_version = v_textbook_version
      and curriculum.release_status = 'ready'
      and not (requested.knowledge_id = any(v_knowledge_ids))
  ) or exists (
    select 1
    from public.chem_junior_daily_sessions as session
    cross join lateral pg_catalog.unnest(session.knowledge_skill_ids)
      as requested(knowledge_id)
    where session.textbook_version = v_textbook_version
      and session.status = 'active'
      and not (requested.knowledge_id = any(v_knowledge_ids))
  ) then
    raise exception 'junior release spec does not fund every ready curriculum or active-session route';
  end if;

  select count(*)::integer
  into v_question_count
  from public.chem_questions as question
  where question.source_release_id = p_release_id;
  if v_question_count <> v_expected then
    raise exception 'junior release must contain exactly % questions, found %',
      v_expected, v_question_count;
  end if;

  select count(*)::integer
  into v_item_count
  from app_private.chem_question_source_release_items as item
  where item.release_id = p_release_id;
  if v_item_count <> v_expected then
    raise exception 'junior release ledger must contain exactly % items, found %',
      v_expected, v_item_count;
  end if;

  if exists (
    select 1
    from app_private.chem_question_assets as asset
    join public.chem_questions as question on question.id = asset.question_id
    where question.source_release_id = p_release_id
  ) then
    raise exception 'junior native-text release must contain zero private assets';
  end if;

  if exists (
    select 1
    from public.chem_questions as question
    left join public.chem_skills as skill on skill.id = question.skill_id
    where question.source_release_id = p_release_id
      and (
        question.grade_band <> '初三'
        or question.textbook_version is distinct from v_textbook_version
        or not (question.knowledge_id = any(v_knowledge_ids))
        or question.skill_id is distinct from question.knowledge_id
        or skill.id is null
        or skill.grade_band <> '初三'
        or not skill.active
        or question.level not between 1 and skill.max_level
        or question.source_kind <> 'user_provided_local'
        or question.review_status <> 'approved'
        or question.scope_status <> 'IN'
        or question.usable_for_review
        or question.usable_for_class_quiz
        or question.usable_for_exam_sprint
        or question.usable_for_demo
        or question.render_mode <> 'native'
        or coalesce(btrim(question.image_url), '') <> ''
        or question.asset_refs <> '[]'::jsonb
        or length(btrim(coalesce(question.mother_id, ''))) = 0
        or length(btrim(coalesce(question.concept_key, ''))) = 0
        or length(btrim(coalesce(question.same_type_key, ''))) = 0
        or length(btrim(coalesce(question.source_item_key, ''))) < 16
        or length(btrim(coalesce(question.parent_source_item_key, ''))) < 16
        or length(btrim(coalesce(question.stem, ''))) = 0
        or length(btrim(coalesce(question.explanation, ''))) = 0
        or pg_catalog.jsonb_typeof(question.options) <> 'array'
        or case when pg_catalog.jsonb_typeof(question.options) = 'array'
          then pg_catalog.jsonb_array_length(question.options) <> 4
          else true
        end
        or question.correct_option not between 0 and 3
        or coalesce(question.content_fingerprint, '') !~ '^[0-9a-f]{64}$'
        or coalesce(question.question_revision_token, '') !~ '^[0-9a-f]{64}$'
        or pg_catalog.jsonb_typeof(question.source_info) <> 'object'
        or length(btrim(coalesce(question.source_info->>'title', ''))) = 0
        or length(btrim(coalesce(question.source_info->>'exam', ''))) = 0
        or length(btrim(coalesce(question.source_info->>'questionNo', ''))) = 0
        or length(btrim(coalesce(question.source_info->>'locator', ''))) = 0
      )
  ) then
    raise exception 'junior release contains an ineligible native-text question';
  end if;

  if exists (
    select 1
    from public.chem_questions as question
    cross join lateral pg_catalog.jsonb_array_elements(question.options) as option_value
    where question.source_release_id = p_release_id
      and (
        pg_catalog.jsonb_typeof(option_value) <> 'string'
        or length(btrim(option_value #>> '{}')) = 0
      )
  ) then
    raise exception 'junior release contains a non-text or empty option';
  end if;

  if exists (
    select 1
    from public.chem_questions as question
    where question.source_release_id = p_release_id
      and (
        select count(distinct btrim(option_text))
        from pg_catalog.jsonb_array_elements_text(question.options) as option_text
      ) <> 4
  ) then
    raise exception 'junior release contains duplicated answer options';
  end if;

  if exists (
    select 1
    from public.chem_questions as question
    where question.source_release_id = p_release_id
      and concat_ws(
        ' ',
        question.stem,
        question.options::text,
        question.explanation,
        question.scaffold
      ) ~ '(来源|出处|选自|题源|中考|模拟|真题)'
  ) then
    raise exception 'junior release contains a visible source label';
  end if;

  if exists (
    select 1
    from public.chem_questions as question
    where question.source_release_id = p_release_id
      and question.content_fingerprint is distinct from
        app_private.chem_h3_content_fingerprint(question.stem, question.options)
  ) then
    raise exception 'junior content fingerprint does not match normalized stem and options';
  end if;

  if exists (
    select 1
    from public.chem_questions as question
    where question.source_release_id = p_release_id
      and question.question_revision_token is distinct from
        app_private.chem_junior_native_revision_sha256(question)
  ) then
    raise exception 'junior revision token does not match the native-text question';
  end if;

  if (
    select pg_catalog.array_agg(distinct question.knowledge_id order by question.knowledge_id)
    from public.chem_questions as question
    where question.source_release_id = p_release_id
  ) is distinct from v_knowledge_ids then
    raise exception 'junior release does not contain the exact declared textbook knowledge routes';
  end if;

  if exists (
    with foundation as (
      select question.knowledge_id, min(question.level) as foundation_level
      from public.chem_questions as question
      where question.source_release_id = p_release_id
      group by question.knowledge_id
    ), route_counts as (
      select
        question.knowledge_id,
        min(foundation.foundation_level)::smallint as foundation_level,
        count(distinct question.parent_source_item_key) as total_count,
        count(distinct question.parent_source_item_key) filter (where question.level = foundation.foundation_level) as foundation_count,
        count(distinct question.parent_source_item_key) filter (where question.level > foundation.foundation_level) as higher_count
      from public.chem_questions as question
      join foundation on foundation.knowledge_id = question.knowledge_id
      where question.source_release_id = p_release_id
      group by question.knowledge_id
    )
    select 1
    from route_counts
    where not app_private.chem_junior_route_inventory_valid(v_textbook_version,knowledge_id,
      total_count,foundation_count,higher_count,foundation_level)
  ) or (
    select count(distinct question.knowledge_id)
    from public.chem_questions as question
    where question.source_release_id = p_release_id
  ) <> cardinality(v_knowledge_ids) then
    raise exception 'each junior route requires seven independent parents: reviewed intro routes require seven L1 parents; all other routes require five foundation and two higher-level parents';
  end if;

  -- Several independently answerable subquestions may share a source parent.
  -- A missing exact recovery pool is reported, never replaced with broad topics.
  perform app_private.chem_assert_junior_subquestion_identities(p_release_id);

  select count(distinct question.source_item_key)::integer
  into v_distinct_count
  from public.chem_questions as question
  where question.source_release_id = p_release_id;
  if v_distinct_count <> v_expected then
    raise exception 'junior source-item identities are not unique inside the release';
  end if;
  select count(distinct question.content_fingerprint)::integer
  into v_distinct_count
  from public.chem_questions as question
  where question.source_release_id = p_release_id;
  if v_distinct_count <> v_expected then
    raise exception 'junior content fingerprints are not unique inside the release';
  end if;
  select count(distinct question.question_revision_token)::integer
  into v_distinct_count
  from public.chem_questions as question
  where question.source_release_id = p_release_id;
  if v_distinct_count <> v_expected then
    raise exception 'junior revision identities are not unique inside the release';
  end if;

  if exists (
    select 1
    from public.chem_questions as question
    left join app_private.chem_question_source_release_items as item
      on item.release_id = question.source_release_id
     and item.question_id = question.id
    where question.source_release_id = p_release_id
      and (
        item.question_id is null
        or item.question_asset_sha256 <> v_empty_asset_sha256
        or item.analysis_asset_sha256 <> v_empty_asset_sha256
        or item.item_sha256 is distinct from
          app_private.chem_junior_native_release_item_sha256(
            question,
            item.canonical_source_id
          )
      )
  ) then
    raise exception 'junior release ledger digest or zero-asset attestation is invalid';
  end if;

  select pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        pg_catalog.string_agg(item.item_sha256, E'\n' order by item.question_id),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
  into v_computed_manifest
  from app_private.chem_question_source_release_items as item
  where item.release_id = p_release_id;

  if v_computed_manifest is distinct from p_manifest_sha256 then
    raise exception 'junior release manifest does not match the exact staged item ledger';
  end if;

  select count(*)::integer
  into v_provenance_count
  from app_private.chem_junior_source_release_provenance as provenance
  where provenance.release_id = p_release_id;
  if v_provenance_count <> cardinality(v_knowledge_ids) or exists (
    select 1
    from app_private.chem_junior_source_release_provenance as provenance
    where provenance.release_id = p_release_id
      and (
        provenance.textbook_version is distinct from v_textbook_version
        or not (provenance.knowledge_id = any(v_knowledge_ids))
        or provenance.verification_status <> 'verified'
        or provenance.verification_actor is distinct from 'codex-source-provenance-qa'
        or provenance.reviewed_at is null
        or coalesce(provenance.source_sha256, '') !~ '^[0-9a-f]{64}$'
      )
  ) then
    raise exception 'junior release requires one verified provenance row for every textbook route';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.chem_junior_repetition_state(p_question chem_questions, p_history jsonb, p_session_id uuid, p_policy text, p_today date)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare h jsonb; matches jsonb:='[]'; last_day date; last_bad date; streak integer; gap integer; due date;
begin
 if p_policy='spaced_review'
   and app_private.chem_junior_route_is_foundation_only(p_question.textbook_version,p_question.knowledge_id)
   and p_question.level is distinct from 1
 then return jsonb_build_object('eligible',false,'kind','foundation_only'); end if;
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
