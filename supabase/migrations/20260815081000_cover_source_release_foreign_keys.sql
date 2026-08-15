-- Cover the foreign-key sides used by source-release joins and answer-lock cleanup.
-- These indexes are intentionally narrow: they add no public access and do not
-- touch the independent class-quiz schema or data.

create index if not exists chem_question_answer_locks_plan_day_idx
  on app_private.chem_question_answer_locks (plan_day_id);

create index if not exists chem_question_answer_locks_question_idx
  on app_private.chem_question_answer_locks (question_id);

create index if not exists chem_question_source_release_items_question_idx
  on app_private.chem_question_source_release_items (question_id);

create index if not exists chem_questions_source_release_idx
  on public.chem_questions (source_release_id);
