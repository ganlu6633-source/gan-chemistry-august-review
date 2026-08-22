-- Applied corrective for the still-unstarted 2026-08-23 formal High-3 REVIEW paths.
--
-- Correct only the still-unstarted formal High-3 REVIEW paths for 2026-08-23.
-- The previous path put skill_order/concept_order before the per-learner hash,
-- so eight learners with no REVIEW history received the same first eight
-- concepts. This candidate preserves unresolved evidence as the first hard
-- priority and preserves the reviewed High-3 easy-error spine in three-skill
-- bands, but deterministically rotates concepts inside each band per learner.

begin;

select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('chem-h3-review-2026-08-23-corrective', 0)
);

-- A licensed High-3 answer is revealed only after the server writes its
-- first-answer lock. Holding these evidence tables in SHARE mode closes the
-- race between the eligibility check, the plan rewrite and a late submission.
lock table
  public.chem_learning_attempts,
  public.chem_attempt_answers,
  app_private.chem_question_answer_locks
in share mode;

do $$
begin
  if pg_catalog.to_regclass('app_private.chem_review_concept_catalog') is null
     or (
       select count(*)
       from app_private.chem_review_concept_catalog catalog
       where catalog.grade_band = '高三'
     ) <> 55
  then
    raise exception 'the reviewed High-3 concept catalog is unavailable';
  end if;

  if (
    select count(*)
    from app_private.chem_question_source_releases release
    where release.grade_band = '高三'
      and release.status = 'active'
      and release.verification_status = 'full_visual_verified'
  ) <> 1
  then
    raise exception 'High-3 must have exactly one active fully verified source release';
  end if;
end $$;

create temporary table _h3_course_order (
  skill_id text primary key,
  skill_order smallint not null unique,
  easy_error_band smallint not null
) on commit drop;

-- The existing course spine already places the most error-prone/high-frequency
-- examination skills first. Three adjacent skills form one hard priority band;
-- the per-learner hash may rotate only inside a band, never across a band.
insert into _h3_course_order(skill_id, skill_order, easy_error_band) values
  ('H3_ION_REDOX',1,1),
  ('H3_STOICH',2,1),
  ('H3_EXPERIMENT',3,1),
  ('H3_AQ',4,2),
  ('H3_ELECTRO',5,2),
  ('H3_EQUILIBRIUM',6,2),
  ('H3_THERMO_RATE',7,3),
  ('H3_INORGANIC',8,3),
  ('H3_PROCESS',9,3),
  ('H3_STRUCTURE',10,4),
  ('H3_ORGANIC',11,4);

create temporary table _eligible_h3_plan on commit drop as
select
  plan.id as plan_id,
  plan.student_id,
  plan.question_count
from public.chem_learning_plans plan
join public.chem_students_v2 student
  on student.id = plan.student_id
where plan.mode = 'REVIEW'
  and plan.plan_date = date '2026-08-23'
  and student.record_status = 'active'
  and student.grade_band = '高三'
  and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb
  and plan.question_count between 1 and 8
  and not exists (
    select 1
    from public.chem_learning_attempts attempt
    where attempt.plan_day_id = plan.id
  )
  and not exists (
    select 1
    from public.chem_learning_attempts attempt
    join public.chem_attempt_answers answer
      on answer.attempt_id = attempt.id
    where attempt.plan_day_id = plan.id
  )
  and not exists (
    select 1
    from app_private.chem_question_answer_locks answer_lock
    where answer_lock.student_id = plan.student_id
      and answer_lock.plan_day_id = plan.id
  );

create unique index on _eligible_h3_plan(plan_id);
create unique index on _eligible_h3_plan(student_id);

do $$
begin
  if exists (
    select 1
    from public.chem_students_v2 student
    join public.chem_learning_plans plan
      on plan.student_id = student.id
     and plan.mode = 'REVIEW'
     and plan.plan_date = date '2026-08-23'
    where student.record_status = 'active'
      and student.grade_band = '高三'
      and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb
    group by student.id
    having count(plan.id) <> 1
  ) then
    raise exception 'a formal High-3 learner does not have exactly one REVIEW plan today';
  end if;
end $$;

-- Lock only rows that passed all three no-evidence gates. The SHARE locks
-- above prevent a first answer, feedback lock or finalized attempt appearing
-- between this row lock and the final guarded update.
do $$
declare
  v_plan record;
begin
  for v_plan in
    select plan.id
    from public.chem_learning_plans plan
    join _eligible_h3_plan eligible on eligible.plan_id = plan.id
    order by plan.student_id, plan.id
    for update of plan
  loop
    null;
  end loop;
end $$;

create temporary table _h3_used_identity on commit drop as
with identity_row as (
  select
    attempt.student_id,
    answer.question_id,
    coalesce(nullif(answer.mother_id,''), question.mother_id) as mother_id,
    coalesce(
      nullif(answer.question_snapshot->>'sourceItemKey',''),
      nullif(question.source_item_key,'')
    ) as source_item_key,
    coalesce(
      nullif(answer.question_snapshot->>'contentFingerprint',''),
      nullif(question.content_fingerprint,'')
    ) as content_fingerprint
  from public.chem_learning_attempts attempt
  join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
  left join public.chem_questions question on question.id = answer.question_id
  join _eligible_h3_plan eligible on eligible.student_id = attempt.student_id
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
  join _eligible_h3_plan eligible on eligible.student_id = answer_lock.student_id
)
select distinct
  student_id, question_id, mother_id, source_item_key, content_fingerprint
from identity_row;

create index on _h3_used_identity(student_id,question_id);
create index on _h3_used_identity(student_id,mother_id);
create index on _h3_used_identity(student_id,source_item_key);
create index on _h3_used_identity(student_id,content_fingerprint);

create temporary table _h3_latest_concept_state on commit drop as
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
    row_number() over (
      partition by
        attempt.student_id,
        coalesce(
          nullif(answer.concept_key,''),
          nullif(answer.question_snapshot->>'conceptKey',''),
          question.concept_key
        )
      order by
        coalesce(attempt.completed_at,attempt.started_at,attempt.created_at) desc,
        attempt.sequence desc,
        answer.id desc
    ) as latest_rank
  from public.chem_learning_attempts attempt
  join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
  left join public.chem_questions question on question.id = answer.question_id
  join _eligible_h3_plan eligible on eligible.student_id = attempt.student_id
  where attempt.mode = 'REVIEW'
)
select student_id,concept_key,correct,uncertain,question_level
from ranked
where latest_rank = 1
  and concept_key is not null
  and question_level between 1 and 5;

create unique index on _h3_latest_concept_state(student_id,concept_key);

create temporary table _h3_fresh_original on commit drop as
select
  eligible.plan_id,
  eligible.student_id,
  eligible.question_count,
  question.id as question_id,
  question.mother_id,
  question.source_item_key,
  question.content_fingerprint,
  question.level,
  question.skill_id,
  question.concept_key,
  catalog.concept_label,
  catalog.concept_order,
  course.skill_order,
  course.easy_error_band,
  latest.correct as latest_correct,
  latest.uncertain as latest_uncertain,
  latest.question_level as latest_question_level,
  case
    when latest.concept_key is not null
      and (not latest.correct or latest.uncertain) then 1
    when latest.concept_key is null then 2
    else 3
  end::smallint as evidence_priority
from _eligible_h3_plan eligible
join app_private.chem_question_source_releases release
  on release.grade_band = '高三'
 and release.status = 'active'
 and release.verification_status = 'full_visual_verified'
join public.chem_questions question
  on question.source_release_id = release.id
 and question.grade_band = '高三'
join app_private.chem_review_concept_catalog catalog
  on catalog.grade_band = question.grade_band
 and catalog.skill_id = question.skill_id
 and catalog.concept_key = question.concept_key
join _h3_course_order course on course.skill_id = question.skill_id
left join _h3_latest_concept_state latest
  on latest.student_id = eligible.student_id
 and latest.concept_key = question.concept_key
where question.review_status = 'approved'
  and question.scope_status = 'IN'
  and question.usable_for_review
  and question.source_kind = 'licensed_local'
  and question.render_mode = 'image_primary'
  and nullif(question.mother_id, '') is not null
  and nullif(question.source_item_key, '') is not null
  and question.content_fingerprint ~ '^[0-9a-f]{64}$'
  and pg_catalog.jsonb_typeof(question.asset_refs) = 'array'
  and exists (
    select 1
    from pg_catalog.jsonb_array_elements(question.asset_refs) asset
    where asset->>'kind' = 'question_image'
      and coalesce(asset->>'path','') <> ''
      and coalesce(asset->>'sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(asset->>'width','0')::integer > 0
      and coalesce(asset->>'height','0')::integer > 0
  )
  and exists (
    select 1
    from pg_catalog.jsonb_array_elements(question.asset_refs) asset
    where asset->>'kind' = 'analysis_image'
      and coalesce(asset->>'path','') <> ''
      and coalesce(asset->>'sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(asset->>'width','0')::integer > 0
      and coalesce(asset->>'height','0')::integer > 0
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
    from _h3_used_identity used
    where used.student_id = eligible.student_id
      and (
        used.question_id = question.id
        or used.mother_id = question.mother_id
        or used.source_item_key = question.source_item_key
        or used.content_fingerprint = question.content_fingerprint
      )
  );

create index on _h3_fresh_original(student_id,concept_key);

do $$
begin
  if exists (
    select 1
    from _h3_fresh_original fresh
    group by fresh.student_id
    having count(*) <> count(distinct fresh.question_id)
        or count(*) <> count(distinct fresh.mother_id)
        or count(*) <> count(distinct fresh.source_item_key)
        or count(*) <> count(distinct fresh.content_fingerprint)
  ) then
    raise exception 'the compatible High-3 pool is not globally unique on all four identities';
  end if;
end $$;

-- Choose the same proof original that the runtime selector will prefer for a
-- concept: lowest level on first pass, nearest strictly harder after a secure
-- answer, or nearest same/easier after an error or uncertainty.
create temporary table _h3_concept_proof on commit drop as
with ranked as (
  select
    fresh.*,
    row_number() over (
      partition by fresh.student_id,fresh.concept_key
      order by
        case
          when fresh.latest_question_level is null then fresh.level
          else abs(fresh.level - fresh.latest_question_level)
        end,
        fresh.level,
        fresh.question_id
    ) as proof_rank
  from _h3_fresh_original fresh
)
select * from ranked where proof_rank = 1;

create unique index on _h3_concept_proof(student_id,concept_key);

-- Evidence priority is hard: unresolved concepts always precede unseen ones,
-- and unseen concepts precede already-secure upgrades. Global easy-error bands
-- are also hard. Only then does the stable student/date/concept hash rotate the
-- path, which fixes the former identical-path bug without random daily drift.
create temporary table _h3_target_choice on commit drop as
with ranked as (
  select
    proof.*,
    row_number() over (
      partition by proof.student_id
      order by
        proof.evidence_priority,
        proof.easy_error_band,
        pg_catalog.hashtextextended(
          proof.student_id::text
            || ':2026-08-23:h3-corrective:'
            || proof.concept_key,
          0
        ),
        proof.skill_order,
        proof.concept_order,
        proof.concept_key
    )::integer as target_order
  from _h3_concept_proof proof
)
select *
from ranked
where target_order <= question_count;

create unique index on _h3_target_choice(student_id,target_order);
create unique index on _h3_target_choice(student_id,concept_key);

create temporary table _h3_assignment on commit drop as
select
  eligible.plan_id,
  eligible.student_id,
  eligible.question_count,
  array(
    select skill.skill_id
    from (
      select target.skill_id,min(target.target_order) as first_target_order
      from _h3_target_choice target
      where target.student_id = eligible.student_id
      group by target.skill_id
    ) skill
    order by skill.first_target_order,skill.skill_id
  )::text[] as skill_ids,
  array(
    select target.concept_key
    from _h3_target_choice target
    where target.student_id = eligible.student_id
    order by target.target_order
  )::text[] as target_concept_keys,
  array(
    select target.concept_label
    from _h3_target_choice target
    where target.student_id = eligible.student_id
    order by target.target_order
  )::text[] as knowledge_summaries,
  array(
    select target.question_id
    from _h3_target_choice target
    where target.student_id = eligible.student_id
    order by target.target_order
  )::text[] as proof_question_ids
from _eligible_h3_plan eligible;

create unique index on _h3_assignment(plan_id);
create unique index on _h3_assignment(student_id);

do $$
begin
  if exists (
    select 1
    from _h3_assignment assignment
    where assignment.question_count not between 1 and 8
       or pg_catalog.cardinality(assignment.skill_ids) not between 1 and assignment.question_count
       or pg_catalog.cardinality(assignment.target_concept_keys) <> assignment.question_count
       or pg_catalog.cardinality(assignment.knowledge_summaries) <> assignment.question_count
       or pg_catalog.cardinality(assignment.proof_question_ids) <> assignment.question_count
  ) then
    raise exception 'a High-3 learner does not have a complete 1..8 source-backed assignment';
  end if;

  if exists (
    select 1
    from _h3_target_choice target
    group by target.student_id
    having count(*) <> count(distinct target.question_id)
        or count(*) <> count(distinct target.mother_id)
        or count(*) <> count(distinct target.source_item_key)
        or count(*) <> count(distinct target.content_fingerprint)
  ) then
    raise exception 'a High-3 assignment repeats one of the four source identities';
  end if;

  if exists (
    select 1
    from _h3_target_choice earlier
    join _h3_target_choice later
      on later.student_id = earlier.student_id
     and later.target_order > earlier.target_order
    where later.evidence_priority < earlier.evidence_priority
       or (
         later.evidence_priority = earlier.evidence_priority
         and later.easy_error_band < earlier.easy_error_band
       )
  ) then
    raise exception 'the individualized path lowered evidence or easy-error priority';
  end if;

  if (
    select count(*)
    from _h3_assignment assignment
  ) > 1
  and (
    select count(distinct pg_catalog.array_to_string(assignment.target_concept_keys,'|'))
    from _h3_assignment assignment
  ) <> (
    select count(*) from _h3_assignment
  )
  then
    raise exception 'two eligible High-3 learners still have the same ordered path';
  end if;
end $$;

update public.chem_learning_plans plan
set
  title = '个性化复习｜高三易错优先',
  skill_ids = assignment.skill_ids,
  target_concept_keys = assignment.target_concept_keys,
  knowledge_summaries = assignment.knowledge_summaries
from _h3_assignment assignment
where plan.id = assignment.plan_id
  and plan.student_id = assignment.student_id
  and plan.mode = 'REVIEW'
  and plan.plan_date = date '2026-08-23'
  and plan.question_count between 1 and 8
  and not exists (
    select 1
    from public.chem_learning_attempts attempt
    where attempt.plan_day_id = plan.id
  )
  and not exists (
    select 1
    from public.chem_learning_attempts attempt
    join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
    where attempt.plan_day_id = plan.id
  )
  and not exists (
    select 1
    from app_private.chem_question_answer_locks answer_lock
    where answer_lock.student_id = plan.student_id
      and answer_lock.plan_day_id = plan.id
  )
  and (
    plan.title is distinct from '个性化复习｜高三易错优先'
    or plan.skill_ids is distinct from assignment.skill_ids
    or plan.target_concept_keys is distinct from assignment.target_concept_keys
    or plan.knowledge_summaries is distinct from assignment.knowledge_summaries
  );

do $$
begin
  if exists (
    select 1
    from _h3_assignment assignment
    join public.chem_learning_plans plan on plan.id = assignment.plan_id
    where plan.student_id <> assignment.student_id
       or plan.mode <> 'REVIEW'
       or plan.plan_date <> date '2026-08-23'
       or plan.question_count <> assignment.question_count
       or plan.question_count not between 1 and 8
       or plan.round_limit is distinct from 1
       or plan.skill_ids is distinct from assignment.skill_ids
       or plan.target_concept_keys is distinct from assignment.target_concept_keys
       or plan.knowledge_summaries is distinct from assignment.knowledge_summaries
  ) then
    raise exception 'the persisted High-3 plans differ from the deterministic assignments';
  end if;

  if exists (
    select 1
    from _h3_assignment assignment
    where exists (
      select 1
      from public.chem_learning_attempts attempt
      where attempt.plan_day_id = assignment.plan_id
    )
       or exists (
         select 1
         from public.chem_learning_attempts attempt
         join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
         where attempt.plan_day_id = assignment.plan_id
       )
       or exists (
         select 1
         from app_private.chem_question_answer_locks answer_lock
         where answer_lock.student_id = assignment.student_id
           and answer_lock.plan_day_id = assignment.plan_id
       )
  ) then
    raise exception 'an eligible High-3 plan acquired learning evidence during the rewrite';
  end if;
end $$;

commit;
