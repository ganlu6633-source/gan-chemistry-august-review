-- Allow the same student account to be found by the preferred name “敏盛”
-- or the teacher-confirmed full name “温敏盛”. This does not rotate codes.
do $$
declare
  v_student_id uuid;
begin
  select id into strict v_student_id
  from public.chem_students_v2
  where display_name = '敏盛'
    and record_status = 'active'
    and coalesce((metadata->>'demo')::boolean, false) = false;

  insert into public.chem_student_aliases(student_id, alias)
  values (v_student_id, '温敏盛')
  on conflict (student_id, alias) do nothing;

  if not exists (
    select 1
    from public.chem_student_aliases
    where student_id = v_student_id and alias = '温敏盛'
  ) then
    raise exception '温敏盛 alias was not persisted';
  end if;
end;
$$;
