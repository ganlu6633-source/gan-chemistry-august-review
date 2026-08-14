-- Historical step: moves only the five approved active high-one profiles' REVIEW
-- calendar so 2026-08-15 is day one. Public source identifies the private roster
-- by one-way profile-id fingerprints rather than names or raw UUIDs.
begin;

create temporary table target_current_high1_students(id uuid primary key) on commit drop;
insert into target_current_high1_students(id)
select s.id
from public.chem_students_v2 s
where encode(extensions.digest(s.id::text,'sha256'),'hex') in (
  '0a38a67e2152013689c87f2398e8d82711400f865597905f33a4bb204a534c86',
  '7340cb871eb1519e1d8cada1e06504a9bc9b955c97fbe4fdecf85260fb013dd9',
  '535bd2f422b89d30fca725096fe110c2b7aecb64abf75ed7335940ec3672f022',
  '3d891e2a95488c044a5210163872d9bb24419bfff6e10db6a1721050f6904ae6',
  'e77669d1f17b1f06a54a7e12161a24fc0dbc8af5eb10b2afee50cc30787a1400'
);

do $$
begin
  if (select count(*) from target_current_high1_students) <> 5 or exists (
    select 1 from target_current_high1_students t
    left join public.chem_students_v2 s on s.id=t.id
    where s.id is null or s.record_status<>'active'
      or s.metadata->>'curriculumCohort'<>'high1_current'
  ) then raise exception 'The five-student target set no longer matches the approved roster'; end if;
  if exists (
    select 1 from target_current_high1_students t
    left join lateral (
      select count(*) plans,count(distinct plan_date) days,min(plan_date) first_day,max(plan_date) last_day
      from public.chem_learning_plans p where p.student_id=t.id and p.mode='REVIEW'
    ) x on true
    where x.plans<>40 or x.days<>40
      or (x.first_day<>date '2026-08-01' or x.last_day<>date '2026-09-09')
         and (x.first_day<>date '2026-08-15' or x.last_day<>date '2026-09-23')
  ) then raise exception 'Target calendars match neither the old nor the already-shifted window'; end if;
end $$;

create temporary table targets_to_shift(id uuid primary key) on commit drop;
insert into targets_to_shift
select t.id from target_current_high1_students t
where exists (
  select 1 from public.chem_learning_plans p where p.student_id=t.id and p.mode='REVIEW' and p.plan_date=date '2026-08-01'
);

do $$
begin
  if exists (select 1 from public.chem_learning_attempts a join targets_to_shift t on t.id=a.student_id)
  then raise exception 'A target student already has an attempt; manual preservation review is required'; end if;
end $$;

-- Use a collision-free staging interval before applying the net +14-day shift.
update public.chem_learning_plans p
set plan_date=plan_date+100
from targets_to_shift t
where p.student_id=t.id and p.mode='REVIEW'
  and p.plan_date between date '2026-08-01' and date '2026-09-09';

update public.chem_learning_plans p
set plan_date=plan_date-86
from targets_to_shift t
where p.student_id=t.id and p.mode='REVIEW'
  and p.plan_date between date '2026-11-09' and date '2026-12-18';

update public.chem_students_v2 s
set metadata=jsonb_set(coalesce(s.metadata,'{}'::jsonb),'{reviewStartDate}','"2026-08-15"'::jsonb,true)
from target_current_high1_students t
where s.id=t.id;

do $$
begin
  if exists (
    select 1 from target_current_high1_students t
    left join lateral (
      select count(*) plans,count(distinct plan_date) days,min(plan_date) first_day,max(plan_date) last_day
      from public.chem_learning_plans p where p.student_id=t.id and p.mode='REVIEW'
    ) x on true
    where x.plans<>40 or x.days<>40 or x.first_day<>date '2026-08-15' or x.last_day<>date '2026-09-23'
  ) then raise exception 'Post-shift 40-day calendar verification failed'; end if;
end $$;

commit;
