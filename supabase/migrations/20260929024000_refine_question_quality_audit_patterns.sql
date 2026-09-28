-- The first audit pass used broad Chinese bigrams that matched ordinary
-- prose (“浓度之和的分数”, “电子数与通过截面…”).  Keep only clear
-- formula-placeholder shapes; this remains a candidate list, never a review.
begin;

create or replace view app_private.chem_question_quality_audit_queue as
select
  question.id as question_id,
  question.grade_band,
  question.source_release_id,
  question.source_item_key,
  (not app_private.chem_question_item_delivery_review_ready(question.id)) as needs_manual_visual_review,
  (question.stem ~ '(为[，。；]|[=＝][[:space:]]*[，。；]|[△Δ]H[[:space:]]*=[[:space:]]*[，。；]|(化学方程式|离子方程式|电极反应式)[[:space:]]*是[[:space:]]*[，。；])'
    or question.options::text ~ '(为[，。；]|[=＝][[:space:]]*[，。；])') as suspected_formula_gap,
  case when review.question_id is null then 'no_item_review'
       else review.review_state end as review_state
from app_private.chem_teaching_ready_questions question
left join app_private.chem_question_item_visual_reviews review
  on review.question_id = question.id
where not app_private.chem_question_item_delivery_review_ready(question.id)
   or question.stem ~ '(为[，。；]|[=＝][[:space:]]*[，。；]|[△Δ]H[[:space:]]*=[[:space:]]*[，。；]|(化学方程式|离子方程式|电极反应式)[[:space:]]*是[[:space:]]*[，。；])'
   or question.options::text ~ '(为[，。；]|[=＝][[:space:]]*[，。；])';

commit;
