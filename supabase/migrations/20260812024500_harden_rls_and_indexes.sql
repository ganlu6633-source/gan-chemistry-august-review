do $$
declare t text;
begin
  foreach t in array array[
    'chem_students_v2','chem_student_aliases','chem_student_sources','chem_student_conflicts',
    'chem_skills','chem_student_skill_state','chem_knowledge_cards','chem_course_nodes','chem_questions',
    'chem_learning_plans','chem_learning_attempts','chem_attempt_answers','chem_teacher_observations',
    'chem_behavior_signals','chem_teacher_alerts','chem_daily_reports','chem_import_audit'
  ] loop
    if not exists (
      select 1 from pg_policies where schemaname='public' and tablename=t and policyname='edge_functions_only'
    ) then
      execute format('create policy edge_functions_only on public.%I as restrictive for all to public using (false) with check (false)', t);
    end if;
  end loop;
end $$;

create index if not exists chem_sessions_access_code_idx on app_private.chem_app_sessions(access_code_id);
create index if not exists chem_sessions_student_idx on app_private.chem_app_sessions(student_id);
create index if not exists chem_answers_question_idx on public.chem_attempt_answers(question_id);
create index if not exists chem_cards_skill_idx on public.chem_knowledge_cards(skill_id);
create index if not exists chem_questions_skill_idx on public.chem_questions(skill_id);
create index if not exists chem_conflicts_student_idx on public.chem_student_conflicts(student_id);
create index if not exists chem_skill_state_skill_idx on public.chem_student_skill_state(skill_id);
create index if not exists chem_sources_student_idx on public.chem_student_sources(student_id);
create index if not exists chem_observations_creator_idx on public.chem_teacher_observations(created_by);
