begin;

-- A carried legacy acceptance is deliberately different from a visual review.
-- This migration captures no project-specific IDs. The deployment separately
-- registers the existing 43-question active base after checking its manifest.
alter table app_private.chem_question_item_visual_reviews
  drop constraint chem_question_item_visual_reviews_review_state_check;
alter table app_private.chem_question_item_visual_reviews
  add constraint chem_question_item_visual_reviews_review_state_check
    check(review_state in ('pending','verified','rejected','legacy_carried')),
  add constraint chem_question_item_legacy_evidence_truth check (
    review_state<>'legacy_carried' or (
      revision_token is not null and source_item_sha256 is not null
      and length(btrim(coalesce(source_locator,'')))>=3
      and length(btrim(coalesce(review_actor,'')))>=3
      and length(btrim(coalesce(review_note,'')))>=12
      and reviewed_at is null
      and question_image_sha256 is null and analysis_image_sha256 is null
      and source_document_sha256 is null
      and review_checks->'source_image_complete' is not distinct from 'false'::jsonb
      and review_checks->'historical_acceptance_carried' is not distinct from 'true'::jsonb
      and review_checks->'exact_content_and_source_fields' is not distinct from 'true'::jsonb
    )
  );

create table app_private.chem_junior_visual_legacy_base (
  singleton boolean primary key default true check(singleton),
  release_id uuid not null unique references app_private.chem_question_source_releases(id) on delete restrict,
  manifest_sha256 text not null check(manifest_sha256 ~ '^[0-9a-f]{64}$'),
  verification_actor text not null,
  verified_at timestamptz not null,
  captured_by text not null check(length(btrim(captured_by))>=3),
  evidence_note text not null check(length(btrim(evidence_note))>=12),
  captured_at timestamptz not null default now()
);
create table app_private.chem_junior_visual_legacy_origins (
  question_id text primary key references public.chem_questions(id) on delete restrict,
  release_id uuid not null references app_private.chem_junior_visual_legacy_base(release_id) on delete restrict,
  revision_token text not null check(revision_token ~ '^[0-9a-f]{64}$'),
  source_item_sha256 text not null check(source_item_sha256 ~ '^[0-9a-f]{64}$'),
  payload_sha256 text not null check(payload_sha256 ~ '^[0-9a-f]{64}$')
);
create table app_private.chem_question_item_legacy_carries (
  question_id text primary key references public.chem_questions(id) on delete restrict,
  source_question_id text not null references app_private.chem_junior_visual_legacy_origins(question_id) on delete restrict,
  source_revision_token text not null check(source_revision_token ~ '^[0-9a-f]{64}$'),
  source_manifest_sha256 text not null check(source_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  target_revision_token text not null check(target_revision_token ~ '^[0-9a-f]{64}$'),
  target_item_sha256 text not null check(target_item_sha256 ~ '^[0-9a-f]{64}$'),
  payload_sha256 text not null check(payload_sha256 ~ '^[0-9a-f]{64}$'),
  carried_by text not null check(length(btrim(carried_by))>=3),
  evidence_note text not null check(length(btrim(evidence_note))>=12),
  carried_at timestamptz not null default now(),
  check(question_id<>source_question_id)
);
create index chem_question_item_legacy_carries_source_idx
  on app_private.chem_question_item_legacy_carries(source_question_id);
alter table app_private.chem_junior_visual_legacy_base enable row level security;
alter table app_private.chem_junior_visual_legacy_origins enable row level security;
alter table app_private.chem_question_item_legacy_carries enable row level security;
revoke all on table app_private.chem_junior_visual_legacy_base,
  app_private.chem_junior_visual_legacy_origins,
  app_private.chem_question_item_legacy_carries from public,anon,authenticated,service_role;

-- The exact 17 import fields are compared independently of the new question ID
-- and release ID; both IDs legitimately change in a cumulative release.
create function app_private.chem_junior_visual_lineage_payload(p_question_id text)
returns jsonb language sql stable security definer set search_path='' as $fn$
  select jsonb_build_object(
    'mother_id',q.mother_id,'knowledge_id',q.knowledge_id,'concept_key',q.concept_key,
    'level',q.level,'stem',q.stem,'options',q.options,'correct_option',q.correct_option,
    'explanation',q.explanation,'scaffold',q.scaffold,'same_type_key',q.same_type_key,
    'source_item_key',q.source_item_key,'parent_source_item_key',q.parent_source_item_key,
    'canonical_source_id',i.canonical_source_id,'source_title',q.source_info->>'title',
    'source_exam',q.source_info->>'exam','source_question_no',q.source_info->>'questionNo',
    'source_locator_label',q.source_info->>'locator')
  from public.chem_questions q
  join app_private.chem_question_source_release_items i on i.question_id=q.id and i.release_id=q.source_release_id
  where q.id=p_question_id and q.grade_band='初三' and q.textbook_version='科粤版'
    and q.source_kind='user_provided_local' and q.render_mode='native'
    and q.image_url is null and q.asset_refs='[]'::jsonb and q.skill_id=q.knowledge_id;
$fn$;

create function app_private.chem_question_has_explicit_visual_hold(p_question_id text)
returns boolean language sql stable security definer set search_path='' as $fn$
  select exists(select 1 from public.chem_questions q
    join public.chem_questions anchor on anchor.id=q.id or anchor.content_fingerprint=q.content_fingerprint
    join app_private.chem_question_delivery_holds h on h.anchor_question_id=anchor.id
    where q.id=p_question_id and h.resolved_at is null);
$fn$;

create function app_private.chem_guard_immutable_visual_lineage()
returns trigger language plpgsql security definer set search_path='' as $fn$
begin
  if tg_op<>'INSERT'
    or coalesce(current_setting('app.chem_visual_legacy_lineage_write',true),'')<>'on' then
    raise exception 'legacy visual lineage is immutable and requires its dedicated registration RPC';
  end if;
  return new;
end;
$fn$;
create trigger chem_immutable_visual_legacy_base before insert or update or delete
  on app_private.chem_junior_visual_legacy_base for each row execute function app_private.chem_guard_immutable_visual_lineage();
create trigger chem_immutable_visual_legacy_origins before insert or update or delete
  on app_private.chem_junior_visual_legacy_origins for each row execute function app_private.chem_guard_immutable_visual_lineage();
create trigger chem_immutable_visual_legacy_carries before insert or update or delete
  on app_private.chem_question_item_legacy_carries for each row execute function app_private.chem_guard_immutable_visual_lineage();

create function public.chem_capture_junior_visual_legacy_base(
  p_release_id uuid,p_manifest_sha256 text,p_actor text,p_evidence_note text)
returns integer language plpgsql security definer set search_path='' as $fn$
declare rel app_private.chem_question_source_releases%rowtype; total integer;
begin
  if p_release_id is null or coalesce(p_manifest_sha256,'') !~ '^[0-9a-f]{64}$'
    or length(btrim(coalesce(p_actor,'')))<3 or length(btrim(coalesce(p_evidence_note,'')))<12 then
    raise exception 'invalid legacy visual base registration';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('chem-source-original-release',0));
  perform pg_advisory_xact_lock(hashtextextended('chem-h3-original-release',0));
  if exists(select 1 from app_private.chem_junior_visual_legacy_base) then
    raise exception 'the legacy visual base was already captured';
  end if;
  select * into rel from app_private.chem_question_source_releases where id=p_release_id for update;
  if not found or rel.grade_band<>'初三' or rel.textbook_version<>'科粤版'
    or rel.status<>'active' or rel.expected_question_count<>43
    or rel.revision_contract<>'v3_junior_native_text'
    or rel.verification_status<>'full_visual_verified' or rel.manifest_sha256<>p_manifest_sha256
    or rel.verification_manifest_sha256<>p_manifest_sha256
    or rel.verified_at is null or rel.activated_at is null or length(btrim(rel.verification_actor))<3 then
    raise exception 'legacy capture requires the existing fully accepted 43-question active base';
  end if;
  perform q.id from public.chem_questions q where q.source_release_id=p_release_id order by q.id for share;
  select count(*) into total from public.chem_questions q where q.source_release_id=p_release_id;
  if total<>43 or exists(select 1 from public.chem_questions q where q.source_release_id=p_release_id and (
    q.review_status<>'approved' or q.scope_status<>'IN' or not q.usable_for_review
    or app_private.chem_junior_visual_lineage_payload(q.id) is null
    or q.question_revision_token is distinct from app_private.chem_junior_native_revision_sha256(q)
    or exists(select 1 from app_private.chem_question_item_visual_reviews v where v.question_id=q.id)
    or app_private.chem_question_has_explicit_visual_hold(q.id))) then
    raise exception 'legacy base must contain exactly 43 unchanged accepted items without any item review or hold';
  end if;
  perform set_config('app.chem_visual_legacy_lineage_write','on',true);
  insert into app_private.chem_junior_visual_legacy_base(release_id,manifest_sha256,verification_actor,verified_at,captured_by,evidence_note)
    values(rel.id,rel.manifest_sha256,rel.verification_actor,rel.verified_at,btrim(p_actor),btrim(p_evidence_note));
  insert into app_private.chem_junior_visual_legacy_origins(question_id,release_id,revision_token,source_item_sha256,payload_sha256)
    select q.id,q.source_release_id,q.question_revision_token,i.item_sha256,
      encode(sha256(convert_to(app_private.chem_junior_visual_lineage_payload(q.id)::text,'UTF8')),'hex')
    from public.chem_questions q join app_private.chem_question_source_release_items i
      on i.question_id=q.id and i.release_id=q.source_release_id where q.source_release_id=p_release_id;
  get diagnostics total=row_count;
  if total<>43 then raise exception 'legacy origin capture count mismatch'; end if;
  perform set_config('app.chem_visual_legacy_lineage_write','off',true);
  return total;
end;
$fn$;

create function app_private.chem_junior_visual_legacy_origin_valid(p_question_id text)
returns boolean language sql stable security definer set search_path='' as $fn$
  select exists(select 1 from app_private.chem_junior_visual_legacy_origins origin
    join app_private.chem_junior_visual_legacy_base base on base.release_id=origin.release_id
    join public.chem_questions q on q.id=origin.question_id and q.source_release_id=origin.release_id
    join app_private.chem_question_source_releases r on r.id=origin.release_id
    join app_private.chem_question_source_release_items i on i.question_id=q.id and i.release_id=r.id
    left join app_private.chem_question_item_visual_reviews review on review.question_id=q.id
    where origin.question_id=p_question_id and r.status in ('active','retired')
      and r.verification_status='full_visual_verified'
      and r.manifest_sha256=base.manifest_sha256 and r.verification_manifest_sha256=base.manifest_sha256
      and r.verification_actor=base.verification_actor and r.verified_at=base.verified_at
      and q.review_status='approved' and q.scope_status='IN'
      and q.question_revision_token=origin.revision_token
      and q.question_revision_token=app_private.chem_junior_native_revision_sha256(q)
      and i.item_sha256=origin.source_item_sha256
      and encode(sha256(convert_to(app_private.chem_junior_visual_lineage_payload(q.id)::text,'UTF8')),'hex')=origin.payload_sha256
      and (review.question_id is null or
        (review.review_state='verified' and app_private.chem_question_item_visual_reviewed(q.id)))
      and not app_private.chem_question_has_explicit_visual_hold(q.id));
$fn$;

create function app_private.chem_question_item_legacy_carried(p_question_id text)
returns boolean language sql stable security definer set search_path='' as $fn$
  select exists(select 1 from app_private.chem_question_item_legacy_carries carry
    join app_private.chem_junior_visual_legacy_origins origin on origin.question_id=carry.source_question_id
    join app_private.chem_junior_visual_legacy_base base on base.release_id=origin.release_id
    join public.chem_questions q on q.id=carry.question_id
    join app_private.chem_question_item_visual_reviews review on review.question_id=q.id and review.source_release_id=q.source_release_id
    join app_private.chem_question_source_release_items item on item.question_id=q.id and item.release_id=q.source_release_id
    where q.id=p_question_id and review.review_state='legacy_carried'
      and review.revision_token=q.question_revision_token and carry.target_revision_token=q.question_revision_token
      and q.question_revision_token=app_private.chem_junior_native_revision_sha256(q)
      and review.source_locator=q.source_info->>'locator'
      and review.source_item_sha256=item.item_sha256 and carry.target_item_sha256=item.item_sha256
      and carry.source_revision_token=origin.revision_token and carry.source_manifest_sha256=base.manifest_sha256
      and carry.payload_sha256=origin.payload_sha256
      and encode(sha256(convert_to(app_private.chem_junior_visual_lineage_payload(q.id)::text,'UTF8')),'hex')=origin.payload_sha256
      and app_private.chem_junior_visual_legacy_origin_valid(origin.question_id)
      and not app_private.chem_question_has_explicit_visual_hold(q.id));
$fn$;

create function app_private.chem_question_item_delivery_review_ready(p_question_id text)
returns boolean language sql stable security definer set search_path='' as $fn$
  select app_private.chem_question_item_visual_reviewed(p_question_id)
    or app_private.chem_question_item_legacy_carried(p_question_id);
$fn$;

create function public.chem_carry_question_item_legacy_review(
  p_question_id text,p_source_question_id text,p_actor text,p_evidence_note text)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare target public.chem_questions%rowtype; origin app_private.chem_junior_visual_legacy_origins%rowtype;
  base app_private.chem_junior_visual_legacy_base%rowtype; item app_private.chem_question_source_release_items%rowtype;
begin
  if p_question_id is null or p_source_question_id is null or p_question_id=p_source_question_id
    or length(btrim(coalesce(p_actor,'')))<3 or length(btrim(coalesce(p_evidence_note,'')))<12 then
    raise exception 'invalid legacy visual carry request';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('chem-source-original-release',0));
  perform pg_advisory_xact_lock(hashtextextended('chem-h3-original-release',0));
  select * into origin from app_private.chem_junior_visual_legacy_origins where question_id=p_source_question_id;
  if not found or not app_private.chem_junior_visual_legacy_origin_valid(p_source_question_id) then
    raise exception 'legacy carry source is not one of the unchanged eligible captured originals';
  end if;
  select * into base from app_private.chem_junior_visual_legacy_base where release_id=origin.release_id;
  perform q.id from public.chem_questions q where q.id=p_source_question_id for share;
  select * into target from public.chem_questions where id=p_question_id for update;
  if not found or target.source_release_id=origin.release_id
    or target.question_revision_token is distinct from app_private.chem_junior_native_revision_sha256(target)
    or not exists(select 1 from app_private.chem_question_source_releases r where r.id=target.source_release_id
      and r.grade_band='初三' and r.textbook_version='科粤版' and r.status='staged' and r.revision_contract='v3_junior_native_text')
    or encode(sha256(convert_to(app_private.chem_junior_visual_lineage_payload(target.id)::text,'UTF8')),'hex')
      is distinct from origin.payload_sha256
    or app_private.chem_question_has_explicit_visual_hold(target.id) then
    raise exception 'legacy carry requires a staged byte-identical content and source payload';
  end if;
  if exists(select 1 from app_private.chem_question_item_legacy_carries c where c.question_id=target.id) then
    if app_private.chem_question_item_legacy_carried(target.id)
      and exists(select 1 from app_private.chem_question_item_legacy_carries c where c.question_id=target.id and c.source_question_id=origin.question_id)
    then return jsonb_build_object('questionId',target.id,'reviewState','legacy_carried','sourceQuestionId',origin.question_id,'idempotent',true);
    end if;
    raise exception 'a queued or changed legacy carry requires a real source review';
  end if;
  -- Initial import-generated pending rows are not an adverse review. Any
  -- human/agent recheck, rejection or earlier real review must not be erased.
  if not exists(select 1 from app_private.chem_question_item_visual_reviews review where review.question_id=target.id
      and review.review_state='pending' and review.review_actor is null and review.review_note is null
      and review.review_checks='{}'::jsonb and review.reviewed_at is null)
    or exists(select 1 from app_private.chem_question_item_visual_review_events e where e.question_id=target.id
      and (e.review_state<>'pending' or e.review_actor is not null or e.review_note is not null)) then
    raise exception 'legacy carry cannot override an item review or explicit recheck';
  end if;
  select * into item from app_private.chem_question_source_release_items
    where question_id=target.id and release_id=target.source_release_id for share;
  if not found then raise exception 'legacy target lacks its source ledger'; end if;
  perform set_config('app.chem_visual_legacy_lineage_write','on',true);
  insert into app_private.chem_question_item_legacy_carries(question_id,source_question_id,source_revision_token,
    source_manifest_sha256,target_revision_token,target_item_sha256,payload_sha256,carried_by,evidence_note)
    values(target.id,origin.question_id,origin.revision_token,base.manifest_sha256,target.question_revision_token,
      item.item_sha256,origin.payload_sha256,btrim(p_actor),btrim(p_evidence_note));
  perform set_config('app.chem_visual_legacy_lineage_write','off',true);
  update app_private.chem_question_item_visual_reviews set
    source_release_id=target.source_release_id,review_state='legacy_carried',revision_token=target.question_revision_token,
    source_item_sha256=item.item_sha256,question_image_sha256=null,analysis_image_sha256=null,source_document_sha256=null,
    source_locator=target.source_info->>'locator',review_checks=jsonb_build_object(
      'source_image_complete',false,'historical_acceptance_carried',true,'exact_content_and_source_fields',true),
    review_note='既有验收原样继承；本次未宣称重新核验原件。'||btrim(p_evidence_note),
    review_actor=btrim(p_actor),reviewed_at=null,updated_at=now() where question_id=target.id;
  if not app_private.chem_question_item_legacy_carried(target.id) then raise exception 'legacy carry postcondition failed'; end if;
  return jsonb_build_object('questionId',target.id,'reviewState','legacy_carried','sourceQuestionId',origin.question_id,'sourceImageComplete',false);
end;
$fn$;

revoke all on function app_private.chem_junior_visual_lineage_payload(text),
  app_private.chem_question_has_explicit_visual_hold(text),
  app_private.chem_guard_immutable_visual_lineage(),
  app_private.chem_junior_visual_legacy_origin_valid(text),
  app_private.chem_question_item_legacy_carried(text),
  app_private.chem_question_item_delivery_review_ready(text),
  public.chem_capture_junior_visual_legacy_base(uuid,text,text,text),
  public.chem_carry_question_item_legacy_review(text,text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.chem_capture_junior_visual_legacy_base(uuid,text,text,text),
  public.chem_carry_question_item_legacy_review(text,text,text,text) to service_role;

-- Delivery distinguishes true verification from explicitly retained legacy acceptance.
CREATE OR REPLACE FUNCTION public.chem_question_delivery_holds()
 RETURNS TABLE(question_id text, reason text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select distinct q.id,h.reason
  from app_private.chem_question_delivery_holds h
  join public.chem_questions anchor on anchor.id=h.anchor_question_id
  join public.chem_questions q on q.id=anchor.id
    or q.content_fingerprint=anchor.content_fingerprint
  where h.resolved_at is null
  union
  select review.question_id,'逐题原题图像、公式和解析待复核'::text
  from app_private.chem_question_item_visual_reviews review
  join public.chem_questions reviewed_question on reviewed_question.id=review.question_id
  join app_private.chem_question_source_releases reviewed_release
    on reviewed_release.id=reviewed_question.source_release_id
  where reviewed_question.usable_for_review and reviewed_release.status='active'
    and (review.review_state in ('pending','rejected')
      or not app_private.chem_question_item_delivery_review_ready(review.question_id));
$function$;

create or replace view app_private.chem_teaching_ready_questions as
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
  WHERE q.review_status = 'approved'::text AND q.scope_status = 'IN'::text AND q.usable_for_review AND r.status = 'active'::text AND r.verification_status = 'full_visual_verified'::text AND r.manifest_sha256 = r.verification_manifest_sha256 AND jsonb_typeof(q.options) = 'array'::text AND jsonb_array_length(q.options) = 4 AND q.correct_option >= 0 AND q.correct_option <= 3 AND length(btrim(q.stem)) > 0 AND length(btrim(q.explanation)) > 0 AND q.content_fingerprint IS NOT NULL AND q.source_item_key IS NOT NULL AND NOT (EXISTS ( SELECT 1
           FROM chem_question_delivery_holds() h(question_id, reason)
          WHERE h.question_id = q.id)) AND (NOT (EXISTS ( SELECT 1
           FROM app_private.chem_question_item_visual_reviews review
          WHERE review.question_id = q.id)) OR app_private.chem_question_item_delivery_review_ready(q.id)) AND ((q.grade_band = ANY (ARRAY['高一'::text, '高二'::text, '高三'::text])) AND q.source_kind = 'licensed_local'::text AND q.render_mode = 'image_primary'::text AND (r.release_kind = 'teaching_material'::text OR (EXISTS ( SELECT 1
           FROM chem_active_verified_source_releases() a(grade_band, source_release_id)
          WHERE a.source_release_id = q.source_release_id AND a.grade_band = q.grade_band))) OR q.grade_band = '初三'::text AND q.source_kind = 'user_provided_local'::text AND q.render_mode = 'native'::text AND q.textbook_version = '科粤版'::text AND (EXISTS ( SELECT 1
           FROM chem_junior_verified_provenance_rows('科粤版'::text, ARRAY[q.knowledge_id]) a(knowledge_id, textbook_version, source_release_id, verification_status, source_release_ready)
          WHERE a.source_release_id = q.source_release_id AND a.source_release_ready AND a.verification_status = 'verified'::text)));
CREATE OR REPLACE FUNCTION app_private.chem_require_item_visual_reviews_before_activation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_count integer; v_verified integer;
begin
  if new.status <> 'active' then return new; end if;
  if tg_op='UPDATE' then
    if old.status='active' then return new; end if;
  end if;
  select count(*) into v_count from public.chem_questions q where q.source_release_id=new.id;
  select count(*) into v_verified from public.chem_questions q
  where q.source_release_id=new.id
    and app_private.chem_question_item_delivery_review_ready(q.id);
  if v_count <> new.expected_question_count or v_verified <> v_count then
    raise exception '逐题原图核验或严格历史继承未满足：发布版 % 已通过 % / %',new.id,v_verified,v_count;
  end if;
  return new;
end;
$function$;

commit;
