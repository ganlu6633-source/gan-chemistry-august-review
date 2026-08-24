-- Publishes the production-dry-run REVIEW calendar after the expanded High-1
-- source release made the remaining window fully fundable.
--
-- Builds the formal REVIEW baseline for 2026-08-24..2026-09-29 from each
-- learner's own remaining source-original capacity.  It deliberately does not
-- assign a fixed five questions per day: a learner with 85 fresh originals is
-- spread across the 37 dates at two or three questions per day.
--
-- Runtime ownership boundary: chem_personalize_next_review_plan may replace
-- tomorrow's baseline targets after today's completion.  That RPC must
-- re-budget the still-unstarted suffix before deployment; see the final
-- contract check and the companion Vitest.  This candidate itself never
-- changes attempts, answers or independent quiz_sessions.

begin;

set transaction isolation level serializable;
set local lock_timeout = '5s';

select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('capacity-funded-formal-review-calendar', 0)
);

-- Prevent a question from becoming answer-locked while the future calendar is
-- being rebuilt.  An existing lock means the corresponding plan has started.
lock table app_private.chem_question_answer_locks in share mode;

-- Evidence and the independent quiz site are outside this migration's write
-- boundary.  Snapshot every row so the final assertion can prove that even an
-- accidental trigger-side mutation did not slip through.
create temporary table _attempt_before on commit drop as
select attempt.id, pg_catalog.to_jsonb(attempt) as row_data
from public.chem_learning_attempts attempt;

create unique index on _attempt_before(id);

create temporary table _answer_before on commit drop as
select answer.id, pg_catalog.to_jsonb(answer) as row_data
from public.chem_attempt_answers answer;

create unique index on _answer_before(id);

create temporary table _quiz_session_before on commit drop as
select session.id, pg_catalog.to_jsonb(session) as row_data
from public.quiz_sessions session;

create unique index on _quiz_session_before(id);

create temporary table _answer_lock_before on commit drop as
select
  answer_lock.student_id,
  answer_lock.plan_day_id,
  answer_lock.attempt_sequence,
  answer_lock.question_id,
  pg_catalog.to_jsonb(answer_lock) as row_data
from app_private.chem_question_answer_locks answer_lock;

create unique index on _answer_lock_before(
  student_id, plan_day_id, attempt_sequence, question_id
);

create temporary table _existing_plan_before on commit drop as
select plan.id, plan.student_id, plan.plan_date, plan.mode
from public.chem_learning_plans plan
join public.chem_students_v2 student on student.id = plan.student_id
where student.record_status = 'active'
  and student.grade_band in ('高一','高二','高三')
  and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb
  and plan.mode = 'REVIEW'
  and plan.plan_date between date '2026-08-24' and date '2026-09-29';

create unique index on _existing_plan_before(id);

do $$
begin
  if pg_catalog.to_regclass('app_private.chem_review_concept_catalog') is null then
    raise exception 'the reviewed 130-row concept catalog is required';
  end if;

  if (select count(*) from app_private.chem_review_concept_catalog) <> 130
     or (select count(*) from app_private.chem_review_concept_catalog where grade_band='高一') <> 35
     or (select count(*) from app_private.chem_review_concept_catalog where grade_band='高二') <> 40
     or (select count(*) from app_private.chem_review_concept_catalog where grade_band='高三') <> 55
     or exists (
       select 1
       from app_private.chem_review_concept_catalog catalog
       where catalog.concept_label = catalog.concept_key
          or catalog.concept_label ~ '^H[123]_[A-Z0-9_]+__C0[1-5]$'
     )
  then
    raise exception 'the reviewed 130-row concept catalog is incomplete or exposes raw keys';
  end if;
end $$;

create temporary table _formal_students on commit drop as
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
  end as confirmed_h1_skills,
  (37 + ((pg_catalog.hashtextextended(student.id::text, 0) % 37 + 37) % 37)) % 37
    as date_rotation
from public.chem_students_v2 student
where student.record_status = 'active'
  and student.grade_band in ('高一','高二','高三')
  and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb;

create unique index on _formal_students(student_id);

create temporary table _review_dates on commit drop as
select
  day::date as plan_date,
  (day::date - date '2026-08-24')::integer as day_index,
  37::integer as date_count
from pg_catalog.generate_series(
  date '2026-08-24', date '2026-09-29', interval '1 day'
) day;

create unique index on _review_dates(plan_date);

do $$
begin
  if (select count(*) from _review_dates) <> 37
     or (select min(plan_date) from _review_dates) <> date '2026-08-24'
     or (select max(plan_date) from _review_dates) <> date '2026-09-29'
  then
    raise exception 'the REVIEW window must contain exactly 37 dates';
  end if;

  if exists (
    select 1
    from _formal_students student
    where student.grade_band = '高一'
      and pg_catalog.cardinality(student.confirmed_h1_skills) = 0
  ) then
    raise exception 'a formal High-1 learner has no confirmed pre-school scope';
  end if;
end $$;

-- Curriculum order is stable; the learner hash rotates the starting point.
-- It never changes the meaning of a concept or imports a source-ingest label.
create temporary table _course_order (
  grade_band text not null,
  skill_id text primary key,
  skill_order smallint not null,
  unique (grade_band, skill_order)
) on commit drop;

insert into _course_order (grade_band, skill_id, skill_order) values
  ('高一','H1_CLASSIFY',1),
  ('高一','H1_PERIODIC',2),
  ('高一','H1_MOLE_INTRO',3),
  ('高一','H1_GAS_MOLAR_VOLUME',4),
  ('高一','H1_REDOX',5),
  ('高一','H1_REACTION_CLASSIFICATION',6),
  ('高一','H1_SOLUTION_CONCENTRATION',7),
  -- Jiangsu Selective Compulsory 1 course spine only.
  ('高二','H2_THERMO',1),
  ('高二','H2_RATE',2),
  ('高二','H2_EQUIL',3),
  ('高二','H2_K',4),
  ('高二','H2_WEAK',5),
  ('高二','H2_PH_HYDRO',6),
  ('高二','H2_KSP',7),
  ('高二','H2_ELECTRO',8),
  -- High-3 error-prone/high-frequency exam spine first.
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

do $$
begin
  if (select count(*) from _course_order) <> 26
     or exists (
       select 1
       from app_private.chem_review_concept_catalog catalog
       left join _course_order course on course.skill_id = catalog.skill_id
       where course.skill_id is null or course.grade_band <> catalog.grade_band
     )
  then
    raise exception 'the grade curriculum order does not cover the reviewed catalog';
  end if;
end $$;

-- Any answered identity is already used, even if a legacy attempt did not
-- receive completed_at.  Identity is recovered from the immutable snapshot
-- first and from the current question row only as a legacy fallback.
create temporary table _used_identity on commit drop as
with identity_rows as (
  select
    attempt.student_id,
    answer.question_id,
    answer.mother_id,
    coalesce(
      nullif(answer.question_snapshot->>'sourceItemKey', ''),
      nullif(question.source_item_key, '')
    ) as source_item_key,
    coalesce(
      nullif(answer.question_snapshot->>'contentFingerprint', ''),
      nullif(question.content_fingerprint, '')
    ) as content_fingerprint
  from public.chem_learning_attempts attempt
  join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
  left join public.chem_questions question on question.id = answer.question_id
  join _formal_students student on student.student_id = attempt.student_id
  where attempt.mode = 'REVIEW'

  union all

  select
    answer_lock.student_id,
    answer_lock.question_id,
    question.mother_id,
    question.source_item_key,
    question.content_fingerprint
  from app_private.chem_question_answer_locks answer_lock
  join public.chem_questions question on question.id = answer_lock.question_id
  join _formal_students student on student.student_id = answer_lock.student_id
)
select distinct * from identity_rows;

create index on _used_identity(student_id, question_id);
create index on _used_identity(student_id, mother_id);
create index on _used_identity(student_id, source_item_key);
create index on _used_identity(student_id, content_fingerprint);

-- The selector treats difficulty direction as a hard eligibility rule.  A
-- mastered concept can only use a strictly harder fresh original; an error or
-- uncertainty can only use the same or an easier level.  Concepts with no
-- compatible next level are omitted from the future spine.
create temporary table _latest_concept_state on commit drop as
with ranked as (
  select
    attempt.student_id,
    coalesce(
      nullif(answer.concept_key, ''),
      nullif(answer.question_snapshot->>'conceptKey', ''),
      question.concept_key
    ) as concept_key,
    answer.correct,
    answer.uncertain,
    coalesce(
      nullif(answer.question_snapshot->>'level', '')::integer,
      answer.level,
      question.level
    )::integer as question_level,
    row_number() over (
      partition by attempt.student_id, coalesce(
        nullif(answer.concept_key, ''),
        nullif(answer.question_snapshot->>'conceptKey', ''),
        question.concept_key
      )
      order by coalesce(attempt.completed_at, attempt.started_at) desc,
        attempt.sequence desc, answer.id desc
    ) as latest_rank
  from public.chem_learning_attempts attempt
  join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
  left join public.chem_questions question on question.id = answer.question_id
  join _formal_students student on student.student_id = attempt.student_id
  where attempt.mode = 'REVIEW'
)
select student_id, concept_key, correct, uncertain, question_level
from ranked
where latest_rank = 1 and concept_key is not null;

-- First-pass coverage is satisfied by either a real historical REVIEW answer
-- or one future target in this 37-day window.  Answer locks are deliberately
-- absent: issuing a question is not the same as the learner answering it.
create temporary table _required_first_pass (
  student_id uuid not null,
  concept_key text not null,
  primary key (student_id, concept_key)
) on commit drop;

insert into _required_first_pass (student_id, concept_key)
select student.student_id, catalog.concept_key
from _formal_students student
join app_private.chem_review_concept_catalog catalog
  on catalog.grade_band = student.grade_band
 and (
   student.grade_band <> '高一'
   or catalog.skill_id = any(student.confirmed_h1_skills)
 )
where not exists (
  select 1
  from _latest_concept_state historical
  where historical.student_id = student.student_id
    and historical.concept_key = catalog.concept_key
);

-- Only the single active release of each grade can fund the calendar.
create temporary table _fresh_original on commit drop as
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
  course.skill_order
from _formal_students student
join app_private.chem_question_source_releases release
  on release.grade_band = student.grade_band
 and release.status = 'active'
 and release.verification_status = 'full_visual_verified'
join public.chem_questions question
  on question.source_release_id = release.id
 and question.grade_band = student.grade_band
join app_private.chem_review_concept_catalog catalog
  on catalog.grade_band = question.grade_band
 and catalog.skill_id = question.skill_id
 and catalog.concept_key = question.concept_key
join _course_order course
  on course.grade_band = question.grade_band
 and course.skill_id = question.skill_id
left join _latest_concept_state latest
  on latest.student_id = student.student_id
 and latest.concept_key = question.concept_key
where question.review_status = 'approved'
  and question.scope_status = 'IN'
  and question.usable_for_review
  and question.source_kind = 'licensed_local'
  and question.render_mode = 'image_primary'
  and question.mother_id is not null
  and question.source_item_key is not null
  and question.content_fingerprint is not null
  and exists (
    select 1
    from pg_catalog.jsonb_array_elements(question.asset_refs) asset
    where asset->>'kind' = 'question_image'
  )
  and exists (
    select 1
    from pg_catalog.jsonb_array_elements(question.asset_refs) asset
    where asset->>'kind' = 'analysis_image'
  )
  and (
    student.grade_band <> '高一'
    or question.skill_id = any(student.confirmed_h1_skills)
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
    from _used_identity used
    where used.student_id = student.student_id
      and (
        used.question_id = question.id
        or used.mother_id = question.mother_id
        or used.source_item_key = question.source_item_key
        or used.content_fingerprint = question.content_fingerprint
      )
  );

create index on _fresh_original(student_id, concept_key);

do $$
begin
  if (
    select count(*)
    from app_private.chem_question_source_releases release
    where release.grade_band in ('高一','高二','高三')
      and release.status='active'
      and release.verification_status='full_visual_verified'
  ) <> 3 then
    raise exception 'exactly one active source release per high-school grade is required';
  end if;

  if exists (
    select 1
    from _fresh_original fresh
    group by fresh.student_id
    having count(*) <> count(distinct fresh.question_id)
       or count(*) <> count(distinct fresh.mother_id)
       or count(*) <> count(distinct fresh.source_item_key)
       or count(*) <> count(distinct fresh.content_fingerprint)
  ) then
    raise exception 'fresh source identities are not one-to-one for a learner';
  end if;
end $$;

create temporary table _remaining_capacity (
  student_id uuid not null,
  grade_band text not null,
  skill_id text not null,
  concept_key text not null,
  concept_order smallint not null,
  concept_label text not null,
  skill_order smallint not null,
  initial_questions integer not null,
  remaining_questions integer not null,
  reserved_questions integer not null,
  primary key (student_id, concept_key)
) on commit drop;

insert into _remaining_capacity (
  student_id, grade_band, skill_id, concept_key,
  concept_order, concept_label, skill_order,
  initial_questions, remaining_questions, reserved_questions
)
select
  fresh.student_id,
  fresh.grade_band,
  fresh.skill_id,
  fresh.concept_key,
  fresh.concept_order,
  fresh.concept_label,
  fresh.skill_order,
  count(*)::integer,
  count(*)::integer,
  0
from _fresh_original fresh
group by fresh.student_id, fresh.grade_band, fresh.skill_id,
  fresh.concept_key, fresh.concept_order, fresh.concept_label, fresh.skill_order;

create temporary table _student_capacity on commit drop as
select
  student.student_id,
  student.grade_band,
  student.confirmed_h1_skills,
  student.date_rotation,
  -- A fine concept can appear only once in one daily package, so more than 37
  -- compatible originals for one concept cannot fund more than 37 dates.
  coalesce(sum(least(capacity.initial_questions, 37)), 0)::integer as fresh_questions,
  count(capacity.concept_key)::integer as fresh_concepts,
  -- Preserve twenty percent source headroom for evidence-driven replacement.
  -- Baseline dates use at most seven questions; runtime may still raise the
  -- immediate wrong/uncertain anchor to the formal maximum of eight.
  greatest(
    37,
    count(capacity.concept_key)::integer,
    least(
      floor(coalesce(sum(least(capacity.initial_questions, 37)), 0) * 0.80)::integer,
      37 * least(7, count(capacity.concept_key)::integer)
    )
  ) as scheduled_questions
from _formal_students student
left join _remaining_capacity capacity on capacity.student_id = student.student_id
group by student.student_id, student.grade_band,
  student.confirmed_h1_skills, student.date_rotation;

do $$
begin
  if exists (
    select 1 from _student_capacity where fresh_questions < 37
  ) then
    raise exception 'a formal learner has fewer than one fresh original per remaining date';
  end if;

  -- First-pass is a hard curriculum contract, not a best-effort rotation.
  -- Every allowed concept not already answered historically must have at
  -- least one compatible original before any formal plan is written.  Across
  -- history + this window that means H1 confirmed scope, all H2=40 concepts,
  -- and all H3=55 concepts.
  if exists (
    select 1
    from _required_first_pass required
    where not exists (
      select 1
      from _remaining_capacity capacity
      where capacity.student_id = required.student_id
        and capacity.concept_key = required.concept_key
        and capacity.initial_questions > 0
    )
  ) then
    raise exception 'first-pass catalog concept has no compatible fresh original';
  end if;
end $$;

-- Divide each personal capacity evenly across the 37 days.  The hash rotates
-- which dates receive the +1, so two learners with the same capacity need not
-- receive identical daily loads.  The result is always in 1..8.
create temporary table _daily_load on commit drop as
select
  student.student_id,
  student.grade_band,
  dates.plan_date,
  dates.day_index,
  (
    student.scheduled_questions / dates.date_count
    + case
        when mod(dates.day_index + student.date_rotation, dates.date_count)
          < mod(student.scheduled_questions, dates.date_count)
        then 1 else 0
      end
  )::smallint as question_count
from _student_capacity student
cross join _review_dates dates;

do $$
begin
  if exists (select 1 from _daily_load where question_count not between 1 and 8)
     or exists (
       select 1
       from _daily_load daily
       group by daily.student_id
       having count(*) <> 37
          or sum(daily.question_count) <> (
            select capacity.scheduled_questions
            from _student_capacity capacity
            where capacity.student_id = daily.student_id
          )
     )
  then
    raise exception 'personal daily-load allocation failed';
  end if;
end $$;

create temporary table _plan_targets (
  student_id uuid not null,
  plan_date date not null,
  target_order smallint not null,
  skill_id text not null,
  concept_key text not null,
  concept_label text not null,
  primary key (student_id, plan_date, target_order),
  unique (student_id, plan_date, concept_key)
) on commit drop;

-- Reserve one still-fresh original for every target occurrence.  High-1 is
-- always hard-filtered by confirmedLearnedSkillIds; advancing to a newly
-- taught Compulsory-1 skill therefore requires the teacher/course workflow to
-- confirm that skill first.  A shortage aborts the transaction.
do $$
declare
  v_student record;
  v_day record;
  v_position integer;
  v_target record;
  v_skill_count integer;
  v_skill_rotation integer;
begin
  for v_student in
    select * from _student_capacity order by student_id
  loop
    select count(*) into v_skill_count
    from _course_order course
    where course.grade_band = v_student.grade_band;

    for v_day in
      select daily.*
      from _daily_load daily
      where daily.student_id = v_student.student_id
      order by daily.plan_date
    loop
      v_skill_rotation := mod(
        v_day.day_index + v_student.date_rotation,
        v_skill_count
      );

      for v_position in 1..v_day.question_count loop
        select capacity.*
        into v_target
        from _remaining_capacity capacity
        where capacity.student_id = v_student.student_id
          and capacity.remaining_questions > 0
          and not exists (
            select 1
            from _plan_targets target
            where target.student_id = v_student.student_id
              and target.plan_date = v_day.plan_date
              and target.concept_key = capacity.concept_key
          )
          and (
            v_student.grade_band <> '高一'
            or capacity.skill_id = any(v_student.confirmed_h1_skills)
          )
        order by
          case
            when capacity.reserved_questions = 0
             and exists (
               select 1
               from _required_first_pass required
               where required.student_id = capacity.student_id
                 and required.concept_key = capacity.concept_key
             )
            then 0 else 1
          end,
          mod(capacity.skill_order - 1 - v_skill_rotation + v_skill_count, v_skill_count),
          mod(
            capacity.concept_order - 1 -
              mod(v_day.day_index + v_position + v_student.date_rotation, 5)
              + 5,
            5
          ),
          capacity.reserved_questions,
          capacity.concept_key
        limit 1
        for update;

        if not found then
          raise exception 'fresh concept capacity exhausted for a learner on %',
            v_day.plan_date;
        end if;

        insert into _plan_targets (
          student_id, plan_date, target_order,
          skill_id, concept_key, concept_label
        ) values (
          v_student.student_id, v_day.plan_date, v_position,
          v_target.skill_id, v_target.concept_key, v_target.concept_label
        );

        update _remaining_capacity capacity
        set
          remaining_questions = capacity.remaining_questions - 1,
          reserved_questions = capacity.reserved_questions + 1
        where capacity.student_id = v_student.student_id
          and capacity.concept_key = v_target.concept_key;
      end loop;
    end loop;
  end loop;
end $$;

-- Before any INSERT/UPDATE, assert that the 37-day target set actually gives
-- every still-unanswered in-scope concept its required first encounter.  With
-- historical answers included, the contract retains the full H2=40 and H3=55
-- catalogs while respecting each H1 confirmed-skill subset.
do $$
begin
  if exists (
    select 1
    from _required_first_pass required
    where not exists (
      select 1
      from _plan_targets target
      where target.student_id = required.student_id
        and target.concept_key = required.concept_key
    )
  ) then
    raise exception 'first-pass concept coverage missing from the 37-day REVIEW targets';
  end if;
end $$;

create temporary table _plan_assignment on commit drop as
select
  daily.student_id,
  daily.grade_band,
  daily.plan_date,
  daily.question_count,
  array(
    select skill.skill_id
    from (
      select owned.skill_id, min(owned.target_order) as first_target_order
      from _plan_targets owned
      where owned.student_id = daily.student_id
        and owned.plan_date = daily.plan_date
      group by owned.skill_id
    ) skill
    order by skill.first_target_order, skill.skill_id
  ) as skill_ids,
  array_agg(target.concept_key order by target.target_order) as target_concept_keys,
  array_agg(target.concept_label order by target.target_order) as knowledge_summaries
from _daily_load daily
join _plan_targets target
  on target.student_id = daily.student_id
 and target.plan_date = daily.plan_date
group by daily.student_id, daily.grade_band, daily.plan_date, daily.question_count;

do $$
begin
  if (select count(*) from _plan_assignment)
       <> (select count(*) from _formal_students) * 37
     or exists (
       select 1
       from _plan_assignment assignment
       where assignment.question_count not between 1 and 8
          or pg_catalog.cardinality(assignment.skill_ids) not between 1 and assignment.question_count
          or pg_catalog.cardinality(assignment.target_concept_keys) <> assignment.question_count
          or pg_catalog.cardinality(assignment.knowledge_summaries) <> assignment.question_count
          or (
            select count(distinct target.concept_key)
            from pg_catalog.unnest(assignment.target_concept_keys) target(concept_key)
          ) <> assignment.question_count
          or exists (
            select 1
            from pg_catalog.unnest(assignment.knowledge_summaries) label
            where label ~ '^H[123]_[A-Z0-9_]+__C0[1-5]$'
          )
     )
     or exists (
       select 1
       from _remaining_capacity capacity
       where capacity.reserved_questions > capacity.initial_questions
          or capacity.remaining_questions < 0
     )
  then
    raise exception 'capacity-funded assignment contract failed';
  end if;
end $$;

-- Fail closed instead of rewriting a plan that a learner has opened.
do $$
begin
  if exists (
    select 1
    from public.chem_learning_attempts attempt
    join public.chem_learning_plans plan on plan.id = attempt.plan_day_id
    join _formal_students student on student.student_id = plan.student_id
    where plan.mode = 'REVIEW'
      and plan.plan_date between date '2026-08-24' and date '2026-09-29'
  ) then
    raise exception 'the publish window contains a started REVIEW plan';
  end if;

  if exists (
    select 1
    from app_private.chem_question_answer_locks answer_lock
    join public.chem_learning_plans plan on plan.id = answer_lock.plan_day_id
    join _formal_students student on student.student_id = plan.student_id
    where plan.mode = 'REVIEW'
      and plan.plan_date between date '2026-08-24' and date '2026-09-29'
  ) then
    raise exception 'the publish window contains an answer-locked REVIEW plan';
  end if;

  if exists (
    select plan.student_id, plan.plan_date
    from public.chem_learning_plans plan
    join _formal_students student on student.student_id = plan.student_id
    where plan.mode='REVIEW'
      and plan.plan_date between date '2026-08-24' and date '2026-09-29'
    group by plan.student_id, plan.plan_date
    having count(*) > 1
  ) then
    raise exception 'a learner/date already contains duplicate REVIEW plans';
  end if;
end $$;

insert into public.chem_learning_plans (
  student_id, plan_date, mode, title,
  skill_ids, target_concept_keys, knowledge_summaries,
  estimated_minutes, source, is_scheduled,
  question_count, round_limit, max_question_level
)
select
  assignment.student_id,
  assignment.plan_date,
  'REVIEW',
  '个性化复习｜容量校准',
  assignment.skill_ids,
  assignment.target_concept_keys,
  assignment.knowledge_summaries,
  least(30, greatest(8, assignment.question_count * 4))::smallint,
  'mixed',
  true,
  assignment.question_count,
  1,
  null
from _plan_assignment assignment
where not exists (
  select 1
  from public.chem_learning_plans plan
  where plan.student_id = assignment.student_id
    and plan.plan_date = assignment.plan_date
    and plan.mode = 'REVIEW'
);

update public.chem_learning_plans plan
set
  title = '个性化复习｜容量校准',
  skill_ids = assignment.skill_ids,
  target_concept_keys = assignment.target_concept_keys,
  knowledge_summaries = assignment.knowledge_summaries,
  estimated_minutes = least(30, greatest(8, assignment.question_count * 4))::smallint,
  source = 'mixed',
  is_scheduled = true,
  question_count = assignment.question_count,
  round_limit = 1,
  max_question_level = null
from _plan_assignment assignment
where plan.student_id = assignment.student_id
  and plan.plan_date = assignment.plan_date
  and plan.mode = 'REVIEW';

do $$
begin
  if exists (
    select 1
    from _plan_assignment assignment
    left join public.chem_learning_plans plan
      on plan.student_id = assignment.student_id
     and plan.plan_date = assignment.plan_date
     and plan.mode = 'REVIEW'
    where plan.id is null
       or plan.question_count is distinct from assignment.question_count
       or plan.round_limit <> 1
       or plan.skill_ids is distinct from assignment.skill_ids
       or plan.target_concept_keys is distinct from assignment.target_concept_keys
       or plan.knowledge_summaries is distinct from assignment.knowledge_summaries
  ) or exists (
    select plan.student_id, plan.plan_date
    from public.chem_learning_plans plan
    join _formal_students student on student.student_id = plan.student_id
    where plan.mode='REVIEW'
      and plan.plan_date between date '2026-08-24' and date '2026-09-29'
    group by plan.student_id, plan.plan_date
    having count(*) <> 1
  ) then
    raise exception 'the persisted formal REVIEW calendar differs from its funded assignment';
  end if;

  if exists (
    select 1
    from (
      select target.student_id, target.concept_key, count(*)::integer as reserved
      from _plan_targets target
      group by target.student_id, target.concept_key
    ) target_count
    left join (
      select
        fresh.student_id,
        fresh.concept_key,
        count(distinct fresh.question_id)::integer as questions,
        count(distinct fresh.mother_id)::integer as mothers,
        count(distinct fresh.source_item_key)::integer as sources,
        count(distinct fresh.content_fingerprint)::integer as fingerprints
      from _fresh_original fresh
      group by fresh.student_id, fresh.concept_key
    ) fresh_count
      on fresh_count.student_id = target_count.student_id
     and fresh_count.concept_key = target_count.concept_key
    where target_count.reserved > coalesce(fresh_count.questions, 0)
       or target_count.reserved > coalesce(fresh_count.mothers, 0)
       or target_count.reserved > coalesce(fresh_count.sources, 0)
       or target_count.reserved > coalesce(fresh_count.fingerprints, 0)
  ) then
    raise exception 'a future target occurrence is not funded by a different original';
  end if;
end $$;

-- Retry compensation jobs only after the complete funded suffix exists.  The
-- RPC records failures instead of inventing or repeating a question; the
-- final assertion rejects the two implementation failures this migration is
-- designed to eliminate.
create temporary table _personalization_retry on commit drop as
select succeeded, status, last_error
from public.chem_retry_pending_review_personalization(25);

do $$
begin
  if exists (
    select 1
    from _personalization_retry retry
    where retry.status = 'pending'
       or retry.last_error in (
         'permission denied for table chem_question_answer_locks',
         'suffix_concept_capacity_shortage'
       )
  ) or exists (
    select 1
    from app_private.review_plan_personalization_jobs job
    where job.status = 'pending'
      and job.last_error in (
        'permission denied for table chem_question_answer_locks',
        'suffix_concept_capacity_shortage'
      )
  ) then
    raise exception 'known REVIEW personalization compensation failure remains';
  end if;

  if exists (
    select before.id
    from _existing_plan_before before
    left join public.chem_learning_plans plan on plan.id = before.id
    where plan.id is null
       or plan.student_id is distinct from before.student_id
       or plan.plan_date is distinct from before.plan_date
       or plan.mode is distinct from before.mode
  ) then
    raise exception 'an existing REVIEW plan identity changed unexpectedly';
  end if;

  if exists (
    select 1
    from public.chem_learning_plans plan
    join _formal_students student on student.student_id = plan.student_id
    where plan.mode = 'REVIEW'
      and plan.plan_date between date '2026-08-24' and date '2026-09-29'
      and (
        plan.question_count not between 1 and 8
        or plan.round_limit <> 1
        or plan.source <> 'mixed'
        or pg_catalog.cardinality(plan.skill_ids) not between 1 and plan.question_count
        or pg_catalog.cardinality(plan.target_concept_keys) <> plan.question_count
        or pg_catalog.cardinality(plan.knowledge_summaries) <> plan.question_count
        or (
          select count(distinct target.concept_key)
          from pg_catalog.unnest(plan.target_concept_keys) target(concept_key)
        ) <> plan.question_count
        or exists (
          select 1
          from pg_catalog.unnest(plan.target_concept_keys)
            with ordinality as target(concept_key, position)
          left join app_private.chem_review_concept_catalog catalog
            on catalog.grade_band = student.grade_band
           and catalog.concept_key = target.concept_key
          where catalog.concept_key is null
             or not (catalog.skill_id = any(plan.skill_ids))
             or plan.knowledge_summaries[target.position] <> catalog.concept_label
        )
      )
  ) then
    raise exception 'final REVIEW calendar semantic contract failed';
  end if;

  if (select count(*) from public.chem_learning_attempts)
       <> (select count(*) from _attempt_before)
     or exists (
       select before.id
       from _attempt_before before
       left join public.chem_learning_attempts attempt on attempt.id = before.id
       where attempt.id is null
          or pg_catalog.to_jsonb(attempt) is distinct from before.row_data
     )
  then
    raise exception 'learning attempts changed unexpectedly';
  end if;

  if (select count(*) from public.chem_attempt_answers)
       <> (select count(*) from _answer_before)
     or exists (
       select before.id
       from _answer_before before
       left join public.chem_attempt_answers answer on answer.id = before.id
       where answer.id is null
          or pg_catalog.to_jsonb(answer) is distinct from before.row_data
     )
  then
    raise exception 'learning answers changed unexpectedly';
  end if;

  if (select count(*) from public.quiz_sessions)
       <> (select count(*) from _quiz_session_before)
     or exists (
       select before.id
       from _quiz_session_before before
       left join public.quiz_sessions session on session.id = before.id
       where session.id is null
          or pg_catalog.to_jsonb(session) is distinct from before.row_data
     )
  then
    raise exception 'independent quiz_sessions changed unexpectedly';
  end if;

  if (select count(*) from app_private.chem_question_answer_locks)
       <> (select count(*) from _answer_lock_before)
     or exists (
       select 1
       from _answer_lock_before before
       left join app_private.chem_question_answer_locks answer_lock
         on answer_lock.student_id = before.student_id
        and answer_lock.plan_day_id = before.plan_day_id
        and answer_lock.attempt_sequence = before.attempt_sequence
        and answer_lock.question_id = before.question_id
       where answer_lock.question_id is null
          or pg_catalog.to_jsonb(answer_lock) is distinct from before.row_data
     )
  then
    raise exception 'issued answer locks changed unexpectedly';
  end if;
end $$;

commit;
