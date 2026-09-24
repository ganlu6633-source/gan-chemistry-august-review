drop index if exists public.chem_learning_plans_one_review_per_student_day_uidx;
create unique index chem_learning_plans_one_review_per_student_day_uidx
  on public.chem_learning_plans (student_id, plan_date)
  where mode = 'REVIEW' and delivery_mode <> 'self_study';
