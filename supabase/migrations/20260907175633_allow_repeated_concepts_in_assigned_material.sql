begin;
-- A teacher-assigned material can contain several original subquestions on
-- one concept. The concept array is a unique set, not a list of question slots.
-- The edge runtime still requires one concept per question for dynamic plans,
-- and validates the complete explicit question-id assignment for fixed plans.
alter table public.chem_learning_plans drop constraint chem_learning_plans_review_target_count_check;
alter table public.chem_learning_plans add constraint chem_learning_plans_review_target_count_check check (
  mode <> 'REVIEW'
  or cardinality(target_concept_keys) = 0
  or (cardinality(target_concept_keys) between 1 and question_count
      and app_private.chem_text_array_is_unique_nonblank(target_concept_keys))
);
commit;
