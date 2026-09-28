-- The delivery view now intentionally excludes every question without an
-- individual review.  An audit queue must start from the active source bank,
-- otherwise the very questions needing repair disappear from the queue.
begin;

create or replace view app_private.chem_question_quality_audit_queue as
with source_questions as materialized (
  select q.id, q.grade_band, q.source_release_id, q.source_item_key,
         q.stem, q.options, q.explanation
  from public.chem_questions q
  join app_private.chem_question_source_releases release
    on release.id = q.source_release_id
  where release.status = 'active'
    and q.review_status = 'approved'
    and q.scope_status = 'IN'
    and q.usable_for_review
), checked as materialized (
  select q.*,
         app_private.chem_question_item_delivery_review_ready(q.id)
           as item_review_ready,
         array_cat(
           app_private.chem_question_ocr_gap_flags(q.stem, q.options),
           array_remove(array[
             case when position(chr(65533) in
                    (coalesce(q.stem,'') || coalesce(q.options::text,'') ||
                     coalesce(q.explanation,''))) > 0
                  then 'replacement_character_in_question' end,
             case when (coalesce(q.stem,'') || coalesce(q.options::text,'') ||
                        coalesce(q.explanation,'')) ~
                       '(6[.]02|1[.]505)[[:space:]]*[×xX][[:space:]]*10(23|22|24)([^0-9]|$)'
                  then 'flattened_scientific_exponent' end,
             case when (select count(*) from regexp_matches(
                         coalesce(q.stem,''),
                         '反应[ⅠⅡⅢⅣIVX0-9]+[：:]', 'g')) >= 2
                       and coalesce(q.stem,'') !~ '[→⟶⇌⇄↔=＝]'
                  then 'reaction_table_arrows_missing' end
           ]::text[], null::text)
         ) as flags
  from source_questions q
)
select q.id as question_id, q.grade_band, q.source_release_id,
       q.source_item_key,
       not q.item_review_ready as needs_manual_visual_review,
       cardinality(q.flags) > 0 as suspected_formula_gap,
       coalesce(review.review_state, 'no_item_review') as review_state,
       q.flags as suspected_formula_gap_flags
from checked q
left join app_private.chem_question_item_visual_reviews review
  on review.question_id = q.id
where not q.item_review_ready or cardinality(q.flags) > 0;

revoke all on app_private.chem_question_quality_audit_queue
  from public, anon, authenticated, service_role;

do $check$
begin
  if exists (
    with expected as materialized (
      select q.id from public.chem_questions q
      join app_private.chem_question_source_releases release
        on release.id=q.source_release_id
      where release.status='active' and q.review_status='approved'
        and q.scope_status='IN' and q.usable_for_review
        and not app_private.chem_question_item_delivery_review_ready(q.id)
    ), audited as materialized (
      select question_id from app_private.chem_question_quality_audit_queue
    )
    select 1 from expected e
    left join audited a on a.question_id=e.id
    where a.question_id is null
  ) then
    raise exception 'Unreviewed active question is absent from the repair queue';
  end if;
end
$check$;

commit;
