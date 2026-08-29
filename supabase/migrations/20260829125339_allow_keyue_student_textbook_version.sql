-- Junior-high 科粤版 now has a verified first-day release.  Accept it as a
-- first-class student curriculum choice without altering existing versions.
alter table public.chem_students_v2
  drop constraint if exists chem_students_v2_textbook_version_check;

alter table public.chem_students_v2
  add constraint chem_students_v2_textbook_version_check
  check (textbook_version in ('苏教版', '人教版', '科粤版', '通用', '待确认'));
