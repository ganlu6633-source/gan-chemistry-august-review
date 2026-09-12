-- Independently reviewed material sets coexist with the current daily bank.
-- Existing question IDs and current student attempts are not replaced.
alter table app_private.chem_question_source_releases add column release_kind text not null default 'primary' check(release_kind in ('primary','teaching_material'));
do $$ declare n text; begin
 select conname into strict n from pg_constraint where conrelid='app_private.chem_question_source_releases'::regclass and contype='c' and pg_get_constraintdef(oid) like '%expected_question_count%';
 execute format('alter table app_private.chem_question_source_releases drop constraint %I',n);
end $$;
alter table app_private.chem_question_source_releases add constraint chem_release_count_by_purpose check (
 (release_kind='teaching_material' and grade_band in ('高一','高二','高三') and expected_question_count between 1 and 5000)
 or (release_kind='primary' and ((grade_band='初三' and expected_question_count between 21 and 2000)
 or (grade_band='高一' and (expected_question_count in (125,175) or expected_question_count between 211 and 275))
 or (grade_band='高二' and expected_question_count between 200 and 2000)
 or (grade_band='高三' and expected_question_count between 275 and 2000))));
drop index app_private.chem_question_source_releases_one_active_grade_uidx;
create unique index chem_question_source_releases_one_active_grade_uidx on app_private.chem_question_source_releases(grade_band) where status='active' and release_kind='primary' and grade_band in ('高一','高二','高三');
create function app_private.chem_guard_release_kind() returns trigger language plpgsql set search_path='' as $$
begin if new.release_kind<>old.release_kind then raise exception 'source release purpose is immutable'; end if; return new; end $$;
create trigger chem_release_kind_immutable before update on app_private.chem_question_source_releases for each row execute function app_private.chem_guard_release_kind();
revoke all on function app_private.chem_guard_release_kind() from public,anon,authenticated;
create or replace function public.chem_active_verified_source_releases() returns table(grade_band text,source_release_id uuid)
language sql stable security definer set search_path='' as $$
 select grade_band,id from app_private.chem_question_source_releases where grade_band in ('高一','高二','高三') and status='active' and verification_status='full_visual_verified' and release_kind='primary' order by grade_band;
$$;
CREATE OR REPLACE FUNCTION public.chem_activate_teaching_material_release(p_release_id uuid, p_manifest_sha256 text)
 RETURNS TABLE(release_id uuid, activated_questions integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    and r.grade_band in ('高一','高二','高三') and r.release_kind='teaching_material'
  for update;

  if not found
    or v_release_manifest <> p_manifest_sha256
    or v_release_status <> 'staged'
    or v_release_expected not between 1 and 5000
    or v_verification_status <> 'full_visual_verified'
    or v_verification_manifest is distinct from p_manifest_sha256
    or length(btrim(coalesce(v_verification_actor, ''))) < 8
    or v_verified_at is null
  then
    raise exception 'release is missing, unverified, already activated, or manifest hash does not match';
  end if;

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
        or q.concept_key !~ ('^'||q.skill_id||'__[A-Z0-9_]+$')
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

  if exists(select 1 from public.chem_questions q join public.chem_skills sk on sk.id=q.skill_id
    where q.source_release_id=p_release_id and (sk.grade_band<>q.grade_band or not sk.active)) then
    raise exception 'material skill metadata must match its source grade';
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
        or coalesce(q.source_info->>'transcriptionPolicy', '') not in (
          'source_image_authoritative',
          'teacher_verified_exact_reflow_of_registered_source',
          'source_crop_sanitized'
        )
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
  set usable_for_review = true,
      updated_at = now()
  where source_release_id = p_release_id;
  get diagnostics v_question_count = row_count;
  if v_question_count <> v_release_expected then
    raise exception 'activation updated %, expected %', v_question_count, v_release_expected;
  end if;

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

  -- Do not leave the narrowly scoped activation bypass enabled for any later
  -- statements when a caller invokes this function inside a larger transaction.
  perform pg_catalog.set_config('app.chem_release_activation', 'off', true);

  return query select p_release_id, v_question_count;
end;
$function$

;
revoke all on function public.chem_activate_teaching_material_release(uuid,text) from public,anon,authenticated;
grant execute on function public.chem_activate_teaching_material_release(uuid,text) to service_role;
CREATE OR REPLACE FUNCTION public.chem_activate_source_original_release(p_release_id uuid, p_manifest_sha256 text)
 RETURNS TABLE(release_id uuid, activated_questions integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    and r.grade_band in ('高一','高二','高三') and r.release_kind='primary'
  for update;

  if not found
    or v_release_manifest <> p_manifest_sha256
    or v_release_status <> 'staged'
    or (v_grade_band = '高一' and v_release_expected not in (125,175) and v_release_expected not between 211 and 275)
    or (v_grade_band = '高二' and v_release_expected not between 200 and 2000)
    or (v_grade_band = '高三' and v_release_expected not between 275 and 2000)
    or v_verification_status <> 'full_visual_verified'
    or v_verification_manifest is distinct from p_manifest_sha256
    or length(btrim(coalesce(v_verification_actor, ''))) < 8
    or v_verified_at is null
  then
    raise exception 'release is missing, unverified, already activated, or manifest hash does not match';
  end if;

  v_expected_skill_ids := case v_grade_band
    when '高一' then case
      when v_release_expected >= 175 then array[
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

  if v_grade_band = '高一' and v_release_expected between 211 and 275 then
    perform app_private.chem_assert_h1_expanded_release(p_release_id);
  elsif exists (
    select 1
    from app_private.chem_question_source_release_extensions extension_row
    where extension_row.release_id = p_release_id
  ) then
    raise exception 'only an expanded High-1 release may declare source-release lineage';
  end if;

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
    having count(distinct q.concept_key) <> 5
      or (v_grade_band = '高一' and v_release_expected in (125,175) and count(*) <> 25)
      or (v_grade_band = '高一' and v_release_expected between 211 and 275 and count(*) < 25)
      or (v_grade_band in ('高二','高三') and count(*) < 25)
  ) then
    raise exception 'every release skill must use exactly five concepts; legacy High-1 requires exactly 25 questions per skill and expanded releases require at least 25';
  end if;

  if (
    select count(*)
    from (
      select q.skill_id, q.concept_key
      from public.chem_questions q
      where q.source_release_id = p_release_id
      group by q.skill_id, q.concept_key
      having (v_grade_band = '高一' and v_release_expected in (125,175) and count(*) = 5)
        or (v_grade_band = '高一' and v_release_expected between 211 and 275 and count(*) >= 5)
        or (v_grade_band in ('高二','高三') and count(*) >= 5)
    ) concept_groups
  ) <> v_expected_concept_count then
    raise exception 'legacy High-1 requires exactly five questions per fine concept; expanded releases and High-2/High-3 require at least five';
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
        or coalesce(q.source_info->>'transcriptionPolicy', '') not in (
          'source_image_authoritative',
          'teacher_verified_exact_reflow_of_registered_source',
          'source_crop_sanitized'
        )
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
    and source_release_id is distinct from p_release_id
    and source_release_id in(select id from app_private.chem_question_source_releases where release_kind='primary');

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
  where grade_band = v_grade_band and status = 'active' and id <> p_release_id and release_kind='primary';

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
      and q.source_release_id is distinct from p_release_id and q.source_release_id in(select id from app_private.chem_question_source_releases where release_kind='primary')
  ) then
    raise exception 'postcondition failed: an older same-grade REVIEW question remains enabled';
  end if;

  select count(*) into v_distinct_count
  from app_private.chem_question_source_releases r
  where r.grade_band = v_grade_band and r.status = 'active' and r.release_kind='primary';
  if v_distinct_count <> 1 then
    raise exception 'postcondition failed: the grade must have exactly one active source release';
  end if;

  -- Do not leave the narrowly scoped activation bypass enabled for any later
  -- statements when a caller invokes this function inside a larger transaction.
  perform pg_catalog.set_config('app.chem_release_activation', 'off', true);

  return query select p_release_id, v_question_count;
end;
$function$

;
create or replace view app_private.chem_teaching_ready_questions as
 select q.* from public.chem_questions q
 join app_private.chem_question_source_releases r on r.id=q.source_release_id
 where q.review_status='approved' and q.scope_status='IN' and q.usable_for_review
 and r.status='active' and r.verification_status='full_visual_verified' and r.manifest_sha256=r.verification_manifest_sha256
 and jsonb_typeof(q.options)='array' and jsonb_array_length(q.options)=4 and q.correct_option between 0 and 3
 and length(btrim(q.stem))>0 and length(btrim(q.explanation))>0 and q.content_fingerprint is not null and q.source_item_key is not null
 and not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=q.id)
 and ((q.grade_band in ('高一','高二','高三') and q.source_kind='licensed_local' and q.render_mode='image_primary'
 and (r.release_kind='teaching_material' or exists(select 1 from public.chem_active_verified_source_releases() a where a.source_release_id=q.source_release_id and a.grade_band=q.grade_band)))
 or (q.grade_band='初三' and q.source_kind='user_provided_local' and q.render_mode='native' and q.textbook_version='科粤版'
 and exists(select 1 from public.chem_junior_verified_provenance_rows('科粤版',array[q.knowledge_id]) a where a.source_release_id=q.source_release_id and a.source_release_ready and a.verification_status='verified')));

create or replace function app_private.chem_build_teaching_preview(p_data jsonb) returns jsonb language plpgsql set search_path='' as $$
declare v_ids uuid[]; v_item jsonb; v_rows jsonb='[]'; v_warnings jsonb='[]'; v_student record; v_topic record; v_q record;
 v_date date; v_keep uuid[]; v_count integer; v_selected text[]; v_used text[]; v_all_used text[]; v_reason text; v_grade text; v_release uuid;
 v_can boolean=true; v_day record; v_today date=(now() at time zone 'Asia/Shanghai')::date;
begin
 if p_data->>'targetType'='student' then
   select array_agg(id order by id) into v_ids from public.chem_students_v2 where id=(p_data->>'targetId')::uuid and record_status='active' and not coalesce((metadata->>'demo')::boolean,false);
 elsif p_data->>'targetType'='class' then
   select array_agg(id order by id) into v_ids from public.chem_students_v2 where teaching_class_id=(p_data->>'targetId')::uuid and record_status='active' and not coalesce((metadata->>'demo')::boolean,false);
 else raise exception '请选择学生或班级'; end if;
 if coalesce(cardinality(v_ids),0)=0 then raise exception '该目标没有在读学生'; end if;
 if jsonb_typeof(coalesce(p_data->'keepExistingPlanIds','[]'))<>'array' or jsonb_array_length(coalesce(p_data->'keepExistingPlanIds','[]'))>1500 then raise exception '保留课程列表无效'; end if;
 v_keep=array(select jsonb_array_elements_text(coalesce(p_data->'keepExistingPlanIds','[]'))::uuid);
 if exists(select 1 from unnest(v_keep) k where not exists(select 1 from public.chem_learning_plans pl where pl.id=k and pl.student_id=any(v_ids) and pl.mode='REVIEW' and pl.plan_date>=v_today)) then raise exception '保留列表包含不属于所选学生的课程，请刷新'; end if;
 if p_data->'replaceFuture' is distinct from 'true'::jsonb then raise exception '排课请求缺少替换范围'; end if;
 if jsonb_typeof(p_data->'items') is distinct from 'array' or jsonb_array_length(p_data->'items')>200 then raise exception '课程列表无效或超过200项'; end if;
 for v_item in select value from jsonb_array_elements(p_data->'items') loop
   if (v_item->>'date') !~ '^\d{4}-\d{2}-\d{2}$' or (v_item->>'questionCount') !~ '^[1-8]$' then raise exception '请填写有效日期和1—8道题'; end if;
   v_date=(v_item->>'date')::date;
   if v_date<v_today or v_date>v_today+730 then raise exception '只能调整今天至未来两年的课程'; end if;
   if not exists(select 1 from app_private.chem_teaching_topics where id=v_item->>'topicId') then raise exception '课程知识点已不存在，请刷新目录'; end if;
 end loop;
 for v_student in select * from public.chem_students_v2 where id=any(v_ids) order by id loop
   select coalesce(array_agg(distinct k),'{}') into v_all_used from (
     select unnest(app_private.chem_teaching_identities(a.question_id,a.mother_id,coalesce(a.question_snapshot->>'sourceItemKey',q.source_item_key),coalesce(a.question_snapshot->>'contentFingerprint',q.content_fingerprint),coalesce(a.question_snapshot->>'parentSourceItemKey',q.parent_source_item_key))) k
       from public.chem_attempt_answers a join public.chem_learning_attempts h on h.id=a.attempt_id left join public.chem_questions q on q.id=a.question_id where h.student_id=v_student.id
     union all select unnest(app_private.chem_teaching_identities(q.id,q.mother_id,q.source_item_key,q.content_fingerprint,q.parent_source_item_key))
       from app_private.chem_question_answer_locks l join public.chem_questions q on q.id=l.question_id where l.student_id=v_student.id
     union all select unnest(app_private.chem_teaching_identities(st.question_id,st.mother_id,st.source_item_key,st.content_fingerprint,st.parent_source_item_key))
       from public.chem_junior_session_steps st join public.chem_junior_daily_sessions se on se.id=st.session_id where se.student_id=v_student.id
   ) h;
   select v_all_used||coalesce(array_agg(distinct k),'{}') into v_all_used from (
     select unnest(app_private.chem_teaching_identities(q.id,q.mother_id,q.source_item_key,q.content_fingerprint,q.parent_source_item_key)) k
     from public.chem_learning_plans pl cross join lateral jsonb_array_elements_text(coalesce(v_student.metadata#>'{reviewProgram,questionAssignments}'->pl.plan_date::text,'[]')) a(qid)
     join public.chem_questions q on q.id=a.qid where pl.student_id=v_student.id and pl.id=any(v_keep)
   ) kept;
   if exists(select 1 from public.chem_learning_plans p where p.student_id=v_student.id and p.mode='REVIEW' and p.plan_date>=v_today and app_private.chem_teaching_plan_started(p.id)) then
      v_warnings=v_warnings||jsonb_build_array(v_student.display_name||'：已开始的题组与历史记录会保留。');
   end if;
   for v_item in select value from jsonb_array_elements(p_data->'items') with ordinality a(value,n) order by value->>'date',n loop
     v_date=(v_item->>'date')::date; v_count=(v_item->>'questionCount')::integer; v_selected='{}'; v_reason=null; v_grade=null; v_release=null;
     select * into v_topic from app_private.chem_teaching_topics where id=v_item->>'topicId';
     if exists(select 1 from public.chem_learning_plans p where p.student_id=v_student.id and p.mode='REVIEW' and p.plan_date=v_date and (p.id=any(v_keep) or app_private.chem_teaching_plan_started(p.id))) then
       v_reason='该日期已有保留或已开始的题组，请取消该日保留（未开始时）或另选日期。';
     else
       -- Prefer the student's own source grade; choose a single attested source release per day.
       select q.grade_band,q.source_release_id into v_grade,v_release from app_private.chem_teaching_ready_questions q
         join app_private.chem_teaching_question_topics m on m.question_id=q.id where m.topic_id=v_topic.id
         group by q.grade_band,q.source_release_id order by (q.grade_band=v_student.grade_band) desc,count(*) desc,q.grade_band,q.source_release_id limit 1;
       for v_q in select q.* from app_private.chem_teaching_ready_questions q join app_private.chem_teaching_question_topics m on m.question_id=q.id
         where m.topic_id=v_topic.id and q.grade_band=v_grade and q.source_release_id=v_release order by q.level,q.id loop
         v_used=app_private.chem_teaching_identities(v_q.id,v_q.mother_id,v_q.source_item_key,v_q.content_fingerprint,v_q.parent_source_item_key);
         if v_all_used && v_used then continue; end if;
         v_selected=array_append(v_selected,v_q.id); v_all_used=v_all_used||v_used;
         exit when cardinality(v_selected)=v_count;
       end loop;
       if cardinality(v_selected)<v_count then v_reason=format('需要%s道独立原题，目前只有%s道已核对且该生未做过的题。待核对材料不能下发。',v_count,cardinality(v_selected)); end if;
     end if;
     if v_reason is not null then v_can=false; end if;
     v_rows=v_rows||jsonb_build_array(jsonb_build_object('studentId',v_student.id,'studentName',v_student.display_name,'date',v_date,'title',v_topic.title,'topicId',v_topic.id,'questionCount',v_count,'questionIds',v_selected,'sourceGrade',v_grade,'sourceReleaseId',v_release,'status',case when v_reason is null then 'ready' else 'blocked' end,'reason',v_reason));
   end loop;
 end loop;
 for v_day in select r->>'studentId' student_id,r->>'date' as plan_date,sum((r->>'questionCount')::integer) qty,count(distinct r->>'sourceReleaseId') grades from jsonb_array_elements(v_rows) r group by 1,2 loop
   if v_day.qty>8 or v_day.grades>1 then
     v_can=false; v_warnings=v_warnings||jsonb_build_array(v_day.plan_date||'：同日合并最多8道基础题，同一天请选择同一份材料集；不同材料可以分两天安排。');
   end if;
 end loop;
 return jsonb_build_object('canApply',v_can,'rows',v_rows,'warnings',v_warnings,'studentIds',v_ids,'preservedPlanCount',cardinality(v_keep),'summary',jsonb_build_object('studentCount',cardinality(v_ids),'planCount',(select count(distinct (r->>'studentId',r->>'date')) from jsonb_array_elements(v_rows) r),'questionCount',coalesce((select sum((r->>'questionCount')::integer) from jsonb_array_elements(v_rows) r),0)));
end $$;
