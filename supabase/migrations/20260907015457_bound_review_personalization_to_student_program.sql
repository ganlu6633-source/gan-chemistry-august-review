-- Bound personalization and suffix capacity to the configured student review program.
CREATE OR REPLACE FUNCTION public.chem_personalize_next_review_plan(p_student_id uuid, p_completed_plan_id uuid, p_completed_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_grade_band text;
  v_student_metadata jsonb;
  v_next_date date;
  v_window_start date;
  v_window_end date := date '2026-09-29';
  v_completed_plan_date date;
  v_evidence_completed_at timestamptz;
  v_completed_skill_ids text[];
  v_allowed_skills text[];
  v_next_plan public.chem_learning_plans%rowtype;
  v_question_count integer;
  v_target_concepts text[];
  v_target_skills text[];
  v_target_labels text[];
  v_skill_ids text[];
  v_raw_unresolved_count integer;
  v_fresh_unresolved_count integer;
  v_unmapped_unresolved_count integer;
  v_rebudget_result jsonb;
begin
  begin
  if p_student_id is null or p_completed_plan_id is null then
    raise exception 'personalization input is incomplete';
  end if;

  select student.grade_band, student.metadata
  into v_grade_band, v_student_metadata
  from public.chem_students_v2 student
  where student.id = p_student_id
    and student.record_status = 'active'
    and student.grade_band in ('高一','高二','高三')
    and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb;

  if v_grade_band is null then
    return false;
  end if;

  if v_student_metadata ? 'reviewProgram' then
    v_window_start := (v_student_metadata->'reviewProgram'->>'startDate')::date;
    v_window_end := (v_student_metadata->'reviewProgram'->>'endDate')::date;
    if not coalesce((v_student_metadata->'reviewProgram'->>'participating')::boolean, false) then
      update app_private.review_plan_personalization_jobs
      set status = 'not_needed', last_error = null, updated_at = pg_catalog.now()
      where completed_plan_id = p_completed_plan_id and student_id = p_student_id;
      return false;
    end if;
  end if;

  -- Match the suffix helper and answer-lock RPC lock order: the learner-level
  -- advisory must be acquired before any plan row is locked.  This prevents
  -- older retry jobs and a newly completed adjacent day from deadlocking.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-review-suffix:' || p_student_id::text, 0)
  );

  select plan.plan_date, plan.skill_ids, evidence.completed_at
  into v_completed_plan_date, v_completed_skill_ids, v_evidence_completed_at
  from public.chem_learning_plans plan
  join lateral (
    select attempt.completed_at
    from public.chem_learning_attempts attempt
    where attempt.student_id = p_student_id
      and attempt.plan_day_id = p_completed_plan_id
      and attempt.mode = 'REVIEW'
      and attempt.completed_at is not null
    order by attempt.completed_at desc, attempt.sequence desc, attempt.id desc
    limit 1
  ) evidence on true
  where plan.id = p_completed_plan_id
    and plan.student_id = p_student_id
    and plan.mode = 'REVIEW';

  if v_completed_plan_date is null or v_evidence_completed_at is null then
    raise exception 'completed REVIEW evidence is missing';
  end if;

  -- "Next day" is the day immediately after the completed plan date. A
  -- learner finishing after midnight must not cause us to skip an already
  -- scheduled plan and mutate a later date instead.
  v_next_date := v_completed_plan_date + 1;

  -- The configured review program ends at v_window_end. Completion of its last
  -- plan is terminal, not a missing-plan failure requiring teacher action.
  if v_next_date > v_window_end or (v_window_start is not null and v_completed_plan_date < v_window_start) then
    insert into app_private.review_plan_personalization_jobs (
      completed_plan_id, student_id, evidence_completed_at, next_plan_date,
      status, attempt_count, last_error, updated_at
    ) values (
      p_completed_plan_id, p_student_id, v_evidence_completed_at, v_next_date,
      'not_needed', 0, null, pg_catalog.now()
    )
    on conflict (completed_plan_id) do update set
      student_id = excluded.student_id,
      evidence_completed_at = excluded.evidence_completed_at,
      next_plan_date = excluded.next_plan_date,
      status = 'not_needed',
      last_error = null,
      updated_at = pg_catalog.now();
    return false;
  end if;

  insert into app_private.review_plan_personalization_jobs (
    completed_plan_id, student_id, evidence_completed_at, next_plan_date,
    status, attempt_count, last_error, updated_at
  ) values (
    p_completed_plan_id, p_student_id, v_evidence_completed_at, v_next_date,
    'pending', 1, null, pg_catalog.now()
  )
  on conflict (completed_plan_id) do update set
    student_id = excluded.student_id,
    evidence_completed_at = excluded.evidence_completed_at,
    next_plan_date = excluded.next_plan_date,
    status = 'pending',
    attempt_count = app_private.review_plan_personalization_jobs.attempt_count + 1,
    last_error = null,
    updated_at = pg_catalog.now();

  select plan.*
  into v_next_plan
  from public.chem_learning_plans plan
  where plan.student_id = p_student_id
    and plan.mode = 'REVIEW'
    and plan.plan_date = v_next_date
    and (not (v_student_metadata ? 'reviewProgram') or plan.is_scheduled)
  order by plan.id
  limit 1
  for update;

  if not found then
    update app_private.review_plan_personalization_jobs
    set last_error = 'next REVIEW plan is missing', updated_at = pg_catalog.now()
    where completed_plan_id = p_completed_plan_id;
    return false;
  end if;

  if exists (
    select 1
    from public.chem_learning_attempts attempt
    where attempt.plan_day_id = v_next_plan.id
  ) or exists (
    select 1
    from app_private.chem_question_answer_locks answer_lock
    where answer_lock.student_id = p_student_id
      and answer_lock.plan_day_id = v_next_plan.id
  ) then
    update app_private.review_plan_personalization_jobs
    set status = 'not_needed', last_error = null, updated_at = pg_catalog.now()
    where completed_plan_id = p_completed_plan_id;
    return false;
  end if;

  if (
    select count(*)
    from public.chem_learning_plans plan
    where plan.student_id = p_student_id
      and plan.mode = 'REVIEW'
      and plan.plan_date = v_next_date
    and (not (v_student_metadata ? 'reviewProgram') or plan.is_scheduled)
  ) <> 1 then
    raise exception 'next date contains more than one REVIEW plan';
  end if;

  v_question_count := v_next_plan.question_count;
  if v_question_count is null or v_question_count < 1 or v_question_count > 8 then
    raise exception 'next REVIEW question_count must be between 1 and 8';
  end if;

  if v_grade_band = '高三' then
    select array_agg(distinct catalog.skill_id order by catalog.skill_id)
    into v_allowed_skills
    from app_private.chem_review_concept_catalog catalog
    where catalog.grade_band = '高三';
  elsif v_grade_band = '高二' then
    select array_agg(distinct allowed.skill_id order by allowed.skill_id)
    into v_allowed_skills
    from (
      select pg_catalog.unnest(v_next_plan.skill_ids) as skill_id
      union
      select pg_catalog.unnest(v_completed_skill_ids) as skill_id
    ) allowed
    join app_private.chem_review_concept_catalog catalog
      on catalog.grade_band = '高二' and catalog.skill_id = allowed.skill_id;
  else
    select array_agg(distinct allowed.skill_id order by allowed.skill_id)
    into v_allowed_skills
    from (
      select pg_catalog.unnest(v_next_plan.skill_ids) as skill_id
      union
      select pg_catalog.unnest(v_completed_skill_ids) as skill_id
      union
      select learned.skill_id
      from pg_catalog.jsonb_array_elements_text(
        case
          when pg_catalog.jsonb_typeof(v_student_metadata->'confirmedLearnedSkillIds') = 'array'
            then v_student_metadata->'confirmedLearnedSkillIds'
          else '[]'::jsonb
        end
      ) learned(skill_id)
    ) allowed
    join app_private.chem_review_concept_catalog catalog
      on catalog.grade_band = '高一' and catalog.skill_id = allowed.skill_id
    where v_next_date >= date '2026-09-01'
       or coalesce(v_student_metadata->'confirmedLearnedSkillIds', '[]'::jsonb) ? allowed.skill_id;
  end if;

  if cardinality(coalesce(v_allowed_skills, array[]::text[])) = 0
     or exists (
       select 1
       from pg_catalog.unnest(v_next_plan.skill_ids) listed(skill_id)
       where not (listed.skill_id = any(v_allowed_skills))
     )
  then
    raise exception 'next REVIEW plan leaves the learner confirmed curriculum scope';
  end if;

  with latest_current_attempt as (
    select attempt.id
    from public.chem_learning_attempts attempt
    where attempt.student_id = p_student_id
      and attempt.plan_day_id = p_completed_plan_id
      and attempt.mode = 'REVIEW'
      and attempt.completed_at is not null
    order by attempt.completed_at desc, attempt.sequence desc, attempt.id desc
    limit 1
  ), unresolved as (
    select distinct coalesce(
      nullif(answer.concept_key, ''),
      nullif(answer.question_snapshot->>'conceptKey', ''),
      answered_question.concept_key
    ) as concept_key
    from latest_current_attempt latest
    join public.chem_attempt_answers answer on answer.attempt_id = latest.id
    left join public.chem_questions answered_question on answered_question.id = answer.question_id
    where not answer.correct or answer.uncertain
  )
  select
    count(*) filter (where concept_key is not null)::integer,
    count(*) filter (where concept_key is null)::integer
  into v_raw_unresolved_count, v_unmapped_unresolved_count
  from unresolved;

  if v_unmapped_unresolved_count <> 0 then
    raise exception 'a wrong or uncertain answer lacks an exact concept mapping';
  end if;
  if v_raw_unresolved_count > 8 then
    raise exception 'a completed daily REVIEW package contains more than eight unresolved concepts';
  end if;

  -- Never truncate the sixth through eighth wrong/uncertain concept merely
  -- because tomorrow was prebuilt as a five-question plan.
  v_question_count := greatest(v_question_count, v_raw_unresolved_count);

  with latest_current_attempt as (
    select attempt.id
    from public.chem_learning_attempts attempt
    where attempt.student_id = p_student_id
      and attempt.plan_day_id = p_completed_plan_id
      and attempt.mode = 'REVIEW'
      and attempt.completed_at is not null
    order by attempt.completed_at desc, attempt.sequence desc, attempt.id desc
    limit 1
  ), used_history as (
    select
      answer.question_id,
      answer.mother_id,
      coalesce(
        nullif(answer.question_snapshot->>'sourceItemKey', ''),
        nullif(used_question.source_item_key, '')
      ) as source_item_key,
      coalesce(
        nullif(answer.question_snapshot->>'contentFingerprint', ''),
        nullif(used_question.content_fingerprint, '')
      ) as content_fingerprint
    from public.chem_learning_attempts attempt
    join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
    left join public.chem_questions used_question on used_question.id = answer.question_id
    where attempt.student_id = p_student_id
      and attempt.mode = 'REVIEW'
      and attempt.completed_at is not null

    union all

    select
      answer_lock.question_id,
      locked_question.mother_id,
      locked_question.source_item_key,
      locked_question.content_fingerprint
    from app_private.chem_question_answer_locks answer_lock
    join public.chem_questions locked_question
      on locked_question.id = answer_lock.question_id
    where answer_lock.student_id = p_student_id
  ), latest_concept_evidence as (
    select *
    from (
      select
        coalesce(
          nullif(answer.concept_key, ''),
          nullif(answer.question_snapshot->>'conceptKey', ''),
          answered_question.concept_key
        ) as concept_key,
        answer.correct,
        answer.uncertain,
        coalesce(
          nullif(answer.question_snapshot->>'level', '')::integer,
          answered_question.level::integer
        ) as question_level,
        row_number() over (
          partition by coalesce(
            nullif(answer.concept_key, ''),
            nullif(answer.question_snapshot->>'conceptKey', ''),
            answered_question.concept_key
          )
          order by attempt.completed_at desc, attempt.sequence desc, answer.id desc
        ) as latest_rank
      from public.chem_learning_attempts attempt
      join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
      left join public.chem_questions answered_question
        on answered_question.id = answer.question_id
      where attempt.student_id = p_student_id
        and attempt.mode = 'REVIEW'
        and attempt.completed_at is not null
    ) ranked
    where ranked.latest_rank = 1
      and ranked.concept_key is not null
  ), fresh_question as (
    select question.*
    from public.chem_questions question
    join app_private.chem_question_source_releases release
      on release.id = question.source_release_id
     and release.grade_band = question.grade_band
     and release.status = 'active'
     and release.verification_status = 'full_visual_verified'
    where question.grade_band = v_grade_band
      and question.skill_id = any(v_allowed_skills)
      and question.review_status = 'approved'
      and question.scope_status = 'IN'
      and question.usable_for_review
      and question.source_kind = 'licensed_local'
      and question.render_mode = 'image_primary'
      and question.source_release_id is not null
      and question.mother_id is not null
      and question.concept_key is not null
      and question.source_item_key is not null
      and question.content_fingerprint is not null
      and (v_next_plan.max_question_level is null or question.level <= v_next_plan.max_question_level)
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
        not exists (
          select 1
          from latest_concept_evidence evidence
          where evidence.concept_key = question.concept_key
        )
        or exists (
          select 1
          from latest_concept_evidence evidence
          where evidence.concept_key = question.concept_key
            and evidence.question_level is not null
            and (
              (
                evidence.correct
                and not evidence.uncertain
                and question.level > evidence.question_level
              )
              or (
                (not evidence.correct or evidence.uncertain)
                and question.level <= evidence.question_level
              )
            )
        )
      )
      and not exists (
        select 1
        from used_history used
        where used.question_id = question.id
           or used.mother_id = question.mother_id
           or used.source_item_key = question.source_item_key
           or used.content_fingerprint = question.content_fingerprint
      )
  ), concept_pool as (
    select
      question.skill_id,
      question.concept_key,
      catalog.concept_label,
      count(distinct question.id) as fresh_questions,
      count(distinct question.mother_id) as fresh_mothers,
      count(distinct question.source_item_key) as fresh_sources,
      count(distinct question.content_fingerprint) as fresh_fingerprints
    from fresh_question question
    join public.chem_skills skill on skill.id = question.skill_id and skill.active
    join app_private.chem_review_concept_catalog catalog
      on catalog.grade_band = question.grade_band
     and catalog.skill_id = question.skill_id
     and catalog.concept_key = question.concept_key
    where exists (
      select 1
      from public.chem_knowledge_cards card
      where card.skill_id = question.skill_id
        and card.review_status = 'approved'
    )
    group by question.skill_id, question.concept_key, catalog.concept_label
    having count(distinct question.id) > 0
      and count(distinct question.id) = count(distinct question.mother_id)
      and count(distinct question.id) = count(distinct question.source_item_key)
      and count(distinct question.id) = count(distinct question.content_fingerprint)
  ), raw_current_unresolved as (
    select distinct on (coalesce(
      nullif(answer.concept_key, ''),
      nullif(answer.question_snapshot->>'conceptKey', ''),
      answered_question.concept_key
    ))
      coalesce(nullif(answer.skill_id, ''), answered_question.skill_id) as skill_id,
      coalesce(
        nullif(answer.concept_key, ''),
        nullif(answer.question_snapshot->>'conceptKey', ''),
        answered_question.concept_key
      ) as concept_key,
      answer.correct,
      answer.uncertain,
      answer.id
    from latest_current_attempt latest
    join public.chem_attempt_answers answer on answer.attempt_id = latest.id
    left join public.chem_questions answered_question on answered_question.id = answer.question_id
    where not answer.correct or answer.uncertain
    order by coalesce(
      nullif(answer.concept_key, ''),
      nullif(answer.question_snapshot->>'conceptKey', ''),
      answered_question.concept_key
    ), answer.id desc
  ), current_unresolved as (
    select
      1 as priority,
      row_number() over (order by raw.id)::integer as evidence_order,
      pool.skill_id,
      pool.concept_key,
      pool.concept_label
    from raw_current_unresolved raw
    join concept_pool pool
      on pool.skill_id = raw.skill_id
     and pool.concept_key = raw.concept_key
  ), answer_history as (
    select
      coalesce(nullif(answer.skill_id, ''), answered_question.skill_id) as skill_id,
      coalesce(
        nullif(answer.concept_key, ''),
        nullif(answer.question_snapshot->>'conceptKey', ''),
        answered_question.concept_key
      ) as concept_key,
      answer.correct,
      answer.uncertain,
      attempt.completed_at,
      attempt.sequence,
      answer.id,
      row_number() over (
        partition by coalesce(
          nullif(answer.concept_key, ''),
          nullif(answer.question_snapshot->>'conceptKey', ''),
          answered_question.concept_key
        )
        order by attempt.completed_at desc, attempt.sequence desc, answer.id desc
      ) as latest_rank
    from public.chem_learning_attempts attempt
    join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
    left join public.chem_questions answered_question on answered_question.id = answer.question_id
    where attempt.student_id = p_student_id
      and attempt.mode = 'REVIEW'
      and attempt.completed_at is not null
  ), prior_unresolved as (
    select
      2 as priority,
      row_number() over (
        order by history.completed_at desc, history.sequence desc, history.id desc
      )::integer as evidence_order,
      pool.skill_id,
      pool.concept_key,
      pool.concept_label
    from answer_history history
    join concept_pool pool
      on pool.skill_id = history.skill_id
     and pool.concept_key = history.concept_key
    where history.latest_rank = 1
      and (not history.correct or history.uncertain)
    order by history.completed_at desc, history.sequence desc, history.id desc
  ), weak_skill as (
    select
      3 as priority,
      row_number() over (
        order by
          state.teacher_intervention desc,
          state.consecutive_errors desc,
          state.verified_level asc,
          state.last_reviewed_at asc nulls first,
          pg_catalog.hashtextextended(
            p_student_id::text || ':' || v_next_date::text || ':weak:' || pool.concept_key,
            0
          )
      )::integer as evidence_order,
      pool.skill_id,
      pool.concept_key,
      pool.concept_label
    from public.chem_student_skill_state state
    join concept_pool pool on pool.skill_id = state.skill_id
    where state.student_id = p_student_id
      and (
        state.teacher_intervention
        or state.consecutive_errors > 0
        or state.stability in ('unknown','learning','forgotten')
        or state.next_review_at <= v_evidence_completed_at
      )
  ), personal_progress as (
    select
      4 as priority,
      row_number() over (
        order by history.completed_at desc, history.sequence desc, history.id desc,
          pg_catalog.hashtextextended(
            p_student_id::text || ':' || v_next_date::text || ':progress:' || pool.concept_key,
            0
          )
      )::integer as evidence_order,
      pool.skill_id,
      pool.concept_key,
      pool.concept_label
    from answer_history history
    join concept_pool pool
      on pool.skill_id = history.skill_id
     and pool.concept_key = history.concept_key
    where history.latest_rank = 1
      and history.correct
      and not history.uncertain
  ), existing_target as (
    select
      5 as priority,
      target.position::integer as evidence_order,
      pool.skill_id,
      pool.concept_key,
      pool.concept_label
    from pg_catalog.unnest(v_next_plan.target_concept_keys)
      with ordinality as target(concept_key, position)
    join concept_pool pool on pool.concept_key = target.concept_key
  ), same_skill_alternative as (
    select
      6 as priority,
      row_number() over (
        order by pg_catalog.hashtextextended(
          p_student_id::text || ':' || v_next_date::text || ':' || pool.concept_key,
          0
        )
      )::integer as evidence_order,
      pool.skill_id,
      pool.concept_key,
      pool.concept_label
    from concept_pool pool
    where pool.skill_id = any(v_next_plan.skill_ids)
  ), learned_alternative as (
    select
      7 as priority,
      row_number() over (
        order by pg_catalog.hashtextextended(
          p_student_id::text || ':' || v_next_date::text || ':learned:' || pool.concept_key,
          0
        )
      )::integer as evidence_order,
      pool.skill_id,
      pool.concept_key,
      pool.concept_label
    from concept_pool pool
    where exists (
      select 1
      from answer_history history
      where history.skill_id = pool.skill_id
    )
  ), candidates as (
    select * from current_unresolved
    union all select * from prior_unresolved
    union all select * from weak_skill
    union all select * from personal_progress
    union all select * from existing_target
    union all select * from same_skill_alternative
    union all select * from learned_alternative
  ), deduplicated as (
    select
      candidates.*,
      row_number() over (
        partition by candidates.concept_key
        order by candidates.priority, candidates.evidence_order, candidates.skill_id
      ) as concept_rank
    from candidates
  ), ordered as (
    select
      deduplicated.*,
      row_number() over (
        order by deduplicated.priority, deduplicated.evidence_order,
          deduplicated.concept_key
      ) as target_order
    from deduplicated
    where deduplicated.concept_rank = 1
  ), chosen as (
    select *
    from ordered
    where target_order <= v_question_count
  )
  select
    array_agg(chosen.concept_key order by chosen.target_order),
    array_agg(chosen.skill_id order by chosen.target_order),
    array_agg(chosen.concept_label order by chosen.target_order),
    (select count(*) from raw_current_unresolved),
    (select count(*) from current_unresolved)
  into
    v_target_concepts,
    v_target_skills,
    v_target_labels,
    v_raw_unresolved_count,
    v_fresh_unresolved_count
  from chosen;

  if v_raw_unresolved_count <> v_fresh_unresolved_count then
    raise exception 'a wrong or uncertain concept has no fresh source original';
  end if;

  if pg_catalog.cardinality(v_target_concepts) <> v_question_count
     or pg_catalog.cardinality(v_target_skills) <> v_question_count
     or pg_catalog.cardinality(v_target_labels) <> v_question_count then
    raise exception 'personalized next-day source capacity is insufficient';
  end if;

  select array_agg(skill.skill_id order by skill.first_position)
  into v_skill_ids
  from (
    select target.skill_id, min(target.position)::integer as first_position
    from pg_catalog.unnest(v_target_skills)
      with ordinality as target(skill_id, position)
    group by target.skill_id
  ) skill;

  if exists (
    select 1
    from pg_catalog.unnest(v_target_concepts)
      with ordinality as target(concept_key, position)
    where not target.concept_key like v_target_skills[target.position] || '__%'
  ) then
    raise exception 'personalized concept-to-skill mapping is invalid';
  end if;

  -- The capacity calendar owns the suffix budget. Do not update tomorrow in
  -- isolation: atomically anchor tomorrow and re-budget every still-unstarted
  -- plan through the configured end date so each occurrence remains funded by a different
  -- original. Dynamic SQL lets this catalog migration land before the
  -- companion capacity migration creates the private helper.
  if pg_catalog.to_regprocedure(
    'app_private.chem_rebudget_unstarted_review_suffix(uuid,uuid,text[])'
  ) is null then
    raise exception 'capacity suffix rebudget helper is not installed';
  end if;

  execute
    'select app_private.chem_rebudget_unstarted_review_suffix($1,$2,$3)'
    into strict v_rebudget_result
    using p_student_id, v_next_plan.id, v_target_concepts;

  if not coalesce((v_rebudget_result->>'ok')::boolean, false) then
    if coalesce(v_rebudget_result->>'reasonCode', '') in (
      'suffix_contains_started_plan',
      'suffix_contains_answer_lock'
    ) then
      if nullif(v_rebudget_result->>'conflictPlanDate', '')::date = v_next_date then
        -- Tomorrow itself has already started, so its issued questions are
        -- immutable and no further personalization is required for this job.
        update app_private.review_plan_personalization_jobs
        set status = 'not_needed', last_error = null, updated_at = pg_catalog.now()
        where completed_plan_id = p_completed_plan_id;
      else
        -- A later suffix date was opened unexpectedly.  Do not silently call
        -- tomorrow personalized: retain a non-retryable teacher-visible block.
        update app_private.review_plan_personalization_jobs
        set status = 'blocked',
            last_error = pg_catalog.left(
              coalesce(v_rebudget_result->>'reasonCode', 'SUFFIX_REBUDGET_BLOCKED')
              || ': conflictPlanDate='
              || coalesce(v_rebudget_result->>'conflictPlanDate', 'unknown'),
              500
            ),
            updated_at = pg_catalog.now()
        where completed_plan_id = p_completed_plan_id;
      end if;
      return false;
    end if;

    update app_private.review_plan_personalization_jobs
    set last_error = pg_catalog.left(
          coalesce(v_rebudget_result->>'reasonCode', 'SUFFIX_REBUDGET_REJECTED')
          || case
               when nullif(v_rebudget_result->>'detail', '') is null then ''
               else ': ' || (v_rebudget_result->>'detail')
             end,
          500
        ),
        updated_at = pg_catalog.now()
    where completed_plan_id = p_completed_plan_id;
    return false;
  end if;

  select plan.*
  into v_next_plan
  from public.chem_learning_plans plan
  where plan.id = v_next_plan.id;

  if v_next_plan.question_count <> v_question_count
     or v_next_plan.round_limit <> 1
     or v_next_plan.target_concept_keys is distinct from v_target_concepts
     or v_next_plan.knowledge_summaries is distinct from v_target_labels
     or v_next_plan.skill_ids is distinct from v_skill_ids
  then
    raise exception 'capacity suffix rebudget persisted a mismatched next-day plan';
  end if;

  update app_private.review_plan_personalization_jobs
  set status = 'succeeded', last_error = null, updated_at = pg_catalog.now()
  where completed_plan_id = p_completed_plan_id;

  return true;
  exception when others then
    if p_completed_plan_id is not null
       and p_student_id is not null
       and exists (
         select 1
         from public.chem_learning_plans plan
         where plan.id = p_completed_plan_id
           and plan.student_id = p_student_id
           and plan.mode = 'REVIEW'
       )
    then
      insert into app_private.review_plan_personalization_jobs (
        completed_plan_id, student_id, evidence_completed_at, next_plan_date,
        status, attempt_count, last_error, updated_at
      ) values (
        p_completed_plan_id, p_student_id, v_evidence_completed_at,
        v_completed_plan_date + 1, 'pending', 1,
        pg_catalog.left(sqlerrm, 500), pg_catalog.now()
      )
      on conflict (completed_plan_id) do update set
        status = 'pending',
        attempt_count = app_private.review_plan_personalization_jobs.attempt_count + 1,
        last_error = excluded.last_error,
        evidence_completed_at = coalesce(
          excluded.evidence_completed_at,
          app_private.review_plan_personalization_jobs.evidence_completed_at
        ),
        next_plan_date = coalesce(
          excluded.next_plan_date,
          app_private.review_plan_personalization_jobs.next_plan_date
        ),
        updated_at = pg_catalog.now();
    end if;
    return false;
  end;
end;
$function$;
CREATE OR REPLACE FUNCTION app_private.chem_rebudget_unstarted_review_suffix(p_student_id uuid, p_anchor_plan_id uuid, p_anchor_concept_keys text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_grade_band text;
  v_program jsonb;
  v_window_start date;
  v_window_end date := date '2026-09-29';
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

  select student.metadata->'reviewProgram' into v_program
  from public.chem_students_v2 student where student.id = p_student_id;
  if v_program is not null then
    v_window_start := (v_program->>'startDate')::date;
    v_window_end := (v_program->>'endDate')::date;
    if not coalesce((v_program->>'participating')::boolean, false) then
      return pg_catalog.jsonb_build_object('ok', false, 'reasonCode', 'outside_review_program');
    end if;
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
    and (v_program is null or plan.is_scheduled)
  for update;

  if v_anchor_date is null
     or v_anchor_date > v_window_end
     or (v_window_start is not null and v_anchor_date < v_window_start)
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
    and (v_program is null or plan.is_scheduled)
    and plan.plan_date between v_anchor_date and v_window_end
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
    and (v_program is null or plan.is_scheduled)
    and plan.plan_date between v_anchor_date and v_window_end;

  v_expected_plan_count := (v_window_end - v_anchor_date)::integer + 1;

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
    and (v_program is null or exists (
      select 1 from public.chem_learning_plans scheduled
      where scheduled.student_id = p_student_id and scheduled.mode = 'REVIEW'
        and scheduled.is_scheduled
        and scheduled.plan_date between v_anchor_date and v_window_end
        and catalog.concept_key = any(scheduled.target_concept_keys)
    ))
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
    -- A concept can appear at most once per daily package.  Aggregate source
    -- capacity therefore has to be capped by remaining dates per concept.
    -- Retaining twenty percent headroom prevents a late suffix from being
    -- forced into an impossible all-capacity matching.  The anchor itself may
    -- still contain all 1..8 unresolved concepts from today's evidence.
    select coalesce(sum(least(
        per_concept.fresh_questions
          - case
              when per_concept.concept_key = any(p_anchor_concept_keys) then 1
              else 0
            end,
        v_remaining_plan_count
      )), 0)::integer
    into v_remaining_question_budget
    from (
      select fresh.concept_key, count(*)::integer as fresh_questions
      from _suffix_fresh_original fresh
      group by fresh.concept_key
    ) per_concept;

    v_remaining_question_budget := least(
      v_remaining_question_budget,
      greatest(
        v_remaining_plan_count,
        v_first_pass_concepts,
        least(
          floor(v_remaining_question_budget * 0.80)::integer,
          v_remaining_plan_count * 7
        )
      )
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
    and (v_program is null or plan.is_scheduled)
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
        'windowEnd', v_window_end
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
$function$;
