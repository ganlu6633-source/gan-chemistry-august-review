-- Surface a few OCR formula gaps already observed in locally verified source
-- comparisons.  This is a candidate audit, not an automatic visual review or
-- delivery hold.  Ready rows with no per-item review remain queued as before.
begin;

create or replace function app_private.chem_question_ocr_gap_flags(
  p_stem text,
  p_options jsonb
) returns text[] language sql immutable parallel safe set search_path = '' as $$
  select array_remove(array[
    case when coalesce(p_stem,'') ~
        '(为[，。；]|[=＝][[:space:]]*[，。；]|[△Δ]H[[:space:]]*=[[:space:]]*[，。；]|(化学方程式|离子方程式|电极反应式)[[:space:]]*是[[:space:]]*[，。；])'
      or coalesce(p_options::text,'') ~ '(为[，。；]|[=＝][[:space:]]*[，。；])'
    then 'bare_formula_punctuation' end,
    case when coalesce(p_stem,'') ~ '已知[[:space:]]*[：:][[:space:]]*为[[:space:]]*(浅黄|黄|红)'
    then 'missing_subject_after_known' end,
    case when coalesce(p_stem,'') ~ '可利用反应[[:space:]]*制备'
    then 'missing_reaction_expression' end,
    case when coalesce(p_stem,'') ~ '脱去[[:space:]]*步骤'
    then 'missing_step_name' end,
    case when coalesce(p_stem,'') ~ '生成[[:space:]]*并[[:space:]]*消耗'
    then 'generated_and_consumed_without_object' end,
    case when coalesce(p_stem,'') ~ '反应[ⅠⅡⅢ①②③1-9][：:][[:space:]]*反应[ⅠⅡⅢ①②③1-9][：:]'
    then 'empty_labeled_reactions' end
  ], null::text);
$$;

revoke all on function app_private.chem_question_ocr_gap_flags(text,jsonb)
  from public, anon, authenticated, service_role;

create or replace view app_private.chem_question_quality_audit_queue as
select
  question.id as question_id,
  question.grade_band,
  question.source_release_id,
  question.source_item_key,
  (not app_private.chem_question_item_delivery_review_ready(question.id)) as needs_manual_visual_review,
  cardinality(gaps.flags) > 0 as suspected_formula_gap,
  case when review.question_id is null then 'no_item_review'
       else review.review_state end as review_state,
  gaps.flags as suspected_formula_gap_flags
from app_private.chem_teaching_ready_questions question
cross join lateral (
  select app_private.chem_question_ocr_gap_flags(question.stem, question.options) as flags
) gaps
left join app_private.chem_question_item_visual_reviews review
  on review.question_id = question.id
where not app_private.chem_question_item_delivery_review_ready(question.id)
   or cardinality(gaps.flags) > 0;

revoke all on app_private.chem_question_quality_audit_queue
  from public, anon, authenticated, service_role;

commit;
