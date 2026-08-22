-- Allow a REVIEW day to name its five exact fine-grained concepts.
--
-- Empty arrays preserve the existing single-skill behaviour. A populated
-- array is used for a mixed day, for example four concepts from the current
-- classroom lesson plus one daily oxidation-reduction concept. The Edge
-- function still verifies uniqueness, skill ownership, source provenance and
-- five unseen originals per concept before issuing any question.

begin;

alter table public.chem_learning_plans
  add column if not exists target_concept_keys text[] not null default array[]::text[];

create or replace function app_private.chem_text_array_is_unique_nonblank(p_values text[])
returns boolean
language sql
immutable
strict
security invoker
set search_path = ''
as $$
  select
    not exists (
      select 1
      from pg_catalog.unnest(p_values) as item(value)
      where pg_catalog.btrim(value) = ''
    )
    and pg_catalog.cardinality(p_values) = (
      select count(distinct pg_catalog.btrim(value))
      from pg_catalog.unnest(p_values) as item(value)
    );
$$;

revoke all on function app_private.chem_text_array_is_unique_nonblank(text[]) from public, anon, authenticated;
grant execute on function app_private.chem_text_array_is_unique_nonblank(text[]) to service_role;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'chem_learning_plans_review_target_count_check'
      and conrelid = 'public.chem_learning_plans'::regclass
  ) then
    alter table public.chem_learning_plans
      add constraint chem_learning_plans_review_target_count_check
      check (
        mode <> 'REVIEW'
        or cardinality(target_concept_keys) = 0
        or (
          cardinality(target_concept_keys) = question_count
          and app_private.chem_text_array_is_unique_nonblank(target_concept_keys)
        )
      );
  end if;
end $$;

comment on column public.chem_learning_plans.target_concept_keys is
  'Optional exact REVIEW concept set. Empty keeps legacy single-skill selection; populated must contain question_count unique concept keys and is fail-closed by chemistry-access.';

create or replace function public.chem_review_answer_history(p_student_id uuid)
returns table(
  attempt_id uuid,
  plan_day_id uuid,
  history_order bigint,
  question_id text,
  mother_id text,
  skill_id text,
  concept_key text,
  correct boolean,
  uncertain boolean,
  question_snapshot jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  with ordered_attempts as (
    select
      attempt.id,
      attempt.plan_day_id,
      pg_catalog.dense_rank() over (
        order by attempt.completed_at, attempt.id
      ) - 1 as history_order
    from public.chem_learning_attempts attempt
    join public.chem_students_v2 student on student.id = attempt.student_id
    where attempt.student_id = p_student_id
      and student.record_status = 'active'
      and attempt.mode = 'REVIEW'
      and attempt.completed_at is not null
  )
  select
    attempt.id,
    attempt.plan_day_id,
    attempt.history_order,
    answer.question_id,
    answer.mother_id,
    answer.skill_id,
    answer.concept_key,
    answer.correct,
    answer.uncertain,
    answer.question_snapshot
  from ordered_attempts attempt
  join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
  order by attempt.history_order, answer.id;
$$;

revoke all on function public.chem_review_answer_history(uuid) from public, anon, authenticated;
grant execute on function public.chem_review_answer_history(uuid) to service_role;

comment on function public.chem_review_answer_history(uuid) is
  'Server-only REVIEW answer history used for cross-date adaptive selection; avoids exposing or placing hundreds of attempt IDs in a PostgREST URL.';

create or replace function public.chem_review_source_usage_counts(p_student_ids uuid[])
returns table(student_id uuid, concept_key text, used_count bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with source_answers as (
    select
      attempt.student_id,
      coalesce(
        nullif(answer.concept_key, ''),
        nullif(answer.question_snapshot->>'conceptKey', ''),
        question.concept_key
      ) as concept_key,
      coalesce(
        nullif(answer.question_snapshot->>'sourceItemKey', ''),
        nullif(question.source_item_key, ''),
        answer.mother_id::text
      ) as source_key
    from public.chem_learning_attempts attempt
    join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
    left join public.chem_questions question on question.id = answer.question_id
    where attempt.mode = 'REVIEW'
      and attempt.completed_at is not null
      and attempt.student_id = any(coalesce(p_student_ids, array[]::uuid[]))
  )
  select source_answers.student_id, source_answers.concept_key, count(distinct source_answers.source_key)::bigint
  from source_answers
  where source_answers.concept_key is not null
    and source_answers.source_key is not null
  group by source_answers.student_id, source_answers.concept_key;
$$;

revoke all on function public.chem_review_source_usage_counts(uuid[]) from public, anon, authenticated;
grant execute on function public.chem_review_source_usage_counts(uuid[]) to service_role;

comment on function public.chem_review_source_usage_counts(uuid[]) is
  'Server-only aggregate used by the teacher readiness panel; returns no answer text, access code or question content.';

do $$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from public.chem_learning_plans p
  where cardinality(p.target_concept_keys) <> 0;
  if v_bad <> 0 then
    raise exception 'target concept migration changed existing plans unexpectedly: % populated rows', v_bad;
  end if;
end $$;

commit;
