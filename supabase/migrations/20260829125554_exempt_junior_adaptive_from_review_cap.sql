-- Formal high-school REVIEW plans remain capped at eight questions.  The
-- junior adaptive delivery mode is a separate 12--15 original-question
-- contract and must not be blocked by that legacy review cap.
alter table public.chem_learning_plans
  drop constraint if exists chem_learning_plans_review_daily_question_cap_check;

alter table public.chem_learning_plans
  add constraint chem_learning_plans_review_daily_question_cap_check
  check (
    delivery_mode = 'junior_adaptive'
    or mode <> 'REVIEW'
    or question_count between 1 and 8
  );
