-- Preserve the pre-existing exact-parent exemption and additionally permit proved ancestors.
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
        and (q.parent_source_item_key=anchor.source_item_key
          or app_private.chem_replacement_has_exact_source_ancestor(q.source_release_id,q.id,anchor.id))
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

