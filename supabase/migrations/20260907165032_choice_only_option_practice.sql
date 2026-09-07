-- Preserve the existing A-D learning flow. This private ledger records only
-- independently reviewed option-to-source bindings, never generic skill matches.
begin;
create table app_private.chem_option_practice_bindings (
  anchor_question_id text not null references public.chem_questions(id) on delete restrict,
  anchor_revision_token text not null check (anchor_revision_token ~ '^[0-9a-f]{64}$'),
  option_index smallint not null check (option_index between 0 and 3),
  knowledge_point text not null check (length(btrim(knowledge_point)) > 0),
  same_type_key text not null check (length(btrim(same_type_key)) > 0),
  candidates jsonb not null check (jsonb_typeof(candidates) = 'array' and jsonb_array_length(candidates) between 3 and 5),
  review_status text not null default 'pending' check (review_status in ('pending','verified','retired')),
  reviewed_by text,
  reviewed_at timestamptz,
  review_note text not null default '',
  primary key (anchor_question_id, option_index),
  check (review_status <> 'verified' or (reviewed_at is not null and length(btrim(reviewed_by)) >= 4))
);
alter table app_private.chem_option_practice_bindings enable row level security;
revoke all on table app_private.chem_option_practice_bindings from public, anon, authenticated, service_role;

create or replace function public.chem_option_practice_bindings(p_question_ids text[])
returns table (question_id text, configuration jsonb)
language sql stable security definer set search_path = ''
as $$
 select b.anchor_question_id, jsonb_build_object(
   'status','verified', 'anchorRevisionToken',b.anchor_revision_token,
   'bindings',jsonb_agg(jsonb_build_object(
     'optionIndex',b.option_index,'knowledgePoint',b.knowledge_point,
     'sameTypeKey',b.same_type_key,'candidates',b.candidates
   ) order by b.option_index))
 from app_private.chem_option_practice_bindings b
 join public.chem_questions q on q.id=b.anchor_question_id
 where cardinality(p_question_ids) between 1 and 48
   and b.anchor_question_id = any(p_question_ids)
   and b.review_status='verified'
   and b.anchor_revision_token=q.question_revision_token
 group by b.anchor_question_id,b.anchor_revision_token;
$$;
revoke all on function public.chem_option_practice_bindings(text[]) from public, anon, authenticated;
grant execute on function public.chem_option_practice_bindings(text[]) to service_role;

-- The base package remains capped at eight. Up to five explicit reserves per
-- base question can be saved in the same atomic attempt, with all existing
-- immutable-answer and revision validation retained.
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
    where q.grade_band in ('高一','高二','高三')
      and q.source_kind = 'licensed_local'
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
$function$;

commit;
