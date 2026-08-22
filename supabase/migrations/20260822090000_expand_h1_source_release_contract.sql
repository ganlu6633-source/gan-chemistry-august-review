-- Allow a rollback-safe High-1 release to grow from five to seven exact skills.
begin;
alter table app_private.chem_question_source_releases
  drop constraint if exists chem_question_source_releases_expected_question_count_check;
alter table app_private.chem_question_source_releases
  add constraint chem_question_source_releases_expected_question_count_check check (
    (grade_band='高一' and expected_question_count in (125,175))
    or (grade_band='高二' and expected_question_count=200)
    or (grade_band='高三' and expected_question_count=275)
  );
create or replace function public.chem_activate_source_original_release(
  p_release_id uuid,
  p_manifest_sha256 text
)
returns table (release_id uuid, activated_questions integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_question_count integer;
  v_distinct_count integer;
  v_computed_manifest text;
  v_release_manifest text;
  v_release_status text;
  v_release_expected integer;
  v_verification_status text;
  v_verification_manifest text;
  v_verification_actor text;
  v_verified_at timestamptz;
  v_skill_ids text[];
  v_expected_skill_ids text[];
  v_grade_band text;
  v_expected_concept_count integer;
begin
  if p_release_id is null or coalesce(p_manifest_sha256, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid release identity';
  end if;

  -- Serialize release switches.  Every assertion and both the old/new pool
  -- updates run in this function's transaction, so a failed assertion leaves
  -- the currently active REVIEW pool unchanged.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release', 0));

  select r.manifest_sha256, r.status, r.expected_question_count,
    r.verification_status, r.verification_manifest_sha256,
    r.verification_actor, r.verified_at, r.grade_band
  into v_release_manifest, v_release_status, v_release_expected,
    v_verification_status, v_verification_manifest,
    v_verification_actor, v_verified_at, v_grade_band
  from app_private.chem_question_source_releases r
  where r.id = p_release_id
    and r.grade_band in ('高一','高二','高三')
  for update;

  if not found
    or v_release_manifest <> p_manifest_sha256
    or v_release_status <> 'staged'
    or (v_grade_band = '高一' and v_release_expected not in (125,175))
    or (v_grade_band = '高二' and v_release_expected <> 200)
    or (v_grade_band = '高三' and v_release_expected <> 275)
    or v_verification_status <> 'full_visual_verified'
    or v_verification_manifest is distinct from p_manifest_sha256
    or length(btrim(coalesce(v_verification_actor, ''))) < 8
    or v_verified_at is null
  then
    raise exception 'release is missing, unverified, already activated, or manifest hash does not match';
  end if;

  v_expected_skill_ids := case v_grade_band
    when '高一' then case
      when v_release_expected = 175 then array[
        'H1_CLASSIFY','H1_GAS_MOLAR_VOLUME','H1_MOLE_INTRO','H1_PERIODIC',
        'H1_REACTION_CLASSIFICATION','H1_REDOX','H1_SOLUTION_CONCENTRATION'
      ]::text[]
      else array['H1_CLASSIFY','H1_GAS_MOLAR_VOLUME','H1_MOLE_INTRO','H1_PERIODIC','H1_REDOX']::text[]
    end
    when '高二' then array['H2_ELECTRO','H2_EQUIL','H2_K','H2_KSP','H2_PH_HYDRO','H2_RATE','H2_THERMO','H2_WEAK']::text[]
    else array['H3_AQ','H3_ELECTRO','H3_EQUILIBRIUM','H3_EXPERIMENT','H3_INORGANIC','H3_ION_REDOX','H3_ORGANIC','H3_PROCESS','H3_STOICH','H3_STRUCTURE','H3_THERMO_RATE']::text[]
  end;
  v_expected_concept_count := pg_catalog.array_length(v_expected_skill_ids, 1) * 5;

  -- Freeze the entire staged release while it is being verified.  The parent
  -- release row lock also blocks concurrent FK inserts; these deterministic
  -- child locks close the check-to-activate race for updates and deletes.
  perform q.id
  from public.chem_questions q
  where q.source_release_id = p_release_id
  order by q.id
  for update;

  perform a.asset_path
  from app_private.chem_question_assets a
  join public.chem_questions q on q.id = a.question_id
  where q.source_release_id = p_release_id
  order by a.asset_path
  for update of a;

  perform ri.question_id
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id
  order by ri.question_id
  for update;

  select count(*) into v_question_count
  from public.chem_questions q
  where q.source_release_id = p_release_id;
  if v_question_count <> v_release_expected then
    raise exception 'release must contain exactly % questions, found %', v_release_expected, v_question_count;
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        q.grade_band <> v_grade_band
        or q.source_kind <> 'licensed_local'
        or q.review_status <> 'approved'
        or q.scope_status <> 'IN'
        or q.usable_for_review
        or q.usable_for_class_quiz
        or q.usable_for_exam_sprint
        or q.usable_for_demo
        or q.mother_id is null
        or q.concept_key is null
        or q.concept_key not in (
          q.skill_id || '__C01', q.skill_id || '__C02', q.skill_id || '__C03',
          q.skill_id || '__C04', q.skill_id || '__C05'
        )
        or length(btrim(coalesce(q.stem, ''))) = 0
        or length(btrim(coalesce(q.explanation, ''))) = 0
        or jsonb_typeof(q.options) <> 'array'
        or case when jsonb_typeof(q.options) = 'array' then
          jsonb_array_length(q.options) <> 4
          or exists (
            select 1 from jsonb_array_elements(q.options) option_value
            where jsonb_typeof(option_value) <> 'string'
          )
          else true end
        or q.correct_option not between 0 and 3
        or coalesce(q.content_fingerprint, '') !~ '^[0-9a-f]{64}$'
        or coalesce(q.question_revision_token, '') !~ '^[0-9a-f]{64}$'
        or q.render_mode <> 'image_primary'
        or jsonb_array_length(q.asset_refs) <> 2
      )
  ) then
    raise exception 'release contains an unapproved, ineligible, non-four-option, or prematurely enabled question';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    cross join lateral jsonb_array_elements_text(q.options) option_text
    where q.source_release_id = p_release_id
      and length(btrim(option_text)) = 0
  ) then
    raise exception 'release contains an empty answer option';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        select count(distinct btrim(option_text))
        from jsonb_array_elements_text(q.options) option_text
      ) <> 4
  ) then
    raise exception 'release contains duplicated answer options';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and q.content_fingerprint is distinct from
        app_private.chem_h3_content_fingerprint(q.stem, q.options)
  ) then
    raise exception 'content fingerprint must equal the normalized stem and four options';
  end if;

  select array_agg(distinct q.skill_id order by q.skill_id)
  into v_skill_ids
  from public.chem_questions q
  where q.source_release_id = p_release_id;
  if v_skill_ids is distinct from v_expected_skill_ids then
    raise exception 'release does not contain the exact REVIEW skills for the release grade';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
    group by q.skill_id
    having count(*) <> 25 or count(distinct q.concept_key) <> 5
  ) then
    raise exception 'every release skill must contain 25 questions across exactly five concepts';
  end if;

  if (
    select count(*)
    from (
      select q.skill_id, q.concept_key
      from public.chem_questions q
      where q.source_release_id = p_release_id
      group by q.skill_id, q.concept_key
      having count(*) = 5
    ) concept_groups
  ) <> v_expected_concept_count then
    raise exception 'every fine concept must contain exactly five questions';
  end if;

  select count(distinct q.id) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'question ids are not unique inside release'; end if;
  select count(distinct q.mother_id) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'mother ids are not unique inside release'; end if;
  select count(distinct q.source_item_key) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'source item identities are not unique inside release'; end if;
  select count(distinct q.content_fingerprint) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'content fingerprints are not unique inside release'; end if;
  select count(distinct q.question_revision_token) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'question revision tokens are not unique inside release'; end if;

  select count(*) into v_question_count
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id;
  if v_question_count <> v_release_expected then
    raise exception 'release ledger must contain exactly % items, found %', v_release_expected, v_question_count;
  end if;

  select count(distinct ri.canonical_source_id) into v_distinct_count
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id;
  if v_distinct_count <> v_release_expected then
    raise exception 'canonical source identities are not unique inside release';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    left join app_private.chem_question_source_release_items ri
      on ri.release_id = p_release_id
     and ri.question_id = q.id
    where q.source_release_id = p_release_id
      and ri.question_id is null
  ) then
    raise exception 'release ledger is missing a staged question';
  end if;

  -- Every descriptor must resolve to the exact binary metadata recorded on
  -- that question.  A non-native question additionally needs a question-side
  -- visual; an analysis image alone is not enough to make the stem readable.
  if exists (
    select 1
    from public.chem_questions q
    cross join lateral jsonb_array_elements(q.asset_refs) ref
    where q.source_release_id = p_release_id
      and (
        coalesce(btrim(ref->>'alt'), '') = ''
        or coalesce(ref->>'path', '') !~ '^[a-zA-Z0-9/_-]{16,200}$'
        or coalesce(ref->>'kind', '') not in ('question_image','formula_fallback','source_scan','analysis_image')
        or coalesce(ref->>'sha256', '') !~ '^[0-9a-f]{64}$'
        or (select count(*) from jsonb_object_keys(ref)) <> 6
        or exists (
          select 1 from jsonb_object_keys(ref) key_name
          where key_name not in ('kind','path','alt','sha256','width','height')
        )
      )
  ) then
    raise exception 'release contains a malformed or inaccessible asset descriptor';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        (select count(*) from jsonb_object_keys(q.source_info)) <> 12
        or exists (
          select 1 from jsonb_object_keys(q.source_info) key_name
          where key_name not in (
            'title','exam','year','questionNo','locator','transcriptionPolicy',
            'optionTranscriptionPolicy','transcriptionAuditMethod','sourcePairingStatus',
            'sourceMarkerStyle','sourceMarkerLabel','conceptLabel'
          )
        )
        or coalesce(q.source_info->>'transcriptionPolicy', '') <> 'source_image_authoritative'
        or coalesce(btrim(q.source_info->>'optionTranscriptionPolicy'), '') = ''
        or coalesce(btrim(q.source_info->>'transcriptionAuditMethod'), '') = ''
        or coalesce(q.source_info->>'sourcePairingStatus', '') not in ('EXACT','SOURCE_NATIVE_PAIR')
        or coalesce(q.source_info->>'sourceMarkerStyle', '') not in ('bracketed','plain_answer_analysis')
        or coalesce(btrim(q.source_info->>'sourceMarkerLabel'), '') = ''
        or coalesce(btrim(q.source_info->>'conceptLabel'), '') = ''
      )
  ) then
    raise exception 'release contains an incomplete or non-canonical public source record';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        jsonb_array_length(q.asset_refs) <> 2
        or jsonb_array_length(q.asset_refs) <> (
          select count(distinct ref->>'path')
          from jsonb_array_elements(q.asset_refs) ref
        )
        or (select count(*) from jsonb_array_elements(q.asset_refs) ref where ref->>'kind' = 'question_image') <> 1
        or (select count(*) from jsonb_array_elements(q.asset_refs) ref where ref->>'kind' = 'analysis_image') <> 1
        or (select count(*) from jsonb_array_elements(q.asset_refs) ref where ref->>'kind' not in ('question_image','analysis_image')) <> 0
      )
  ) then
    raise exception 'every release question must have exactly one question image and one analysis image';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    cross join lateral jsonb_array_elements(q.asset_refs) ref
    left join app_private.chem_question_assets a
      on a.question_id = q.id
     and a.asset_path = ref->>'path'
     and a.asset_kind = ref->>'kind'
     and a.sha256 = ref->>'sha256'
     and a.width::text = ref->>'width'
     and a.height::text = ref->>'height'
    where q.source_release_id = p_release_id
      and a.asset_path is null
  ) then
    raise exception 'release contains a missing or metadata-mismatched private asset';
  end if;

  if exists (
    select 1
    from app_private.chem_question_assets a
    join public.chem_questions q on q.id = a.question_id
    where q.source_release_id = p_release_id
      and encode(extensions.digest(decode(a.payload_base64, 'base64'), 'sha256'), 'hex') <> a.sha256
  ) then
    raise exception 'private asset payload does not match its SHA-256 digest';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    left join lateral (
      select
        count(*) as asset_count,
        count(*) filter (where a.asset_kind = 'question_image') as question_count,
        count(*) filter (where a.asset_kind = 'analysis_image') as analysis_count
      from app_private.chem_question_assets a
      where a.question_id = q.id
    ) counts on true
    where q.source_release_id = p_release_id
      and (
        counts.asset_count <> 2
        or counts.question_count <> 1
        or counts.analysis_count <> 1
      )
  ) then
    raise exception 'private asset store must contain exactly the two declared images per question';
  end if;

  if exists (
    select 1
    from app_private.chem_question_assets a
    join public.chem_questions q on q.id = a.question_id
    where q.source_release_id = p_release_id
      and a.mime_type <> 'image/webp'
  ) then
    raise exception 'release assets must use the audited lossless WebP transport';
  end if;

  if exists (
    select 1
    from app_private.chem_question_source_release_items ri
    join public.chem_questions q
      on q.id = ri.question_id
     and q.source_release_id = ri.release_id
    join app_private.chem_question_assets question_asset
      on question_asset.question_id = q.id
     and question_asset.asset_kind = 'question_image'
    join app_private.chem_question_assets analysis_asset
      on analysis_asset.question_id = q.id
     and analysis_asset.asset_kind = 'analysis_image'
    where ri.release_id = p_release_id
      and (
        ri.question_asset_sha256 <> question_asset.sha256
        or ri.analysis_asset_sha256 <> analysis_asset.sha256
        or q.question_revision_token is distinct from
          app_private.chem_h3_question_revision_sha256(
            q,
            question_asset.sha256,
            analysis_asset.sha256
          )
        or ri.item_sha256 <> app_private.chem_h3_release_item_sha256(
          q,
          ri.canonical_source_id,
          question_asset.sha256,
          analysis_asset.sha256
        )
      )
  ) then
    raise exception 'release revision token or ledger digest does not match the staged question and assets';
  end if;

  select pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        pg_catalog.string_agg(ri.item_sha256, E'\n' order by ri.question_id),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
  into v_computed_manifest
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id;

  if v_computed_manifest is distinct from v_release_manifest
    or v_computed_manifest is distinct from p_manifest_sha256
  then
    raise exception 'release manifest does not match the staged source items';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and q.render_mode <> 'native'
      and not exists (
        select 1
        from jsonb_array_elements(q.asset_refs) ref
        join app_private.chem_question_assets a
          on a.question_id = q.id
         and a.asset_path = ref->>'path'
         and a.asset_kind = ref->>'kind'
        where ref->>'kind' in ('question_image','formula_fallback','source_scan')
      )
  ) then
    raise exception 'every non-native question must have a verified question-side asset';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        not exists (
          select 1
          from jsonb_array_elements(q.asset_refs) ref
          join app_private.chem_question_assets a
            on a.question_id = q.id
           and a.asset_path = ref->>'path'
           and a.asset_kind = 'question_image'
          where ref->>'kind' = 'question_image'
        )
        or not exists (
          select 1
          from jsonb_array_elements(q.asset_refs) ref
          join app_private.chem_question_assets a
            on a.question_id = q.id
           and a.asset_path = ref->>'path'
           and a.asset_kind = 'analysis_image'
          where ref->>'kind' = 'analysis_image'
        )
      )
  ) then
    raise exception 'every source-backed question must have both question and analysis images';
  end if;

  perform pg_catalog.set_config('app.chem_release_activation', 'on', true);

  update public.chem_questions
  set usable_for_review = false,
      updated_at = now()
  where grade_band = v_grade_band
    and usable_for_review
    and source_release_id is distinct from p_release_id;

  update public.chem_questions
  set usable_for_review = true,
      updated_at = now()
  where source_release_id = p_release_id;
  get diagnostics v_question_count = row_count;
  if v_question_count <> v_release_expected then
    raise exception 'activation updated %, expected %', v_question_count, v_release_expected;
  end if;

  update app_private.chem_question_source_releases
  set status = 'retired', retired_at = now()
  where grade_band = v_grade_band and status = 'active' and id <> p_release_id;

  update app_private.chem_question_source_releases
  set status = 'active', activated_at = now(), retired_at = null
  where id = p_release_id;
  get diagnostics v_distinct_count = row_count;
  if v_distinct_count <> 1 then
    raise exception 'release activation status update affected %, expected 1', v_distinct_count;
  end if;

  select count(*) into v_question_count
  from public.chem_questions q
  where q.grade_band = v_grade_band
    and q.usable_for_review
    and q.source_release_id = p_release_id;
  if v_question_count <> v_release_expected then
    raise exception 'postcondition failed: active release exposes %, expected %', v_question_count, v_release_expected;
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.grade_band = v_grade_band
      and q.usable_for_review
      and q.source_release_id is distinct from p_release_id
  ) then
    raise exception 'postcondition failed: an older same-grade REVIEW question remains enabled';
  end if;

  select count(*) into v_distinct_count
  from app_private.chem_question_source_releases r
  where r.grade_band = v_grade_band and r.status = 'active';
  if v_distinct_count <> 1 then
    raise exception 'postcondition failed: the grade must have exactly one active source release';
  end if;

  -- Do not leave the narrowly scoped activation bypass enabled for any later
  -- statements when a caller invokes this function inside a larger transaction.
  perform pg_catalog.set_config('app.chem_release_activation', 'off', true);

  return query select p_release_id, v_question_count;
end;
$$;
revoke all on function public.chem_activate_source_original_release(uuid,text) from public, anon, authenticated;
grant execute on function public.chem_activate_source_original_release(uuid,text) to service_role;
commit;
