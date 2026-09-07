-- Teacher-curated material assignments must not be silently rewritten by
-- completion jobs or the suffix capacity allocator. Existing grants are kept.
do $migration$
declare
  definition text;
  old_guard text;
  new_guard text;
begin
  select pg_get_functiondef('public.chem_personalize_next_review_plan(uuid,uuid,timestamptz)'::regprocedure) into definition;
  old_guard := 'if not coalesce((v_student_metadata->''reviewProgram''->>''participating'')::boolean, false) then';
  new_guard := 'if not coalesce((v_student_metadata->''reviewProgram''->>''participating'')::boolean, false) or (v_student_metadata->''reviewProgram'' ? ''questionAssignments'') then';
  if strpos(definition, old_guard)=0 then raise exception 'Expected bounded personalizer guard was not found'; end if;
  execute replace(definition, old_guard, new_guard);

  select pg_get_functiondef('app_private.chem_rebudget_unstarted_review_suffix(uuid,uuid,text[])'::regprocedure) into definition;
  old_guard := 'if v_program is not null then';
  new_guard := E'if v_program ? ''questionAssignments'' then\n    return pg_catalog.jsonb_build_object(''ok'', true, ''replannedPlans'', 0, ''reasonCode'', ''teacher_material_assignment_preserved'');\n  end if;\n  if v_program is not null then';
  if strpos(definition, old_guard)=0 then raise exception 'Expected bounded suffix guard was not found'; end if;
  execute replace(definition, old_guard, new_guard);
end;
$migration$;
