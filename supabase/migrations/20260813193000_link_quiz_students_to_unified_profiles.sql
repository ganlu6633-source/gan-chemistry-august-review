begin;

create table if not exists public.chem_quiz_student_links (
  quiz_student_id uuid primary key references public.students(id) on delete cascade,
  chem_student_id uuid not null unique references public.chem_students_v2(id) on delete cascade,
  source text not null default 'explicit-name-pair',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.chem_quiz_student_links is
  'Explicit identity bridge from the live quiz roster to unified chemistry student profiles.';

alter table public.chem_quiz_student_links enable row level security;
revoke all on table public.chem_quiz_student_links from anon, authenticated;
grant select, insert, update, delete on table public.chem_quiz_student_links to service_role;

do $$
declare
  matched_pair_count integer;
begin
  with expected_pairs(quiz_name, chem_name) as (
    values
      ('林天佑'::text, '天佑'::text),
      ('肖欣慧'::text, '肖欣慧'::text),
      ('胡浩霖'::text, '浩霖'::text),
      ('郑洪杰'::text, '洪杰'::text),
      ('陈浩洋'::text, '浩洋'::text)
  )
  select count(*)
    into matched_pair_count
  from expected_pairs p
  join public.students quiz_student
    on quiz_student.display_name = p.quiz_name
   and quiz_student.active = true
  join public.chem_students_v2 chem_student
    on chem_student.display_name = p.chem_name
   and chem_student.record_status = 'active';

  if matched_pair_count <> 5 then
    raise exception
      'Expected exactly 5 active quiz-to-unified student matches, found %',
      matched_pair_count;
  end if;
end
$$;

with expected_pairs(quiz_name, chem_name) as (
  values
    ('林天佑'::text, '天佑'::text),
    ('肖欣慧'::text, '肖欣慧'::text),
    ('胡浩霖'::text, '浩霖'::text),
    ('郑洪杰'::text, '洪杰'::text),
    ('陈浩洋'::text, '浩洋'::text)
)
insert into public.chem_quiz_student_links (
  quiz_student_id,
  chem_student_id,
  source,
  updated_at
)
select
  quiz_student.id,
  chem_student.id,
  'explicit-name-pair-2026-08-13',
  now()
from expected_pairs p
join public.students quiz_student
  on quiz_student.display_name = p.quiz_name
 and quiz_student.active = true
join public.chem_students_v2 chem_student
  on chem_student.display_name = p.chem_name
 and chem_student.record_status = 'active'
on conflict (quiz_student_id) do update
set chem_student_id = excluded.chem_student_id,
    source = excluded.source,
    updated_at = excluded.updated_at;

commit;
