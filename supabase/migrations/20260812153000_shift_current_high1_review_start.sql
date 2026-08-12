-- Moves only the five active high-one students' REVIEW calendar so 2026-08-15 is day one.
begin;

create temporary table target_current_high1_students(id uuid primary key, expected_name text) on commit drop;
insert into target_current_high1_students values
  ('6423ac81-cda4-4cbb-9eb8-9cf9bb20d02b','洪杰'),
  ('f0306011-7ef5-4da2-b784-90279c7580be','天佑'),
  ('2e9dc98d-b4e3-4e67-a4fa-16298137c9bb','肖欣慧'),
  ('afb34c18-e94e-4492-ae59-69300fb87db4','浩洋'),
  ('b925f0b3-f827-41ec-b7ab-aa99b529f4a4','浩霖');

do $$
begin
  if exists (
    select 1 from target_current_high1_students t
    left join public.chem_students_v2 s on s.id=t.id
    where s.id is null or s.display_name<>t.expected_name or s.record_status<>'active'
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
