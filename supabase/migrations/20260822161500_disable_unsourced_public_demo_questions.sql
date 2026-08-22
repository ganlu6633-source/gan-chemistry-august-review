-- Public demos must not present synthetic questions as if they were exact
-- originals from the teacher-provided source material. Licensed originals stay
-- server-only and remain available to real students and authenticated teacher
-- previews; the independent quiz system is intentionally untouched.
begin;

update public.chem_questions
set
  usable_for_demo = false,
  updated_at = now()
where grade_band in ('高一', '高二', '高三')
  and usable_for_demo = true
  and source_release_id is null;

do $$
begin
  if exists (
    select 1
    from public.chem_questions q
    where q.grade_band in ('高一', '高二', '高三')
      and q.usable_for_demo = true
      and (
        q.source_release_id is null
        or q.source_info is null
        or nullif(btrim(q.source_item_key), '') is null
      )
  ) then
    raise exception 'an unsourced high-school public demo question is still enabled';
  end if;
end;
$$;

commit;
