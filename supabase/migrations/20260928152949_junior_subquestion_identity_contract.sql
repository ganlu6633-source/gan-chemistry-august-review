begin;

-- Source items are independently answerable subquestions. Mother/parent keys
-- remain the original question identity and must not be fabricated per subpart.
drop index public.chem_questions_junior_release_mother_uidx;
drop index public.chem_questions_junior_release_parent_source_item_uidx;
create index chem_questions_junior_release_mother_idx
  on public.chem_questions(source_release_id,mother_id)
  where grade_band='初三' and source_kind='user_provided_local';
create index chem_questions_junior_release_parent_source_item_idx
  on public.chem_questions(source_release_id,parent_source_item_key)
  where grade_band='初三' and source_kind='user_provided_local';
alter table app_private.chem_question_source_release_items
  drop constraint chem_question_source_release__release_id_canonical_source_i_key;
create index chem_question_source_release_items_canonical_idx
  on app_private.chem_question_source_release_items(release_id,canonical_source_id);

create function app_private.chem_guard_junior_subquestion_identity()
returns trigger language plpgsql security definer set search_path='' as $fn$
begin
  if new.grade_band<>'初三' or new.source_kind<>'user_provided_local' then return new; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release',0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release',0));
  if exists(select 1 from public.chem_questions q
    where q.source_release_id=new.source_release_id and q.id<>new.id and
      ((q.parent_source_item_key=new.parent_source_item_key and q.mother_id is distinct from new.mother_id)
        or (q.mother_id=new.mother_id and q.parent_source_item_key is distinct from new.parent_source_item_key))) then
    raise exception 'junior subquestion parent/mother mapping is inconsistent';
  end if;
  return new;
end;
$fn$;
create trigger chem_junior_subquestion_identity
  before insert or update of grade_band,source_kind,source_release_id,mother_id,parent_source_item_key
  on public.chem_questions for each row execute function app_private.chem_guard_junior_subquestion_identity();

create function app_private.chem_guard_release_canonical_subquestion()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare rel app_private.chem_question_source_releases%rowtype;
  question public.chem_questions%rowtype;
begin
  -- Same lock used by the existing release-ledger mutation guard. This
  -- serializes duplicate checks, including concurrent imports.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release',0));
  select * into rel from app_private.chem_question_source_releases where id=new.release_id;
  if rel.grade_band='初三' and rel.revision_contract='v3_junior_native_text' then
    select * into question from public.chem_questions where id=new.question_id;
    if question.source_release_id is distinct from new.release_id
      or length(btrim(coalesce(question.parent_source_item_key,'')))<16 then
      raise exception 'junior canonical source lacks its exact question parent';
    end if;
    if exists(select 1 from app_private.chem_question_source_release_items i
      join public.chem_questions q on q.id=i.question_id
      where i.release_id=new.release_id and i.canonical_source_id=new.canonical_source_id
        and i.question_id<>new.question_id
        and q.parent_source_item_key is distinct from question.parent_source_item_key) then
      raise exception 'a junior canonical source may be shared only by subquestions of the same parent';
    end if;
  elsif exists(select 1 from app_private.chem_question_source_release_items i
    where i.release_id=new.release_id and i.canonical_source_id=new.canonical_source_id
      and i.question_id<>new.question_id) then
    raise exception 'canonical source identities remain unique for non-junior releases' using errcode='23505';
  end if;
  return new;
end;
$fn$;
create trigger chem_question_release_items_zcanonical_guard
  before insert or update on app_private.chem_question_source_release_items
  for each row execute function app_private.chem_guard_release_canonical_subquestion();

create function app_private.chem_assert_junior_subquestion_identities(p_release_id uuid)
returns void language plpgsql stable security definer set search_path='' as $fn$
begin
  if exists(select 1 from public.chem_questions q where q.source_release_id=p_release_id
    group by q.parent_source_item_key having count(distinct q.mother_id)<>1)
    or exists(select 1 from public.chem_questions q where q.source_release_id=p_release_id
      group by q.mother_id having count(distinct q.parent_source_item_key)<>1) then
    raise exception 'junior subquestion parent/mother mapping is inconsistent';
  end if;
  if exists(select 1 from app_private.chem_question_source_release_items i
    join public.chem_questions q on q.id=i.question_id
    where i.release_id=p_release_id group by i.canonical_source_id
    having count(distinct q.parent_source_item_key)<>1) then
    raise exception 'a junior canonical source may be shared only by subquestions of the same parent';
  end if;
end;
$fn$;
revoke all on function app_private.chem_guard_junior_subquestion_identity(),
  app_private.chem_guard_release_canonical_subquestion(),
  app_private.chem_assert_junior_subquestion_identities(uuid) from public,anon,authenticated,service_role;

-- All original question/option validation, source rights, exact digest,
-- visual-review, knowledge-card, and active-curriculum checks stay in place.
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
    where total_count < 7 or foundation_count < 5 or higher_count < 2
  ) or (
    select count(distinct question.knowledge_id)
    from public.chem_questions as question
    where question.source_release_id = p_release_id
  ) <> cardinality(v_knowledge_ids) then
    raise exception 'each junior route requires at least seven independent parents, including five foundation and two higher-level parents';
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
$function$
;

-- Inventory only: this reports an upper bound before exact option bindings,
-- historical mother deduplication and current source holds are considered.
-- It does not authorize delivery and cannot replace a verified 3-5 item pool.
create function public.chem_junior_source_reserve_coverage(p_release_id uuid)
returns table(knowledge_id text,same_type_key text,item_count bigint,
  independent_parent_count bigint,potential_other_parent_count bigint,
  needs_more_independent_parents boolean)
language sql stable security definer set search_path='' as $fn$
  select q.knowledge_id,q.same_type_key,count(*),
    count(distinct q.parent_source_item_key),
    greatest(0,count(distinct q.parent_source_item_key)-1),
    count(distinct q.parent_source_item_key)<4
  from public.chem_questions q
  join app_private.chem_question_source_releases r on r.id=q.source_release_id
  where q.source_release_id=p_release_id and r.grade_band='初三'
    and r.revision_contract='v3_junior_native_text'
  group by q.knowledge_id,q.same_type_key order by q.knowledge_id,q.same_type_key;
$fn$;
revoke all on function public.chem_junior_source_reserve_coverage(uuid) from public,anon,authenticated;
grant execute on function public.chem_junior_source_reserve_coverage(uuid) to service_role;
comment on function public.chem_junior_source_reserve_coverage(uuid) is
  'Inventory upper bound only; exact verified option bindings and student-history freshness still govern recovery delivery.';

commit;
