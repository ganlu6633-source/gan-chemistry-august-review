-- Applied restoration of the 2026-08-23 formal REVIEW packages without inventing or repeating
-- questions.  This is deliberately limited to today: the capacity-funded
-- 38-day calendar remains a separate fail-closed migration.
-- It never writes attempts, answers, independent quizzes, or quiz_sessions.

begin;

select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('chem-review-2026-08-23-restore', 0)
);

lock table app_private.chem_question_answer_locks in share mode;

do $$
begin
  if pg_catalog.to_regclass('app_private.chem_review_concept_catalog') is null
     or (select count(*) from app_private.chem_review_concept_catalog) <> 130
  then
    raise exception 'the reviewed concept catalog is unavailable';
  end if;
end $$;

create temporary table _today_formal_student on commit drop as
select
  student.id as student_id,
  student.grade_band,
  case
    when student.grade_band <> '高一' then array[]::text[]
    else array(
      select learned.skill_id
      from pg_catalog.jsonb_array_elements_text(
        case
          when pg_catalog.jsonb_typeof(student.metadata->'confirmedLearnedSkillIds') = 'array'
            then student.metadata->'confirmedLearnedSkillIds'
          else '[]'::jsonb
        end
      ) with ordinality as learned(skill_id, position)
      where learned.skill_id in (
        'H1_CLASSIFY','H1_PERIODIC','H1_MOLE_INTRO',
        'H1_GAS_MOLAR_VOLUME','H1_REDOX',
        'H1_REACTION_CLASSIFICATION','H1_SOLUTION_CONCENTRATION'
      )
      order by learned.position
    )
  end as confirmed_h1_skills
from public.chem_students_v2 student
where student.record_status = 'active'
  and student.grade_band in ('高一','高二','高三')
  and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb;

create unique index on _today_formal_student(student_id);

do $$
begin
  if exists (
    select 1 from _today_formal_student student
    where student.grade_band='高一'
      and pg_catalog.cardinality(student.confirmed_h1_skills)=0
  ) then
    raise exception 'a formal High-1 learner has no confirmed learned scope';
  end if;

  if exists (
    select 1
    from _today_formal_student student
    left join public.chem_learning_plans plan
      on plan.student_id=student.student_id
     and plan.mode='REVIEW'
     and plan.plan_date=date '2026-08-23'
    group by student.student_id
    having count(plan.id) <> 1
  ) then
    raise exception 'every formal learner must have exactly one REVIEW plan today';
  end if;

  if exists (
    select 1
    from public.chem_learning_plans plan
    join _today_formal_student student on student.student_id=plan.student_id
    where plan.mode='REVIEW'
      and plan.plan_date=date '2026-08-23'
      and (
        exists (
          select 1 from public.chem_learning_attempts attempt
          where attempt.plan_day_id=plan.id
        )
        or exists (
          select 1 from app_private.chem_question_answer_locks answer_lock
          where answer_lock.student_id=plan.student_id
            and answer_lock.plan_day_id=plan.id
        )
      )
  ) then
    raise exception 'a learner has already started today; do not reshape issued work';
  end if;
end $$;

-- Lock the exact plan rows after taking the migration advisory and answer-lock
-- maintenance lock.  No student can receive a first-answer lock mid-rewrite.
do $$
declare v_plan record;
begin
  for v_plan in
    select plan.id
    from public.chem_learning_plans plan
    join _today_formal_student student on student.student_id=plan.student_id
    where plan.mode='REVIEW' and plan.plan_date=date '2026-08-23'
    order by plan.student_id,plan.id
    for update of plan
  loop
    null;
  end loop;
end $$;

create temporary table _today_course_order (
  grade_band text not null,
  skill_id text primary key,
  skill_order smallint not null,
  unique(grade_band,skill_order)
) on commit drop;

insert into _today_course_order(grade_band,skill_id,skill_order) values
  ('高一','H1_CLASSIFY',1),
  ('高一','H1_PERIODIC',2),
  ('高一','H1_MOLE_INTRO',3),
  ('高一','H1_GAS_MOLAR_VOLUME',4),
  ('高一','H1_REDOX',5),
  ('高一','H1_REACTION_CLASSIFICATION',6),
  ('高一','H1_SOLUTION_CONCENTRATION',7),
  ('高二','H2_THERMO',1),
  ('高二','H2_RATE',2),
  ('高二','H2_EQUIL',3),
  ('高二','H2_K',4),
  ('高二','H2_WEAK',5),
  ('高二','H2_PH_HYDRO',6),
  ('高二','H2_KSP',7),
  ('高二','H2_ELECTRO',8),
  ('高三','H3_ION_REDOX',1),
  ('高三','H3_STOICH',2),
  ('高三','H3_EXPERIMENT',3),
  ('高三','H3_AQ',4),
  ('高三','H3_ELECTRO',5),
  ('高三','H3_EQUILIBRIUM',6),
  ('高三','H3_THERMO_RATE',7),
  ('高三','H3_INORGANIC',8),
  ('高三','H3_PROCESS',9),
  ('高三','H3_STRUCTURE',10),
  ('高三','H3_ORGANIC',11);

create temporary table _today_used_identity on commit drop as
with identity_row as (
  select
    attempt.student_id,
    answer.question_id,
    answer.mother_id,
    coalesce(
      nullif(answer.question_snapshot->>'sourceItemKey',''),
      nullif(question.source_item_key,'')
    ) as source_item_key,
    coalesce(
      nullif(answer.question_snapshot->>'contentFingerprint',''),
      nullif(question.content_fingerprint,'')
    ) as content_fingerprint
  from public.chem_learning_attempts attempt
  join public.chem_attempt_answers answer on answer.attempt_id=attempt.id
  left join public.chem_questions question on question.id=answer.question_id
  join _today_formal_student student on student.student_id=attempt.student_id
  where attempt.mode='REVIEW'

  union all

  select
    answer_lock.student_id,
    answer_lock.question_id,
    question.mother_id,
    question.source_item_key,
    question.content_fingerprint
  from app_private.chem_question_answer_locks answer_lock
  join public.chem_questions question on question.id=answer_lock.question_id
  join _today_formal_student student on student.student_id=answer_lock.student_id
)
select distinct * from identity_row;

create index on _today_used_identity(student_id,question_id);
create index on _today_used_identity(student_id,mother_id);
create index on _today_used_identity(student_id,source_item_key);
create index on _today_used_identity(student_id,content_fingerprint);

create temporary table _today_latest_concept_state on commit drop as
with ranked as (
  select
    attempt.student_id,
    coalesce(
      nullif(answer.concept_key,''),
      nullif(answer.question_snapshot->>'conceptKey',''),
      question.concept_key
    ) as concept_key,
    answer.correct,
    answer.uncertain,
    coalesce(
      nullif(answer.question_snapshot->>'level','')::integer,
      answer.level,
      question.level
    )::integer as question_level,
    row_number() over(
      partition by attempt.student_id,coalesce(
        nullif(answer.concept_key,''),
        nullif(answer.question_snapshot->>'conceptKey',''),
        question.concept_key
      )
      order by coalesce(attempt.completed_at,attempt.started_at) desc,
        attempt.sequence desc,answer.id desc
    ) as latest_rank
  from public.chem_learning_attempts attempt
  join public.chem_attempt_answers answer on answer.attempt_id=attempt.id
  left join public.chem_questions question on question.id=answer.question_id
  join _today_formal_student student on student.student_id=attempt.student_id
  where attempt.mode='REVIEW'
)
select student_id,concept_key,correct,uncertain,question_level
from ranked
where latest_rank=1 and concept_key is not null;

create temporary table _today_fresh_original on commit drop as
select
  student.student_id,
  student.grade_band,
  question.id as question_id,
  question.mother_id,
  question.source_item_key,
  question.content_fingerprint,
  question.level,
  question.skill_id,
  question.concept_key,
  catalog.concept_order,
  catalog.concept_label,
  course.skill_order,
  case
    when latest.concept_key is not null
      and (not latest.correct or latest.uncertain) then 1
    when latest.concept_key is null then 2
    else 3
  end as review_priority
from _today_formal_student student
join app_private.chem_question_source_releases release
  on release.grade_band=student.grade_band
 and release.status='active'
 and release.verification_status='full_visual_verified'
join public.chem_questions question
  on question.source_release_id=release.id
 and question.grade_band=student.grade_band
join app_private.chem_review_concept_catalog catalog
  on catalog.grade_band=question.grade_band
 and catalog.skill_id=question.skill_id
 and catalog.concept_key=question.concept_key
join _today_course_order course
  on course.grade_band=question.grade_band
 and course.skill_id=question.skill_id
left join _today_latest_concept_state latest
  on latest.student_id=student.student_id
 and latest.concept_key=question.concept_key
where question.review_status='approved'
  and question.scope_status='IN'
  and question.usable_for_review
  and question.source_kind='licensed_local'
  and question.render_mode='image_primary'
  and question.mother_id is not null
  and question.source_item_key is not null
  and question.content_fingerprint is not null
  and exists (
    select 1 from pg_catalog.jsonb_array_elements(question.asset_refs) asset
    where asset->>'kind'='question_image'
      and coalesce(asset->>'path','') <> ''
      and coalesce(asset->>'sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(asset->>'width','0')::integer > 0
      and coalesce(asset->>'height','0')::integer > 0
  )
  and exists (
    select 1 from pg_catalog.jsonb_array_elements(question.asset_refs) asset
    where asset->>'kind'='analysis_image'
      and coalesce(asset->>'path','') <> ''
      and coalesce(asset->>'sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(asset->>'width','0')::integer > 0
      and coalesce(asset->>'height','0')::integer > 0
  )
  and (
    student.grade_band <> '高一'
    or question.skill_id=any(student.confirmed_h1_skills)
  )
  and (
    latest.concept_key is null
    or (
      latest.correct and not latest.uncertain
      and question.level > latest.question_level
    )
    or (
      (not latest.correct or latest.uncertain)
      and question.level <= latest.question_level
    )
  )
  and not exists (
    select 1
    from _today_used_identity used
    where used.student_id=student.student_id
      and (
        used.question_id=question.id
        or used.mother_id=question.mother_id
        or used.source_item_key=question.source_item_key
        or used.content_fingerprint=question.content_fingerprint
      )
  );

create index on _today_fresh_original(student_id,concept_key);

create temporary table _today_concept_choice on commit drop as
with capacity as (
  select
    fresh.student_id,
    fresh.grade_band,
    fresh.skill_id,
    fresh.concept_key,
    fresh.concept_label,
    fresh.skill_order,
    fresh.concept_order,
    min(fresh.review_priority) as review_priority,
    count(distinct fresh.question_id)::integer as questions,
    count(distinct fresh.mother_id)::integer as mothers,
    count(distinct fresh.source_item_key)::integer as source_items,
    count(distinct fresh.content_fingerprint)::integer as fingerprints
  from _today_fresh_original fresh
  group by fresh.student_id,fresh.grade_band,fresh.skill_id,
    fresh.concept_key,fresh.concept_label,fresh.skill_order,fresh.concept_order
), ranked as (
  select capacity.*,
    row_number() over(
      partition by capacity.student_id
      order by capacity.review_priority,capacity.skill_order,
        capacity.concept_order,
        pg_catalog.hashtextextended(
          capacity.student_id::text || ':2026-08-23:' || capacity.concept_key,
          0
        )
    )::integer as target_order
  from capacity
  where least(capacity.questions,capacity.mothers,
    capacity.source_items,capacity.fingerprints) >= 1
)
select * from ranked where target_order <= 8;

create unique index on _today_concept_choice(student_id,target_order);
create unique index on _today_concept_choice(student_id,concept_key);

create temporary table _today_assignment on commit drop as
select
  student.student_id,
  count(choice.concept_key)::smallint as question_count,
  array(
    select owned.skill_id
    from (
      select selected.skill_id,min(selected.target_order) as first_order
      from _today_concept_choice selected
      where selected.student_id=student.student_id
      group by selected.skill_id
      order by min(selected.target_order)
    ) owned
  )::text[] as skill_ids,
  array_agg(choice.concept_key order by choice.target_order)::text[]
    as target_concept_keys,
  array_agg(choice.concept_label order by choice.target_order)::text[]
    as knowledge_summaries
from _today_formal_student student
left join _today_concept_choice choice on choice.student_id=student.student_id
group by student.student_id;

do $$
begin
  if exists (
    select 1 from _today_assignment assignment
    where assignment.question_count not between 1 and 8
       or pg_catalog.cardinality(assignment.skill_ids) not between 1 and assignment.question_count
       or pg_catalog.cardinality(assignment.target_concept_keys) <> assignment.question_count
       or pg_catalog.cardinality(assignment.knowledge_summaries) <> assignment.question_count
  ) then
    raise exception 'a formal learner has no safe source original for today';
  end if;
end $$;

update public.chem_learning_plans plan
set
  title='个性化复习｜今日容量校准',
  skill_ids=assignment.skill_ids,
  target_concept_keys=assignment.target_concept_keys,
  knowledge_summaries=assignment.knowledge_summaries,
  estimated_minutes=least(30,greatest(8,assignment.question_count*4))::smallint,
  source='mixed',
  is_scheduled=true,
  question_count=assignment.question_count,
  round_limit=1,
  max_question_level=null
from _today_assignment assignment
where plan.student_id=assignment.student_id
  and plan.mode='REVIEW'
  and plan.plan_date=date '2026-08-23'
  and not exists (
    select 1 from public.chem_learning_attempts attempt
    where attempt.plan_day_id=plan.id
  )
  and not exists (
    select 1 from app_private.chem_question_answer_locks answer_lock
    where answer_lock.student_id=plan.student_id
      and answer_lock.plan_day_id=plan.id
  );

do $$
begin
  if exists (
    select 1
    from _today_assignment assignment
    left join public.chem_learning_plans plan
      on plan.student_id=assignment.student_id
     and plan.mode='REVIEW'
     and plan.plan_date=date '2026-08-23'
    where plan.id is null
       or plan.question_count is distinct from assignment.question_count
       or plan.round_limit <> 1
       or plan.skill_ids is distinct from assignment.skill_ids
       or plan.target_concept_keys is distinct from assignment.target_concept_keys
       or plan.knowledge_summaries is distinct from assignment.knowledge_summaries
  ) then
    raise exception 'today persisted REVIEW packages differ from funded assignments';
  end if;

  if exists (
    select 1
    from _today_concept_choice target
    left join _today_fresh_original fresh
      on fresh.student_id=target.student_id
     and fresh.concept_key=target.concept_key
    group by target.student_id,target.concept_key
    having count(fresh.question_id)=0
  ) then
    raise exception 'today target is not backed by a compatible fresh original';
  end if;
end $$;

commit;
