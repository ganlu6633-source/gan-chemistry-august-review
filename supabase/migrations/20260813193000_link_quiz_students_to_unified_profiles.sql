begin;

create table if not exists public.chem_quiz_student_links (
  quiz_student_id uuid primary key references public.students(id) on delete cascade,
  chem_student_id uuid not null unique references public.chem_students_v2(id) on delete cascade,
  source text not null default 'explicit-id-fingerprint-pair',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.chem_quiz_student_links is
  'Private identity bridge from the live quiz roster to unified chemistry student profiles.';

alter table public.chem_quiz_student_links enable row level security;
revoke all on table public.chem_quiz_student_links from anon, authenticated;
grant select, insert, update, delete on table public.chem_quiz_student_links to service_role;

do $$
declare
  matched_pair_count integer;
begin
  with expected_pairs(quiz_id_sha256, chem_id_sha256) as (
    values
      ('3753fcb623aec430d4cd313d34c069e401d9bffce22aa808639df67ac2f87ae8'::text, '535bd2f422b89d30fca725096fe110c2b7aecb64abf75ed7335940ec3672f022'::text),
      ('45827f2653bff4db0ca4f6b32598f6b051517f7057b8623b9eda2e62744b9938'::text, '3d891e2a95488c044a5210163872d9bb24419bfff6e10db6a1721050f6904ae6'::text),
      ('ab14edf74c7b3ef032657587bc5567952bb0a067364e1c2fa1107994fe811e7b'::text, '0a38a67e2152013689c87f2398e8d82711400f865597905f33a4bb204a534c86'::text),
      ('d14299f56dd41ac7febe436322e42a86c567bd429ece7bdd670bf228adf5c64c'::text, 'e77669d1f17b1f06a54a7e12161a24fc0dbc8af5eb10b2afee50cc30787a1400'::text),
      ('de78557ac655404ac32087e579a683556a90e5f1e1a254fa4b39fd5b861bb95e'::text, '7340cb871eb1519e1d8cada1e06504a9bc9b955c97fbe4fdecf85260fb013dd9'::text)
  )
  select count(*)
    into matched_pair_count
  from expected_pairs p
  join public.students quiz_student
    on encode(extensions.digest(quiz_student.id::text,'sha256'),'hex') = p.quiz_id_sha256
   and quiz_student.active = true
  join public.chem_students_v2 chem_student
    on encode(extensions.digest(chem_student.id::text,'sha256'),'hex') = p.chem_id_sha256
   and chem_student.record_status = 'active';

  if matched_pair_count <> 5 then
    raise exception
      'Expected exactly 5 active quiz-to-unified student matches, found %',
      matched_pair_count;
  end if;
end
$$;

with expected_pairs(quiz_id_sha256, chem_id_sha256) as (
  values
    ('3753fcb623aec430d4cd313d34c069e401d9bffce22aa808639df67ac2f87ae8'::text, '535bd2f422b89d30fca725096fe110c2b7aecb64abf75ed7335940ec3672f022'::text),
    ('45827f2653bff4db0ca4f6b32598f6b051517f7057b8623b9eda2e62744b9938'::text, '3d891e2a95488c044a5210163872d9bb24419bfff6e10b2afee50cc30787a1400'::text),
    ('ab14edf74c7b3ef032657587bc5567952bb0a067364e1c2fa1107994fe811e7b'::text, '0a38a67e2152013689c87f2398e8d82711400f865597905f33a4bb204a534c86'::text),
    ('d14299f56dd41ac7febe436322e42a86c567bd429ece7bdd670bf228adf5c64c'::text, 'e77669d1f17b1f06a54a7e12161a24fc0dbc8af5eb10b2afee50cc30787a1400'::text),
    ('de78557ac655404ac32087e579a683556a90e5f1e1a254fa4b39fd5b861bb95e'::text, '7340cb871eb1519e1d8cada1e06504a9bc9b955c97fbe4fdecf85260fb013dd9'::text)
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
  'explicit-id-fingerprint-pair-2026-08-13',
  now()
from expected_pairs p
join public.students quiz_student
  on encode(extensions.digest(quiz_student.id::text,'sha256'),'hex') = p.quiz_id_sha256
 and quiz_student.active = true
join public.chem_students_v2 chem_student
  on encode(extensions.digest(chem_student.id::text,'sha256'),'hex') = p.chem_id_sha256
 and chem_student.record_status = 'active'
on conflict (quiz_student_id) do update
set chem_student_id = excluded.chem_student_id,
    source = excluded.source,
    updated_at = excluded.updated_at;

commit;
