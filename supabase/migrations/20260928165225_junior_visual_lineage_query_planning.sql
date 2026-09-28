begin;

-- Keep every digest, source identity, review, and hold assertion. PL/pgSQL
-- caches these parameterized queries across row calls; the nested SQL-language
-- security-definer bodies were being planned repeatedly by the delivery scan.
CREATE OR REPLACE FUNCTION app_private.chem_junior_visual_lineage_payload(p_question_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return (
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
    and q.image_url is null and q.asset_refs='[]'::jsonb and q.skill_id=q.knowledge_id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.chem_junior_visual_legacy_origin_valid(p_question_id text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return (
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
      and not app_private.chem_question_has_explicit_visual_hold(q.id))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.chem_question_item_legacy_carried(p_question_id text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return (
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
      and not app_private.chem_question_has_explicit_visual_hold(q.id))
  );
end;
$function$;

create or replace function app_private.chem_question_has_explicit_visual_hold(p_question_id text)
returns boolean language plpgsql stable security definer set search_path='' as $fn$
begin
  return exists(
    select 1 from app_private.chem_question_delivery_holds hold
    join public.chem_questions anchor on anchor.id=hold.anchor_question_id
    where hold.resolved_at is null and
      (hold.anchor_question_id=p_question_id
        or anchor.content_fingerprint=(select target.content_fingerprint from public.chem_questions target where target.id=p_question_id))
  );
end;
$fn$;

-- Dispatch from the stored review state. Do not execute the entire visual
-- source-image join first for a known legacy row or a known pending row.
create or replace function app_private.chem_question_item_delivery_review_ready(p_question_id text)
returns boolean language plpgsql stable security definer set search_path='' as $fn$
declare state text;
begin
  select review_state into state from app_private.chem_question_item_visual_reviews where question_id=p_question_id;
  if state='verified' then return app_private.chem_question_item_visual_reviewed(p_question_id); end if;
  if state='legacy_carried' then return app_private.chem_question_item_legacy_carried(p_question_id); end if;
  return false;
end;
$fn$;

create or replace function public.chem_question_delivery_holds()
returns table(question_id text,reason text)
language sql stable security definer set search_path='' as $fn$
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
    and case review.review_state when 'verified' then not app_private.chem_question_item_visual_reviewed(review.question_id) when 'legacy_carried' then not app_private.chem_question_item_legacy_carried(review.question_id) else true end;
$fn$;

commit;
