-- Complete unambiguous full-name / given-name login pairs confirmed by the
-- canonical three-character student names. No access code is changed.
do $$
declare
  v_pair text[];
  v_student_id uuid;
begin
  foreach v_pair slice 1 in array array[
    array['吴皓轩','皓轩'],
    array['张龙凯','龙凯'],
    array['连世晟','世晟']
  ] loop
    select id into strict v_student_id
    from public.chem_students_v2
    where display_name = v_pair[1]
      and record_status = 'active'
      and coalesce((metadata->>'demo')::boolean, false) = false;

    insert into public.chem_student_aliases(student_id, alias)
    values (v_student_id, v_pair[2])
    on conflict (student_id, alias) do nothing;
  end loop;
end;
$$;
