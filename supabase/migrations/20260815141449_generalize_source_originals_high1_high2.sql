-- Extend the audited private source-release machinery from High-3 to High-1/High-2.
-- The browser still receives no direct table access and no source citation.

alter table app_private.chem_question_source_releases
  drop constraint if exists chem_question_source_releases_grade_band_check,
  drop constraint if exists chem_question_source_releases_expected_question_count_check,
  add constraint chem_question_source_releases_grade_band_check
    check (grade_band in ('高一','高二','高三')),
  add constraint chem_question_source_releases_expected_question_count_check
    check (expected_question_count = case grade_band when '高一' then 125 when '高二' then 200 else 275 end);

drop index if exists app_private.chem_question_source_releases_one_active_h3_uidx;
create unique index chem_question_source_releases_one_active_grade_uidx
  on app_private.chem_question_source_releases(grade_band)
  where status = 'active';

drop index if exists public.chem_questions_h3_review_original_source_item_uidx;
drop index if exists public.chem_questions_h3_review_original_fingerprint_uidx;
drop index if exists public.chem_questions_h3_review_original_mother_uidx;
create unique index chem_questions_review_original_source_item_uidx
  on public.chem_questions(grade_band, source_item_key)
  where grade_band in ('高一','高二','高三') and source_kind='licensed_local' and review_status='approved' and usable_for_review;
create unique index chem_questions_review_original_fingerprint_uidx
  on public.chem_questions(grade_band, content_fingerprint)
  where grade_band in ('高一','高二','高三') and source_kind='licensed_local' and review_status='approved' and usable_for_review;
create unique index chem_questions_review_original_mother_uidx
  on public.chem_questions(grade_band, mother_id)
  where grade_band in ('高一','高二','高三') and source_kind='licensed_local' and review_status='approved' and usable_for_review;

update public.chem_questions
set usable_for_demo = true
where grade_band in ('高一','高二') and source_kind='teacher_original' and id like 'Q5R_H%';

create or replace function public.chem_lock_question_answer(
  p_student_id uuid,
  p_plan_day_id uuid,
  p_attempt_sequence integer,
  p_question_id text,
  p_selected_option integer,
  p_uncertain boolean,
  p_duration_sec integer,
  p_revision_token text
)
returns table (
  selected_option integer,
  uncertain boolean,
  duration_sec integer,
  revision_token text,
  created_at timestamptz,
  is_new boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inserted integer := 0;
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

  if not exists (
    select 1
    from public.chem_learning_plans p
    where p.id = p_plan_day_id
      and p.student_id = p_student_id
  ) then
    raise exception 'plan does not belong to student';
  end if;

  if not exists (
    select 1
    from public.chem_questions q
    where q.id = p_question_id
      and q.grade_band in ('高一','高二','高三')
      and q.source_kind = 'licensed_local'
      and q.review_status = 'approved'
      and q.scope_status = 'IN'
      and q.usable_for_review
      and q.question_revision_token is not distinct from nullif(p_revision_token, '')
  ) then
    raise exception 'question revision is stale or not eligible for an answer lock';
  end if;

  insert into app_private.chem_question_answer_locks (
    student_id,
    plan_day_id,
    attempt_sequence,
    question_id,
    selected_option,
    uncertain,
    duration_sec,
    revision_token
  ) values (
    p_student_id,
    p_plan_day_id,
    p_attempt_sequence,
    p_question_id,
    p_selected_option,
    coalesce(p_uncertain, false),
    p_duration_sec,
    nullif(p_revision_token, '')
  )
  on conflict (student_id, plan_day_id, attempt_sequence, question_id) do nothing;
  get diagnostics v_inserted = row_count;

  return query
  select
    l.selected_option::integer,
    l.uncertain,
    l.duration_sec,
    l.revision_token,
    l.created_at,
    v_inserted = 1
  from app_private.chem_question_answer_locks l
  where l.student_id = p_student_id
    and l.plan_day_id = p_plan_day_id
    and l.attempt_sequence = p_attempt_sequence
    and l.question_id = p_question_id;
end;
$$;

create or replace function public.chem_get_question_answer_locks(
  p_student_id uuid,
  p_plan_day_id uuid,
  p_attempt_sequence integer,
  p_question_ids text[]
)
returns table (
  question_id text,
  selected_option integer,
  uncertain boolean,
  duration_sec integer,
  revision_token text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_student_id is null
    or p_plan_day_id is null
    or p_attempt_sequence is null
    or p_attempt_sequence not between 0 and 7
    or coalesce(array_length(p_question_ids, 1), 0) not between 1 and 10
  then
    raise exception 'invalid answer lock lookup';
  end if;

  return query
  select
    l.question_id,
    l.selected_option::integer,
    l.uncertain,
    l.duration_sec,
    l.revision_token,
    l.created_at
  from app_private.chem_question_answer_locks l
  where l.student_id = p_student_id
    and l.plan_day_id = p_plan_day_id
    and l.attempt_sequence = p_attempt_sequence
    and l.question_id = any(p_question_ids);
end;
$$;

create or replace function public.chem_delete_question_answer_locks(
  p_student_id uuid,
  p_plan_day_id uuid,
  p_attempt_sequence integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  delete from app_private.chem_question_answer_locks l
  where l.student_id = p_student_id
    and l.plan_day_id = p_plan_day_id
    and l.attempt_sequence = p_attempt_sequence;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

create or replace function public.chem_has_current_question_answer_lock(
  p_student_id uuid,
  p_plan_day_id uuid,
  p_attempt_sequence integer,
  p_question_id text,
  p_revision_token text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from app_private.chem_question_answer_locks l
    join public.chem_learning_plans p
      on p.id = l.plan_day_id
     and p.student_id = l.student_id
    where l.student_id = p_student_id
      and l.plan_day_id = p_plan_day_id
      and l.attempt_sequence = p_attempt_sequence
      and l.question_id = p_question_id
      and l.revision_token is not distinct from nullif(p_revision_token, '')
      and l.attempt_sequence = (
        select count(*)::integer
        from public.chem_learning_attempts a
        where a.student_id = l.student_id
          and a.plan_day_id = l.plan_day_id
      )
  );
$$;

-- Finalizing a learning round is one database transaction.  The Edge
-- Function still recomputes and validates the exact server-issued question
-- set, but a process interruption can no longer leave an attempt without all
-- answers, mismatched skill state, or uncleared first-answer locks.
create or replace function public.chem_finalize_learning_attempt(
  p_attempt_id uuid,
  p_student_id uuid,
  p_plan_day_id uuid,
  p_attempt_kind text,
  p_sequence integer,
  p_mode text,
  p_started_at timestamptz,
  p_completed_at timestamptz,
  p_first_score integer,
  p_answers jsonb,
  p_skill_states jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
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
  if v_answer_count not between 1 and 10
    or jsonb_array_length(p_skill_states) not between 1 and 10
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
$$;

revoke all on function public.chem_lock_question_answer(uuid,uuid,integer,text,integer,boolean,integer,text) from public, anon, authenticated;
revoke all on function public.chem_get_question_answer_locks(uuid,uuid,integer,text[]) from public, anon, authenticated;
revoke all on function public.chem_delete_question_answer_locks(uuid,uuid,integer) from public, anon, authenticated;
revoke all on function public.chem_has_current_question_answer_lock(uuid,uuid,integer,text,text) from public, anon, authenticated;
revoke all on function public.chem_finalize_learning_attempt(uuid,uuid,uuid,text,integer,text,timestamptz,timestamptz,integer,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.chem_lock_question_answer(uuid,uuid,integer,text,integer,boolean,integer,text) to service_role;

create or replace function public.chem_reset_source_original_staged_release(
  p_release_id uuid,
  p_manifest_sha256 text,
  p_grade_band text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_grade_band not in ('高一','高二') then
    raise exception 'only High-1 and High-2 use this staging entrypoint';
  end if;
  if coalesce(p_manifest_sha256, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid release manifest digest';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release', 0));
  if exists (
    select 1 from app_private.chem_question_source_releases r
    where r.id = p_release_id and r.status in ('active','retired')
  ) then
    raise exception 'an active or retired release cannot be reset';
  end if;

  delete from app_private.chem_question_source_release_items where release_id = p_release_id;
  delete from app_private.chem_question_assets a
  using public.chem_questions q
  where q.source_release_id = p_release_id and a.question_id = q.id;
  delete from public.chem_questions where source_release_id = p_release_id;
  delete from app_private.chem_question_source_releases where id = p_release_id;

  insert into app_private.chem_question_source_releases(
    id, manifest_sha256, grade_band, status, expected_question_count,
    verification_status, verification_manifest_sha256, verification_actor, verified_at
  ) values (
    p_release_id, p_manifest_sha256, p_grade_band, 'staged',
    case p_grade_band when '高一' then 125 else 200 end,
    'pending', null, null, null
  );
end;
$$;

create or replace function public.chem_stage_source_original_assets(
  p_release_id uuid,
  p_assets jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expected integer;
  v_inserted integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release', 0));
  if not exists (
    select 1 from app_private.chem_question_source_releases r
    where r.id = p_release_id and r.status = 'staged'
  ) then
    raise exception 'assets can only be added to a staged release';
  end if;
  if p_assets is null or jsonb_typeof(p_assets) <> 'array' then
    raise exception 'invalid source asset batch';
  end if;
  if jsonb_array_length(p_assets) not between 1 and 20
    or coalesce((
      select sum(length(e->>'payload_base64')) from jsonb_array_elements(p_assets) e
    ), 0) > 4000000
    or exists (
      select 1 from jsonb_array_elements(p_assets) e
      where (select count(*) from pg_catalog.jsonb_object_keys(e)) <> 8
        or not (e ?& array['asset_path','question_id','asset_kind','mime_type','payload_base64','sha256','width','height'])
    )
  then
    raise exception 'invalid source asset batch';
  end if;
  v_expected := jsonb_array_length(p_assets);
  if exists (
    select 1
    from jsonb_to_recordset(p_assets) as x(question_id text)
    left join public.chem_questions q on q.id = x.question_id
    where q.id is null or q.source_release_id is distinct from p_release_id
  ) then
    raise exception 'an asset does not belong to this staged release';
  end if;

  insert into app_private.chem_question_assets(
    asset_path, question_id, asset_kind, mime_type, payload_base64, sha256, width, height
  )
  select x.asset_path, x.question_id, x.asset_kind, x.mime_type,
    x.payload_base64, x.sha256, x.width, x.height
  from jsonb_to_recordset(p_assets) as x(
    asset_path text, question_id text, asset_kind text, mime_type text,
    payload_base64 text, sha256 text, width integer, height integer
  );
  get diagnostics v_inserted = row_count;
  if v_inserted <> v_expected then raise exception 'source asset batch was not inserted completely'; end if;
  return v_inserted;
end;
$$;

create or replace function public.chem_stage_source_original_release_items(
  p_release_id uuid,
  p_items jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expected integer;
  v_inserted integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release', 0));
  if not exists (
    select 1 from app_private.chem_question_source_releases r
    where r.id = p_release_id and r.status = 'staged'
  ) then
    raise exception 'release items can only be added to a staged release';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'invalid release item batch';
  end if;
  if jsonb_array_length(p_items) not between 1 and 275
    or exists (
      select 1 from jsonb_array_elements(p_items) e
      where (select count(*) from pg_catalog.jsonb_object_keys(e)) <> 5
        or not (e ?& array['question_id','canonical_source_id','question_asset_sha256','analysis_asset_sha256','item_sha256'])
    )
  then
    raise exception 'invalid release item batch';
  end if;
  v_expected := jsonb_array_length(p_items);
  if exists (
    select 1
    from jsonb_to_recordset(p_items) as x(question_id text)
    left join public.chem_questions q on q.id = x.question_id
    where q.id is null or q.source_release_id is distinct from p_release_id
  ) then
    raise exception 'a release item does not belong to this staged release';
  end if;

  insert into app_private.chem_question_source_release_items(
    release_id, question_id, canonical_source_id,
    question_asset_sha256, analysis_asset_sha256, item_sha256
  )
  select p_release_id, x.question_id, x.canonical_source_id,
    x.question_asset_sha256, x.analysis_asset_sha256, x.item_sha256
  from jsonb_to_recordset(p_items) as x(
    question_id text, canonical_source_id text,
    question_asset_sha256 text, analysis_asset_sha256 text, item_sha256 text
  );
  get diagnostics v_inserted = row_count;
  if v_inserted <> v_expected then raise exception 'release item batch was not inserted completely'; end if;
  return v_inserted;
end;
$$;

create or replace function public.chem_mark_source_original_release_visually_verified(
  p_release_id uuid,
  p_manifest_sha256 text,
  p_verification_actor text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release', 0));
  if p_verification_actor is distinct from 'codex-full-visual-qa' then
    raise exception 'verification actor is not the server-owned full visual QA identity';
  end if;
  update app_private.chem_question_source_releases
  set verification_status = 'full_visual_verified',
      verification_manifest_sha256 = p_manifest_sha256,
      verification_actor = btrim(p_verification_actor),
      verified_at = now()
  where id = p_release_id
    and status = 'staged'
    and manifest_sha256 = p_manifest_sha256;
  if not found then raise exception 'staged release and verified manifest do not match'; end if;
end;
$$;

create or replace function public.chem_preflight_source_original_release(
  p_release_id uuid,
  p_manifest_sha256 text
)
returns table (
  status text,
  "verificationStatus" text,
  questions integer,
  assets integer,
  items integer,
  active boolean
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_release_id is null or coalesce(p_manifest_sha256, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid release identity';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release', 0));
  if not exists (
    select 1
    from app_private.chem_question_source_releases r
    where r.id = p_release_id
      and r.manifest_sha256 = p_manifest_sha256
      and r.grade_band in ('高一','高二','高三')
  ) then
    raise exception 'source release and manifest do not match';
  end if;

  return query
  select
    r.status,
    r.verification_status,
    (
      select count(*)::integer
      from public.chem_questions q
      where q.source_release_id = r.id
    ),
    (
      select count(*)::integer
      from app_private.chem_question_assets a
      join public.chem_questions q on q.id = a.question_id
      where q.source_release_id = r.id
    ),
    (
      select count(*)::integer
      from app_private.chem_question_source_release_items ri
      where ri.release_id = r.id
    ),
    r.status = 'active'
  from app_private.chem_question_source_releases r
  where r.id = p_release_id
    and r.manifest_sha256 = p_manifest_sha256;
end;
$$;

revoke all on function public.chem_reset_source_original_staged_release(uuid,text,text) from public, anon, authenticated;
revoke all on function public.chem_stage_source_original_assets(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.chem_stage_source_original_release_items(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.chem_mark_source_original_release_visually_verified(uuid,text,text) from public, anon, authenticated;
revoke all on function public.chem_preflight_source_original_release(uuid,text) from public, anon, authenticated;
grant execute on function public.chem_reset_source_original_staged_release(uuid,text,text) to service_role;
grant execute on function public.chem_stage_source_original_assets(uuid,jsonb) to service_role;
grant execute on function public.chem_stage_source_original_release_items(uuid,jsonb) to service_role;
grant execute on function public.chem_mark_source_original_release_visually_verified(uuid,text,text) to service_role;
grant execute on function public.chem_preflight_source_original_release(uuid,text) to service_role;

create or replace function public.chem_activate_source_original_release(
  p_release_id uuid,
  p_manifest_sha256 text
)
returns table (release_id uuid, activated_questions integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_question_count integer;
  v_distinct_count integer;
  v_computed_manifest text;
  v_release_manifest text;
  v_release_status text;
  v_release_expected integer;
  v_verification_status text;
  v_verification_manifest text;
  v_verification_actor text;
  v_verified_at timestamptz;
  v_skill_ids text[];
  v_expected_skill_ids text[];
  v_grade_band text;
  v_expected_concept_count integer;
begin
  if p_release_id is null or coalesce(p_manifest_sha256, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid release identity';
  end if;

  -- Serialize release switches.  Every assertion and both the old/new pool
  -- updates run in this function's transaction, so a failed assertion leaves
  -- the currently active REVIEW pool unchanged.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release', 0));

  select r.manifest_sha256, r.status, r.expected_question_count,
    r.verification_status, r.verification_manifest_sha256,
    r.verification_actor, r.verified_at, r.grade_band
  into v_release_manifest, v_release_status, v_release_expected,
    v_verification_status, v_verification_manifest,
    v_verification_actor, v_verified_at, v_grade_band
  from app_private.chem_question_source_releases r
  where r.id = p_release_id
    and r.grade_band in ('高一','高二','高三')
  for update;

  if not found
    or v_release_manifest <> p_manifest_sha256
    or v_release_status <> 'staged'
    or v_release_expected <> (case v_grade_band when '高一' then 125 when '高二' then 200 else 275 end)
    or v_verification_status <> 'full_visual_verified'
    or v_verification_manifest is distinct from p_manifest_sha256
    or length(btrim(coalesce(v_verification_actor, ''))) < 8
    or v_verified_at is null
  then
    raise exception 'release is missing, unverified, already activated, or manifest hash does not match';
  end if;

  v_expected_skill_ids := case v_grade_band
    when '高一' then array['H1_CLASSIFY','H1_GAS_MOLAR_VOLUME','H1_MOLE_INTRO','H1_PERIODIC','H1_REDOX']::text[]
    when '高二' then array['H2_ELECTRO','H2_EQUIL','H2_K','H2_KSP','H2_PH_HYDRO','H2_RATE','H2_THERMO','H2_WEAK']::text[]
    else array['H3_AQ','H3_ELECTRO','H3_EQUILIBRIUM','H3_EXPERIMENT','H3_INORGANIC','H3_ION_REDOX','H3_ORGANIC','H3_PROCESS','H3_STOICH','H3_STRUCTURE','H3_THERMO_RATE']::text[]
  end;
  v_expected_concept_count := pg_catalog.array_length(v_expected_skill_ids, 1) * 5;

  -- Freeze the entire staged release while it is being verified.  The parent
  -- release row lock also blocks concurrent FK inserts; these deterministic
  -- child locks close the check-to-activate race for updates and deletes.
  perform q.id
  from public.chem_questions q
  where q.source_release_id = p_release_id
  order by q.id
  for update;

  perform a.asset_path
  from app_private.chem_question_assets a
  join public.chem_questions q on q.id = a.question_id
  where q.source_release_id = p_release_id
  order by a.asset_path
  for update of a;

  perform ri.question_id
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id
  order by ri.question_id
  for update;

  select count(*) into v_question_count
  from public.chem_questions q
  where q.source_release_id = p_release_id;
  if v_question_count <> v_release_expected then
    raise exception 'release must contain exactly % questions, found %', v_release_expected, v_question_count;
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        q.grade_band <> v_grade_band
        or q.source_kind <> 'licensed_local'
        or q.review_status <> 'approved'
        or q.scope_status <> 'IN'
        or q.usable_for_review
        or q.usable_for_class_quiz
        or q.usable_for_exam_sprint
        or q.usable_for_demo
        or q.mother_id is null
        or q.concept_key is null
        or q.concept_key not in (
          q.skill_id || '__C01', q.skill_id || '__C02', q.skill_id || '__C03',
          q.skill_id || '__C04', q.skill_id || '__C05'
        )
        or length(btrim(coalesce(q.stem, ''))) = 0
        or length(btrim(coalesce(q.explanation, ''))) = 0
        or jsonb_typeof(q.options) <> 'array'
        or case when jsonb_typeof(q.options) = 'array' then
          jsonb_array_length(q.options) <> 4
          or exists (
            select 1 from jsonb_array_elements(q.options) option_value
            where jsonb_typeof(option_value) <> 'string'
          )
          else true end
        or q.correct_option not between 0 and 3
        or coalesce(q.content_fingerprint, '') !~ '^[0-9a-f]{64}$'
        or coalesce(q.question_revision_token, '') !~ '^[0-9a-f]{64}$'
        or q.render_mode <> 'image_primary'
        or jsonb_array_length(q.asset_refs) <> 2
      )
  ) then
    raise exception 'release contains an unapproved, ineligible, non-four-option, or prematurely enabled question';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    cross join lateral jsonb_array_elements_text(q.options) option_text
    where q.source_release_id = p_release_id
      and length(btrim(option_text)) = 0
  ) then
    raise exception 'release contains an empty answer option';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        select count(distinct btrim(option_text))
        from jsonb_array_elements_text(q.options) option_text
      ) <> 4
  ) then
    raise exception 'release contains duplicated answer options';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and q.content_fingerprint is distinct from
        app_private.chem_h3_content_fingerprint(q.stem, q.options)
  ) then
    raise exception 'content fingerprint must equal the normalized stem and four options';
  end if;

  select array_agg(distinct q.skill_id order by q.skill_id)
  into v_skill_ids
  from public.chem_questions q
  where q.source_release_id = p_release_id;
  if v_skill_ids is distinct from v_expected_skill_ids then
    raise exception 'release does not contain the exact REVIEW skills for the release grade';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
    group by q.skill_id
    having count(*) <> 25 or count(distinct q.concept_key) <> 5
  ) then
    raise exception 'every release skill must contain 25 questions across exactly five concepts';
  end if;

  if (
    select count(*)
    from (
      select q.skill_id, q.concept_key
      from public.chem_questions q
      where q.source_release_id = p_release_id
      group by q.skill_id, q.concept_key
      having count(*) = 5
    ) concept_groups
  ) <> v_expected_concept_count then
    raise exception 'every fine concept must contain exactly five questions';
  end if;

  select count(distinct q.id) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'question ids are not unique inside release'; end if;
  select count(distinct q.mother_id) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'mother ids are not unique inside release'; end if;
  select count(distinct q.source_item_key) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'source item identities are not unique inside release'; end if;
  select count(distinct q.content_fingerprint) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'content fingerprints are not unique inside release'; end if;
  select count(distinct q.question_revision_token) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'question revision tokens are not unique inside release'; end if;

  select count(*) into v_question_count
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id;
  if v_question_count <> v_release_expected then
    raise exception 'release ledger must contain exactly % items, found %', v_release_expected, v_question_count;
  end if;

  select count(distinct ri.canonical_source_id) into v_distinct_count
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id;
  if v_distinct_count <> v_release_expected then
    raise exception 'canonical source identities are not unique inside release';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    left join app_private.chem_question_source_release_items ri
      on ri.release_id = p_release_id
     and ri.question_id = q.id
    where q.source_release_id = p_release_id
      and ri.question_id is null
  ) then
    raise exception 'release ledger is missing a staged question';
  end if;

  -- Every descriptor must resolve to the exact binary metadata recorded on
  -- that question.  A non-native question additionally needs a question-side
  -- visual; an analysis image alone is not enough to make the stem readable.
  if exists (
    select 1
    from public.chem_questions q
    cross join lateral jsonb_array_elements(q.asset_refs) ref
    where q.source_release_id = p_release_id
      and (
        coalesce(btrim(ref->>'alt'), '') = ''
        or coalesce(ref->>'path', '') !~ '^[a-zA-Z0-9/_-]{16,200}$'
        or coalesce(ref->>'kind', '') not in ('question_image','formula_fallback','source_scan','analysis_image')
        or coalesce(ref->>'sha256', '') !~ '^[0-9a-f]{64}$'
        or (select count(*) from jsonb_object_keys(ref)) <> 6
        or exists (
          select 1 from jsonb_object_keys(ref) key_name
          where key_name not in ('kind','path','alt','sha256','width','height')
        )
      )
  ) then
    raise exception 'release contains a malformed or inaccessible asset descriptor';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        (select count(*) from jsonb_object_keys(q.source_info)) <> 12
        or exists (
          select 1 from jsonb_object_keys(q.source_info) key_name
          where key_name not in (
            'title','exam','year','questionNo','locator','transcriptionPolicy',
            'optionTranscriptionPolicy','transcriptionAuditMethod','sourcePairingStatus',
            'sourceMarkerStyle','sourceMarkerLabel','conceptLabel'
          )
        )
        or coalesce(q.source_info->>'transcriptionPolicy', '') <> 'source_image_authoritative'
        or coalesce(btrim(q.source_info->>'optionTranscriptionPolicy'), '') = ''
        or coalesce(btrim(q.source_info->>'transcriptionAuditMethod'), '') = ''
        or coalesce(q.source_info->>'sourcePairingStatus', '') not in ('EXACT','SOURCE_NATIVE_PAIR')
        or coalesce(q.source_info->>'sourceMarkerStyle', '') not in ('bracketed','plain_answer_analysis')
        or coalesce(btrim(q.source_info->>'sourceMarkerLabel'), '') = ''
        or coalesce(btrim(q.source_info->>'conceptLabel'), '') = ''
      )
  ) then
    raise exception 'release contains an incomplete or non-canonical public source record';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        jsonb_array_length(q.asset_refs) <> 2
        or jsonb_array_length(q.asset_refs) <> (
          select count(distinct ref->>'path')
          from jsonb_array_elements(q.asset_refs) ref
        )
        or (select count(*) from jsonb_array_elements(q.asset_refs) ref where ref->>'kind' = 'question_image') <> 1
        or (select count(*) from jsonb_array_elements(q.asset_refs) ref where ref->>'kind' = 'analysis_image') <> 1
        or (select count(*) from jsonb_array_elements(q.asset_refs) ref where ref->>'kind' not in ('question_image','analysis_image')) <> 0
      )
  ) then
    raise exception 'every release question must have exactly one question image and one analysis image';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    cross join lateral jsonb_array_elements(q.asset_refs) ref
    left join app_private.chem_question_assets a
      on a.question_id = q.id
     and a.asset_path = ref->>'path'
     and a.asset_kind = ref->>'kind'
     and a.sha256 = ref->>'sha256'
     and a.width::text = ref->>'width'
     and a.height::text = ref->>'height'
    where q.source_release_id = p_release_id
      and a.asset_path is null
  ) then
    raise exception 'release contains a missing or metadata-mismatched private asset';
  end if;

  if exists (
    select 1
    from app_private.chem_question_assets a
    join public.chem_questions q on q.id = a.question_id
    where q.source_release_id = p_release_id
      and encode(extensions.digest(decode(a.payload_base64, 'base64'), 'sha256'), 'hex') <> a.sha256
  ) then
    raise exception 'private asset payload does not match its SHA-256 digest';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    left join lateral (
      select
        count(*) as asset_count,
        count(*) filter (where a.asset_kind = 'question_image') as question_count,
        count(*) filter (where a.asset_kind = 'analysis_image') as analysis_count
      from app_private.chem_question_assets a
      where a.question_id = q.id
    ) counts on true
    where q.source_release_id = p_release_id
      and (
        counts.asset_count <> 2
        or counts.question_count <> 1
        or counts.analysis_count <> 1
      )
  ) then
    raise exception 'private asset store must contain exactly the two declared images per question';
  end if;

  if exists (
    select 1
    from app_private.chem_question_assets a
    join public.chem_questions q on q.id = a.question_id
    where q.source_release_id = p_release_id
      and a.mime_type <> 'image/webp'
  ) then
    raise exception 'release assets must use the audited lossless WebP transport';
  end if;

  if exists (
    select 1
    from app_private.chem_question_source_release_items ri
    join public.chem_questions q
      on q.id = ri.question_id
     and q.source_release_id = ri.release_id
    join app_private.chem_question_assets question_asset
      on question_asset.question_id = q.id
     and question_asset.asset_kind = 'question_image'
    join app_private.chem_question_assets analysis_asset
      on analysis_asset.question_id = q.id
     and analysis_asset.asset_kind = 'analysis_image'
    where ri.release_id = p_release_id
      and (
        ri.question_asset_sha256 <> question_asset.sha256
        or ri.analysis_asset_sha256 <> analysis_asset.sha256
        or q.question_revision_token is distinct from
          app_private.chem_h3_question_revision_sha256(
            q,
            question_asset.sha256,
            analysis_asset.sha256
          )
        or ri.item_sha256 <> app_private.chem_h3_release_item_sha256(
          q,
          ri.canonical_source_id,
          question_asset.sha256,
          analysis_asset.sha256
        )
      )
  ) then
    raise exception 'release revision token or ledger digest does not match the staged question and assets';
  end if;

  select pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        pg_catalog.string_agg(ri.item_sha256, E'\n' order by ri.question_id),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
  into v_computed_manifest
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id;

  if v_computed_manifest is distinct from v_release_manifest
    or v_computed_manifest is distinct from p_manifest_sha256
  then
    raise exception 'release manifest does not match the staged source items';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and q.render_mode <> 'native'
      and not exists (
        select 1
        from jsonb_array_elements(q.asset_refs) ref
        join app_private.chem_question_assets a
          on a.question_id = q.id
         and a.asset_path = ref->>'path'
         and a.asset_kind = ref->>'kind'
        where ref->>'kind' in ('question_image','formula_fallback','source_scan')
      )
  ) then
    raise exception 'every non-native question must have a verified question-side asset';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        not exists (
          select 1
          from jsonb_array_elements(q.asset_refs) ref
          join app_private.chem_question_assets a
            on a.question_id = q.id
           and a.asset_path = ref->>'path'
           and a.asset_kind = 'question_image'
          where ref->>'kind' = 'question_image'
        )
        or not exists (
          select 1
          from jsonb_array_elements(q.asset_refs) ref
          join app_private.chem_question_assets a
            on a.question_id = q.id
           and a.asset_path = ref->>'path'
           and a.asset_kind = 'analysis_image'
          where ref->>'kind' = 'analysis_image'
        )
      )
  ) then
    raise exception 'every source-backed question must have both question and analysis images';
  end if;

  perform pg_catalog.set_config('app.chem_release_activation', 'on', true);

  update public.chem_questions
  set usable_for_review = false,
      updated_at = now()
  where grade_band = v_grade_band
    and usable_for_review
    and source_release_id is distinct from p_release_id;

  update public.chem_questions
  set usable_for_review = true,
      updated_at = now()
  where source_release_id = p_release_id;
  get diagnostics v_question_count = row_count;
  if v_question_count <> v_release_expected then
    raise exception 'activation updated %, expected %', v_question_count, v_release_expected;
  end if;

  update app_private.chem_question_source_releases
  set status = 'retired', retired_at = now()
  where grade_band = v_grade_band and status = 'active' and id <> p_release_id;

  update app_private.chem_question_source_releases
  set status = 'active', activated_at = now(), retired_at = null
  where id = p_release_id;
  get diagnostics v_distinct_count = row_count;
  if v_distinct_count <> 1 then
    raise exception 'release activation status update affected %, expected 1', v_distinct_count;
  end if;

  select count(*) into v_question_count
  from public.chem_questions q
  where q.grade_band = v_grade_band
    and q.usable_for_review
    and q.source_release_id = p_release_id;
  if v_question_count <> v_release_expected then
    raise exception 'postcondition failed: active release exposes %, expected %', v_question_count, v_release_expected;
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.grade_band = v_grade_band
      and q.usable_for_review
      and q.source_release_id is distinct from p_release_id
  ) then
    raise exception 'postcondition failed: an older same-grade REVIEW question remains enabled';
  end if;

  select count(*) into v_distinct_count
  from app_private.chem_question_source_releases r
  where r.grade_band = v_grade_band and r.status = 'active';
  if v_distinct_count <> 1 then
    raise exception 'postcondition failed: the grade must have exactly one active source release';
  end if;

  -- Do not leave the narrowly scoped activation bypass enabled for any later
  -- statements when a caller invokes this function inside a larger transaction.
  perform pg_catalog.set_config('app.chem_release_activation', 'off', true);

  return query select p_release_id, v_question_count;
end;
$$;

revoke all on function public.chem_activate_source_original_release(uuid, text) from public, anon, authenticated;
grant execute on function public.chem_activate_source_original_release(uuid, text) to service_role;
