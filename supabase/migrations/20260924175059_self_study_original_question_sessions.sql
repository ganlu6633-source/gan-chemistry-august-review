alter table public.chem_learning_plans
  drop constraint chem_learning_plans_delivery_mode_check,
  add constraint chem_learning_plans_delivery_mode_check
    check (delivery_mode = any (array['legacy_round', 'junior_adaptive', 'self_study']));

alter table public.chem_learning_plans
  drop constraint chem_learning_plans_question_count_check,
  add constraint chem_learning_plans_question_count_check
    check (
      (delivery_mode in ('legacy_round', 'self_study') and question_count between 1 and 10)
      or (delivery_mode = 'junior_adaptive' and question_count = 12)
    );
