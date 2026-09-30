-- Keep the one-time recovery copy away from the metadata read on every request.
create table app_private.chem_choice_calendar_backups (
 student_id uuid not null references public.chem_students_v2(id) on delete cascade,
 migration_key text not null,
 captured_at timestamptz not null default now(),
 previous_program jsonb,
 previous_plans jsonb not null check(jsonb_typeof(previous_plans)='array'),
 primary key(student_id,migration_key)
);
alter table app_private.chem_choice_calendar_backups enable row level security;
revoke all on app_private.chem_choice_calendar_backups from public,anon,authenticated,service_role;
