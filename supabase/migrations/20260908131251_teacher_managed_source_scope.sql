create function public.chem_teaching_ready_question_ids(p_grade text,p_question_ids text[])
returns table(question_id text,source_release_id uuid) language sql stable security definer set search_path='' as $$
 select q.id,q.source_release_id from app_private.chem_teaching_ready_questions q
 where p_grade in ('初三','高一','高二','高三') and cardinality(p_question_ids) between 1 and 1000 and q.grade_band=p_grade and q.id=any(p_question_ids);
$$;
revoke all on function public.chem_teaching_ready_question_ids(text,text[]) from public,anon,authenticated;
grant execute on function public.chem_teaching_ready_question_ids(text,text[]) to service_role;
create function public.chem_junior_choice_identity_history(p_student_id uuid)
returns table(question_id text,mother_id text,source_item_key text,parent_source_item_key text,content_fingerprint text)
language sql stable security definer set search_path='' as $$
 select distinct st.question_id,st.mother_id,st.source_item_key,st.parent_source_item_key,st.content_fingerprint
 from public.chem_junior_session_steps st join public.chem_junior_daily_sessions se on se.id=st.session_id where se.student_id=p_student_id;
$$;
revoke all on function public.chem_junior_choice_identity_history(uuid) from public,anon,authenticated;
grant execute on function public.chem_junior_choice_identity_history(uuid) to service_role;

CREATE OR REPLACE FUNCTION public.chem_lock_question_answer(p_student_id uuid, p_plan_day_id uuid, p_attempt_sequence integer, p_question_id text, p_selected_option integer, p_uncertain boolean, p_duration_sec integer, p_revision_token text)
 RETURNS TABLE(selected_option integer, uncertain boolean, duration_sec integer, revision_token text, created_at timestamp with time zone, is_new boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_inserted integer := 0;
  v_plan public.chem_learning_plans;
  v_assigned jsonb;
begin
  if p_student_id is null
    or p_plan_day_id is null
    or p_attempt_sequence is null
    or p_attempt_sequence not between 0 and 7
    or length(coalesce(p_question_id, '')) not between 1 and 160
    or p_selected_option is null
    or p_selected_option not between 0 and 9
    or p_duration_sec is null
    or p_duration_sec not between 0 and 3600
  then
    raise exception 'invalid answer lock request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-review-suffix:' || p_student_id::text, 0)
  );

  select * into v_plan from public.chem_learning_plans where id=p_plan_day_id and student_id=p_student_id for update;
  if not found then raise exception 'plan does not belong to student'; end if;
  if v_plan.teaching_managed then
    select metadata#>'{reviewProgram,questionAssignments}'->v_plan.plan_date::text into v_assigned from public.chem_students_v2 where id=p_student_id;
    if v_plan.mode<>'REVIEW' or v_plan.delivery_mode<>'legacy_round' or p_selected_option not between 0 and 3
      or jsonb_array_length(coalesce(v_assigned,'[]'))<>v_plan.question_count or not exists(
      select 1 from app_private.chem_teaching_ready_questions q where q.id=p_question_id and q.grade_band=v_plan.teaching_source_grade
       and q.question_revision_token is not distinct from p_revision_token and (
         v_assigned ? q.id or exists(select 1 from app_private.chem_option_practice_bindings b
          join public.chem_questions anchor on anchor.id=b.anchor_question_id
          where v_assigned ? b.anchor_question_id and b.review_status='verified' and b.anchor_revision_token=anchor.question_revision_token
          and exists(select 1 from jsonb_array_elements(b.candidates) c where c->>'questionId'=q.id))
       )) then raise exception 'managed question is not authorized by this plan and active source'; end if;
  elsif not exists (
    select 1
    from public.chem_questions question
    join app_private.chem_question_source_releases release
      on release.id = question.source_release_id
     and release.grade_band = question.grade_band
     and release.status = 'active'
     and release.verification_status = 'full_visual_verified'
    where question.id = p_question_id
      and question.grade_band in ('高一','高二','高三')
      and question.source_kind = 'licensed_local'
      and question.review_status = 'approved'
      and question.scope_status = 'IN'
      and question.usable_for_review
      and question.render_mode = 'image_primary'
      and question.question_revision_token is not distinct from nullif(p_revision_token, '')
      and exists (
        select 1 from pg_catalog.jsonb_array_elements(question.asset_refs) asset
        where asset->>'kind' = 'question_image'
      )
      and exists (
        select 1 from pg_catalog.jsonb_array_elements(question.asset_refs) asset
        where asset->>'kind' = 'analysis_image'
      )
  ) then
    raise exception 'question revision is stale or not eligible for an answer lock';
  end if;

  insert into app_private.chem_question_answer_locks (
    student_id, plan_day_id, attempt_sequence, question_id,
    selected_option, uncertain, duration_sec, revision_token
  ) values (
    p_student_id, p_plan_day_id, p_attempt_sequence, p_question_id,
    p_selected_option, coalesce(p_uncertain, false), p_duration_sec,
    nullif(p_revision_token, '')
  )
  on conflict (student_id, plan_day_id, attempt_sequence, question_id) do nothing;
  get diagnostics v_inserted = row_count;

  return query
  select lock.selected_option::integer, lock.uncertain, lock.duration_sec,
    lock.revision_token, lock.created_at, v_inserted = 1
  from app_private.chem_question_answer_locks lock
  where lock.student_id = p_student_id
    and lock.plan_day_id = p_plan_day_id
    and lock.attempt_sequence = p_attempt_sequence
    and lock.question_id = p_question_id;
end;
$function$

;

CREATE OR REPLACE FUNCTION public.chem_finalize_learning_attempt(p_attempt_id uuid, p_student_id uuid, p_plan_day_id uuid, p_attempt_kind text, p_sequence integer, p_mode text, p_started_at timestamp with time zone, p_completed_at timestamp with time zone, p_first_score integer, p_answers jsonb, p_skill_states jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_answer_count integer;
  v_correct_count integer;
  v_current_sequence integer;
  v_inserted_answers integer;
  v_inserted_states integer;
  v_managed boolean;
  v_source_grade text;
begin
  if p_attempt_id is null
    or p_student_id is null
    or p_plan_day_id is null
    or p_attempt_kind not in ('scheduled', 'review')
    or p_sequence is null
    or p_sequence not between 0 and 7
    or p_mode not in ('REVIEW', 'CLASS_QUIZ', 'EXAM_SPRINT')
    or p_started_at is null
    or p_completed_at is null
    or p_completed_at < p_started_at
    or jsonb_typeof(p_answers) <> 'array'
    or jsonb_typeof(p_skill_states) <> 'array'
  then
    raise exception 'invalid learning attempt finalization request';
  end if;

  v_answer_count := jsonb_array_length(p_answers);
  if v_answer_count not between 1 and (case when p_mode = 'REVIEW' then 48 else 10 end)
    or jsonb_array_length(p_skill_states) not between 1 and 48
    or p_first_score not between 0 and v_answer_count
  then
    raise exception 'invalid learning attempt finalization cardinality';
  end if;

  select teaching_managed,teaching_source_grade into v_managed,v_source_grade from public.chem_learning_plans where id=p_plan_day_id and student_id=p_student_id for update;
  if v_managed and exists(select 1 from jsonb_array_elements(p_answers) a where not exists(select 1 from app_private.chem_teaching_ready_questions q where q.id=a->>'question_id' and q.grade_band=v_source_grade)) then
    raise exception 'managed source changed before finalization';
  end if;
  if not exists (
    select 1
    from public.chem_learning_plans p
    where p.id = p_plan_day_id
      and p.student_id = p_student_id
      and p.mode = p_mode
  ) then
    raise exception 'plan does not belong to student or mode';
  end if;

  select count(*)::integer
  into v_current_sequence
  from public.chem_learning_attempts a
  where a.student_id = p_student_id
    and a.plan_day_id = p_plan_day_id;

  if p_sequence <> v_current_sequence
    or p_attempt_kind <> (case when p_sequence = 0 then 'scheduled' else 'review' end)
  then
    raise exception 'attempt sequence changed';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_answers) as x(
      question_id text,
      selected_option integer,
      correct boolean
    )
    left join public.chem_questions q on q.id = x.question_id
    where q.id is null
      or x.selected_option is null
      or x.correct is distinct from (x.selected_option = q.correct_option)
  ) then
    raise exception 'answer correctness does not match server question';
  end if;

  select (count(*) filter (where x.correct))::integer
  into v_correct_count
  from jsonb_to_recordset(p_answers) as x(correct boolean);
  if v_correct_count <> p_first_score then
    raise exception 'first score does not match canonical answers';
  end if;

  if p_mode = 'REVIEW' and exists (
    select 1
    from jsonb_to_recordset(p_answers) as x(
      question_id text,
      selected_option integer,
      uncertain boolean,
      duration_sec integer,
      revision_token text
    )
    join public.chem_questions q on q.id = x.question_id
    where (v_managed or (q.grade_band in ('高一','高二','高三') and q.source_kind = 'licensed_local'))
      and (
        x.revision_token is distinct from q.question_revision_token
        or not exists (
        select 1
        from app_private.chem_question_answer_locks l
        where l.student_id = p_student_id
          and l.plan_day_id = p_plan_day_id
          and l.attempt_sequence = p_sequence
          and l.question_id = x.question_id
          and l.selected_option = x.selected_option
          and l.uncertain = coalesce(x.uncertain, false)
          and l.duration_sec = coalesce(x.duration_sec, 0)
          and l.revision_token is not distinct from nullif(x.revision_token, '')
        )
      )
  ) then
    raise exception 'licensed answer is not backed by the immutable first-answer lock';
  end if;

  insert into public.chem_learning_attempts (
    id, student_id, plan_day_id, attempt_kind, sequence, mode,
    started_at, completed_at, first_score
  ) values (
    p_attempt_id, p_student_id, p_plan_day_id, p_attempt_kind, p_sequence,
    p_mode, p_started_at, p_completed_at, p_first_score
  );

  insert into public.chem_attempt_answers (
    attempt_id, question_id, mother_id, skill_id, concept_key, level,
    correct, uncertain, duration_sec, selected_option, question_snapshot
  )
  select
    p_attempt_id,
    x.question_id,
    x.mother_id,
    x.skill_id,
    nullif(x.concept_key, ''),
    x.level::smallint,
    x.correct,
    coalesce(x.uncertain, false),
    x.duration_sec,
    x.selected_option::smallint,
    x.question_snapshot
  from jsonb_to_recordset(p_answers) as x(
    question_id text,
    mother_id text,
    skill_id text,
    concept_key text,
    level integer,
    correct boolean,
    uncertain boolean,
    duration_sec integer,
    selected_option integer,
    revision_token text,
    question_snapshot jsonb
  );
  get diagnostics v_inserted_answers = row_count;
  if v_inserted_answers <> v_answer_count then
    raise exception 'not every answer was inserted';
  end if;

  insert into public.chem_student_skill_state (
    student_id, skill_id, verified_level, candidate_level, stability,
    consecutive_errors, next_review_at, review_interval_index,
    last_reviewed_at, teacher_intervention, updated_at
  )
  select
    p_student_id,
    x.skill_id,
    x.verified_level::smallint,
    x.candidate_level::smallint,
    x.stability,
    x.consecutive_errors,
    x.next_review_at,
    x.review_interval_index::smallint,
    x.last_reviewed_at,
    x.teacher_intervention,
    x.updated_at
  from jsonb_to_recordset(p_skill_states) as x(
    skill_id text,
    verified_level integer,
    candidate_level integer,
    stability text,
    consecutive_errors integer,
    next_review_at timestamptz,
    review_interval_index integer,
    last_reviewed_at timestamptz,
    teacher_intervention boolean,
    updated_at timestamptz
  )
  on conflict (student_id, skill_id) do update set
    verified_level = excluded.verified_level,
    candidate_level = excluded.candidate_level,
    stability = excluded.stability,
    consecutive_errors = excluded.consecutive_errors,
    next_review_at = excluded.next_review_at,
    review_interval_index = excluded.review_interval_index,
    last_reviewed_at = excluded.last_reviewed_at,
    teacher_intervention = excluded.teacher_intervention,
    updated_at = excluded.updated_at;
  get diagnostics v_inserted_states = row_count;
  if v_inserted_states <> jsonb_array_length(p_skill_states) then
    raise exception 'not every skill state was written';
  end if;

  delete from app_private.chem_question_answer_locks l
  where l.student_id = p_student_id
    and l.plan_day_id = p_plan_day_id
    and l.attempt_sequence = p_sequence;

  return true;
end;
$function$

;
