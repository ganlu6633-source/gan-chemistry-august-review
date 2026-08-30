begin;

-- Cover the foreign-key lookup paths used by the junior release, curriculum,
-- session and evidence flows.  These indexes also keep parent-row checks and
-- controlled cleanup from scanning the full child tables.

create index if not exists chem_junior_card_bindings_card_idx
  on app_private.chem_junior_knowledge_card_bindings (card_id);

create index if not exists chem_junior_card_bindings_knowledge_idx
  on app_private.chem_junior_knowledge_card_bindings (knowledge_id);

create index if not exists chem_junior_knowledge_provenance_knowledge_idx
  on app_private.chem_junior_knowledge_provenance (knowledge_id);

create index if not exists chem_junior_knowledge_provenance_release_idx
  on app_private.chem_junior_knowledge_provenance (source_release_id);

create index if not exists chem_junior_release_provenance_knowledge_idx
  on app_private.chem_junior_source_release_provenance (knowledge_id);

create index if not exists chem_junior_sessions_curriculum_idx
  on public.chem_junior_daily_sessions (curriculum_day_id);

create index if not exists chem_junior_steps_knowledge_idx
  on public.chem_junior_session_steps (knowledge_id);

create index if not exists chem_junior_steps_question_idx
  on public.chem_junior_session_steps (question_id);

create index if not exists chem_learning_plans_junior_curriculum_idx
  on public.chem_learning_plans (junior_curriculum_day_id);

commit;
