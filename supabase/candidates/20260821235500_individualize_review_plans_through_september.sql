-- Build the exact High-1/High-2/High-3 REVIEW calendar for 2026-08-22
-- through 2026-09-29.
--
-- Safety and teaching invariants:
--   * Only active high-school REVIEW plans in this date window are changed.
--   * Existing 2026-08-22..2026-09-25 plan ids are preserved; four missing
--     dates are inserted without hard-coded student ids.
--   * Every formal day names five exact fine concepts. Ordinary days contain
--     five classroom concepts. Recovery anchors contain four classroom
--     concepts plus one latest unresolved concept; when no submitted evidence
--     exists, the fifth concept is explicitly a classroom diagnostic.
--   * The metadata-selected daily-redox profiles receive four classroom
--     concepts plus one rotating REDOX concept, never five REDOX questions.
--   * Before 2026-09-01, every High-1 target stays inside the profile's
--     confirmed learned scope. Afterwards the sequence starts from Jiangsu
--     Education Press Compulsory 1 Unit 1.
--   * Formal students receive only approved, in-scope, review-enabled,
--     image-primary licensed originals. Demo students remain on the separate
--     teacher-original demo pool.
--   * Capacity is funded after each student's completed REVIEW history for
--     all five possible rounds, with question/mother/source/fingerprint
--     uniqueness and a real difficulty ladder. Any shortage aborts the whole
--     migration; no repeated or substitute question is silently assigned.
--   * Attempts, answers and the independent quiz_sessions table are immutable.

begin;

set transaction isolation level serializable;
set local lock_timeout = '5s';

create temporary table _schedule_students (
  student_id uuid primary key,
  grade_band text not null,
  demo boolean not null,
  confirmed_h1_skills text[] not null,
  daily_redox boolean not null,
  non_redox_fallback text
) on commit drop;

with active_students as (
  select
    s.id,
    s.grade_band,
    s.metadata,
    coalesce(s.metadata->'demo' = 'true'::jsonb, false) as demo,
    case
      when s.grade_band <> '高一' then array[]::text[]
      else array(
        select learned.skill_id
        from jsonb_array_elements_text(
          case
            when jsonb_typeof(s.metadata->'confirmedLearnedSkillIds') = 'array'
              then s.metadata->'confirmedLearnedSkillIds'
            else '[]'::jsonb
          end
        ) with ordinality as learned(skill_id, position)
        where learned.skill_id in (
          'H1_CLASSIFY','H1_PERIODIC','H1_MOLE_INTRO',
          'H1_GAS_MOLAR_VOLUME','H1_REDOX'
        )
        order by learned.position
      )
    end as confirmed_h1_skills
  from public.chem_students_v2 s
  where s.record_status = 'active'
    and s.grade_band in ('高一','高二','高三')
)
insert into _schedule_students (
  student_id, grade_band, demo, confirmed_h1_skills,
  daily_redox, non_redox_fallback
)
select
  active.id,
  active.grade_band,
  active.demo,
  active.confirmed_h1_skills,
  active.grade_band = '高一'
    and not active.demo
    and coalesce(active.metadata->>'curriculumCohort', '') = 'high1_current'
    and coalesce(active.metadata->'confirmedLearnedSkillIds', '[]'::jsonb) ? 'H1_REDOX',
  case
    when active.grade_band <> '高一' then null
    else (
      select confirmed.skill_id
      from unnest(active.confirmed_h1_skills) with ordinality as confirmed(skill_id, position)
      where confirmed.skill_id <> 'H1_REDOX'
      order by
        case when confirmed.skill_id = 'H1_GAS_MOLAR_VOLUME' then 0 else 1 end,
        confirmed.position
      limit 1
    )
  end
from active_students active;

create temporary table _skill_catalog (
  grade_band text not null,
  skill_id text primary key,
  display_name text not null
) on commit drop;

insert into _skill_catalog (grade_band, skill_id, display_name) values
  ('高一','H1_CLASSIFY','物质的分类'),
  ('高一','H1_PERIODIC','元素周期律'),
  ('高一','H1_MOLE_INTRO','物质的量与阿伏加德罗常数'),
  ('高一','H1_GAS_MOLAR_VOLUME','气体摩尔体积'),
  ('高一','H1_REDOX','氧化还原反应'),
  ('高一','H1_REACTION_CLASSIFICATION','化学反应的分类与物质转化'),
  ('高一','H1_SOLUTION_CONCENTRATION','物质的量浓度与溶液配制'),
  ('高二','H2_THERMO','化学反应的热效应'),
  ('高二','H2_RATE','化学反应速率'),
  ('高二','H2_EQUIL','化学平衡'),
  ('高二','H2_K','化学平衡常数'),
  ('高二','H2_WEAK','弱电解质的电离平衡'),
  ('高二','H2_PH_HYDRO','水的电离、pH与盐类水解'),
  ('高二','H2_KSP','沉淀溶解平衡'),
  ('高二','H2_ELECTRO','电化学与金属腐蚀防护'),
  ('高三','H3_ION_REDOX','离子反应与氧化还原'),
  ('高三','H3_STOICH','化学计量与守恒'),
  ('高三','H3_EXPERIMENT','化学实验'),
  ('高三','H3_AQ','水溶液中的离子平衡'),
  ('高三','H3_ELECTRO','电化学'),
  ('高三','H3_EQUILIBRIUM','化学平衡'),
  ('高三','H3_THERMO_RATE','热化学与反应速率'),
  ('高三','H3_INORGANIC','元素化合物'),
  ('高三','H3_PROCESS','无机工艺流程'),
  ('高三','H3_STRUCTURE','物质结构与性质'),
  ('高三','H3_ORGANIC','有机化学基础');

create temporary table _review_dates (
  plan_date date primary key,
  day_index integer not null unique,
  recovery_slot integer
) on commit drop;

insert into _review_dates (plan_date, day_index, recovery_slot)
select
  generated.plan_date,
  generated.day_index,
  array_position(array[0,4,9,14,20,27,34]::integer[], generated.day_index)
from (
  select
    day::date as plan_date,
    (day::date - date '2026-08-22')::integer as day_index
  from generate_series(date '2026-08-22', date '2026-09-29', interval '1 day') day
) generated;

create temporary table _grade_schedule (
  grade_band text not null,
  day_index integer not null,
  skill_id text not null,
  primary key (grade_band, day_index)
) on commit drop;

-- GENERATED_GRADE_SCHEDULE_BEGIN
insert into _grade_schedule (grade_band, day_index, skill_id)
select '高一', (item.position - 1)::integer, item.skill_id
from unnest(array[
  'H1_CLASSIFY','H1_PERIODIC','H1_MOLE_INTRO','H1_GAS_MOLAR_VOLUME','H1_CLASSIFY',
  'H1_PERIODIC','H1_MOLE_INTRO','H1_GAS_MOLAR_VOLUME','H1_REDOX','H1_MOLE_INTRO',
  'H1_CLASSIFY','H1_REACTION_CLASSIFICATION','H1_CLASSIFY','H1_REACTION_CLASSIFICATION','H1_MOLE_INTRO',
  'H1_MOLE_INTRO','H1_SOLUTION_CONCENTRATION','H1_SOLUTION_CONCENTRATION','H1_MOLE_INTRO','H1_SOLUTION_CONCENTRATION',
  'H1_GAS_MOLAR_VOLUME','H1_GAS_MOLAR_VOLUME','H1_CLASSIFY','H1_REACTION_CLASSIFICATION','H1_MOLE_INTRO',
  'H1_SOLUTION_CONCENTRATION','H1_REACTION_CLASSIFICATION','H1_GAS_MOLAR_VOLUME','H1_CLASSIFY','H1_MOLE_INTRO',
  'H1_SOLUTION_CONCENTRATION','H1_REACTION_CLASSIFICATION','H1_GAS_MOLAR_VOLUME','H1_CLASSIFY','H1_MOLE_INTRO',
  'H1_SOLUTION_CONCENTRATION','H1_REACTION_CLASSIFICATION','H1_GAS_MOLAR_VOLUME','H1_CLASSIFY'
]::text[]) with ordinality as item(skill_id, position);

insert into _grade_schedule (grade_band, day_index, skill_id)
select '高二', (item.position - 1)::integer, item.skill_id
from unnest(array[
  'H2_THERMO','H2_RATE','H2_EQUIL','H2_K','H2_WEAK',
  'H2_PH_HYDRO','H2_KSP','H2_ELECTRO','H2_THERMO','H2_ELECTRO',
  'H2_THERMO','H2_THERMO','H2_THERMO','H2_THERMO','H2_ELECTRO',
  'H2_ELECTRO','H2_ELECTRO','H2_ELECTRO','H2_ELECTRO','H2_THERMO',
  'H2_ELECTRO','H2_ELECTRO','H2_THERMO','H2_ELECTRO','H2_RATE',
  'H2_RATE','H2_EQUIL','H2_EQUIL','H2_K','H2_RATE',
  'H2_EQUIL','H2_K','H2_WEAK','H2_PH_HYDRO','H2_KSP',
  'H2_ELECTRO','H2_EQUIL','H2_K','H2_RATE'
]::text[]) with ordinality as item(skill_id, position);

insert into _grade_schedule (grade_band, day_index, skill_id)
select '高三', (item.position - 1)::integer, item.skill_id
from unnest(array[
  'H3_ION_REDOX','H3_STOICH','H3_EXPERIMENT','H3_AQ','H3_ION_REDOX',
  'H3_ELECTRO','H3_STOICH','H3_EQUILIBRIUM','H3_EXPERIMENT','H3_THERMO_RATE',
  'H3_ION_REDOX','H3_INORGANIC','H3_AQ','H3_PROCESS','H3_STOICH',
  'H3_STRUCTURE','H3_EXPERIMENT','H3_ORGANIC','H3_ION_REDOX','H3_ELECTRO',
  'H3_AQ','H3_EQUILIBRIUM','H3_STOICH','H3_THERMO_RATE','H3_EXPERIMENT',
  'H3_INORGANIC','H3_PROCESS','H3_ION_REDOX','H3_AQ','H3_STRUCTURE',
  'H3_STOICH','H3_ORGANIC','H3_ELECTRO','H3_EQUILIBRIUM','H3_EXPERIMENT',
  'H3_ION_REDOX','H3_STOICH','H3_AQ','H3_PROCESS'
]::text[]) with ordinality as item(skill_id, position);
-- GENERATED_GRADE_SCHEDULE_END

-- The formal catalog is derived only from the currently review-enabled
-- licensed visual release. Labels must be stable because the same labels are
-- shown in the five-item knowledge summary before a student starts.
create temporary table _licensed_concept_groups on commit drop as
select
  q.grade_band,
  q.skill_id,
  q.concept_key,
  min(nullif(btrim(q.source_info->>'conceptLabel'), '')) as concept_label,
  count(distinct nullif(btrim(q.source_info->>'conceptLabel'), '')) as label_count
from public.chem_questions q
join _skill_catalog skill
  on skill.grade_band = q.grade_band and skill.skill_id = q.skill_id
where q.review_status = 'approved'
  and q.scope_status = 'IN'
  and q.usable_for_review
  and q.source_kind = 'licensed_local'
  and q.render_mode = 'image_primary'
  and q.source_release_id is not null
  and q.concept_key is not null
group by q.grade_band, q.skill_id, q.concept_key;

create temporary table _licensed_concepts on commit drop as
select
  grouped.grade_band,
  grouped.skill_id,
  grouped.concept_key,
  grouped.concept_label,
  row_number() over (
    partition by grouped.grade_band, grouped.skill_id
    order by grouped.concept_key
  )::integer as concept_order
from _licensed_concept_groups grouped;

create temporary table _base_assignment on commit drop as
select
  student.student_id,
  student.grade_band,
  student.demo,
  student.confirmed_h1_skills,
  student.daily_redox,
  dates.plan_date,
  dates.day_index,
  dates.recovery_slot,
  schedule.skill_id as scheduled_skill,
  case
    when student.demo and schedule.skill_id = 'H1_REACTION_CLASSIFICATION'
      then 'H1_CLASSIFY'
    when student.demo and schedule.skill_id = 'H1_SOLUTION_CONCENTRATION'
      then 'H1_MOLE_INTRO'
    when student.grade_band = '高一'
      and student.daily_redox
      and schedule.skill_id = 'H1_REDOX'
      then student.non_redox_fallback
    when student.grade_band = '高一'
      and not student.demo
      and dates.plan_date < date '2026-09-01'
      and not (schedule.skill_id = any(student.confirmed_h1_skills))
      and schedule.skill_id = 'H1_REDOX'
      and 'H1_GAS_MOLAR_VOLUME' = any(student.confirmed_h1_skills)
      then 'H1_GAS_MOLAR_VOLUME'
    when student.grade_band = '高一'
      and not student.demo
      and dates.plan_date < date '2026-09-01'
      and not (schedule.skill_id = any(student.confirmed_h1_skills))
      then student.confirmed_h1_skills[
        1 + mod(dates.day_index, greatest(cardinality(student.confirmed_h1_skills), 1))
      ]
    else schedule.skill_id
  end as classroom_skill
from _schedule_students student
cross join _review_dates dates
join _grade_schedule schedule
  on schedule.grade_band = student.grade_band
 and schedule.day_index = dates.day_index;

-- For each concept, keep only its latest completed state. A concept whose
-- latest answer is correct and confident is closed; an older error may not
-- follow the student forever.
create temporary table _unresolved_evidence on commit drop as
with answer_history as (
  select
    student.student_id,
    student.grade_band,
    coalesce(nullif(answer.skill_id, ''), question.skill_id) as skill_id,
    coalesce(
      nullif(answer.concept_key, ''),
      nullif(answer.question_snapshot->>'conceptKey', ''),
      question.concept_key
    ) as concept_key,
    answer.correct,
    answer.uncertain,
    attempt.completed_at,
    attempt.sequence,
    answer.id as answer_id,
    row_number() over (
      partition by student.student_id, coalesce(
        nullif(answer.concept_key, ''),
        nullif(answer.question_snapshot->>'conceptKey', ''),
        question.concept_key
      )
      order by attempt.completed_at desc, attempt.sequence desc, answer.id desc
    )::integer as latest_rank
  from _schedule_students student
  join public.chem_learning_attempts attempt
    on attempt.student_id = student.student_id
   and attempt.mode = 'REVIEW'
   and attempt.completed_at is not null
   and attempt.completed_at < timestamptz '2026-08-22 00:00:00+08'
  join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
  left join public.chem_questions question on question.id = answer.question_id
  where not student.demo
), unresolved as (
  select history.*
  from answer_history history
  join _licensed_concepts concept
    on concept.grade_band = history.grade_band
   and concept.skill_id = history.skill_id
   and concept.concept_key = history.concept_key
  where history.latest_rank = 1
    and (not history.correct or history.uncertain)
), ranked as (
  select
    unresolved.*,
    row_number() over (
      partition by unresolved.student_id
      order by unresolved.completed_at desc,
        unresolved.sequence desc, unresolved.answer_id desc,
        unresolved.concept_key
    )::integer as evidence_rank,
    count(*) over (partition by unresolved.student_id)::integer as evidence_count
  from unresolved
)
select * from ranked;

create temporary table _assignment_context on commit drop as
select
  base.*,
  evidence.skill_id as evidence_skill,
  evidence.concept_key as evidence_concept,
  case
    when base.demo then 'demo_course'
    when base.daily_redox then 'daily_redox'
    when base.recovery_slot is not null and evidence.concept_key is not null
      then 'answer_evidence'
    when base.recovery_slot is not null then 'classroom_diagnostic'
    else 'classroom_sequence'
  end as assignment_reason
from _base_assignment base
left join _unresolved_evidence evidence
  on evidence.student_id = base.student_id
 and base.recovery_slot is not null
 and not base.daily_redox
 and evidence.evidence_rank = 1 + mod(base.recovery_slot - 1, evidence.evidence_count);

create temporary table _personal_target on commit drop as
select
  context.student_id,
  context.plan_date,
  coalesce(context.evidence_skill, classroom.skill_id) as skill_id,
  coalesce(context.evidence_concept, classroom.concept_key) as concept_key,
  coalesce(evidence_label.concept_label, classroom.concept_label) as concept_label
from _assignment_context context
join _licensed_concepts classroom
  on classroom.grade_band = context.grade_band
 and classroom.skill_id = context.classroom_skill
 and classroom.concept_order = 1 + mod(context.recovery_slot - 1, 5)
left join _licensed_concepts evidence_label
  on evidence_label.grade_band = context.grade_band
 and evidence_label.skill_id = context.evidence_skill
 and evidence_label.concept_key = context.evidence_concept
where not context.demo
  and not context.daily_redox
  and context.recovery_slot is not null;

create temporary table _daily_redox_target on commit drop as
select
  context.student_id,
  context.plan_date,
  redox.skill_id,
  redox.concept_key,
  redox.concept_label
from _assignment_context context
join _licensed_concepts redox
  on redox.grade_band = '高一'
 and redox.skill_id = 'H1_REDOX'
 and redox.concept_order = 1 + mod(context.day_index, 5)
where not context.demo and context.daily_redox;

create temporary table _plan_targets (
  student_id uuid not null,
  plan_date date not null,
  target_order integer not null,
  skill_id text not null,
  concept_key text not null,
  concept_label text not null,
  primary key (student_id, plan_date, concept_key)
) on commit drop;

-- Ordinary formal days: all five classroom concepts.
insert into _plan_targets (
  student_id, plan_date, target_order, skill_id, concept_key, concept_label
)
select
  context.student_id,
  context.plan_date,
  concept.concept_order,
  concept.skill_id,
  concept.concept_key,
  concept.concept_label
from _assignment_context context
join _licensed_concepts concept
  on concept.grade_band = context.grade_band
 and concept.skill_id = context.classroom_skill
where not context.demo
  and not context.daily_redox
  and context.recovery_slot is null;

-- Evidence/diagnostic anchors: four classroom concepts plus the exact
-- personal concept. If the personal concept belongs to today's classroom
-- skill, exclude that same concept from the four so it appears once, last.
insert into _plan_targets (
  student_id, plan_date, target_order, skill_id, concept_key, concept_label
)
select
  context.student_id,
  context.plan_date,
  row_number() over (
    partition by context.student_id, context.plan_date
    order by concept.concept_order
  )::integer,
  concept.skill_id,
  concept.concept_key,
  concept.concept_label
from _assignment_context context
join _personal_target personal
  on personal.student_id = context.student_id and personal.plan_date = context.plan_date
join _licensed_concepts concept
  on concept.grade_band = context.grade_band
 and concept.skill_id = context.classroom_skill
where not context.demo
  and not context.daily_redox
  and context.recovery_slot is not null
  and (
    (personal.skill_id = context.classroom_skill and concept.concept_key <> personal.concept_key)
    or
    (personal.skill_id <> context.classroom_skill
      and concept.concept_order <> 1 + mod(context.recovery_slot - 1, 5))
  );

insert into _plan_targets (
  student_id, plan_date, target_order, skill_id, concept_key, concept_label
)
select
  personal.student_id,
  personal.plan_date,
  5,
  personal.skill_id,
  personal.concept_key,
  personal.concept_label
from _personal_target personal;

-- Daily redox: four non-REDOX classroom concepts plus one rotating REDOX
-- concept. Even the skeleton's REDOX date is replaced with a confirmed
-- non-REDOX classroom skill for these profiles.
insert into _plan_targets (
  student_id, plan_date, target_order, skill_id, concept_key, concept_label
)
select
  context.student_id,
  context.plan_date,
  row_number() over (
    partition by context.student_id, context.plan_date
    order by concept.concept_order
  )::integer,
  concept.skill_id,
  concept.concept_key,
  concept.concept_label
from _assignment_context context
join _licensed_concepts concept
  on concept.grade_band = context.grade_band
 and concept.skill_id = context.classroom_skill
where not context.demo
  and context.daily_redox
  and concept.concept_order <> 1 + mod(context.day_index, 5);

insert into _plan_targets (
  student_id, plan_date, target_order, skill_id, concept_key, concept_label
)
select
  daily.student_id,
  daily.plan_date,
  5,
  daily.skill_id,
  daily.concept_key,
  daily.concept_label
from _daily_redox_target daily;

create temporary table _plan_target_summary on commit drop as
select
  target.student_id,
  target.plan_date,
  array_agg(target.concept_key order by target.target_order) as target_concept_keys,
  array_agg(target.concept_label order by target.target_order) as knowledge_summaries
from _plan_targets target
group by target.student_id, target.plan_date;

create temporary table _plan_skill_summary on commit drop as
select
  first_target.student_id,
  first_target.plan_date,
  array_agg(first_target.skill_id order by first_target.first_order) as skill_ids
from (
  select
    target.student_id,
    target.plan_date,
    target.skill_id,
    min(target.target_order) as first_order
  from _plan_targets target
  group by target.student_id, target.plan_date, target.skill_id
) first_target
group by first_target.student_id, first_target.plan_date;

create temporary table _plan_assignment on commit drop as
select
  context.student_id,
  context.grade_band,
  context.demo,
  context.plan_date,
  context.day_index,
  context.recovery_slot,
  context.classroom_skill,
  context.assignment_reason,
  targets.target_concept_keys,
  targets.knowledge_summaries,
  skills.skill_ids,
  case
    when context.demo then '演示复习｜' || catalog.display_name
    when context.assignment_reason = 'daily_redox'
      then '课堂主线＋每日氧化还原｜' || catalog.display_name
    when context.assignment_reason = 'answer_evidence'
      then '个人回收｜' || targets.knowledge_summaries[5]
    when context.assignment_reason = 'classroom_diagnostic'
      then '课堂诊断｜' || catalog.display_name
    when context.grade_band = '高一' and context.plan_date < date '2026-09-01'
      then '暑期复习收口｜' || catalog.display_name
    when context.grade_band = '高一'
      then '必修一第一单元｜' || catalog.display_name
    when context.grade_band = '高二' and context.plan_date < date '2026-09-01'
      then '暑期复习诊断｜' || catalog.display_name
    when context.grade_band = '高二'
      then '选择性必修一｜' || catalog.display_name
    else '高频易错优先｜' || catalog.display_name
  end as title,
  case
    when context.assignment_reason = 'answer_evidence' then 'mastery'
    when context.assignment_reason = 'daily_redox' then 'mixed'
    when context.grade_band = '高三' then 'exam'
    else 'course'
  end as source,
  case context.grade_band when '高一' then 15 when '高二' then 18 else 20 end::smallint
    as estimated_minutes,
  case when context.grade_band in ('高一','高二') then 3 else null end::smallint
    as max_question_level
from _assignment_context context
join _skill_catalog catalog
  on catalog.grade_band = context.grade_band and catalog.skill_id = context.classroom_skill
join _plan_target_summary targets
  on targets.student_id = context.student_id and targets.plan_date = context.plan_date
join _plan_skill_summary skills
  on skills.student_id = context.student_id and skills.plan_date = context.plan_date
where not context.demo;

-- Demo plans intentionally keep the legacy skill-level contract (an empty
-- exact-target array). The student access path then selects only approved
-- teacher_original rows with usable_for_demo=true for that one safe skill.
-- Human-readable summaries may reuse the five generic concept labels, but no
-- licensed question, image or source identity is exposed to a demo profile.
create temporary table _demo_skill_summaries on commit drop as
select
  concept.grade_band,
  concept.skill_id,
  array_agg(concept.concept_label order by concept.concept_order) as knowledge_summaries
from _licensed_concepts concept
group by concept.grade_band, concept.skill_id;

create temporary table _demo_assignment on commit drop as
select
  context.student_id,
  context.grade_band,
  context.demo,
  context.plan_date,
  context.day_index,
  context.recovery_slot,
  context.classroom_skill,
  context.assignment_reason,
  array[]::text[] as target_concept_keys,
  summaries.knowledge_summaries,
  array[context.classroom_skill]::text[] as skill_ids,
  '演示复习｜' || catalog.display_name as title,
  'course'::text as source,
  case context.grade_band when '高一' then 15 when '高二' then 18 else 20 end::smallint
    as estimated_minutes,
  case when context.grade_band in ('高一','高二') then 3 else null end::smallint
    as max_question_level
from _assignment_context context
join _skill_catalog catalog
  on catalog.grade_band = context.grade_band and catalog.skill_id = context.classroom_skill
join _demo_skill_summaries summaries
  on summaries.grade_band = context.grade_band and summaries.skill_id = context.classroom_skill
where context.demo;

create temporary table _all_plan_assignment on commit drop as
select * from _plan_assignment
union all
select * from _demo_assignment;

-- Formal plans are the migration target for the full window. Existing demo
-- plans remain byte-for-byte unchanged (including any teacher-preview attempt);
-- demos receive only the four newly added dates on the safe legacy branch.
create temporary table _mutation_assignment on commit drop as
select * from _plan_assignment
union all
select * from _demo_assignment
where plan_date between date '2026-09-26' and date '2026-09-29';

-- Structural preconditions. These checks intentionally happen before the
-- first permanent-table write so an incomplete source import leaves every
-- existing plan untouched.
do $$
declare
  v_bad integer;
  v_expected integer;
begin
  if (select count(*) from _review_dates) <> 39
    or (select min(plan_date) from _review_dates) <> date '2026-08-22'
    or (select max(plan_date) from _review_dates) <> date '2026-09-29'
  then
    raise exception 'September REVIEW schedule must contain exactly 2026-08-22 through 2026-09-29';
  end if;

  select count(*) into v_bad
  from (
    select grade_band, count(*) as day_count
    from _grade_schedule
    group by grade_band
    having count(*) <> 39
  ) broken_grade;
  if v_bad <> 0 or (select count(distinct grade_band) from _grade_schedule) <> 3 then
    raise exception 'grade schedule is incomplete: % grade rows failed', v_bad;
  end if;

  select count(*) into v_bad
  from _grade_schedule schedule
  left join _skill_catalog skill
    on skill.grade_band = schedule.grade_band and skill.skill_id = schedule.skill_id
  where skill.skill_id is null;
  if v_bad <> 0 then
    raise exception 'grade schedule contains % unknown skills', v_bad;
  end if;

  select count(*) into v_bad
  from _schedule_students student
  where student.grade_band = '高一'
    and not student.demo
    and cardinality(student.confirmed_h1_skills) = 0;
  if v_bad <> 0 then
    raise exception 'High-1 summer scope is missing for % formal profiles', v_bad;
  end if;

  if (select count(*) from _schedule_students where daily_redox) <> 2 then
    raise exception 'daily-redox metadata gate must select exactly the two confirmed formal profiles';
  end if;

  select count(*) into v_bad
  from _schedule_students student
  where student.daily_redox
    and (
      not ('H1_REDOX' = any(student.confirmed_h1_skills))
      or student.non_redox_fallback is null
      or student.non_redox_fallback = 'H1_REDOX'
    );
  if v_bad <> 0 then
    raise exception 'daily-redox scope guard failed for % profiles', v_bad;
  end if;

  select count(*) into v_bad
  from _licensed_concept_groups grouped
  where grouped.concept_label is null or grouped.label_count <> 1;
  if v_bad <> 0 then
    raise exception 'licensed concept labels are missing or inconsistent for % concepts', v_bad;
  end if;

  select count(*) into v_bad
  from (
    select
      skill.grade_band,
      skill.skill_id,
      count(concept.concept_key) as concept_count
    from _skill_catalog skill
    left join _licensed_concepts concept
      on concept.grade_band = skill.grade_band and concept.skill_id = skill.skill_id
    group by skill.grade_band, skill.skill_id
    having count(concept.concept_key) <> 5
  ) broken_skill;
  if v_bad <> 0 then
    raise exception 'formal source capacity is incomplete: five fine concepts are missing for % skills', v_bad;
  end if;

  select count(*) into v_bad
  from (
    select
      demo_skill.grade_band,
      demo_skill.classroom_skill,
      count(distinct question.id) as safe_question_count
    from (
      select distinct grade_band, classroom_skill
      from _base_assignment
      where demo
    ) demo_skill
    left join public.chem_questions question
      on question.grade_band = demo_skill.grade_band
     and question.skill_id = demo_skill.classroom_skill
     and question.review_status = 'approved'
     and question.scope_status = 'IN'
     and question.source_kind = 'teacher_original'
     and question.usable_for_demo
    group by demo_skill.grade_band, demo_skill.classroom_skill
    having count(distinct question.id) < 5
  ) broken_demo_skill;
  if v_bad <> 0 then
    raise exception 'teacher-original demo pool has fewer than five safe questions for % skills', v_bad;
  end if;

  select count(*) into v_expected from _schedule_students;
  v_expected := v_expected * 39;
  if (select count(*) from _base_assignment) <> v_expected
    or (select count(*) from _assignment_context) <> v_expected
    or (select count(*) from _all_plan_assignment) <> v_expected
  then
    raise exception 'one or more student-days could not be built from the schedule catalogs';
  end if;

  select count(*) into v_expected
  from _schedule_students
  where not demo;
  v_expected := v_expected * 39;
  if (select count(*) from _plan_assignment) <> v_expected then
    raise exception 'one or more formal student-days could not be built from the exact concept catalog';
  end if;

  select count(*) into v_bad
  from (
    select
      assignment.student_id,
      assignment.plan_date,
      count(target.concept_key) as target_count,
      count(distinct target.concept_key) as distinct_target_count,
      count(distinct target.skill_id) as skill_count
    from _plan_assignment assignment
    left join _plan_targets target
      on target.student_id = assignment.student_id
     and target.plan_date = assignment.plan_date
    group by assignment.student_id, assignment.plan_date
    having count(target.concept_key) <> 5
      or count(distinct target.concept_key) <> 5
      or count(distinct target.skill_id) < 1
  ) broken_target_day;
  if v_bad <> 0 then
    raise exception 'exact five-concept target construction failed for % student-days', v_bad;
  end if;

  select count(*) into v_bad
  from _plan_assignment assignment
  where cardinality(assignment.target_concept_keys) <> 5
    or cardinality(assignment.knowledge_summaries) <> 5
    or cardinality(assignment.skill_ids) < 1
    or cardinality(assignment.skill_ids) > 2
    or assignment.title like '%薄弱%';
  if v_bad <> 0 then
    raise exception 'plan shape or honest diagnostic wording failed for % student-days', v_bad;
  end if;

  select count(*) into v_bad
  from _demo_assignment assignment
  where cardinality(assignment.target_concept_keys) <> 0
    or cardinality(assignment.knowledge_summaries) <> 5
    or cardinality(assignment.skill_ids) <> 1
    or assignment.assignment_reason <> 'demo_course';
  if v_bad <> 0 then
    raise exception 'safe legacy demo plan shape failed for % student-days', v_bad;
  end if;

  -- Every High-1 target before school opens must be explicitly confirmed in
  -- that profile. This is the data-driven guard for the 8/30 REDOX skeleton:
  -- students without REDOX confirmation receive GAS or another confirmed
  -- module, never a name-based exception.
  select count(*) into v_bad
  from _plan_targets target
  join _schedule_students student on student.student_id = target.student_id
  where student.grade_band = '高一'
    and not student.demo
    and target.plan_date < date '2026-09-01'
    and not (target.skill_id = any(student.confirmed_h1_skills));
  if v_bad <> 0 then
    raise exception 'High-1 confirmed summer scope was violated by % targets', v_bad;
  end if;

  select count(*) into v_bad
  from _assignment_context context
  where context.daily_redox and context.classroom_skill = 'H1_REDOX';
  if v_bad <> 0 then
    raise exception 'daily-redox profiles received a REDOX-only classroom day';
  end if;

  select count(*) into v_bad
  from (
    select
      context.student_id,
      context.plan_date,
      count(*) filter (where target.skill_id = 'H1_REDOX') as redox_count,
      count(*) filter (where target.skill_id <> 'H1_REDOX') as classroom_count
    from _assignment_context context
    join _plan_targets target
      on target.student_id = context.student_id and target.plan_date = context.plan_date
    where context.daily_redox
    group by context.student_id, context.plan_date
    having count(*) filter (where target.skill_id = 'H1_REDOX') <> 1
      or count(*) filter (where target.skill_id <> 'H1_REDOX') <> 4
  ) broken_daily_redox;
  if v_bad <> 0 then
    raise exception 'daily-redox 4+1 contract failed for % student-days', v_bad;
  end if;

  -- The fifth recovery target is evidence-backed when evidence exists. A
  -- diagnostic target is allowed only when there is no unresolved submitted
  -- concept available for that profile.
  select count(*) into v_bad
  from _assignment_context context
  join _plan_targets target
    on target.student_id = context.student_id
   and target.plan_date = context.plan_date
   and target.target_order = 5
  where context.assignment_reason = 'answer_evidence'
    and not exists (
      select 1
      from _unresolved_evidence evidence
      where evidence.student_id = context.student_id
        and evidence.concept_key = target.concept_key
    );
  if v_bad <> 0 then
    raise exception 'personal recovery target lacks submitted evidence for % student-days', v_bad;
  end if;

  select count(*) into v_bad
  from _assignment_context context
  where context.assignment_reason = 'classroom_diagnostic'
    and exists (
      select 1 from _unresolved_evidence evidence
      where evidence.student_id = context.student_id
    );
  if v_bad <> 0 then
    raise exception 'an evidenced profile was mislabeled as classroom diagnostic';
  end if;
end $$;

-- Read-only snapshots prove that the migration does not touch an earlier day,
-- another learning mode, an answer/attempt, or the independent quiz product.
create temporary table _preserved_plan_snapshot on commit drop as
select plan.id, to_jsonb(plan) as row_data
from public.chem_learning_plans plan
where not exists (
  select 1
  from _mutation_assignment assignment
  where assignment.student_id = plan.student_id
    and plan.mode = 'REVIEW'
    and assignment.plan_date = plan.plan_date
);

create temporary table _existing_window_identity on commit drop as
select
  plan.id,
  plan.student_id,
  plan.plan_date,
  plan.mode,
  plan.created_at
from public.chem_learning_plans plan
join _schedule_students student on student.student_id = plan.student_id
where plan.mode = 'REVIEW'
  and plan.plan_date between date '2026-08-22' and date '2026-09-25';

create temporary table _attempt_snapshot on commit drop as
select attempt.id, to_jsonb(attempt) as row_data
from public.chem_learning_attempts attempt;

create temporary table _answer_snapshot on commit drop as
select answer.id, to_jsonb(answer) as row_data
from public.chem_attempt_answers answer;

create temporary table _quiz_session_snapshot on commit drop as
select session.id, to_jsonb(session) as row_data
from public.quiz_sessions session;

do $$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from (
    select
      student.student_id,
      dates.plan_date,
      count(plan.id) as plan_count
    from _schedule_students student
    cross join _review_dates dates
    left join public.chem_learning_plans plan
      on plan.student_id = student.student_id
     and plan.mode = 'REVIEW'
     and plan.plan_date = dates.plan_date
    where dates.plan_date <= date '2026-09-25'
    group by student.student_id, dates.plan_date
    having count(plan.id) <> 1
  ) broken_existing_day;
  if v_bad <> 0 then
    raise exception 'existing future REVIEW calendar is missing or duplicated for % student-days', v_bad;
  end if;

  select count(*) into v_bad
  from public.chem_learning_plans plan
  join _schedule_students student on student.student_id = plan.student_id
  where plan.mode = 'REVIEW'
    and plan.plan_date between date '2026-09-26' and date '2026-09-29';
  if v_bad <> 0 then
    raise exception 'new September dates already contain % REVIEW plans; stopped instead of duplicating', v_bad;
  end if;

  select count(*) into v_bad
  from public.chem_learning_attempts attempt
  join public.chem_learning_plans plan on plan.id = attempt.plan_day_id
  join _mutation_assignment assignment
    on assignment.student_id = plan.student_id
   and assignment.plan_date = plan.plan_date
  where plan.mode = 'REVIEW';
  if v_bad <> 0 then
    raise exception 'a future REVIEW plan already has % attempts; stopped instead of rewriting started work', v_bad;
  end if;
end $$;

-- Candidate identities and complete REVIEW history are compared directly.
-- This funds every possible future round after removing anything the student
-- has already seen by question id, mother id, source item or fingerprint.
create temporary table _historical_identity on commit drop as
select
  attempt.student_id,
  answer.question_id,
  nullif(answer.mother_id, '') as mother_id,
  coalesce(
    nullif(answer.question_snapshot->>'sourceItemKey', ''),
    nullif(question.source_item_key, '')
  ) as source_item_key,
  coalesce(
    nullif(answer.question_snapshot->>'contentFingerprint', ''),
    nullif(question.content_fingerprint, '')
  ) as content_fingerprint
from public.chem_learning_attempts attempt
join _schedule_students student
  on student.student_id = attempt.student_id and not student.demo
join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
left join public.chem_questions question on question.id = answer.question_id
where attempt.mode = 'REVIEW'
  and attempt.completed_at is not null;

create temporary table _candidate_question on commit drop as
select
  q.id,
  q.mother_id,
  q.grade_band,
  q.skill_id,
  q.concept_key,
  q.level,
  q.source_item_key,
  q.content_fingerprint
from public.chem_questions q
where q.review_status = 'approved'
  and q.scope_status = 'IN'
  and q.usable_for_review
  and q.source_kind = 'licensed_local'
  and q.render_mode = 'image_primary'
  and q.source_release_id is not null
  and q.concept_key is not null
  and q.mother_id is not null
  and q.source_item_key is not null
  and q.content_fingerprint is not null
  and (q.grade_band = '高三' or q.level <= 3)
  and jsonb_typeof(q.asset_refs) = 'array'
  and exists (
    select 1 from jsonb_array_elements(q.asset_refs) asset
    where asset->>'kind' = 'question_image'
  )
  and exists (
    select 1 from jsonb_array_elements(q.asset_refs) asset
    where asset->>'kind' = 'analysis_image'
  );

create temporary table _future_concept_need on commit drop as
select
  target.student_id,
  student.grade_band,
  target.skill_id,
  target.concept_key,
  count(*)::integer as planned_visits,
  (count(*) * 5)::integer as required_fresh_originals
from _plan_targets target
join _schedule_students student on student.student_id = target.student_id
where not student.demo
group by target.student_id, student.grade_band, target.skill_id, target.concept_key;

create temporary table _remaining_concept_pool on commit drop as
select
  need.student_id,
  need.grade_band,
  need.skill_id,
  need.concept_key,
  count(candidate.id)::integer as remaining_originals,
  count(distinct candidate.level)::integer as remaining_level_count,
  array_agg(distinct candidate.level order by candidate.level) as remaining_levels
from _future_concept_need need
left join _candidate_question candidate
  on candidate.grade_band = need.grade_band
 and candidate.skill_id = need.skill_id
 and candidate.concept_key = need.concept_key
 and not exists (
   select 1
   from _historical_identity history
   where history.student_id = need.student_id
     and (
       history.question_id = candidate.id
       or history.mother_id = candidate.mother_id
       or history.source_item_key = candidate.source_item_key
       or history.content_fingerprint = candidate.content_fingerprint
     )
 )
group by need.student_id, need.grade_band, need.skill_id, need.concept_key;

do $$
declare
  v_bad integer;
begin
  -- Every eligible row in a planned concept must carry the complete source
  -- identity and the two audited images; otherwise the count would overstate
  -- what the access function can safely show.
  select count(*) into v_bad
  from public.chem_questions q
  join (
    select distinct grade_band, skill_id, concept_key
    from _future_concept_need
  ) needed
    on needed.grade_band = q.grade_band
   and needed.skill_id = q.skill_id
   and needed.concept_key = q.concept_key
  where q.review_status = 'approved'
    and q.scope_status = 'IN'
    and q.usable_for_review
    and q.source_kind = 'licensed_local'
    and q.render_mode = 'image_primary'
    and q.source_release_id is not null
    and (q.grade_band = '高三' or q.level <= 3)
    and not exists (
      select 1 from _candidate_question candidate where candidate.id = q.id
    );
  if v_bad <> 0 then
    raise exception 'planned source pool contains % incomplete licensed originals', v_bad;
  end if;

  -- Identity uniqueness is global within each grade's active pool. This
  -- prevents a source item mapped to two concepts from disappearing during
  -- source-level de-duplication and starving one target.
  select count(*) into v_bad
  from (
    select
      candidate.grade_band,
      count(*) as question_count,
      count(distinct candidate.id) as id_count,
      count(distinct candidate.mother_id) as mother_count,
      count(distinct candidate.source_item_key) as source_count,
      count(distinct candidate.content_fingerprint) as fingerprint_count
    from _candidate_question candidate
    join (
      select distinct grade_band, skill_id, concept_key
      from _future_concept_need
    ) needed
      on needed.grade_band = candidate.grade_band
     and needed.skill_id = candidate.skill_id
     and needed.concept_key = candidate.concept_key
    group by candidate.grade_band
    having count(*) <> count(distinct candidate.id)
      or count(*) <> count(distinct candidate.mother_id)
      or count(*) <> count(distinct candidate.source_item_key)
      or count(*) <> count(distinct candidate.content_fingerprint)
  ) duplicate_identity;
  if v_bad <> 0 then
    raise exception 'planned licensed pool repeats an id, mother, source item or fingerprint in % grades', v_bad;
  end if;

  select count(*) into v_bad
  from _future_concept_need need
  left join _remaining_concept_pool remaining
    on remaining.student_id = need.student_id
   and remaining.concept_key = need.concept_key
  where coalesce(remaining.remaining_originals, 0) < need.required_fresh_originals;
  if v_bad <> 0 then
    raise exception 'fresh-source capacity is insufficient for % student/concepts after history; plans were not changed', v_bad;
  end if;

  select count(*) into v_bad
  from _future_concept_need need
  join _remaining_concept_pool remaining
    on remaining.student_id = need.student_id
   and remaining.concept_key = need.concept_key
  where (
    need.grade_band in ('高一','高二')
      and not remaining.remaining_levels @> array[1,2,3]::smallint[]
  ) or (
    need.grade_band = '高三'
      and remaining.remaining_level_count < 2
  );
  if v_bad <> 0 then
    raise exception 'difficulty progression is insufficient for % student/concepts', v_bad;
  end if;

  select count(*) into v_bad
  from (
    select
      assigned.skill_id,
      count(card.id) as card_count,
      count(card.id) filter (
        where length(btrim(card.title)) > 0
          and length(btrim(card.core)) > 0
          and length(btrim(card.detail)) > 0
          and length(btrim(card.micro_example)) > 0
          and jsonb_typeof(card.structured_content) = 'object'
          and card.structured_content <> '{}'::jsonb
      ) as complete_count
    from (
      select distinct unnest(skill_ids) as skill_id
      from _mutation_assignment
    ) assigned
    left join public.chem_knowledge_cards card
      on card.skill_id = assigned.skill_id
     and card.review_status = 'approved'
    group by assigned.skill_id
    having count(card.id) <> 1
      or count(card.id) filter (
        where length(btrim(card.title)) > 0
          and length(btrim(card.core)) > 0
          and length(btrim(card.detail)) > 0
          and length(btrim(card.micro_example)) > 0
          and jsonb_typeof(card.structured_content) = 'object'
          and card.structured_content <> '{}'::jsonb
      ) <> 1
  ) broken_card;
  if v_bad <> 0 then
    raise exception 'approved structured knowledge card is incomplete for % assigned skills', v_bad;
  end if;
end $$;

-- Update the existing 35 days in place, preserving every plan id.
do $$
declare
  v_expected integer;
  v_updated integer;
begin
  select count(*) into v_expected
  from _mutation_assignment
  where plan_date <= date '2026-09-25';

  update public.chem_learning_plans plan
  set
    title = assignment.title,
    skill_ids = assignment.skill_ids,
    target_concept_keys = assignment.target_concept_keys,
    knowledge_summaries = assignment.knowledge_summaries,
    estimated_minutes = assignment.estimated_minutes,
    source = assignment.source,
    is_scheduled = true,
    question_count = 5,
    round_limit = 5,
    max_question_level = assignment.max_question_level
  from _mutation_assignment assignment
  where plan.student_id = assignment.student_id
    and plan.mode = 'REVIEW'
    and plan.plan_date = assignment.plan_date
    and assignment.plan_date <= date '2026-09-25';

  get diagnostics v_updated = row_count;
  if v_updated <> v_expected then
    raise exception 'future REVIEW update changed % rows; expected %', v_updated, v_expected;
  end if;
end $$;

-- Add only 2026-09-26..2026-09-29. The table default generates ids inside
-- the target database, so no student identifier or login data is embedded in
-- this repository.
do $$
declare
  v_expected integer;
  v_inserted integer;
begin
  select count(*) into v_expected
  from _mutation_assignment
  where plan_date between date '2026-09-26' and date '2026-09-29';

  insert into public.chem_learning_plans (
    student_id, plan_date, mode, title, skill_ids, target_concept_keys,
    knowledge_summaries, estimated_minutes, source, is_scheduled,
    question_count, round_limit, max_question_level
  )
  select
    assignment.student_id,
    assignment.plan_date,
    'REVIEW',
    assignment.title,
    assignment.skill_ids,
    assignment.target_concept_keys,
    assignment.knowledge_summaries,
    assignment.estimated_minutes,
    assignment.source,
    true,
    5,
    5,
    assignment.max_question_level
  from _mutation_assignment assignment
  where assignment.plan_date between date '2026-09-26' and date '2026-09-29';

  get diagnostics v_inserted = row_count;
  if v_inserted <> v_expected then
    raise exception 'September REVIEW insert changed % rows; expected %', v_inserted, v_expected;
  end if;
end $$;

-- Exact postconditions for calendar, curriculum order and privacy-safe demo.
do $$
declare
  v_bad integer;
  v_expected integer;
begin
  select count(*) into v_expected from _schedule_students;
  v_expected := v_expected * 39;

  select count(*) into v_bad
  from public.chem_learning_plans plan
  join _schedule_students student on student.student_id = plan.student_id
  where plan.mode = 'REVIEW'
    and plan.plan_date between date '2026-08-22' and date '2026-09-29';
  if v_bad <> v_expected then
    raise exception 'final REVIEW calendar contains % rows; expected %', v_bad, v_expected;
  end if;

  select count(*) into v_bad
  from _mutation_assignment assignment
  left join public.chem_learning_plans plan
    on plan.student_id = assignment.student_id
   and plan.mode = 'REVIEW'
   and plan.plan_date = assignment.plan_date
  where plan.id is null
    or plan.title is distinct from assignment.title
    or plan.skill_ids is distinct from assignment.skill_ids
    or plan.target_concept_keys is distinct from assignment.target_concept_keys
    or plan.knowledge_summaries is distinct from assignment.knowledge_summaries
    or plan.estimated_minutes is distinct from assignment.estimated_minutes
    or plan.source is distinct from assignment.source
    or plan.is_scheduled is distinct from true
    or plan.question_count is distinct from 5
    or plan.round_limit is distinct from 5
    or plan.max_question_level is distinct from assignment.max_question_level;
  if v_bad <> 0 then
    raise exception 'persisted REVIEW plan differs from assignment for % student-days', v_bad;
  end if;

  select count(*) into v_bad
  from _existing_window_identity before
  left join public.chem_learning_plans plan on plan.id = before.id
  where plan.id is null
    or plan.student_id is distinct from before.student_id
    or plan.plan_date is distinct from before.plan_date
    or plan.mode is distinct from before.mode
    or plan.created_at is distinct from before.created_at;
  if v_bad <> 0
    or (select count(*) from _existing_window_identity) <> (
      select count(*)
      from public.chem_learning_plans plan
      join _schedule_students student on student.student_id = plan.student_id
      where plan.mode = 'REVIEW'
        and plan.plan_date between date '2026-08-22' and date '2026-09-25'
    )
  then
    raise exception 'an existing future REVIEW plan id or identity changed';
  end if;

  -- Formal plans have exact targets owned by every listed skill.
  select count(*) into v_bad
  from public.chem_learning_plans plan
  join _schedule_students student on student.student_id = plan.student_id
  where not student.demo
    and plan.mode = 'REVIEW'
    and plan.plan_date between date '2026-08-22' and date '2026-09-29'
    and (
      cardinality(plan.target_concept_keys) <> 5
      or cardinality(plan.knowledge_summaries) <> 5
      or exists (
        select 1
        from unnest(plan.target_concept_keys) concept_key
        where not exists (
          select 1 from unnest(plan.skill_ids) skill_id
          where left(concept_key, length(skill_id) + 2) = skill_id || '__'
        )
      )
      or exists (
        select 1
        from unnest(plan.skill_ids) skill_id
        where not exists (
          select 1 from unnest(plan.target_concept_keys) concept_key
          where left(concept_key, length(skill_id) + 2) = skill_id || '__'
        )
      )
    );
  if v_bad <> 0 then
    raise exception 'formal target/skill ownership postcondition failed for % plans', v_bad;
  end if;

  -- Demo plans retain an empty target list, so the access path stays on its
  -- legacy skill-level branch. That branch is funded only by teacher originals.
  select count(*) into v_bad
  from public.chem_learning_plans plan
  join _schedule_students student
    on student.student_id = plan.student_id and student.demo
  where plan.mode = 'REVIEW'
    and plan.plan_date between date '2026-08-22' and date '2026-09-29'
    and (
      cardinality(plan.target_concept_keys) <> 0
      or cardinality(plan.knowledge_summaries) <> 5
      or cardinality(plan.skill_ids) <> 1
    );
  if v_bad <> 0 then
    raise exception 'persisted legacy demo shape failed for % plans', v_bad;
  end if;

  select count(*) into v_bad
  from (
    select
      plan.student_id,
      plan.plan_date,
      count(distinct question.id) as safe_count
    from public.chem_learning_plans plan
    join _schedule_students student
      on student.student_id = plan.student_id and student.demo
    cross join unnest(plan.skill_ids) as assigned_skill(skill_id)
    left join public.chem_questions question
      on question.grade_band = student.grade_band
     and question.skill_id = assigned_skill.skill_id
     and question.review_status = 'approved'
     and question.scope_status = 'IN'
     and question.source_kind = 'teacher_original'
     and question.usable_for_demo
    where plan.mode = 'REVIEW'
      and plan.plan_date between date '2026-08-22' and date '2026-09-29'
    group by plan.student_id, plan.plan_date
    having count(distinct question.id) < 5
  ) unsafe_demo_target;
  if v_bad <> 0 then
    raise exception 'teacher-original demo pool is short for % student-days', v_bad;
  end if;

  -- Curriculum gates after school opens.
  select count(*) into v_bad
  from _assignment_context context
  where not context.demo
    and context.grade_band = '高一'
    and context.plan_date >= date '2026-09-01'
    and context.classroom_skill not in (
      'H1_CLASSIFY','H1_REACTION_CLASSIFICATION','H1_MOLE_INTRO',
      'H1_SOLUTION_CONCENTRATION','H1_GAS_MOLAR_VOLUME'
    );
  if v_bad <> 0 then
    raise exception 'High-1 post-opening sequence jumped beyond Compulsory 1 Unit 1 on % days', v_bad;
  end if;

  select count(*) into v_bad
  from _assignment_context context
  where not context.demo
    and context.grade_band = '高二'
    and context.plan_date between date '2026-09-01' and date '2026-09-14'
    and context.classroom_skill not in ('H2_THERMO','H2_ELECTRO');
  if v_bad <> 0 then
    raise exception 'High-2 opening sequence left thermal/electrochemistry on % days', v_bad;
  end if;

  select count(*) into v_bad
  from _assignment_context context
  where not context.demo
    and context.grade_band = '高三'
    and context.day_index < 10
    and context.classroom_skill not in (
      'H3_ION_REDOX','H3_STOICH','H3_EXPERIMENT','H3_AQ',
      'H3_ELECTRO','H3_EQUILIBRIUM','H3_THERMO_RATE'
    );
  if v_bad <> 0 then
    raise exception 'High-3 opening sequence did not keep high-frequency error-prone content first';
  end if;
end $$;

-- Preservation assertions run after all intended writes.
do $$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from _preserved_plan_snapshot before
  left join public.chem_learning_plans plan on plan.id = before.id
  where plan.id is null or to_jsonb(plan) is distinct from before.row_data;
  if v_bad <> 0
    or (select count(*) from _preserved_plan_snapshot) <> (
      select count(*)
      from public.chem_learning_plans plan
      where not exists (
        select 1
        from _mutation_assignment assignment
        where assignment.student_id = plan.student_id
          and plan.mode = 'REVIEW'
          and assignment.plan_date = plan.plan_date
      )
    )
  then
    raise exception 'a past, out-of-window or non-REVIEW plan changed';
  end if;

  select count(*) into v_bad
  from _attempt_snapshot before
  left join public.chem_learning_attempts attempt on attempt.id = before.id
  where attempt.id is null or to_jsonb(attempt) is distinct from before.row_data;
  if v_bad <> 0
    or (select count(*) from _attempt_snapshot) <> (select count(*) from public.chem_learning_attempts)
  then
    raise exception 'chem_learning_attempts changed unexpectedly';
  end if;

  select count(*) into v_bad
  from _answer_snapshot before
  left join public.chem_attempt_answers answer on answer.id = before.id
  where answer.id is null or to_jsonb(answer) is distinct from before.row_data;
  if v_bad <> 0
    or (select count(*) from _answer_snapshot) <> (select count(*) from public.chem_attempt_answers)
  then
    raise exception 'chem_attempt_answers changed unexpectedly';
  end if;

  select count(*) into v_bad
  from _quiz_session_snapshot before
  left join public.quiz_sessions session on session.id = before.id
  where session.id is null or to_jsonb(session) is distinct from before.row_data;
  if v_bad <> 0
    or (select count(*) from _quiz_session_snapshot) <> (select count(*) from public.quiz_sessions)
  then
    raise exception 'independent quiz_sessions changed unexpectedly';
  end if;
end $$;

commit;
