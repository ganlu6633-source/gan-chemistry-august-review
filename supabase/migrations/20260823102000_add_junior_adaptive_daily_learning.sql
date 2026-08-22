-- Junior-high source-original daily learning.  This migration deliberately
-- adds a separate delivery path: existing high-school five-round plans remain
-- constrained to their legacy 1--10 question contract.

alter table public.chem_learning_plans
  add column if not exists delivery_mode text not null default 'legacy_round';

alter table public.chem_learning_plans
  drop constraint if exists chem_learning_plans_delivery_mode_check;

alter table public.chem_learning_plans
  add constraint chem_learning_plans_delivery_mode_check
  check (delivery_mode in ('legacy_round', 'junior_adaptive'));

alter table public.chem_learning_plans
  drop constraint if exists chem_learning_plans_question_count_check;

alter table public.chem_learning_plans
  add constraint chem_learning_plans_question_count_check
  check (
    (delivery_mode = 'legacy_round' and question_count between 1 and 10)
    or (delivery_mode = 'junior_adaptive' and question_count = 12)
  );

alter table public.chem_questions
  add column if not exists textbook_version text,
  add column if not exists knowledge_id text,
  add column if not exists same_type_key text,
  add column if not exists parent_source_item_key text;

alter table public.chem_questions
  drop constraint if exists chem_questions_junior_source_contract;

alter table public.chem_questions
  add constraint chem_questions_junior_source_contract
  check (
    grade_band <> '初三'
    or source_kind <> 'licensed_local'
    or (
      textbook_version is not null and length(btrim(textbook_version)) > 0
      and knowledge_id is not null and length(btrim(knowledge_id)) > 0
      and same_type_key is not null and length(btrim(same_type_key)) > 0
      and source_item_key is not null and length(btrim(source_item_key)) >= 16
      and parent_source_item_key is not null and length(btrim(parent_source_item_key)) >= 16
      and content_fingerprint ~ '^[0-9a-f]{64}$'
      and source_release_id is not null
    )
  );

create index if not exists chem_questions_junior_adaptive_pool_idx
  on public.chem_questions (
    textbook_version, knowledge_id, same_type_key, level, id
  )
  where grade_band = '初三'
    and source_kind = 'licensed_local'
    and review_status = 'approved'
    and scope_status = 'IN'
    and usable_for_review;

create table if not exists public.chem_junior_curriculum_days (
  id text primary key,
  textbook_version text not null,
  day_number smallint not null check (day_number >= 1),
  unit_id text not null,
  unit_title text not null,
  title text not null,
  knowledge_skill_ids text[] not null check (cardinality(knowledge_skill_ids) = 3),
  knowledge_summaries text[] not null check (cardinality(knowledge_summaries) = 3),
  estimated_minutes smallint not null default 30 check (estimated_minutes between 10 and 90),
  release_status text not null default 'draft' check (release_status in ('draft', 'ready', 'retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (textbook_version, day_number)
);

alter table public.chem_learning_plans
  add column if not exists junior_curriculum_day_id text references public.chem_junior_curriculum_days(id) on delete restrict;

create table if not exists app_private.chem_junior_knowledge_provenance (
  knowledge_id text primary key references public.chem_skills(id) on delete restrict,
  textbook_version text not null,
  source_release_id uuid references app_private.chem_question_source_releases(id) on delete restrict,
  source_id text not null,
  source_locator text not null,
  source_sha256 text not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  verification_status text not null check (verification_status in ('pending_review', 'verified', 'retired')),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.chem_junior_daily_sessions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  plan_day_id uuid not null unique references public.chem_learning_plans(id) on delete cascade,
  curriculum_day_id text not null references public.chem_junior_curriculum_days(id) on delete restrict,
  study_date date not null,
  textbook_version text not null,
  knowledge_skill_ids text[] not null check (cardinality(knowledge_skill_ids) = 3),
  initial_question_target smallint not null default 12 check (initial_question_target = 12),
  hard_question_cap smallint not null default 15 check (hard_question_cap = 15),
  status text not null default 'active' check (status in ('active', 'completed', 'blocked', 'abandoned')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, curriculum_day_id)
);

create table if not exists public.chem_junior_session_steps (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.chem_junior_daily_sessions(id) on delete cascade,
  sequence smallint not null check (sequence between 1 and 15),
  question_id text not null references public.chem_questions(id) on delete restrict,
  mother_id text not null,
  skill_id text not null references public.chem_skills(id) on delete restrict,
  knowledge_id text not null references public.chem_skills(id) on delete restrict,
  same_type_key text not null,
  source_item_key text not null,
  parent_source_item_key text not null,
  content_fingerprint text not null check (content_fingerprint ~ '^[0-9a-f]{64}$'),
  level smallint not null check (level between 1 and 8),
  route_kind text not null check (route_kind in ('new_learning', 'advance', 'stability_validation', 'foundation_repair', 'prior_error_recovery')),
  route_reason text not null,
  question_snapshot jsonb not null,
  selected_option smallint,
  uncertain boolean,
  duration_sec integer,
  correct boolean,
  answered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (session_id, sequence),
  unique (session_id, question_id),
  check (
    (answered_at is null and selected_option is null and uncertain is null and duration_sec is null and correct is null)
    or (answered_at is not null and selected_option is not null and uncertain is not null and duration_sec is not null and correct is not null)
  )
);

create index if not exists chem_junior_session_steps_student_history_idx
  on public.chem_junior_session_steps (skill_id, same_type_key, source_item_key, parent_source_item_key, content_fingerprint);

create index if not exists chem_junior_session_steps_session_idx
  on public.chem_junior_session_steps (session_id, sequence);

alter table public.chem_junior_curriculum_days enable row level security;
alter table public.chem_junior_daily_sessions enable row level security;
alter table public.chem_junior_session_steps enable row level security;

create or replace function public.chem_junior_record_step(
  p_session_id uuid,
  p_student_id uuid,
  p_step_id uuid,
  p_selected_option smallint,
  p_uncertain boolean,
  p_duration_sec integer,
  p_revision_token text
)
returns table (
  step_id uuid,
  question_id text,
  selected_option smallint,
  uncertain boolean,
  duration_sec integer,
  correct boolean,
  answered_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_step record;
  v_correct boolean;
  v_duration integer;
begin
  if p_session_id is null or p_student_id is null or p_step_id is null
    or p_selected_option is null or p_selected_option < 0 or p_selected_option > 9
    or p_duration_sec is null or p_duration_sec < 0 or p_duration_sec > 3600 then
    raise exception 'invalid junior step answer';
  end if;

  select
    step.id, step.question_id, step.skill_id, step.level, step.answered_at,
    question.correct_option, question.question_revision_token
  into v_step
  from public.chem_junior_session_steps step
  join public.chem_junior_daily_sessions session on session.id = step.session_id
  join public.chem_questions question on question.id = step.question_id
  where step.id = p_step_id
    and step.session_id = p_session_id
    and session.student_id = p_student_id
    and session.status = 'active'
  for update of step;

  if not found then
    raise exception 'junior session step is unavailable';
  end if;
  if v_step.answered_at is not null then
    raise exception 'junior session step is already locked';
  end if;
  if coalesce(v_step.question_revision_token, '') <> coalesce(p_revision_token, '') then
    raise exception 'junior source question revision changed';
  end if;

  v_duration := least(3600, greatest(0, p_duration_sec));
  v_correct := p_selected_option = v_step.correct_option;

  update public.chem_junior_session_steps
  set selected_option = p_selected_option,
      uncertain = coalesce(p_uncertain, false),
      duration_sec = v_duration,
      correct = v_correct,
      answered_at = now(),
      updated_at = now()
  where id = p_step_id
  returning id, question_id, selected_option, uncertain, duration_sec, correct, answered_at
  into step_id, question_id, selected_option, uncertain, duration_sec, correct, answered_at;

  insert into public.chem_student_skill_state (
    student_id, skill_id, verified_level, candidate_level, stability,
    consecutive_errors, next_review_at, review_interval_index,
    last_reviewed_at, teacher_intervention, updated_at
  ) values (
    p_student_id,
    v_step.skill_id,
    case when v_correct and not coalesce(p_uncertain, false) then v_step.level else 0 end,
    case when v_correct and not coalesce(p_uncertain, false) then v_step.level else null end,
    case when v_correct and not coalesce(p_uncertain, false) then 'verified' else 'learning' end,
    case when v_correct and not coalesce(p_uncertain, false) then 0 else 1 end,
    now() + case when v_correct and not coalesce(p_uncertain, false) then interval '3 days' else interval '1 day' end,
    case when v_correct and not coalesce(p_uncertain, false) then 1 else 0 end,
    now(),
    false,
    now()
  )
  on conflict (student_id, skill_id) do update set
    verified_level = case
      when v_correct and not coalesce(p_uncertain, false)
        then greatest(public.chem_student_skill_state.verified_level, v_step.level)
      else public.chem_student_skill_state.verified_level
    end,
    candidate_level = case when v_correct and not coalesce(p_uncertain, false) then v_step.level else public.chem_student_skill_state.candidate_level end,
    stability = case when v_correct and not coalesce(p_uncertain, false) then 'verified' else 'learning' end,
    consecutive_errors = case when v_correct and not coalesce(p_uncertain, false) then 0 else public.chem_student_skill_state.consecutive_errors + 1 end,
    next_review_at = now() + case when v_correct and not coalesce(p_uncertain, false) then interval '3 days' else interval '1 day' end,
    review_interval_index = case when v_correct and not coalesce(p_uncertain, false) then least(4, public.chem_student_skill_state.review_interval_index + 1) else 0 end,
    last_reviewed_at = now(),
    teacher_intervention = case when v_correct and not coalesce(p_uncertain, false) then public.chem_student_skill_state.teacher_intervention else public.chem_student_skill_state.consecutive_errors >= 2 end,
    updated_at = now();

  return next;
end;
$$;

create or replace function public.chem_junior_finalize_session(
  p_session_id uuid,
  p_student_id uuid
)
returns table (completed boolean, total_questions integer, correct_questions integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session record;
  v_total integer;
  v_answered integer;
  v_correct integer;
begin
  select * into v_session
  from public.chem_junior_daily_sessions
  where id = p_session_id and student_id = p_student_id
  for update;
  if not found then raise exception 'junior session is unavailable'; end if;
  if v_session.status = 'completed' then
    select count(*)::integer, count(*) filter (where correct)::integer
    into v_total, v_correct
    from public.chem_junior_session_steps where session_id = p_session_id;
    return query select true, v_total, v_correct;
    return;
  end if;
  if v_session.status <> 'active' then raise exception 'junior session cannot be finalized'; end if;

  select count(*)::integer, (count(*) filter (where answered_at is not null))::integer,
         (count(*) filter (where correct))::integer
  into v_total, v_answered, v_correct
  from public.chem_junior_session_steps
  where session_id = p_session_id;
  if v_total not between v_session.initial_question_target and v_session.hard_question_cap
    or v_answered <> v_total then
    raise exception 'junior session is not ready to finalize';
  end if;

  update public.chem_junior_daily_sessions
  set status = 'completed', completed_at = now(), updated_at = now()
  where id = p_session_id;
  return query select true, v_total, v_correct;
end;
$$;

revoke all on function public.chem_junior_record_step(uuid, uuid, uuid, smallint, boolean, integer, text) from public, anon, authenticated;
revoke all on function public.chem_junior_finalize_session(uuid, uuid) from public, anon, authenticated;
grant execute on function public.chem_junior_record_step(uuid, uuid, uuid, smallint, boolean, integer, text) to service_role;
grant execute on function public.chem_junior_finalize_session(uuid, uuid) to service_role;
