-- The old compatibility branch admitted active-release questions that had no
-- item-level review row at all. A release manifest is insufficient evidence
-- that every formula, choice, answer and explanation survived conversion.
-- All student delivery paths read this view, so fail closed until the current
-- question revision has an individual verified (or valid lineage) review.
begin;

create or replace view app_private.chem_teaching_ready_questions as
with held as materialized (
  -- A correlated set-returning function call recalculated all holds once per
  -- candidate question; calculate the hold set once for a catalog request.
  select distinct question_id from public.chem_question_delivery_holds()
), junior_knowledge as materialized (
  select distinct knowledge_id
  from public.chem_questions
  where grade_band = '初三' and knowledge_id is not null
), junior_ready as materialized (
  -- A provenance check hashes source/card manifests. Resolve each knowledge
  -- point once, instead of repeating the same work for every question.
  select p.knowledge_id, p.source_release_id
  from junior_knowledge k
  cross join lateral public.chem_junior_verified_provenance_rows(
    '科粤版', array[k.knowledge_id]) p
  where p.source_release_ready and p.verification_status = 'verified'
)
select q.id, q.mother_id, q.skill_id, q.level, q.grade_band,
       q.stem, q.options, q.correct_option, q.explanation, q.scaffold,
       q.review_status, q.scope_status, q.source_kind, q.image_url,
       q.created_at, q.updated_at, q.usable_for_class_quiz,
       q.usable_for_review, q.usable_for_exam_sprint, q.concept_key,
       q.source_info, q.asset_refs, q.render_mode, q.source_item_key,
       q.content_fingerprint, q.question_revision_token,
       q.source_release_id, q.usable_for_demo, q.textbook_version,
       q.knowledge_id, q.same_type_key, q.parent_source_item_key
from public.chem_questions q
join app_private.chem_question_source_releases r
  on r.id = q.source_release_id
left join held on held.question_id = q.id
where q.review_status = 'approved'
  and q.scope_status = 'IN'
  and q.usable_for_review
  and r.status = 'active'
  and r.verification_status = 'full_visual_verified'
  and r.manifest_sha256 = r.verification_manifest_sha256
  and jsonb_typeof(q.options) = 'array'
  and jsonb_array_length(q.options) = 4
  and q.correct_option between 0 and 3
  and length(btrim(q.stem)) > 0
  and length(btrim(q.explanation)) > 0
  and q.content_fingerprint is not null
  and q.source_item_key is not null
  and held.question_id is null
  and app_private.chem_question_item_delivery_review_ready(q.id)
  and (
    (q.grade_band in ('高一', '高二', '高三')
      and q.source_kind = 'licensed_local'
      and q.render_mode = 'image_primary'
      and (r.release_kind = 'teaching_material' or exists (
        select 1 from public.chem_active_verified_source_releases() a
        where a.source_release_id = q.source_release_id
          and a.grade_band = q.grade_band
      )))
    or
    (q.grade_band = '初三'
      and q.source_kind = 'user_provided_local'
      and q.render_mode = 'native'
      and q.textbook_version = '科粤版'
      and exists (
        select 1 from junior_ready a
        where a.knowledge_id = q.knowledge_id
          and a.source_release_id = q.source_release_id
      ))
  );

do $check$
begin
  if exists (
    select 1 from app_private.chem_teaching_ready_questions q
    where not app_private.chem_question_item_delivery_review_ready(q.id)
  ) then
    raise exception 'Student-ready question lacks a valid current item review';
  end if;
end
$check$;

commit;
