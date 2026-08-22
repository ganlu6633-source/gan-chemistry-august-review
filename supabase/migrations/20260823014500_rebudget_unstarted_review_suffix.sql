-- Applied server-side suffix re-budgeter for the runtime REVIEW
-- personalizer.  This file is intentionally separate from the public
-- chem_personalize_next_review_plan candidate and defines no function with the
-- same name.
--
-- Required caller contract:
--   1. Build tomorrow's unique wrong/uncertain-first concept array in memory.
--   2. Do NOT update tomorrow's plan directly.
--   3. Call app_private.chem_rebudget_unstarted_review_suffix(student, plan,
--      concepts).  It atomically fixes that anchor and re-plans every later,
--      unstarted REVIEW through 2026-09-29.
--   4. On {ok:false}, return false without raising.  Raising in the caller
--      would roll back the teacher-visible shortage row as well.
--   5. On {ok:true}, the caller may update title only; it must not replace the
--      three funded arrays.

begin;

create table if not exists app_private.chem_review_capacity_shortages (
  id bigint generated always as identity primary key,
  student_id uuid not null references public.chem_students_v2(id) on delete restrict,
  anchor_date date not null,
  reason_code text not null,
  detail jsonb not null default '{}'::jsonb
    check (pg_catalog.jsonb_typeof(detail) = 'object'),
  created_at timestamptz not null default pg_catalog.now(),
  resolved_at timestamptz,
  check (pg_catalog.length(pg_catalog.btrim(reason_code)) between 3 and 80)
);

alter table app_private.chem_review_capacity_shortages enable row level security;
revoke all on table app_private.chem_review_capacity_shortages
  from public, anon, authenticated;
grant select on table app_private.chem_review_capacity_shortages to service_role;

create unique index if not exists chem_review_capacity_shortages_open_uidx
  on app_private.chem_review_capacity_shortages(student_id, anchor_date, reason_code)
  where resolved_at is null;

comment on table app_private.chem_review_capacity_shortages is
  'Server-only teacher readiness queue. A row means suffix personalization was refused without changing any learning plan.';

create or replace function app_private.chem_rebudget_unstarted_review_suffix(
  p_student_id uuid,
  p_anchor_plan_id uuid,
  p_anchor_concept_keys text[]
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_grade_band text;
  v_anchor_date date;
  v_anchor_question_count integer;
  v_confirmed_h1_skills text[] := array[]::text[];
  v_expected_plan_count integer;
  v_required_questions integer;
  v_fresh_questions integer;
  v_remaining_plan_count integer;
  v_remaining_question_budget integer;
  v_base_daily_count integer;
  v_extra_daily_days integer;
  v_daily_offset integer;
  v_first_pass_concepts integer;
  v_unfunded_first_pass_concepts integer;
  v_uncovered_first_pass_concepts integer;
  v_reason text := 'unexpected_suffix_rebudget_error';
  v_detail jsonb := '{}'::jsonb;
  v_plan record;
  v_position integer;
  v_target record;
  v_desired_concept text;
  v_desired_skill text;
  v_skill_count integer;
  v_skill_rotation integer;
  v_updated_plans integer;
  v_conflict_date date;
begin
  -- An Edge RPC transaction may retry the personalizer or personalize more
  -- than one learner on the same pooled connection.  ON COMMIT DROP alone is
  -- insufficient in that case, so clear only this helper's private worktables
  -- before every invocation.
  drop table if exists
    pg_temp._suffix_plan_arrays,
    pg_temp._suffix_assignment,
    pg_temp._suffix_capacity,
    pg_temp._suffix_fresh_original,
    pg_temp._suffix_raw_fresh_original,
    pg_temp._suffix_latest_concept_state,
    pg_temp._suffix_required_first_pass,
    pg_temp._suffix_used_identity,
    pg_temp._suffix_course_order,
    pg_temp._suffix_plans;

  if p_student_id is null or p_anchor_plan_id is null then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'reasonCode', 'invalid_rebudget_input'
    );
  end if;

  select
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
    end
  into v_grade_band, v_confirmed_h1_skills
  from public.chem_students_v2 student
  where student.id = p_student_id
    and student.record_status = 'active'
    and student.grade_band in ('高一','高二','高三')
    and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb;

  if v_grade_band is null then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'reasonCode', 'formal_student_not_found'
    );
  end if;

  -- Every writer for one learner takes this lock before any plan-row lock.
  -- Keeping one lock order avoids a cross-anchor deadlock when an older retry
  -- and a newly completed plan are personalized at the same time.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'chem-review-suffix:' || p_student_id::text,
      0
    )
  );

  select plan.plan_date, plan.question_count
  into v_anchor_date, v_anchor_question_count
  from public.chem_learning_plans plan
  where plan.id = p_anchor_plan_id
    and plan.student_id = p_student_id
    and plan.mode = 'REVIEW'
  for update;

  if v_anchor_date is null
     or v_anchor_date > date '2026-09-29'
     or v_anchor_question_count not between 1 and 8 then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'reasonCode', 'invalid_anchor_plan'
    );
  end if;

  -- The runtime may discover 6..8 unresolved concepts even when tomorrow's
  -- stored baseline was smaller.  The supplied unique anchor array is the new
  -- authoritative daily count, still bounded by the formal maximum of eight.
  if p_anchor_concept_keys is null
     or pg_catalog.cardinality(p_anchor_concept_keys) not between 1 and 8
     or (
       select count(distinct forced.concept_key)
       from pg_catalog.unnest(p_anchor_concept_keys) forced(concept_key)
     ) <> pg_catalog.cardinality(p_anchor_concept_keys) then
    v_reason := 'anchor_concept_cardinality_invalid';
    raise exception 'suffix rebudget refused';
  end if;
  v_anchor_question_count := pg_catalog.cardinality(p_anchor_concept_keys);

  if pg_catalog.to_regclass('app_private.chem_review_concept_catalog') is null
     or (select count(*) from app_private.chem_review_concept_catalog) <> 130 then
    v_reason := 'authoritative_catalog_unavailable';
    raise exception 'suffix rebudget refused';
  end if;

  if v_grade_band = '高一' and pg_catalog.cardinality(v_confirmed_h1_skills) = 0 then
    v_reason := 'high1_confirmed_scope_missing';
    raise exception 'suffix rebudget refused';
  end if;

  -- Lock the complete suffix deterministically before inspecting attempts.
  perform plan.id
  from public.chem_learning_plans plan
  where plan.student_id = p_student_id
    and plan.mode = 'REVIEW'
    and plan.plan_date between v_anchor_date and date '2026-09-29'
  order by plan.plan_date, plan.id
  for update;

  create temporary table _suffix_plans on commit drop as
  select
    plan.id,
    plan.plan_date,
    case
      when plan.id = p_anchor_plan_id then v_anchor_question_count
      else plan.question_count
    end::smallint as question_count,
    plan.skill_ids,
    plan.target_concept_keys,
    (plan.plan_date - v_anchor_date)::integer as day_index
  from public.chem_learning_plans plan
  where plan.student_id = p_student_id
    and plan.mode = 'REVIEW'
    and plan.plan_date between v_anchor_date and date '2026-09-29';

  v_expected_plan_count := (date '2026-09-29' - v_anchor_date)::integer + 1;

  if (select count(*) from _suffix_plans) <> v_expected_plan_count
     or exists (
       select plan_date from _suffix_plans
       group by plan_date having count(*) <> 1
     ) then
    v_reason := 'suffix_plan_calendar_incomplete';
    v_detail := pg_catalog.jsonb_build_object(
      'expectedPlans', v_expected_plan_count,
      'foundPlans', (select count(*) from _suffix_plans)
    );
    raise exception 'suffix rebudget refused';
  end if;

  select min(plan.plan_date)
  into v_conflict_date
  from public.chem_learning_attempts attempt
  join _suffix_plans plan on plan.id = attempt.plan_day_id;

  if v_conflict_date is not null then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'reasonCode', 'suffix_contains_started_plan',
      'anchorDate', v_anchor_date,
      'conflictPlanDate', v_conflict_date
    );
  end if;

  /*
    A lock row means the learner has already seen that exact plan.  It is not
    safe to reshuffle any earlier suffix date around that evidence.
  */
  select min(plan.plan_date)
  into v_conflict_date
  from app_private.chem_question_answer_locks answer_lock
  join _suffix_plans plan on plan.id = answer_lock.plan_day_id
  where answer_lock.student_id = p_student_id;

  -- Lock only this learner's existing suffix lock rows.  Never take a table
  -- SHARE lock in the runtime path: that would stall unrelated learners.
  -- chem_lock_question_answer takes the same per-student advisory before
  -- INSERT; the final guarded UPDATE below is a second TOCTOU defense.
  perform answer_lock.question_id
    from app_private.chem_question_answer_locks answer_lock
    join _suffix_plans plan on plan.id = answer_lock.plan_day_id
    where answer_lock.student_id = p_student_id
    order by answer_lock.plan_day_id,
      answer_lock.attempt_sequence, answer_lock.question_id
    for share;

  if v_conflict_date is not null then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'reasonCode', 'suffix_contains_answer_lock',
      'anchorDate', v_anchor_date,
      'conflictPlanDate', v_conflict_date
    );
  end if;

  if exists (
    select 1 from _suffix_plans where question_count not between 1 and 8
  ) then
    v_reason := 'suffix_daily_count_out_of_range';
    raise exception 'suffix rebudget refused';
  end if;

  create temporary table _suffix_course_order (
    grade_band text not null,
    skill_id text primary key,
    skill_order smallint not null,
    unique (grade_band, skill_order)
  ) on commit drop;

  insert into _suffix_course_order (grade_band, skill_id, skill_order) values
    ('高一','H1_CLASSIFY',1),
    ('高一','H1_PERIODIC',2),
    ('高一','H1_MOLE_INTRO',3),
    ('高一','H1_GAS_MOLAR_VOLUME',4),
    ('高一','H1_REDOX',5),
    ('高一','H1_REACTION_CLASSIFICATION',6),
    ('高一','H1_SOLUTION_CONCENTRATION',7),
    -- Jiangsu Selective Compulsory 1: thermal effect -> rate/equilibrium ->
    -- aqueous equilibria -> electrochemistry.  No history-derived skill enters.
    ('高二','H2_THERMO',1),
    ('高二','H2_RATE',2),
    ('高二','H2_EQUIL',3),
    ('高二','H2_K',4),
    ('高二','H2_WEAK',5),
    ('高二','H2_PH_HYDRO',6),
    ('高二','H2_KSP',7),
    ('高二','H2_ELECTRO',8),
    -- High-3 begins with high-frequency, error-prone foundations and then
    -- rotates through the remaining exam modules.
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

  select count(*) into v_skill_count
  from _suffix_course_order course
  where course.grade_band = v_grade_band;

  if v_skill_count not in (7,8,11) then
    v_reason := 'grade_course_spine_incomplete';
    raise exception 'suffix rebudget refused';
  end if;

  if exists (
    select 1
    from app_private.chem_review_concept_catalog catalog
    left join _suffix_course_order course
      on course.grade_band = catalog.grade_band
     and course.skill_id = catalog.skill_id
    where catalog.grade_band = v_grade_band
      and course.skill_id is null
  ) then
    v_reason := 'grade_catalog_skill_outside_spine';
    raise exception 'suffix rebudget refused';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(p_anchor_concept_keys) forced(concept_key)
    left join app_private.chem_review_concept_catalog catalog
      on catalog.concept_key = forced.concept_key
     and catalog.grade_band = v_grade_band
    left join _suffix_course_order course
      on course.grade_band = catalog.grade_band
     and course.skill_id = catalog.skill_id
    where catalog.concept_key is null
       or course.skill_id is null
       or (
         v_grade_band = '高一'
         and not (catalog.skill_id = any(v_confirmed_h1_skills))
       )
  ) then
    v_reason := 'anchor_concept_outside_learned_scope';
    raise exception 'suffix rebudget refused';
  end if;

  -- A concept leaves this set only after the learner has actually answered a
  -- REVIEW original for it.  Locks alone do not count as first-pass mastery.
  -- Scope stays curricular: confirmed High-1 skills, all High-2 Selective
  -- Compulsory-1 concepts, or the reviewed High-3 exam catalog.
  create temporary table _suffix_required_first_pass (
    concept_key text primary key
  ) on commit drop;

  insert into _suffix_required_first_pass (concept_key)
  select catalog.concept_key
  from app_private.chem_review_concept_catalog catalog
  where catalog.grade_band = v_grade_band
    and (
      v_grade_band <> '高一'
      or catalog.skill_id = any(v_confirmed_h1_skills)
    )
    and not exists (
      select 1
      from public.chem_learning_attempts attempt
      join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
      left join public.chem_questions question on question.id = answer.question_id
      where attempt.student_id = p_student_id
        and attempt.mode = 'REVIEW'
        and coalesce(
          nullif(answer.concept_key, ''),
          nullif(answer.question_snapshot->>'conceptKey', ''),
          question.concept_key
        ) = catalog.concept_key
    );

  create temporary table _suffix_used_identity on commit drop as
  with identity_rows as (
    select
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
    where attempt.student_id = p_student_id
      and attempt.mode = 'REVIEW'

    union all

    select
      answer_lock.question_id,
      question.mother_id,
      question.source_item_key,
      question.content_fingerprint
    from app_private.chem_question_answer_locks answer_lock
    join public.chem_questions question on question.id = answer_lock.question_id
    where answer_lock.student_id = p_student_id
  )
  select distinct * from identity_rows;

  create index on _suffix_used_identity(question_id);
  create index on _suffix_used_identity(mother_id);
  create index on _suffix_used_identity(source_item_key);
  create index on _suffix_used_identity(content_fingerprint);

  create temporary table _suffix_latest_concept_state on commit drop as
  with ranked as (
    select
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
        partition by coalesce(
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
    where attempt.student_id = p_student_id
      and attempt.mode = 'REVIEW'
  )
  select concept_key, correct, uncertain, question_level
  from ranked
  where latest_rank = 1 and concept_key is not null;

  -- Keep the raw fresh pool for diagnostic separation: a concept can be out
  -- of source originals entirely, or have originals but none that satisfy the
  -- selector's strict difficulty direction.
  create temporary table _suffix_raw_fresh_original on commit drop as
  select
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
  from app_private.chem_question_source_releases release
  join public.chem_questions question on question.source_release_id = release.id
  join app_private.chem_review_concept_catalog catalog
    on catalog.grade_band = question.grade_band
   and catalog.skill_id = question.skill_id
   and catalog.concept_key = question.concept_key
  join _suffix_course_order course
    on course.grade_band = question.grade_band
   and course.skill_id = question.skill_id
  where release.grade_band = v_grade_band
    and release.status = 'active'
    and release.verification_status = 'full_visual_verified'
    and question.grade_band = v_grade_band
    and question.review_status = 'approved'
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
      v_grade_band <> '高一'
      or question.skill_id = any(v_confirmed_h1_skills)
    )
    and not exists (
      select 1
      from _suffix_used_identity used
      where used.question_id = question.id
         or used.mother_id = question.mother_id
         or used.source_item_key = question.source_item_key
         or used.content_fingerprint = question.content_fingerprint
    );

  create temporary table _suffix_fresh_original on commit drop as
  select raw.*
  from _suffix_raw_fresh_original raw
  left join _suffix_latest_concept_state latest
    on latest.concept_key = raw.concept_key
  where latest.concept_key is null
    or (
      latest.correct and not latest.uncertain
      and raw.level > latest.question_level
    )
    or (
      (not latest.correct or latest.uncertain)
      and raw.level <= latest.question_level
    );

  select count(*)::integer into v_fresh_questions
  from _suffix_fresh_original;

  select count(*)::integer into v_first_pass_concepts
  from _suffix_required_first_pass;

  select count(*)::integer into v_unfunded_first_pass_concepts
  from _suffix_required_first_pass required
  where not exists (
    select 1
    from _suffix_fresh_original fresh
    where fresh.concept_key = required.concept_key
  );

  if v_unfunded_first_pass_concepts > 0 then
    v_reason := 'first_pass_concept_coverage_shortage';
    v_detail := pg_catalog.jsonb_build_object(
      'remainingFirstPassConcepts', v_first_pass_concepts,
      'unfundedFirstPassConcepts', v_unfunded_first_pass_concepts
    );
    raise exception 'suffix rebudget refused';
  end if;

  -- The anchor count is fixed by today's wrong/uncertain evidence.  Every
  -- later unstarted date is re-funded from the *current* difficulty-compatible
  -- originals instead of inheriting the baseline count.  This is essential
  -- after a correct answer makes same-level High-3 originals ineligible.
  --
  -- The compatible remainder is spread as evenly as possible (counts differ
  -- by at most one); a stable learner/date hash rotates which dates receive
  -- the extra question.  When an anchor grows from 7 to 8 under a tight total
  -- budget, this naturally removes one question from a later date.
  v_remaining_plan_count := v_expected_plan_count - 1;

  if v_fresh_questions < v_anchor_question_count + v_remaining_plan_count then
    v_reason := 'suffix_minimum_daily_capacity_shortage';
    v_detail := pg_catalog.jsonb_build_object(
      'anchorQuestions', v_anchor_question_count,
      'remainingDates', v_remaining_plan_count,
      'freshQuestions', v_fresh_questions,
      'shortBy',
        v_anchor_question_count + v_remaining_plan_count - v_fresh_questions
    );
    raise exception 'suffix rebudget refused';
  end if;

  if v_remaining_plan_count > 0 then
    v_remaining_question_budget := least(
      v_fresh_questions - v_anchor_question_count,
      v_remaining_plan_count * 8
    );
    v_base_daily_count := v_remaining_question_budget / v_remaining_plan_count;
    v_extra_daily_days := v_remaining_question_budget % v_remaining_plan_count;
    v_daily_offset := (
      (
        pg_catalog.hashtextextended(
          p_student_id::text || ':' || v_anchor_date::text,
          0
        ) % v_remaining_plan_count + v_remaining_plan_count
      ) % v_remaining_plan_count
    )::integer;

    update _suffix_plans plan
    set question_count = (
      v_base_daily_count
      + case
          when pg_catalog.mod(
            plan.day_index - 1 - v_daily_offset + v_remaining_plan_count,
            v_remaining_plan_count
          ) < v_extra_daily_days then 1
          else 0
        end
    )::smallint
    where plan.plan_date > v_anchor_date;
  end if;

  if exists (
    select 1
    from _suffix_fresh_original fresh
    having count(*) <> count(distinct fresh.question_id)
       or count(*) <> count(distinct fresh.mother_id)
       or count(*) <> count(distinct fresh.source_item_key)
       or count(*) <> count(distinct fresh.content_fingerprint)
  ) then
    v_reason := 'fresh_identity_contract_invalid';
    raise exception 'suffix rebudget refused';
  end if;

  create temporary table _suffix_capacity (
    skill_id text not null,
    concept_key text primary key,
    concept_order smallint not null,
    concept_label text not null,
    skill_order smallint not null,
    fresh_questions integer not null,
    remaining_questions integer not null,
    reserved_questions integer not null default 0
  ) on commit drop;

  insert into _suffix_capacity (
    skill_id, concept_key, concept_order, concept_label, skill_order,
    fresh_questions, remaining_questions
  )
  select
    fresh.skill_id,
    fresh.concept_key,
    fresh.concept_order,
    fresh.concept_label,
    fresh.skill_order,
    count(*)::integer,
    count(*)::integer
  from _suffix_fresh_original fresh
  group by fresh.skill_id, fresh.concept_key, fresh.concept_order,
    fresh.concept_label, fresh.skill_order;

  select sum(question_count)::integer into v_required_questions
  from _suffix_plans;

  select count(*)::integer into v_uncovered_first_pass_concepts
  from _suffix_required_first_pass required
  where not (required.concept_key = any(p_anchor_concept_keys));

  if v_required_questions - v_anchor_question_count
       < v_uncovered_first_pass_concepts then
    v_reason := 'first_pass_concept_coverage_shortage';
    v_detail := pg_catalog.jsonb_build_object(
      'remainingFirstPassConcepts', v_first_pass_concepts,
      'firstPassConceptsOutsideAnchor', v_uncovered_first_pass_concepts,
      'laterTargetSlots', v_required_questions - v_anchor_question_count
    );
    raise exception 'suffix rebudget refused';
  end if;

  if v_required_questions > v_fresh_questions then
    v_reason := 'suffix_rebalanced_capacity_invalid';
    v_detail := pg_catalog.jsonb_build_object(
      'requiredQuestions', v_required_questions,
      'freshQuestions', v_fresh_questions,
      'shortBy', v_required_questions - v_fresh_questions
    );
    raise exception 'suffix rebudget refused';
  end if;

  create temporary table _suffix_assignment (
    plan_id uuid not null,
    plan_date date not null,
    target_order smallint not null,
    skill_id text not null,
    concept_key text not null,
    concept_label text not null,
    primary key (plan_id, target_order),
    unique (plan_id, concept_key)
  ) on commit drop;

  -- The runtime wrong/uncertain-first anchor is retained exactly.  Each visit
  -- consumes one remaining original for that fine concept.
  for v_position in 1..v_anchor_question_count loop
    select capacity.* into v_target
    from _suffix_capacity capacity
    where capacity.concept_key = p_anchor_concept_keys[v_position]
      and capacity.remaining_questions > 0
    for update;

    if not found then
      select case
        when not exists (
          select 1 from _suffix_raw_fresh_original raw
          where raw.concept_key = p_anchor_concept_keys[v_position]
        ) then 'source_original_exhausted'
        when exists (
          select 1 from _suffix_latest_concept_state latest
          where latest.concept_key = p_anchor_concept_keys[v_position]
            and latest.correct and not latest.uncertain
        ) then 'no_upgrade_original'
        else 'no_non_escalating_original'
      end
      into v_reason;
      v_detail := pg_catalog.jsonb_build_object(
        'conceptLabel', (
          select catalog.concept_label
          from app_private.chem_review_concept_catalog catalog
          where catalog.concept_key = p_anchor_concept_keys[v_position]
        )
      );
      raise exception 'suffix rebudget refused';
    end if;

    insert into _suffix_assignment (
      plan_id, plan_date, target_order, skill_id, concept_key, concept_label
    ) values (
      p_anchor_plan_id, v_anchor_date, v_position,
      v_target.skill_id, v_target.concept_key, v_target.concept_label
    );

    update _suffix_capacity capacity
    set
      remaining_questions = capacity.remaining_questions - 1,
      reserved_questions = capacity.reserved_questions + 1
    where capacity.concept_key = v_target.concept_key;
  end loop;

  -- Re-plan every later date.  Existing target position is the first choice;
  -- same-skill alternatives preserve the course spine; the final fallback is
  -- the stable grade-specific spine, never an arbitrary historical skill.
  for v_plan in
    select * from _suffix_plans
    where plan_date > v_anchor_date
    order by plan_date
  loop
    v_skill_rotation := mod(
      v_plan.day_index
        + ((pg_catalog.hashtextextended(p_student_id::text, 0) % v_skill_count
          + v_skill_count) % v_skill_count),
      v_skill_count
    );

    for v_position in 1..v_plan.question_count loop
      v_desired_concept := v_plan.target_concept_keys[v_position];
      select catalog.skill_id into v_desired_skill
      from app_private.chem_review_concept_catalog catalog
      where catalog.grade_band = v_grade_band
        and catalog.concept_key = v_desired_concept;

      select capacity.* into v_target
      from _suffix_capacity capacity
      where capacity.remaining_questions > 0
        and not exists (
          select 1
          from _suffix_assignment assignment
          where assignment.plan_id = v_plan.id
            and assignment.concept_key = capacity.concept_key
        )
      order by
        case
          when exists (
            select 1
            from _suffix_required_first_pass required
            where required.concept_key = capacity.concept_key
              and not exists (
                select 1
                from _suffix_assignment covered
                where covered.concept_key = capacity.concept_key
              )
          ) then 0
          else 1
        end,
        case
          when capacity.concept_key = v_desired_concept then 0
          when capacity.skill_id = v_desired_skill then 1
          else 2
        end,
        mod(capacity.skill_order - 1 - v_skill_rotation + v_skill_count, v_skill_count),
        mod(capacity.concept_order - 1 - mod(v_plan.day_index + v_position, 5) + 5, 5),
        capacity.reserved_questions,
        capacity.concept_key
      limit 1
      for update;

      if not found then
        v_reason := 'suffix_concept_capacity_shortage';
        v_detail := pg_catalog.jsonb_build_object(
          'planDate', v_plan.plan_date,
          'targetPosition', v_position
        );
        raise exception 'suffix rebudget refused';
      end if;

      insert into _suffix_assignment (
        plan_id, plan_date, target_order, skill_id, concept_key, concept_label
      ) values (
        v_plan.id, v_plan.plan_date, v_position,
        v_target.skill_id, v_target.concept_key, v_target.concept_label
      );

      update _suffix_capacity capacity
      set
        remaining_questions = capacity.remaining_questions - 1,
        reserved_questions = capacity.reserved_questions + 1
      where capacity.concept_key = v_target.concept_key;
    end loop;
  end loop;

  if exists (
    select 1
    from _suffix_required_first_pass required
    where not exists (
      select 1
      from _suffix_assignment assignment
      where assignment.concept_key = required.concept_key
    )
  ) then
    v_reason := 'first_pass_concept_coverage_shortage';
    v_detail := pg_catalog.jsonb_build_object(
      'remainingFirstPassConcepts', v_first_pass_concepts,
      'coveredFirstPassConcepts', (
        select count(*)
        from _suffix_required_first_pass required
        where exists (
          select 1
          from _suffix_assignment assignment
          where assignment.concept_key = required.concept_key
        )
      )
    );
    raise exception 'suffix rebudget refused';
  end if;

  create temporary table _suffix_plan_arrays on commit drop as
  select
    assignment.plan_id,
    assignment.plan_date,
    count(*)::smallint as question_count,
    array(
      select skill.skill_id
      from (
        select owned.skill_id, min(owned.target_order) as first_target_order
        from _suffix_assignment owned
        where owned.plan_id = assignment.plan_id
        group by owned.skill_id
      ) skill
      order by skill.first_target_order, skill.skill_id
    ) as skill_ids,
    array_agg(assignment.concept_key order by assignment.target_order) as target_concept_keys,
    array_agg(assignment.concept_label order by assignment.target_order) as knowledge_summaries
  from _suffix_assignment assignment
  group by assignment.plan_id, assignment.plan_date;

  if (select count(*) from _suffix_plan_arrays) <> v_expected_plan_count
     or exists (
       select 1
       from _suffix_plan_arrays arrays
       join _suffix_plans plan on plan.id = arrays.plan_id
       where pg_catalog.cardinality(arrays.skill_ids) not between 1 and plan.question_count
          or pg_catalog.cardinality(arrays.target_concept_keys) <> plan.question_count
          or pg_catalog.cardinality(arrays.knowledge_summaries) <> plan.question_count
          or exists (
            select 1 from pg_catalog.unnest(arrays.knowledge_summaries) label
            where label ~ '^H[123]_[A-Z0-9_]+__C0[1-5]$'
          )
     )
     or exists (
       select 1 from _suffix_capacity capacity
       where capacity.reserved_questions > capacity.fresh_questions
          or capacity.remaining_questions < 0
     ) then
    v_reason := 'suffix_assignment_contract_failed';
    raise exception 'suffix rebudget refused';
  end if;

  -- Re-check immediately before the write and row-lock anything that appeared
  -- since the initial read.  The UPDATE repeats the predicate so a visible
  -- lock converts to an exact row-count failure rather than a rewritten plan.
  perform answer_lock.question_id
  from app_private.chem_question_answer_locks answer_lock
  join _suffix_plans suffix_plan on suffix_plan.id = answer_lock.plan_day_id
  where answer_lock.student_id = p_student_id
  order by answer_lock.plan_day_id,
    answer_lock.attempt_sequence, answer_lock.question_id
  for share;

  if found then
    v_reason := 'suffix_contains_answer_lock';
    raise exception 'suffix rebudget refused';
  end if;

  update public.chem_learning_plans plan
  set
    question_count = arrays.question_count,
    skill_ids = arrays.skill_ids,
    target_concept_keys = arrays.target_concept_keys,
    knowledge_summaries = arrays.knowledge_summaries,
    round_limit = 1,
    max_question_level = null,
    source = 'mixed',
    estimated_minutes = least(30, greatest(8, arrays.question_count * 4))::smallint
  from _suffix_plan_arrays arrays
  where plan.id = arrays.plan_id
    and plan.student_id = p_student_id
    and plan.mode = 'REVIEW'
    and not exists (
      select 1 from public.chem_learning_attempts attempt
      where attempt.plan_day_id = plan.id
    )
    and not exists (
      select 1
      from app_private.chem_question_answer_locks answer_lock
      where answer_lock.student_id = p_student_id
        and answer_lock.plan_day_id = plan.id
    );

  get diagnostics v_updated_plans = row_count;
  if v_updated_plans <> v_expected_plan_count then
    v_reason := 'suffix_update_row_count_mismatch';
    v_detail := pg_catalog.jsonb_build_object(
      'expectedPlans', v_expected_plan_count,
      'updatedPlans', v_updated_plans
    );
    raise exception 'suffix rebudget refused';
  end if;

  if exists (
    select 1
    from _suffix_plan_arrays arrays
    join public.chem_learning_plans plan on plan.id = arrays.plan_id
    where plan.skill_ids is distinct from arrays.skill_ids
       or plan.target_concept_keys is distinct from arrays.target_concept_keys
       or plan.knowledge_summaries is distinct from arrays.knowledge_summaries
       or plan.question_count is distinct from arrays.question_count
       or plan.question_count not between 1 and 8
       or plan.round_limit <> 1
  ) then
    v_reason := 'suffix_persist_contract_failed';
    raise exception 'suffix rebudget refused';
  end if;

  update app_private.chem_review_capacity_shortages shortage
  set resolved_at = pg_catalog.now()
  where shortage.student_id = p_student_id
    and shortage.anchor_date = v_anchor_date
    and shortage.resolved_at is null;

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'anchorDate', v_anchor_date,
    'replannedPlans', v_expected_plan_count,
    'requiredQuestions', v_required_questions,
    'freshQuestions', v_fresh_questions
  );

exception when others then
  if v_anchor_date is not null then
    insert into app_private.chem_review_capacity_shortages (
      student_id, anchor_date, reason_code, detail
    ) values (
      p_student_id,
      v_anchor_date,
      coalesce(nullif(v_reason, ''), 'unexpected_suffix_rebudget_error'),
      coalesce(v_detail, '{}'::jsonb) || pg_catalog.jsonb_build_object(
        'windowEnd', date '2026-09-29'
      )
    )
    on conflict (student_id, anchor_date, reason_code)
      where resolved_at is null
    do update set
      detail = excluded.detail,
      created_at = pg_catalog.now();
  end if;

  return pg_catalog.jsonb_build_object(
    'ok', false,
    'reasonCode', coalesce(nullif(v_reason, ''), 'unexpected_suffix_rebudget_error'),
    'anchorDate', v_anchor_date
  );
end;
$$;

revoke all on function app_private.chem_rebudget_unstarted_review_suffix(uuid,uuid,text[])
  from public, anon, authenticated;
grant usage on schema app_private to service_role;
grant execute on function app_private.chem_rebudget_unstarted_review_suffix(uuid,uuid,text[])
  to service_role;

comment on function app_private.chem_rebudget_unstarted_review_suffix(uuid,uuid,text[]) is
  'Server-only atomic suffix planner: fixes a personalized next-day anchor, re-funds every unstarted REVIEW through 2026-09-29, or records a teacher shortage without changing plans.';

create or replace function public.chem_review_capacity_shortage_rows()
returns table (
  student_id uuid,
  anchor_date date,
  reason_code text,
  detail jsonb,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    shortage.student_id,
    shortage.anchor_date,
    shortage.reason_code,
    shortage.detail,
    shortage.created_at
  from app_private.chem_review_capacity_shortages shortage
  where shortage.resolved_at is null
  order by shortage.created_at desc, shortage.anchor_date, shortage.student_id;
$$;

revoke all on function public.chem_review_capacity_shortage_rows()
  from public, anon, authenticated;
grant execute on function public.chem_review_capacity_shortage_rows()
  to service_role;

comment on function public.chem_review_capacity_shortage_rows() is
  'Server-only teacher alert feed. Returns capacity reason metadata only; never question content, answers, access codes or family privacy.';

commit;
