-- Reviewed image-backed teaching materials for all four grades.
-- Generated from deployed definitions on 2026-10-04; applied after full rollback verification.
-- Junior primary/native rebuilding retains its 21-question / 7-per-route rules.
-- Every junior image question must also bind its individual original document.
begin;
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release',0));
do $live$ begin
  if encode(extensions.digest(convert_to(pg_get_functiondef('chem_activate_teaching_material_release(uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex') <> '1440d6bee33da18968991fba954482847c67b058994e217ee9a09e01b1cb004c' then raise exception 'Live function changed; review draft again: public.chem_activate_teaching_material_release'; end if;
  if encode(extensions.digest(convert_to(pg_get_functiondef('chem_lock_question_answer(uuid,uuid,integer,text,integer,boolean,integer,text)'::regprocedure),'UTF8'),'sha256'),'hex') <> '211a040681d13a6e89688c0845d4274cacc240e16f49e7d30cd24742b95bd59d' then raise exception 'Live function changed; review draft again: public.chem_lock_question_answer'; end if;
  if encode(extensions.digest(convert_to(pg_get_functiondef('chem_finalize_learning_attempt(uuid,uuid,uuid,text,integer,text,timestamp with time zone,timestamp with time zone,integer,jsonb,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') <> 'aa551f35bbf0703cf3b2c5c2fa67a2ed81c9d30aa24cea1ff9058656faa6af42' then raise exception 'Live function changed; review draft again: public.chem_finalize_learning_attempt'; end if;
  if encode(extensions.digest(convert_to(pg_get_functiondef('chem_record_question_item_visual_review(text,text,text,text,text,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') <> '4b058faed58179fda669b200d058b9c804a51745b90c5cd9f7b2a71300c9e26a' then raise exception 'Live function changed; review draft again: public.chem_record_question_item_visual_review'; end if;
  if encode(extensions.digest(convert_to(pg_get_functiondef('app_private.chem_question_item_visual_reviewed(text)'::regprocedure),'UTF8'),'sha256'),'hex') <> '8f0a63417b4444fc8b75fcda8c6bf775c774e080a410ead4b6d638a9245caecb' then raise exception 'Live function changed; review draft again: app_private.chem_question_item_visual_reviewed'; end if;
  if encode(extensions.digest(convert_to(pg_get_functiondef('app_private.chem_guard_junior_private_asset_lifecycle()'::regprocedure),'UTF8'),'sha256'),'hex') <> '74330470704ee281fcb6d9b45c60ba862f294bfe86e416e1f24752f8c6fd58dc' then raise exception 'Live function changed; review draft again: app_private.chem_guard_junior_private_asset_lifecycle'; end if;
  if encode(extensions.digest(convert_to(pg_get_functiondef('app_private.chem_guard_junior_release_item_lifecycle()'::regprocedure),'UTF8'),'sha256'),'hex') <> '6c77ac14c78ec321023f0898f13b32aa3147577704db3cf025ba39287d5001ba' then raise exception 'Live function changed; review draft again: app_private.chem_guard_junior_release_item_lifecycle'; end if;
  if encode(extensions.digest(convert_to(pg_get_functiondef('app_private.chem_guard_junior_question_lifecycle()'::regprocedure),'UTF8'),'sha256'),'hex') <> '74b6637a39f97ff747d10365255fd359a36178a704b250a7c3e936c6bbefe5da' then raise exception 'Live function changed; review draft again: app_private.chem_guard_junior_question_lifecycle'; end if;
  if encode(extensions.digest(convert_to(pg_get_functiondef('app_private.chem_guard_junior_release_lifecycle()'::regprocedure),'UTF8'),'sha256'),'hex') <> '0557c43b091cf43ac7901f67ffb32e4b569b9dd88ea3f48d7e478b34283f1cdb' then raise exception 'Live function changed; review draft again: app_private.chem_guard_junior_release_lifecycle'; end if;
  if encode(extensions.digest(convert_to(pg_get_functiondef('app_private.chem_require_junior_rights_before_activation()'::regprocedure),'UTF8'),'sha256'),'hex') <> 'a1d75c3f50a7bfe5f4ed086cd47883e446e29f90c85a3b1bc62e0e60493aad13' then raise exception 'Live function changed; review draft again: app_private.chem_require_junior_rights_before_activation'; end if;
  if encode(extensions.digest(convert_to(pg_get_functiondef('app_private.chem_track_junior_active_release_routes()'::regprocedure),'UTF8'),'sha256'),'hex') <> '6f54a54c66ff45d12aa292875f1b8ad7a61d25d2082f09856dacb6a268b2358a' then raise exception 'Live function changed; review draft again: app_private.chem_track_junior_active_release_routes'; end if;
  if encode(extensions.digest(convert_to(pg_get_functiondef('chem_teaching_ready_question_ids(text,text[])'::regprocedure),'UTF8'),'sha256'),'hex') <> 'f80974ddd44bc2758f9bd961882d45c65288f2b52f8ae95938767cd11180e248' then raise exception 'Live function changed; review draft again: public.chem_teaching_ready_question_ids'; end if;
  if encode(extensions.digest(convert_to(pg_get_viewdef('app_private.chem_teaching_ready_questions'::regclass,true),'UTF8'),'sha256'),'hex') <> 'c2ed14bb27e9291e1c9a4fd4a996c7f4af5059a3f01df4b1ec83c852243ec4e9' then raise exception 'Live ready view changed; review draft again'; end if;
  if (select encode(extensions.digest(convert_to(pg_get_constraintdef(c.oid),'UTF8'),'sha256'),'hex') from pg_constraint c where c.conname='chem_release_count_by_purpose') is distinct from '0d7cbf58a72a3818b369861ff5a556185a3107b0ea58d4384a88c5c6efd6902d' then raise exception 'Live constraint changed; review draft again: chem_release_count_by_purpose'; end if;
  if (select encode(extensions.digest(convert_to(pg_get_constraintdef(c.oid),'UTF8'),'sha256'),'hex') from pg_constraint c where c.conname='chem_questions_junior_no_new_legacy_licensed') is distinct from 'c6d4c9900af954470e686d7f3c782a78f8d47a44a1c94e0ba51dd57e836751e3' then raise exception 'Live constraint changed; review draft again: chem_questions_junior_no_new_legacy_licensed'; end if;
  if to_regprocedure('public.chem_teaching_source_release_context(uuid)') is not null then raise exception 'Release-context RPC already exists; review draft again'; end if;
end $live$;

alter table app_private.chem_question_source_releases drop constraint chem_release_count_by_purpose;
alter table app_private.chem_question_source_releases add constraint chem_release_count_by_purpose CHECK ((((release_kind = 'teaching_material'::text) AND (grade_band = ANY (ARRAY['初三'::text, '高一'::text, '高二'::text, '高三'::text])) AND ((expected_question_count >= 1) AND (expected_question_count <= 5000))) OR ((release_kind = 'primary'::text) AND (((grade_band = '初三'::text) AND ((expected_question_count >= 21) AND (expected_question_count <= 2000))) OR ((grade_band = '高一'::text) AND ((expected_question_count = ANY (ARRAY[125, 175])) OR ((expected_question_count >= 211) AND (expected_question_count <= 275)))) OR ((grade_band = '高二'::text) AND ((expected_question_count >= 200) AND (expected_question_count <= 2000))) OR ((grade_band = '高三'::text) AND ((expected_question_count >= 275) AND (expected_question_count <= 2000)))))));

alter table public.chem_questions drop constraint chem_questions_junior_no_new_legacy_licensed;
alter table public.chem_questions add constraint chem_questions_junior_no_new_legacy_licensed check (
  grade_band<>'初三' or source_kind<>'licensed_local' or (
    textbook_version='科粤版' and render_mode='image_primary'
    and knowledge_id is not null and skill_id=knowledge_id
    and source_release_id is not null and review_status='approved' and scope_status='IN'
    and jsonb_array_length(asset_refs)=2 and not usable_for_class_quiz
    and not usable_for_exam_sprint and not usable_for_demo
  )
) not valid;
-- NOT VALID preserves old historical rows; all newly inserted/updated rows are checked.
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
    and r.grade_band in ('初三','高一','高二','高三') and r.release_kind='teaching_material'
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
          'teacher_verified_multiple_choice_adaptation',
          'source_crop_sanitized',
          'source_native_minimal_scientific_errata'
        )
        or (q.source_info->>'transcriptionPolicy'='source_native_minimal_scientific_errata'
          and (coalesce(q.source_info->>'sourceMarkerLabel','') !~ '(修正版|校正版)'
            or coalesce(q.source_info->>'transcriptionAuditMethod','') !~ '独立.*来源'
            or coalesce(q.source_info->>'transcriptionAuditMethod','') !~ '科学.*核查'))
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

  -- A genuine source fill-in may be presented as four choices only with explicit provenance.
  if exists (
    select 1 from public.chem_questions q
    where q.source_release_id=p_release_id
      and q.source_info->>'transcriptionPolicy'='teacher_verified_multiple_choice_adaptation'
      and (
        q.grade_band<>'高一' or q.source_kind<>'licensed_local' or q.render_mode<>'image_primary'
        or case (q.source_info->>'transcriptionAuditMethod')::jsonb->>'kind'
          when 'native_fill_in_to_four_choices' then position('原填空改四选' in coalesce(q.source_info->>'title',''))=0
          when 'native_true_false_to_four_choices' then
            position('原判断改四选' in coalesce(q.source_info->>'title',''))=0
            or jsonb_typeof((q.source_info->>'transcriptionAuditMethod')::jsonb->'originalTrueFalseKey') is distinct from 'boolean'
            or (q.source_info->>'transcriptionAuditMethod')::jsonb->'correctChoiceStatesOriginalJudgement' is distinct from 'true'::jsonb
          else true end
        or q.source_info->>'sourcePairingStatus' not in ('EXACT','SOURCE_NATIVE_PAIR')
        or case (q.source_info->>'transcriptionAuditMethod')::jsonb->>'kind'
          when 'native_fill_in_to_four_choices' then
            q.source_info->>'optionTranscriptionPolicy' is distinct from 'native_fill_in_to_four_choices: all choices adapted; A/B/C/D distractors explicitly generated; original conditions and correct answer preserved'
          when 'native_true_false_to_four_choices' then
            q.source_info->>'optionTranscriptionPolicy' is distinct from 'native_true_false_to_four_choices: all choices adapted; A/B/C/D distractors explicitly generated; original judgement, conditions and correct answer preserved'
          else true end
        or coalesce((q.source_info->>'transcriptionAuditMethod')::jsonb->>'kind','') not in ('native_fill_in_to_four_choices','native_true_false_to_four_choices')
        or coalesce(btrim((q.source_info->>'transcriptionAuditMethod')::jsonb->>'originalPrompt'),'')=''
        or coalesce(btrim((q.source_info->>'transcriptionAuditMethod')::jsonb->>'originalCorrectAnswer'),'')=''
        or (q.source_info->>'transcriptionAuditMethod')::jsonb->'generatedOptions' is distinct from 'true'::jsonb
        or (q.source_info->>'transcriptionAuditMethod')::jsonb->'originalConditionsUnchanged' is distinct from 'true'::jsonb
        or (q.source_info->>'transcriptionAuditMethod')::jsonb->'correctChoiceMatchesOriginal' is distinct from 'true'::jsonb
        or (q.source_info->>'sourcePairingStatus'='SOURCE_NATIVE_PAIR'
          and (q.source_info->>'transcriptionAuditMethod')::jsonb->'nativeStudentTeacherProofRetained' is distinct from 'true'::jsonb)
        or (q.source_info->>'sourcePairingStatus'='EXACT'
          and (
            (q.source_info->>'transcriptionAuditMethod')::jsonb->>'originalSourceMode' is distinct from 'same_native_question_and_key'
            or (q.source_info->>'transcriptionAuditMethod')::jsonb->'nativeSameDocumentQuestionAndKeyProofRetained' is distinct from 'true'::jsonb
            or coalesce((q.source_info->>'transcriptionAuditMethod')::jsonb->>'nativeOriginalDocumentSha256','') !~ '^[0-9a-f]{64}$'
          ))
      )
  ) then
    raise exception 'Source fill-in choice adaptation lacks explicit original prompt, key, generated choices or native provenance';
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

  -- A staged teaching-material revision may have the same normalized stem and
  -- options as its damaged predecessor when only the explanation/image changes.
  -- Retire only an explicitly held, exact-lineage predecessor in this same
  -- release switch. Unrelated or unheld duplicates still fail the unique index.
  perform old_q.id
  from public.chem_questions new_q
  join public.chem_questions old_q
    on old_q.source_item_key = new_q.parent_source_item_key
   and old_q.grade_band = new_q.grade_band
   and old_q.content_fingerprint = new_q.content_fingerprint
   and old_q.id <> new_q.id
  where new_q.source_release_id = p_release_id
    and old_q.usable_for_review
  order by old_q.id
  for update of old_q;

  if exists (
    select 1
    from public.chem_questions new_q
    join public.chem_questions old_q
      on old_q.source_item_key = new_q.parent_source_item_key
     and old_q.grade_band = new_q.grade_band
     and old_q.content_fingerprint = new_q.content_fingerprint
     and old_q.id <> new_q.id
    where new_q.source_release_id = p_release_id
      and old_q.usable_for_review
      and not exists (
        select 1 from app_private.chem_question_delivery_holds h
        where h.anchor_question_id = old_q.id
          and h.resolved_at is null
      )
  ) then
    raise exception 'same-fingerprint predecessor must be explicitly held before a revision replaces it';
  end if;

  
  if exists (
    select 1 from public.chem_questions question
    where question.source_release_id = p_release_id
      and not app_private.chem_question_item_delivery_review_ready(question.id)
  ) then
    raise exception 'release contains a question without current item-level source review';
  end if;

  perform pg_catalog.set_config('app.chem_release_activation', 'on', true);

  update public.chem_questions old_q
  set usable_for_review = false,
      usable_for_class_quiz = false,
      usable_for_exam_sprint = false,
      usable_for_demo = false,
      updated_at = now()
  from public.chem_questions new_q
  where new_q.source_release_id = p_release_id
    and old_q.source_item_key = new_q.parent_source_item_key
    and old_q.grade_band = new_q.grade_band
    and old_q.content_fingerprint = new_q.content_fingerprint
    and old_q.id <> new_q.id
    and old_q.usable_for_review
    and exists (
      select 1 from app_private.chem_question_delivery_holds h
      where h.anchor_question_id = old_q.id
          and h.resolved_at is null
    );

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
$function$;

CREATE OR REPLACE FUNCTION public.chem_lock_question_answer(p_student_id uuid, p_plan_day_id uuid, p_attempt_sequence integer, p_question_id text, p_selected_option integer, p_uncertain boolean, p_duration_sec integer, p_revision_token text)
 RETURNS TABLE(selected_option integer, uncertain boolean, duration_sec integer, revision_token text, created_at timestamp with time zone, is_new boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_inserted integer := 0;
  v_plan public.chem_learning_plans;
  v_assigned jsonb;
begin
  if p_student_id is null
    or p_plan_day_id is null
    or p_attempt_sequence is null
    or p_attempt_sequence not between 0 and 7
    or length(coalesce(p_question_id, '')) not between 1 and 160
    or p_selected_option is null
    or p_selected_option not between 0 and 9
    or p_duration_sec is null
    or p_duration_sec not between 0 and 3600
  then
    raise exception 'invalid answer lock request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-review-suffix:' || p_student_id::text, 0)
  );

  perform s.id from public.chem_students_v2 s where s.id=p_student_id for update;
  select * into v_plan from public.chem_learning_plans where id=p_plan_day_id and student_id=p_student_id for update;
  if not found then raise exception 'plan does not belong to student'; end if;
  if v_plan.teaching_managed then
    select metadata#>'{reviewProgram,questionAssignments}'->v_plan.plan_date::text into v_assigned from public.chem_students_v2 where id=p_student_id;
    if v_plan.mode<>'REVIEW' or v_plan.delivery_mode<>'legacy_round' or p_selected_option not between 0 and 3
      or jsonb_array_length(coalesce(v_assigned,'[]'))<>v_plan.question_count or not exists(
      select 1 from app_private.chem_teaching_ready_questions q where q.id=p_question_id and q.grade_band=v_plan.teaching_source_grade
       and q.question_revision_token is not distinct from p_revision_token and (
         v_assigned ? q.id or exists(select 1 from app_private.chem_option_practice_bindings b
          join public.chem_questions anchor on anchor.id=b.anchor_question_id
          where v_assigned ? b.anchor_question_id and b.review_status='verified' and b.anchor_revision_token=anchor.question_revision_token
          and exists(select 1 from jsonb_array_elements(b.candidates) c where c->>'questionId'=q.id))
       )) then raise exception 'managed question is not authorized by this plan and active source'; end if;
  elsif not exists (
    select 1
    from app_private.chem_teaching_ready_questions question
    join app_private.chem_question_source_releases release
      on release.id = question.source_release_id
     and release.grade_band = question.grade_band
     and release.status = 'active'
     and release.verification_status = 'full_visual_verified'
    where question.id = p_question_id
      and question.grade_band in ('初三','高一','高二','高三')
      and question.source_kind = 'licensed_local'
      and question.review_status = 'approved'
      and question.scope_status = 'IN'
      and question.usable_for_review
      and not exists (
        select 1 from public.chem_question_delivery_holds() hold
        where hold.question_id = question.id
      )
      and question.render_mode = 'image_primary'
      and question.question_revision_token is not distinct from nullif(p_revision_token, '')
      and exists (
        select 1 from pg_catalog.jsonb_array_elements(question.asset_refs) asset
        where asset->>'kind' = 'question_image'
      )
      and exists (
        select 1 from pg_catalog.jsonb_array_elements(question.asset_refs) asset
        where asset->>'kind' = 'analysis_image'
      )
  ) then
    raise exception 'question revision is stale or not eligible for an answer lock';
  end if;

  insert into app_private.chem_question_answer_locks (
    student_id, plan_day_id, attempt_sequence, question_id,
    selected_option, uncertain, duration_sec, revision_token
  ) values (
    p_student_id, p_plan_day_id, p_attempt_sequence, p_question_id,
    p_selected_option, coalesce(p_uncertain, false), p_duration_sec,
    nullif(p_revision_token, '')
  )
  on conflict (student_id, plan_day_id, attempt_sequence, question_id) do nothing;
  get diagnostics v_inserted = row_count;

  return query
  select lock.selected_option::integer, lock.uncertain, lock.duration_sec,
    lock.revision_token, lock.created_at, v_inserted = 1
  from app_private.chem_question_answer_locks lock
  where lock.student_id = p_student_id
    and lock.plan_day_id = p_plan_day_id
    and lock.attempt_sequence = p_attempt_sequence
    and lock.question_id = p_question_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.chem_finalize_learning_attempt(p_attempt_id uuid, p_student_id uuid, p_plan_day_id uuid, p_attempt_kind text, p_sequence integer, p_mode text, p_started_at timestamp with time zone, p_completed_at timestamp with time zone, p_first_score integer, p_answers jsonb, p_skill_states jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_answer_count integer;
  v_correct_count integer;
  v_current_sequence integer;
  v_inserted_answers integer;
  v_inserted_states integer;
  v_managed boolean;
  v_source_grade text;
begin
  if p_attempt_id is null
    or p_student_id is null
    or p_plan_day_id is null
    or p_attempt_kind not in ('scheduled', 'review')
    or p_sequence is null
    or p_sequence not between 0 and 7
    or p_mode not in ('REVIEW', 'CLASS_QUIZ', 'EXAM_SPRINT')
    or p_started_at is null
    or p_completed_at is null
    or p_completed_at < p_started_at
    or jsonb_typeof(p_answers) <> 'array'
    or jsonb_typeof(p_skill_states) <> 'array'
  then
    raise exception 'invalid learning attempt finalization request';
  end if;

  v_answer_count := jsonb_array_length(p_answers);
  if v_answer_count not between 1 and (case when p_mode = 'REVIEW' then 48 else 10 end)
    or jsonb_array_length(p_skill_states) not between 1 and 48
    or p_first_score not between 0 and v_answer_count
  then
    raise exception 'invalid learning attempt finalization cardinality';
  end if;

  perform s.id from public.chem_students_v2 s where s.id=p_student_id for update;
  select teaching_managed,teaching_source_grade into v_managed,v_source_grade from public.chem_learning_plans where id=p_plan_day_id and student_id=p_student_id for update;
  if v_managed and exists(select 1 from jsonb_array_elements(p_answers) a where not exists(select 1 from app_private.chem_teaching_ready_questions q where q.id=a->>'question_id' and q.grade_band=v_source_grade)) then
    raise exception 'managed source changed before finalization';
  end if;
  -- A question held after issuance must not be finalized from a stale client.
  if exists (
    select 1 from jsonb_array_elements(p_answers) answer
    join public.chem_question_delivery_holds() hold
      on hold.question_id = answer->>'question_id'
  ) then
    raise exception 'question was held before finalization';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_answers) answer
    where not exists (
      select 1 from app_private.chem_teaching_ready_questions ready
      where ready.id = answer->>'question_id'
    )
  ) then
    raise exception 'question is not ready for finalization';
  end if;
  if not exists (
    select 1
    from public.chem_learning_plans p
    where p.id = p_plan_day_id
      and p.student_id = p_student_id
      and p.mode = p_mode
  ) then
    raise exception 'plan does not belong to student or mode';
  end if;

  select count(*)::integer
  into v_current_sequence
  from public.chem_learning_attempts a
  where a.student_id = p_student_id
    and a.plan_day_id = p_plan_day_id;

  if p_sequence <> v_current_sequence
    or p_attempt_kind <> (case when p_sequence = 0 then 'scheduled' else 'review' end)
  then
    raise exception 'attempt sequence changed';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_answers) as x(
      question_id text,
      selected_option integer,
      correct boolean
    )
    left join public.chem_questions q on q.id = x.question_id
    where q.id is null
      or x.selected_option is null
      or x.correct is distinct from (x.selected_option = q.correct_option)
  ) then
    raise exception 'answer correctness does not match server question';
  end if;

  select (count(*) filter (where x.correct))::integer
  into v_correct_count
  from jsonb_to_recordset(p_answers) as x(correct boolean);
  if v_correct_count <> p_first_score then
    raise exception 'first score does not match canonical answers';
  end if;

  if p_mode = 'REVIEW' and exists (
    select 1
    from jsonb_to_recordset(p_answers) as x(
      question_id text,
      selected_option integer,
      uncertain boolean,
      duration_sec integer,
      revision_token text
    )
    join public.chem_questions q on q.id = x.question_id
    where (v_managed or (q.grade_band in ('初三','高一','高二','高三') and q.source_kind = 'licensed_local'))
      and (
        x.revision_token is distinct from q.question_revision_token
        or not exists (
        select 1
        from app_private.chem_question_answer_locks l
        where l.student_id = p_student_id
          and l.plan_day_id = p_plan_day_id
          and l.attempt_sequence = p_sequence
          and l.question_id = x.question_id
          and l.selected_option = x.selected_option
          and l.uncertain = coalesce(x.uncertain, false)
          and l.duration_sec = coalesce(x.duration_sec, 0)
          and l.revision_token is not distinct from nullif(x.revision_token, '')
        )
      )
  ) then
    raise exception 'licensed answer is not backed by the immutable first-answer lock';
  end if;

  insert into public.chem_learning_attempts (
    id, student_id, plan_day_id, attempt_kind, sequence, mode,
    started_at, completed_at, first_score
  ) values (
    p_attempt_id, p_student_id, p_plan_day_id, p_attempt_kind, p_sequence,
    p_mode, p_started_at, p_completed_at, p_first_score
  );

  insert into public.chem_attempt_answers (
    attempt_id, question_id, mother_id, skill_id, concept_key, level,
    correct, uncertain, duration_sec, selected_option, question_snapshot
  )
  select
    p_attempt_id,
    x.question_id,
    x.mother_id,
    x.skill_id,
    nullif(x.concept_key, ''),
    x.level::smallint,
    x.correct,
    coalesce(x.uncertain, false),
    x.duration_sec,
    x.selected_option::smallint,
    x.question_snapshot
  from jsonb_to_recordset(p_answers) as x(
    question_id text,
    mother_id text,
    skill_id text,
    concept_key text,
    level integer,
    correct boolean,
    uncertain boolean,
    duration_sec integer,
    selected_option integer,
    revision_token text,
    question_snapshot jsonb
  );
  get diagnostics v_inserted_answers = row_count;
  if v_inserted_answers <> v_answer_count then
    raise exception 'not every answer was inserted';
  end if;

  insert into public.chem_student_skill_state (
    student_id, skill_id, verified_level, candidate_level, stability,
    consecutive_errors, next_review_at, review_interval_index,
    last_reviewed_at, teacher_intervention, updated_at
  )
  select
    p_student_id,
    x.skill_id,
    x.verified_level::smallint,
    x.candidate_level::smallint,
    x.stability,
    x.consecutive_errors,
    x.next_review_at,
    x.review_interval_index::smallint,
    x.last_reviewed_at,
    x.teacher_intervention,
    x.updated_at
  from jsonb_to_recordset(p_skill_states) as x(
    skill_id text,
    verified_level integer,
    candidate_level integer,
    stability text,
    consecutive_errors integer,
    next_review_at timestamptz,
    review_interval_index integer,
    last_reviewed_at timestamptz,
    teacher_intervention boolean,
    updated_at timestamptz
  )
  on conflict (student_id, skill_id) do update set
    verified_level = excluded.verified_level,
    candidate_level = excluded.candidate_level,
    stability = excluded.stability,
    consecutive_errors = excluded.consecutive_errors,
    next_review_at = excluded.next_review_at,
    review_interval_index = excluded.review_interval_index,
    last_reviewed_at = excluded.last_reviewed_at,
    teacher_intervention = excluded.teacher_intervention,
    updated_at = excluded.updated_at;
  get diagnostics v_inserted_states = row_count;
  if v_inserted_states <> jsonb_array_length(p_skill_states) then
    raise exception 'not every skill state was written';
  end if;

  delete from app_private.chem_question_answer_locks l
  where l.student_id = p_student_id
    and l.plan_day_id = p_plan_day_id
    and l.attempt_sequence = p_sequence;

  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.chem_record_question_item_visual_review(p_question_id text, p_revision_token text, p_source_locator text, p_review_actor text, p_review_note text, p_checks jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_question public.chem_questions%rowtype;
  v_item app_private.chem_question_source_release_items%rowtype;
  v_document app_private.chem_junior_question_source_documents%rowtype;
begin
  if p_revision_token !~ '^[0-9a-f]{64}$'
    or length(btrim(coalesce(p_source_locator,''))) < 3
    or length(btrim(coalesce(p_review_actor,''))) < 3
    or length(btrim(coalesce(p_review_note,''))) < 12
    or jsonb_typeof(p_checks) is distinct from 'object'
    or p_checks->'stem_options_and_formula' is distinct from 'true'::jsonb
    or p_checks->'answer_and_explanation' is distinct from 'true'::jsonb
    or p_checks->'source_image_complete' is distinct from 'true'::jsonb
    or p_checks->'source_locator_matches' is distinct from 'true'::jsonb
  then raise exception '逐题核验须包含原图、公式上下标及电荷、四个选项、答案解析和来源定位'; end if;

  select * into v_question from public.chem_questions
  where id=p_question_id and source_release_id is not null for update;
  if not found or v_question.question_revision_token is distinct from p_revision_token
    or v_question.source_info->>'locator' is distinct from p_source_locator
  then raise exception '题目修订或来源定位已变化，请重新核验'; end if;

  select * into v_item from app_private.chem_question_source_release_items
  where release_id=v_question.source_release_id and question_id=v_question.id for update;
  if not found then raise exception '原题缺少对应的来源清单'; end if;

  if v_question.grade_band in ('初三','高一','高二','高三') and v_question.render_mode='image_primary' then
    if v_question.render_mode <> 'image_primary'
      or not exists (
        select 1 from app_private.chem_question_assets asset
        where asset.question_id=v_question.id and asset.asset_kind='question_image'
          and asset.sha256=v_item.question_asset_sha256
          and exists (
            select 1 from jsonb_array_elements(v_question.asset_refs) ref
            where ref->>'kind'='question_image' and ref->>'path'=asset.asset_path
              and ref->>'sha256'=asset.sha256
          )
      )
      or not exists (
        select 1 from app_private.chem_question_assets asset
        where asset.question_id=v_question.id and asset.asset_kind='analysis_image'
          and asset.sha256=v_item.analysis_asset_sha256
          and exists (
            select 1 from jsonb_array_elements(v_question.asset_refs) ref
            where ref->>'kind'='analysis_image' and ref->>'path'=asset.asset_path
              and ref->>'sha256'=asset.sha256
          )
      )
    then raise exception '原题图或答案图未与来源清单及页面引用一致'; end if;
  elsif v_question.grade_band<>'初三' or v_question.source_kind<>'user_provided_local' or v_question.render_mode<>'native' then
    raise exception '未支持的年级或原题格式';
  end if;

  -- Junior image imports also retain the per-question original document proof.
  if v_question.grade_band='初三' then
    select * into v_document
    from app_private.chem_junior_question_source_documents source_doc
    where source_doc.question_id=v_question.id
      and source_doc.source_release_id=v_question.source_release_id
      and source_doc.revision_token=v_question.question_revision_token
      and source_doc.source_item_sha256=v_item.item_sha256
      and source_doc.source_locator=v_question.source_info->>'locator'
    for update;
    if not found then
      raise exception '这道初三题还没有单独核对原始材料，请先登记该题的原文件';
    end if;
  end if;

  insert into app_private.chem_question_item_visual_reviews(
    question_id,source_release_id,review_state,revision_token,
    source_item_sha256,question_image_sha256,analysis_image_sha256,
    source_document_sha256,source_locator,review_checks,review_note,
    review_actor,reviewed_at,updated_at
  ) values (
    v_question.id,v_question.source_release_id,'verified',p_revision_token,
    v_item.item_sha256,
    case when v_question.render_mode='image_primary' then v_item.question_asset_sha256 end,
    case when v_question.render_mode='image_primary' then v_item.analysis_asset_sha256 end,
    case when v_question.grade_band='初三' then v_document.source_document_sha256 end,
    p_source_locator,p_checks,btrim(p_review_note),btrim(p_review_actor),now(),now()
  ) on conflict(question_id) do update set
    source_release_id=excluded.source_release_id,
    review_state=excluded.review_state,
    revision_token=excluded.revision_token,
    source_item_sha256=excluded.source_item_sha256,
    question_image_sha256=excluded.question_image_sha256,
    analysis_image_sha256=excluded.analysis_image_sha256,
    source_document_sha256=excluded.source_document_sha256,
    source_locator=excluded.source_locator,
    review_checks=excluded.review_checks,
    review_note=excluded.review_note,
    review_actor=excluded.review_actor,
    reviewed_at=excluded.reviewed_at,
    updated_at=excluded.updated_at;
  return jsonb_build_object('questionId',v_question.id,'reviewState','verified',
    'sourceItemSha256',v_item.item_sha256,'revisionToken',p_revision_token);
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.chem_question_item_visual_reviewed(p_question_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select exists(
    select 1 from public.chem_questions q
    join app_private.chem_question_item_visual_reviews review
      on review.question_id=q.id and review.source_release_id=q.source_release_id
    join app_private.chem_question_source_release_items item
      on item.question_id=q.id and item.release_id=q.source_release_id
    where q.id=p_question_id
      and review.review_state='verified'
      and review.revision_token=q.question_revision_token
      and review.source_locator=q.source_info->>'locator'
      and review.source_item_sha256=item.item_sha256
      and (
        (q.grade_band in ('初三','高一','高二','高三') and q.render_mode='image_primary'
          and review.question_image_sha256=item.question_asset_sha256
          and review.analysis_image_sha256=item.analysis_asset_sha256)
        or (q.grade_band='初三' and q.source_kind='user_provided_local' and q.render_mode='native')
      )
      and (q.grade_band<>'初三' or exists (
        select 1 from app_private.chem_junior_question_source_documents source_doc
        where source_doc.question_id=q.id
          and source_doc.source_release_id=q.source_release_id
          and source_doc.revision_token=q.question_revision_token
          and source_doc.source_item_sha256=item.item_sha256
          and source_doc.source_locator=q.source_info->>'locator'
          and source_doc.source_document_sha256=review.source_document_sha256
      ))
  );
$function$;

CREATE OR REPLACE FUNCTION app_private.chem_guard_junior_private_asset_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if (
      (tg_op = 'INSERT' and exists (
        select 1
        from public.chem_questions as question
        join app_private.chem_question_source_releases as release_row
          on release_row.id = question.source_release_id
        where question.id = new.question_id and (release_row.grade_band = '初三' and release_row.release_kind='primary')
      ))
      or (tg_op = 'DELETE' and exists (
        select 1
        from public.chem_questions as question
        join app_private.chem_question_source_releases as release_row
          on release_row.id = question.source_release_id
        where question.id = old.question_id and (release_row.grade_band = '初三' and release_row.release_kind='primary')
      ))
      or (tg_op = 'UPDATE' and exists (
        select 1
        from public.chem_questions as question
        join app_private.chem_question_source_releases as release_row
          on release_row.id = question.source_release_id
        where question.id in (old.question_id, new.question_id)
          and (release_row.grade_band = '初三' and release_row.release_kind='primary')
      ))
    )
    and (
      tg_op <> 'DELETE'
      or coalesce(pg_catalog.current_setting('app.chem_junior_release_lifecycle', true), '') <> 'on'
    )
  then
    raise exception 'junior native-text releases cannot contain private assets';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.chem_guard_junior_release_item_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if (
      (tg_op = 'INSERT' and exists (
        select 1 from app_private.chem_question_source_releases as release_row
        where release_row.id = new.release_id and (release_row.grade_band = '初三' and release_row.release_kind='primary')
      ))
      or (tg_op = 'DELETE' and exists (
        select 1 from app_private.chem_question_source_releases as release_row
        where release_row.id = old.release_id and (release_row.grade_band = '初三' and release_row.release_kind='primary')
      ))
      or (tg_op = 'UPDATE' and exists (
        select 1 from app_private.chem_question_source_releases as release_row
        where (release_row.grade_band = '初三' and release_row.release_kind='primary')
          and release_row.id in (old.release_id, new.release_id)
      ))
    )
    and coalesce(pg_catalog.current_setting('app.chem_junior_release_lifecycle', true), '') <> 'on'
  then
    raise exception 'junior release items may change only through the dedicated server lifecycle';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.chem_guard_junior_question_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if (
      (
        tg_op = 'INSERT'
        and (
          (new.grade_band = '初三' and new.source_kind='user_provided_local')
          or exists (
            select 1
            from app_private.chem_question_source_releases as release_row
            where release_row.id = new.source_release_id and (release_row.grade_band = '初三' and release_row.release_kind='primary')
          )
        )
      )
      or (
        tg_op = 'DELETE'
        and (
          (old.grade_band = '初三' and old.source_kind='user_provided_local')
          or exists (
            select 1
            from app_private.chem_question_source_releases as release_row
            where release_row.id = old.source_release_id and (release_row.grade_band = '初三' and release_row.release_kind='primary')
          )
        )
      )
      or (
        tg_op = 'UPDATE'
        and (
          (old.grade_band = '初三' and old.source_kind='user_provided_local')
          or (new.grade_band = '初三' and new.source_kind='user_provided_local')
          or exists (
            select 1
            from app_private.chem_question_source_releases as release_row
            where (release_row.grade_band = '初三' and release_row.release_kind='primary')
              and release_row.id in (old.source_release_id, new.source_release_id)
          )
        )
      )
    )
    and coalesce(pg_catalog.current_setting('app.chem_junior_release_lifecycle', true), '') <> 'on'
  then
    raise exception 'junior source questions may change only through the dedicated server lifecycle';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.chem_guard_junior_release_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if (
      (tg_op = 'INSERT' and (new.grade_band = '初三' and new.release_kind='primary'))
      or (tg_op = 'DELETE' and (old.grade_band = '初三' and old.release_kind='primary'))
      or (tg_op = 'UPDATE' and ((old.grade_band = '初三' and old.release_kind='primary') or (new.grade_band = '初三' and new.release_kind='primary')))
    )
    and coalesce(pg_catalog.current_setting('app.chem_junior_release_lifecycle', true), '') <> 'on'
  then
    raise exception 'junior source releases may change only through the dedicated server lifecycle';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.chem_require_junior_rights_before_activation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  -- Independent, fully reviewed image materials use the four-grade material contract.
  -- Existing primary/native route and rights checks are retained below.
  if new.release_kind='teaching_material' then return new; end if;
  if new.grade_band = '初三' and new.status = 'active' then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('chem-source-original-release', 0)
    );
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('chem-h3-original-release', 0)
    );
    perform binding.knowledge_id
    from app_private.chem_junior_knowledge_card_bindings as binding
    where binding.release_id = new.id
    order by binding.knowledge_id
    for share;
    perform card.id
    from app_private.chem_junior_knowledge_card_bindings as binding
    join public.chem_knowledge_cards as card on card.id = binding.card_id
    where binding.release_id = new.id
    order by card.id
    for share of card;
  end if;
  if new.grade_band = '初三'
    and new.status = 'active'
    and (
      case
        when tg_op = 'INSERT' then true
        else (
          old.status is distinct from 'active'
          or old.grade_band is distinct from new.grade_band
          or old.textbook_version is distinct from new.textbook_version
        )
      end
    )
    and (
      new.textbook_version is distinct from '科粤版'
      or not exists (
        select 1
        from app_private.chem_junior_source_release_rights as rights
        where rights.release_id = new.id
          and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
          and rights.redistribution_allowed = false
          and rights.attested_manifest_sha256 = new.manifest_sha256
          and rights.attested_card_manifest_sha256 =
            app_private.chem_junior_knowledge_card_manifest_sha256(new.id)
          and rights.attested_at is not null
          and length(btrim(rights.attestation_actor)) > 0
      )
      or exists (
        select 1
        from app_private.chem_junior_source_release_specs as spec
        cross join lateral pg_catalog.unnest(spec.knowledge_ids) as required(knowledge_id)
        where spec.release_id = new.id
          and not app_private.chem_junior_knowledge_card_binding_matches(
            new.id,
            new.textbook_version,
            required.knowledge_id
          )
      )
      or not exists (
        select 1
        from app_private.chem_junior_source_release_specs as spec
        where spec.release_id = new.id
          and spec.textbook_version = new.textbook_version
          and cardinality(spec.knowledge_ids) between 3 and 200
      )
    )
  then
    raise exception 'junior activation requires the private-use rights contract and redistribution_allowed=false';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.chem_track_junior_active_release_routes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_routes integer;
begin
  -- Independent, fully reviewed image materials use the four-grade material contract.
  -- Existing primary/native route and rights checks are retained below.
  if new.release_kind='teaching_material' then return new; end if;
  if tg_op='UPDATE' and old.grade_band='初三'
    and old.status='active' and new.status is distinct from 'active'
  then
    delete from app_private.chem_junior_active_release_routes route
    where route.source_release_id=old.id;
  end if;

  if new.grade_band='初三' and new.status='active'
    and (tg_op='INSERT' or old.status is distinct from 'active')
  then
    if new.textbook_version is distinct from '科粤版'
      or exists (
        select 1 from public.chem_questions q
        where q.source_release_id=new.id and q.usable_for_review
          and not exists (
            select 1 from app_private.chem_junior_knowledge_provenance p
            where p.textbook_version='科粤版'
              and p.knowledge_id=q.knowledge_id
              and p.source_release_id=new.id
              and p.verification_status='verified'
          )
      )
    then
      raise exception 'active junior questions need exact verified route ownership';
    end if;

    insert into app_private.chem_junior_active_release_routes (
      textbook_version,knowledge_id,source_release_id
    )
    select distinct p.textbook_version,p.knowledge_id,p.source_release_id
    from app_private.chem_junior_knowledge_provenance p
    join public.chem_questions q
      on q.source_release_id=new.id and q.knowledge_id=p.knowledge_id
    where p.textbook_version='科粤版'
      and p.source_release_id=new.id
      and p.verification_status='verified'
      and q.usable_for_review;
    get diagnostics v_routes = row_count;
    if v_routes < 1 then
      raise exception 'active junior release has no owned knowledge route';
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.chem_teaching_ready_question_ids(p_grade text, p_question_ids text[])
 RETURNS TABLE(question_id text, source_release_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_grade is null or p_grade not in ('初三','高一','高二','高三')
    or cardinality(p_question_ids) is null or cardinality(p_question_ids) not between 1 and 1000
  then return; end if;
  -- Image materials and native originals can coexist in the junior catalog.
  if true then
    return query
    with requested as materialized (
      select q.* from public.chem_questions q
      where q.grade_band=p_grade and q.id=any(p_question_ids)
    ), held as materialized (
      select distinct h.question_id
      from public.chem_question_delivery_holds_for(array(select id from requested)) h
    )
    select q.id,q.source_release_id
    from requested q
    join app_private.chem_question_source_releases r on r.id=q.source_release_id
    left join held on held.question_id=q.id
    where q.review_status='approved' and q.scope_status='IN' and q.usable_for_review
      and r.status='active' and r.verification_status='full_visual_verified'
      and r.manifest_sha256=r.verification_manifest_sha256
      and jsonb_typeof(q.options)='array' and jsonb_array_length(q.options)=4
      and q.correct_option between 0 and 3
      and length(btrim(q.stem))>0 and length(btrim(q.explanation))>0
      and q.content_fingerprint is not null and q.source_item_key is not null
      and held.question_id is null
      and app_private.chem_question_item_delivery_review_ready(q.id)
      and q.source_kind='licensed_local' and q.render_mode='image_primary'
      and (r.release_kind='teaching_material' or exists (
        select 1 from public.chem_active_verified_source_releases() a
        where a.source_release_id=q.source_release_id and a.grade_band=q.grade_band
      ));
    if p_grade <> '初三' then return; end if;
  end if;
  return query
  with requested as materialized (
    select q.* from public.chem_questions q
    where q.grade_band = '初三' and q.id = any(p_question_ids)
  ), held as materialized (
    select distinct h.question_id
    from public.chem_question_delivery_holds_for(array(select id from requested)) h
  ), knowledge_batches as materialized (
    select array_agg(knowledge_id order by knowledge_id) knowledge_ids
    from (
      select knowledge_id, (row_number() over (order by knowledge_id) - 1) / 20 batch
      from (select distinct knowledge_id from requested where knowledge_id is not null) k
    ) numbered group by batch
  ), junior_ready as materialized (
    select p.knowledge_id, p.source_release_id
    from knowledge_batches b
    cross join lateral public.chem_junior_verified_provenance_rows('科粤版', b.knowledge_ids) p
    where p.source_release_ready and p.verification_status = 'verified'
  )
  select q.id, q.source_release_id
  from requested q
  join app_private.chem_question_source_releases r on r.id = q.source_release_id
  left join held on held.question_id = q.id
  where q.review_status = 'approved' and q.scope_status = 'IN' and q.usable_for_review
    and r.status = 'active' and r.verification_status = 'full_visual_verified'
    and r.manifest_sha256 = r.verification_manifest_sha256
    and jsonb_typeof(q.options) = 'array' and jsonb_array_length(q.options) = 4
    and q.correct_option >= 0 and q.correct_option <= 3
    and length(btrim(q.stem)) > 0 and length(btrim(q.explanation)) > 0
    and q.content_fingerprint is not null and q.source_item_key is not null
    and held.question_id is null
    and app_private.chem_question_item_delivery_review_ready(q.id)
    and q.source_kind = 'user_provided_local' and q.render_mode = 'native'
    and q.textbook_version = '科粤版'
    and exists (
      select 1 from junior_ready a
      where a.knowledge_id = q.knowledge_id and a.source_release_id = q.source_release_id
    );
end;
$function$;

create or replace view app_private.chem_teaching_ready_questions as
 WITH held AS MATERIALIZED (
         SELECT DISTINCT chem_question_delivery_holds.question_id
           FROM chem_question_delivery_holds() chem_question_delivery_holds(question_id, reason)
        ), junior_knowledge AS MATERIALIZED (
         SELECT DISTINCT chem_questions.knowledge_id
           FROM chem_questions
          WHERE chem_questions.grade_band = '初三'::text AND chem_questions.knowledge_id IS NOT NULL
        ), junior_ready AS MATERIALIZED (
         SELECT p.knowledge_id,
            p.source_release_id
           FROM junior_knowledge k
             CROSS JOIN LATERAL chem_junior_verified_provenance_rows('科粤版'::text, ARRAY[k.knowledge_id]) p(knowledge_id, textbook_version, source_release_id, verification_status, source_release_ready)
          WHERE p.source_release_ready AND p.verification_status = 'verified'::text
        )
 SELECT q.id,
    q.mother_id,
    q.skill_id,
    q.level,
    q.grade_band,
    q.stem,
    q.options,
    q.correct_option,
    q.explanation,
    q.scaffold,
    q.review_status,
    q.scope_status,
    q.source_kind,
    q.image_url,
    q.created_at,
    q.updated_at,
    q.usable_for_class_quiz,
    q.usable_for_review,
    q.usable_for_exam_sprint,
    q.concept_key,
    q.source_info,
    q.asset_refs,
    q.render_mode,
    q.source_item_key,
    q.content_fingerprint,
    q.question_revision_token,
    q.source_release_id,
    q.usable_for_demo,
    q.textbook_version,
    q.knowledge_id,
    q.same_type_key,
    q.parent_source_item_key
   FROM chem_questions q
     JOIN app_private.chem_question_source_releases r ON r.id = q.source_release_id
     LEFT JOIN held ON held.question_id = q.id
  WHERE q.review_status = 'approved'::text AND q.scope_status = 'IN'::text AND q.usable_for_review AND r.status = 'active'::text AND r.verification_status = 'full_visual_verified'::text AND r.manifest_sha256 = r.verification_manifest_sha256 AND jsonb_typeof(q.options) = 'array'::text AND jsonb_array_length(q.options) = 4 AND q.correct_option >= 0 AND q.correct_option <= 3 AND length(btrim(q.stem)) > 0 AND length(btrim(q.explanation)) > 0 AND q.content_fingerprint IS NOT NULL AND q.source_item_key IS NOT NULL AND held.question_id IS NULL AND app_private.chem_question_item_delivery_review_ready(q.id) AND ((q.grade_band = ANY (ARRAY['初三'::text, '高一'::text, '高二'::text, '高三'::text])) AND q.source_kind = 'licensed_local'::text AND q.render_mode = 'image_primary'::text AND (r.release_kind = 'teaching_material'::text OR (EXISTS ( SELECT 1
           FROM chem_active_verified_source_releases() a(grade_band, source_release_id)
          WHERE a.source_release_id = q.source_release_id AND a.grade_band = q.grade_band))) OR q.grade_band = '初三'::text AND q.source_kind = 'user_provided_local'::text AND q.render_mode = 'native'::text AND q.textbook_version = '科粤版'::text AND (EXISTS ( SELECT 1
           FROM junior_ready a
          WHERE a.knowledge_id = q.knowledge_id AND a.source_release_id = q.source_release_id)));

-- Server-owned format metadata for an exact, verified source release.
-- Used by plan reading to distinguish junior native originals from junior images.
create function public.chem_teaching_source_release_context(p_release_id uuid)
returns table(grade_band text,source_kind text,render_mode text)
language sql stable security definer set search_path='' as $$
  select r.grade_band,
    case when r.grade_band='初三' and r.release_kind='primary'
      then 'user_provided_local' else 'licensed_local' end,
    case when r.grade_band='初三' and r.release_kind='primary'
      then 'native' else 'image_primary' end
  from app_private.chem_question_source_releases r
  where r.id=p_release_id and r.status='active'
    and r.verification_status='full_visual_verified'
    and r.manifest_sha256=r.verification_manifest_sha256
    and r.grade_band in ('初三','高一','高二','高三');
$$;
revoke all on function public.chem_teaching_source_release_context(uuid)
  from public,anon,authenticated;
grant execute on function public.chem_teaching_source_release_context(uuid) to service_role;
commit;
