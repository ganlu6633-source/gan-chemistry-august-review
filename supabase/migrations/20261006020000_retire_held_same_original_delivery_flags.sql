-- Preserve immutable source content when retiring held exact-original delivery flags.
-- The original duplicate index remains unchanged; unrelated duplicates still fail.

create or replace function app_private.chem_replacement_has_exact_source_ancestor(p_release_id uuid,p_new_id text,p_old_id text)
returns boolean language sql stable security definer set search_path to '' as $function$
with recursive chain(id,source_item_key,parent_source_item_key,grade_band,canonical_source_id) as (
  select p.id,p.source_item_key,p.parent_source_item_key,p.grade_band,pi.canonical_source_id
  from public.chem_questions n
  join app_private.chem_question_source_release_items ni on ni.question_id=n.id and ni.release_id=n.source_release_id
  join app_private.chem_question_source_release_lineage l on l.question_id=n.id and l.release_id=n.source_release_id
  join public.chem_questions p on p.id=l.previous_question_id and p.source_release_id=l.previous_release_id
  join app_private.chem_question_source_release_items pi on pi.question_id=p.id and pi.release_id=p.source_release_id
  where n.id=p_new_id and n.source_release_id=p_release_id and n.parent_source_item_key=p.source_item_key
    and n.grade_band=p.grade_band and ni.canonical_source_id=pi.canonical_source_id
  union
  select p.id,p.source_item_key,p.parent_source_item_key,p.grade_band,pi.canonical_source_id
  from chain c join public.chem_questions p on p.source_item_key=c.parent_source_item_key
  join app_private.chem_question_source_release_items pi on pi.question_id=p.id and pi.release_id=p.source_release_id
  where p.grade_band=c.grade_band and pi.canonical_source_id=c.canonical_source_id
)
select exists(select 1 from chain where id=p_old_id);
$function$;
revoke all on function app_private.chem_replacement_has_exact_source_ancestor(uuid,text,text) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION app_private.chem_guard_source_question_content_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_source_kind text := case when tg_op = 'INSERT' then new.source_kind else old.source_kind end;
  v_release_id uuid := case when tg_op = 'INSERT' then new.source_release_id else old.source_release_id end;
  v_question_id text := case when tg_op = 'INSERT' then new.id else old.id end;
  v_touches_source_identity boolean := case
    when tg_op = 'INSERT' then new.source_kind in ('licensed_local', 'user_provided_local') or new.source_release_id is not null
    when tg_op = 'DELETE' then old.source_kind in ('licensed_local', 'user_provided_local') or old.source_release_id is not null
    else old.source_kind in ('licensed_local', 'user_provided_local')
      or new.source_kind in ('licensed_local', 'user_provided_local')
      or old.source_release_id is not null
      or new.source_release_id is not null
  end;
begin

  -- Only retire delivery flags of held exact ancestors during verified activation.
  if tg_op='UPDATE' and pg_catalog.current_setting('app.chem_release_activation',true)='on'
    and coalesce(pg_catalog.current_setting('app.chem_held_revision_retirement',true),'') ~ '^[0-9a-f-]{36}$'
    and old.source_kind='licensed_local' and old.usable_for_review
    and not new.usable_for_review and not new.usable_for_class_quiz
    and not new.usable_for_exam_sprint and not new.usable_for_demo
    and (to_jsonb(new)-array['usable_for_review','usable_for_class_quiz','usable_for_exam_sprint','usable_for_demo','updated_at'])
      = (to_jsonb(old)-array['usable_for_review','usable_for_class_quiz','usable_for_exam_sprint','usable_for_demo','updated_at'])
    and exists(select 1 from app_private.chem_question_delivery_holds h where h.anchor_question_id=old.id and h.resolved_at is null)
    and exists(
      select 1 from public.chem_questions n
      join app_private.chem_question_source_releases r on r.id=n.source_release_id
      join app_private.chem_question_source_release_items ni on ni.release_id=r.id and ni.question_id=n.id
      join app_private.chem_question_source_release_items oi on oi.release_id=old.source_release_id and oi.question_id=old.id
      where r.id::text=pg_catalog.current_setting('app.chem_held_revision_retirement',true)
        and r.status='staged' and r.release_kind='teaching_material'
        and r.verification_status='full_visual_verified' and r.verification_manifest_sha256=r.manifest_sha256
        and n.grade_band=old.grade_band and n.content_fingerprint=old.content_fingerprint
        and ni.canonical_source_id=oi.canonical_source_id and not n.usable_for_review
        and app_private.chem_replacement_has_exact_source_ancestor(r.id,n.id,old.id)
        and app_private.chem_question_item_delivery_review_ready(n.id)
    ) then return new; end if;

  if v_touches_source_identity then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release', 0));
    if tg_op = 'UPDATE' and (
      new.id is distinct from old.id
      or new.source_kind is distinct from old.source_kind
      or new.source_release_id is distinct from old.source_release_id
    ) then
      raise exception 'source question identity cannot be changed; insert a new staged revision instead';
    end if;
    if tg_op = 'INSERT' and (
      new.source_kind not in ('licensed_local', 'user_provided_local')
      or new.source_release_id is null
      or not exists (
      select 1
      from app_private.chem_question_source_releases r
      where r.id = v_release_id and r.status = 'staged'
      )
    ) then
      raise exception 'source-backed questions can only be inserted into a staged release';
    end if;
    if tg_op <> 'INSERT' and (
      exists (
        select 1 from public.chem_attempt_answers aa where aa.question_id = v_question_id
      )
      or exists (
        select 1
        from app_private.chem_question_source_releases r
        where r.id = v_release_id and r.status in ('active','retired')
      )
    ) then
      raise exception 'an activated or answered source-backed question is immutable; create a new revision instead';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$
;

create or replace function app_private.chem_retire_held_same_original_revisions(p_release_id uuid)
returns void language plpgsql security definer set search_path to '' as $function$
begin
  if pg_catalog.current_setting('app.chem_release_activation',true) is distinct from 'on'
    or not exists(select 1 from app_private.chem_question_source_releases r where r.id=p_release_id
      and r.status='staged' and r.release_kind='teaching_material'
      and r.verification_status='full_visual_verified' and r.verification_manifest_sha256=r.manifest_sha256) then
    raise exception 'retirement requires the controlled verified teaching activation';
  end if;
  perform old_q.id from public.chem_questions old_q
join app_private.chem_question_source_release_items oi on oi.release_id=old_q.source_release_id and oi.question_id=old_q.id
join app_private.chem_question_source_release_items ni on ni.canonical_source_id=oi.canonical_source_id and ni.release_id=p_release_id
join public.chem_questions new_q on new_q.id=ni.question_id and new_q.source_release_id=p_release_id
where old_q.id<>new_q.id and old_q.grade_band=new_q.grade_band
and old_q.source_kind='licensed_local' and old_q.usable_for_review and old_q.content_fingerprint=new_q.content_fingerprint order by old_q.id for update of old_q,oi;
  perform h.anchor_question_id from app_private.chem_question_delivery_holds h
    where h.anchor_question_id in(select old_q.id from public.chem_questions old_q
join app_private.chem_question_source_release_items oi on oi.release_id=old_q.source_release_id and oi.question_id=old_q.id
join app_private.chem_question_source_release_items ni on ni.canonical_source_id=oi.canonical_source_id and ni.release_id=p_release_id
join public.chem_questions new_q on new_q.id=ni.question_id and new_q.source_release_id=p_release_id
where old_q.id<>new_q.id and old_q.grade_band=new_q.grade_band
and old_q.source_kind='licensed_local' and old_q.usable_for_review and old_q.content_fingerprint=new_q.content_fingerprint)
    order by h.anchor_question_id for update of h;
  if exists(select 1 from public.chem_questions old_q
join app_private.chem_question_source_release_items oi on oi.release_id=old_q.source_release_id and oi.question_id=old_q.id
join app_private.chem_question_source_release_items ni on ni.canonical_source_id=oi.canonical_source_id and ni.release_id=p_release_id
join public.chem_questions new_q on new_q.id=ni.question_id and new_q.source_release_id=p_release_id
where old_q.id<>new_q.id and old_q.grade_band=new_q.grade_band
and old_q.source_kind='licensed_local' and old_q.usable_for_review and old_q.content_fingerprint=new_q.content_fingerprint
    and (not exists(select 1 from app_private.chem_question_delivery_holds h where h.anchor_question_id=old_q.id and h.resolved_at is null)
      or not app_private.chem_replacement_has_exact_source_ancestor(p_release_id,new_q.id,old_q.id)
      or not app_private.chem_question_item_delivery_review_ready(new_q.id)))
  then raise exception 'same-original retirement requires unresolved hold, exact ancestor lineage and current item review'; end if;
  perform pg_catalog.set_config('app.chem_held_revision_retirement',p_release_id::text,true);
  update public.chem_questions old_q
    set usable_for_review=false,usable_for_class_quiz=false,usable_for_exam_sprint=false,usable_for_demo=false,updated_at=now()
    from app_private.chem_question_source_release_items oi,app_private.chem_question_source_release_items ni,public.chem_questions new_q
    where oi.release_id=old_q.source_release_id and oi.question_id=old_q.id
      and ni.canonical_source_id=oi.canonical_source_id and ni.release_id=p_release_id
      and new_q.id=ni.question_id and new_q.source_release_id=p_release_id
      and old_q.id<>new_q.id and old_q.grade_band=new_q.grade_band
      and old_q.source_kind='licensed_local' and old_q.usable_for_review
      and old_q.content_fingerprint=new_q.content_fingerprint;
  perform pg_catalog.set_config('app.chem_held_revision_retirement','',true);
end; $function$;
revoke all on function app_private.chem_retire_held_same_original_revisions(uuid) from public,anon,authenticated,service_role;
revoke all on function app_private.chem_guard_source_question_content_mutation() from public,anon,authenticated,service_role;

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
        q.grade_band not in ('初三','高一','高二','高三') or q.source_kind<>'licensed_local' or q.render_mode<>'image_primary'
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

  perform app_private.chem_retire_held_same_original_revisions(p_release_id);

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


create or replace function app_private.chem_guard_held_original_delivery_retirement()
returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  -- Only retire delivery flags of held exact ancestors during verified activation.
  if tg_op='UPDATE' and pg_catalog.current_setting('app.chem_release_activation',true)='on'
    and coalesce(pg_catalog.current_setting('app.chem_held_revision_retirement',true),'') ~ '^[0-9a-f-]{36}$'
    and old.source_kind='licensed_local' and old.usable_for_review
    and not new.usable_for_review and not new.usable_for_class_quiz
    and not new.usable_for_exam_sprint and not new.usable_for_demo
    and (to_jsonb(new)-array['usable_for_review','usable_for_class_quiz','usable_for_exam_sprint','usable_for_demo','updated_at'])
      = (to_jsonb(old)-array['usable_for_review','usable_for_class_quiz','usable_for_exam_sprint','usable_for_demo','updated_at'])
    and exists(select 1 from app_private.chem_question_delivery_holds h where h.anchor_question_id=old.id and h.resolved_at is null)
    and exists(
      select 1 from public.chem_questions n
      join app_private.chem_question_source_releases r on r.id=n.source_release_id
      join app_private.chem_question_source_release_items ni on ni.release_id=r.id and ni.question_id=n.id
      join app_private.chem_question_source_release_items oi on oi.release_id=old.source_release_id and oi.question_id=old.id
      where r.id::text=pg_catalog.current_setting('app.chem_held_revision_retirement',true)
        and r.status='staged' and r.release_kind='teaching_material'
        and r.verification_status='full_visual_verified' and r.verification_manifest_sha256=r.manifest_sha256
        and n.grade_band=old.grade_band and n.content_fingerprint=old.content_fingerprint
        and ni.canonical_source_id=oi.canonical_source_id and not n.usable_for_review
        and app_private.chem_replacement_has_exact_source_ancestor(r.id,n.id,old.id)
        and app_private.chem_question_item_delivery_review_ready(n.id)
    ) then return new; end if;


  if coalesce(pg_catalog.current_setting('app.chem_held_revision_retirement',true),'')<>''
    and old.source_release_id is not null
    and exists(select 1 from app_private.chem_question_source_releases r where r.id=old.source_release_id and r.status in ('active','retired'))
  then raise exception 'an activated or answered source-backed question is immutable; retirement requires exact held source ancestry'; end if;
  return new;
end; $function$;
revoke all on function app_private.chem_guard_held_original_delivery_retirement() from public,anon,authenticated,service_role;
create trigger chem_questions_guard_held_delivery_retirement before update of usable_for_review,usable_for_class_quiz,usable_for_exam_sprint,usable_for_demo
on public.chem_questions for each row execute function app_private.chem_guard_held_original_delivery_retirement();


create or replace function public.chem_question_delivery_holds()
returns table(question_id text,reason text) language sql stable security definer set search_path to '' as $function$
select distinct q.id,h.reason
from app_private.chem_question_delivery_holds h
join public.chem_questions anchor on anchor.id=h.anchor_question_id
join public.chem_questions q on q.id=anchor.id or (
  q.content_fingerprint=anchor.content_fingerprint and not coalesce((
    q.id<>anchor.id and q.grade_band=anchor.grade_band
    and q.source_release_id is distinct from anchor.source_release_id
    and exists(
      select 1 from app_private.chem_question_source_release_items child_item
      join app_private.chem_question_source_release_items parent_item
        on parent_item.canonical_source_id=child_item.canonical_source_id
        and parent_item.question_id=anchor.id and parent_item.release_id=anchor.source_release_id
      join app_private.chem_question_source_releases child_release on child_release.id=q.source_release_id
      where child_item.question_id=q.id and child_item.release_id=q.source_release_id
        and child_release.status='active' and child_release.verification_status='full_visual_verified'
        and child_release.manifest_sha256=child_release.verification_manifest_sha256
        and app_private.chem_replacement_has_exact_source_ancestor(q.source_release_id,q.id,anchor.id)
        and app_private.chem_question_item_visual_reviewed(q.id)
    )
  ),false)
)
where h.resolved_at is null
union
select review.question_id,'逐题原题图像、公式和解析待复核'::text
from app_private.chem_question_item_visual_reviews review
join public.chem_questions reviewed_question on reviewed_question.id=review.question_id
join app_private.chem_question_source_releases reviewed_release on reviewed_release.id=reviewed_question.source_release_id
where reviewed_question.usable_for_review and reviewed_release.status='active'
  and case review.review_state when 'verified' then not app_private.chem_question_item_visual_reviewed(review.question_id)
    when 'legacy_carried' then not app_private.chem_question_item_legacy_carried(review.question_id) else true end;
$function$;
revoke all on function public.chem_question_delivery_holds() from public,anon,authenticated;
grant execute on function public.chem_question_delivery_holds() to service_role;

