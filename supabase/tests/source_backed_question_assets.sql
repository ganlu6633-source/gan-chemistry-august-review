do $$
declare
  asset_rpc regprocedure := to_regprocedure('public.chem_get_question_assets(text[])');
  activation_rpc regprocedure := to_regprocedure('public.chem_activate_h3_original_release(uuid,text)');
  preflight_rpc regprocedure := to_regprocedure('public.chem_preflight_h3_original_release(uuid,text)');
  reset_release_rpc regprocedure := to_regprocedure('public.chem_reset_h3_original_staged_release(uuid,text)');
  stage_assets_rpc regprocedure := to_regprocedure('public.chem_stage_h3_original_assets(uuid,jsonb)');
  stage_items_rpc regprocedure := to_regprocedure('public.chem_stage_h3_original_release_items(uuid,jsonb)');
  mark_verified_rpc regprocedure := to_regprocedure('public.chem_mark_h3_original_release_visually_verified(uuid,text,text)');
  asset_guard_rpc regprocedure := to_regprocedure('app_private.chem_guard_source_asset_mutation()');
  question_guard_rpc regprocedure := to_regprocedure('app_private.chem_guard_source_question_content_mutation()');
  release_item_guard_rpc regprocedure := to_regprocedure('app_private.chem_guard_release_item_mutation()');
  eligibility_guard_rpc regprocedure := to_regprocedure('app_private.chem_guard_active_source_question_eligibility()');
  asset_table regclass := to_regclass('app_private.chem_question_assets');
  release_item_table regclass := to_regclass('app_private.chem_question_source_release_items');
  item_digest_rpc regprocedure := to_regprocedure('app_private.chem_h3_release_item_sha256(public.chem_questions,text,text,text)');
  content_fingerprint_rpc regprocedure := to_regprocedure('app_private.chem_h3_content_fingerprint(text,jsonb)');
  revision_digest_rpc regprocedure := to_regprocedure('app_private.chem_h3_question_revision_sha256(public.chem_questions,text,text)');
  answer_lock_table regclass := to_regclass('app_private.chem_question_answer_locks');
  answer_lock_rpc regprocedure := to_regprocedure('public.chem_lock_question_answer(uuid,uuid,integer,text,integer,boolean,integer,text)');
  answer_lock_lookup_rpc regprocedure := to_regprocedure('public.chem_get_question_answer_locks(uuid,uuid,integer,text[])');
  answer_lock_evidence_rpc regprocedure := to_regprocedure('public.chem_has_current_question_answer_lock(uuid,uuid,integer,text,text)');
  finalize_attempt_rpc regprocedure := to_regprocedure('public.chem_finalize_learning_attempt(uuid,uuid,uuid,text,integer,text,timestamptz,timestamptz,integer,jsonb,jsonb)');
begin
  if asset_table is null then
    raise exception 'app_private.chem_question_assets is missing';
  end if;
  if not coalesce((select relrowsecurity from pg_class where oid = asset_table), false) then
    raise exception 'private question assets must have RLS enabled';
  end if;
  if asset_rpc is null or activation_rpc is null or preflight_rpc is null
    or reset_release_rpc is null or stage_assets_rpc is null
    or stage_items_rpc is null or mark_verified_rpc is null then
    raise exception 'source-backed asset or activation RPC is missing';
  end if;
  if asset_guard_rpc is null or question_guard_rpc is null
    or release_item_guard_rpc is null or eligibility_guard_rpc is null then
    raise exception 'source-backed mutation guard is missing';
  end if;
  if exists (
    select 1
    from pg_proc
    where oid in (asset_guard_rpc, question_guard_rpc, release_item_guard_rpc, eligibility_guard_rpc)
      and not prosecdef
  ) then
    raise exception 'source-backed mutation guards must execute as security definer';
  end if;
  if release_item_table is null or item_digest_rpc is null
    or content_fingerprint_rpc is null or revision_digest_rpc is null then
    raise exception 'release manifest ledger or deterministic content/revision/item digest is missing';
  end if;
  if answer_lock_table is null or answer_lock_rpc is null or answer_lock_lookup_rpc is null or answer_lock_evidence_rpc is null or finalize_attempt_rpc is null then
    raise exception 'private first-answer lock table or RPC is missing';
  end if;
  if not coalesce((select relrowsecurity from pg_class where oid = answer_lock_table), false) then
    raise exception 'private first-answer locks must have RLS enabled';
  end if;
  if not coalesce((select relrowsecurity from pg_class where oid = release_item_table), false) then
    raise exception 'private release item ledger must have RLS enabled';
  end if;
  if has_function_privilege('anon', asset_rpc, 'execute')
     or has_function_privilege('authenticated', asset_rpc, 'execute')
     or has_function_privilege('anon', answer_lock_rpc, 'execute')
     or has_function_privilege('authenticated', answer_lock_rpc, 'execute')
     or has_function_privilege('anon', answer_lock_lookup_rpc, 'execute')
     or has_function_privilege('authenticated', answer_lock_lookup_rpc, 'execute')
     or has_function_privilege('anon', answer_lock_evidence_rpc, 'execute')
     or has_function_privilege('authenticated', answer_lock_evidence_rpc, 'execute')
     or has_function_privilege('anon', finalize_attempt_rpc, 'execute')
     or has_function_privilege('authenticated', finalize_attempt_rpc, 'execute')
     or has_function_privilege('anon', activation_rpc, 'execute')
     or has_function_privilege('authenticated', activation_rpc, 'execute')
     or has_function_privilege('anon', preflight_rpc, 'execute')
     or has_function_privilege('authenticated', preflight_rpc, 'execute')
     or has_function_privilege('anon', reset_release_rpc, 'execute')
     or has_function_privilege('authenticated', reset_release_rpc, 'execute')
     or has_function_privilege('anon', stage_assets_rpc, 'execute')
     or has_function_privilege('authenticated', stage_assets_rpc, 'execute')
     or has_function_privilege('anon', stage_items_rpc, 'execute')
     or has_function_privilege('authenticated', stage_items_rpc, 'execute')
     or has_function_privilege('anon', mark_verified_rpc, 'execute')
     or has_function_privilege('authenticated', mark_verified_rpc, 'execute') then
    raise exception 'browser roles must not execute private source RPCs';
  end if;
  if not has_function_privilege('service_role', asset_rpc, 'execute')
     or not has_function_privilege('service_role', answer_lock_rpc, 'execute')
     or not has_function_privilege('service_role', answer_lock_lookup_rpc, 'execute')
     or not has_function_privilege('service_role', answer_lock_evidence_rpc, 'execute')
     or not has_function_privilege('service_role', finalize_attempt_rpc, 'execute')
     or not has_function_privilege('service_role', activation_rpc, 'execute')
     or not has_function_privilege('service_role', preflight_rpc, 'execute')
     or not has_function_privilege('service_role', reset_release_rpc, 'execute')
     or not has_function_privilege('service_role', stage_assets_rpc, 'execute')
     or not has_function_privilege('service_role', stage_items_rpc, 'execute')
     or not has_function_privilege('service_role', mark_verified_rpc, 'execute') then
    raise exception 'server role cannot execute source-backed RPCs';
  end if;
  if exists (
    select 1
    from information_schema.role_table_grants
    where table_schema = 'app_private'
      and table_name in ('chem_question_assets', 'chem_question_source_releases', 'chem_question_source_release_items', 'chem_question_answer_locks')
      and grantee in ('anon', 'authenticated')
  ) then
    raise exception 'browser role has a direct grant on private source tables';
  end if;
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'chem_questions'
      and column_name = 'content_fingerprint'
  ) or not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'chem_questions'
      and column_name = 'source_release_id'
  ) or not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'chem_questions'
      and column_name = 'question_revision_token'
  ) then
    raise exception 'source identity/revision/release columns are missing from chem_questions';
  end if;
  if app_private.chem_h3_content_fingerprint(
      ' A' || chr(160) || chr(61480) || 'B ',
      jsonb_build_array(' C ', E'D\n', chr(12288) || 'E', chr(61481) || ' F')
    ) is distinct from app_private.chem_h3_content_fingerprint(
      'A(B',
      jsonb_build_array('C', 'D', 'E', ')F')
    )
  then
    raise exception 'semantic content normalization is not deterministic';
  end if;
end;
$$;

begin;

do $$
declare
  fixture record;
  sequence_no integer;
  attempt_kind text;
  answer_payload jsonb;
  valid_state_payload jsonb;
  bad_answer_attempt uuid := gen_random_uuid();
  bad_state_attempt uuid := gen_random_uuid();
  success_attempt uuid := gen_random_uuid();
  failed_as_expected boolean;
begin
  select
    p.id as plan_id,
    p.student_id,
    p.mode,
    q.id as question_id,
    q.mother_id,
    q.skill_id,
    q.concept_key,
    q.level,
    q.grade_band,
    q.stem,
    q.options,
    q.correct_option,
    q.explanation,
    q.content_fingerprint,
    q.question_revision_token
  into fixture
  from public.chem_learning_plans p
  join public.chem_students_v2 s on s.id = p.student_id
  join lateral (
    select q.*
    from public.chem_questions q
    where q.grade_band = s.grade_band
      and q.skill_id = any(p.skill_ids)
      and q.source_kind <> 'licensed_local'
    order by q.id
    limit 1
  ) q on true
  where p.mode = 'REVIEW'
    and s.grade_band in ('高一', '高二')
    and (select count(*) from public.chem_learning_attempts a where a.plan_day_id = p.id) between 0 and 7
  order by (select count(*) from public.chem_learning_attempts a where a.plan_day_id = p.id), p.plan_date
  limit 1;

  if fixture.plan_id is null then
    raise exception 'transactional finalize test needs one High-1/High-2 REVIEW fixture';
  end if;

  select count(*)::integer
  into sequence_no
  from public.chem_learning_attempts a
  where a.student_id = fixture.student_id
    and a.plan_day_id = fixture.plan_id;
  attempt_kind := case when sequence_no = 0 then 'scheduled' else 'review' end;

  answer_payload := jsonb_build_object(
    'question_id', fixture.question_id,
    'mother_id', fixture.mother_id,
    'skill_id', fixture.skill_id,
    'concept_key', fixture.concept_key,
    'level', fixture.level,
    'correct', true,
    'uncertain', false,
    'duration_sec', 1,
    'selected_option', fixture.correct_option,
    'revision_token', fixture.question_revision_token,
    'question_snapshot', jsonb_build_object(
      'questionId', fixture.question_id,
      'motherId', fixture.mother_id,
      'skillId', fixture.skill_id,
      'level', fixture.level,
      'gradeBand', fixture.grade_band,
      'stem', fixture.stem,
      'options', fixture.options,
      'correctOption', fixture.correct_option,
      'explanation', fixture.explanation,
      'contentFingerprint', fixture.content_fingerprint,
      'revisionToken', fixture.question_revision_token
    )
  );
  valid_state_payload := jsonb_build_object(
    'skill_id', fixture.skill_id,
    'verified_level', 0,
    'candidate_level', null,
    'stability', 'learning',
    'consecutive_errors', 0,
    'next_review_at', now() + interval '1 day',
    'review_interval_index', 0,
    'last_reviewed_at', now(),
    'teacher_intervention', false,
    'updated_at', now()
  );

  -- The attempt insert happens first inside the RPC. A later answer FK failure
  -- must roll the attempt back with the rest of the function statement.
  failed_as_expected := false;
  begin
    perform public.chem_finalize_learning_attempt(
      bad_answer_attempt,
      fixture.student_id,
      fixture.plan_id,
      attempt_kind,
      sequence_no,
      fixture.mode,
      now() - interval '1 minute',
      now(),
      1,
      jsonb_build_array(answer_payload || jsonb_build_object('skill_id', '__missing_skill__')),
      jsonb_build_array(valid_state_payload)
    );
  exception when others then
    failed_as_expected := true;
  end;
  if not failed_as_expected or exists (select 1 from public.chem_learning_attempts where id = bad_answer_attempt) then
    raise exception 'answer failure left a partial learning attempt';
  end if;

  -- A state constraint failure occurs after both attempt and answers insert;
  -- all of them must still disappear atomically.
  failed_as_expected := false;
  begin
    perform public.chem_finalize_learning_attempt(
      bad_state_attempt,
      fixture.student_id,
      fixture.plan_id,
      attempt_kind,
      sequence_no,
      fixture.mode,
      now() - interval '1 minute',
      now(),
      1,
      jsonb_build_array(answer_payload),
      jsonb_build_array(valid_state_payload || jsonb_build_object('stability', '__invalid__'))
    );
  exception when others then
    failed_as_expected := true;
  end;
  if not failed_as_expected
    or exists (select 1 from public.chem_learning_attempts where id = bad_state_attempt)
    or exists (select 1 from public.chem_attempt_answers where attempt_id = bad_state_attempt)
  then
    raise exception 'skill-state failure left a partial learning attempt or answer';
  end if;

  insert into app_private.chem_question_answer_locks (
    student_id, plan_day_id, attempt_sequence, question_id,
    selected_option, uncertain, duration_sec, revision_token
  ) values (
    fixture.student_id, fixture.plan_id, sequence_no, fixture.question_id,
    fixture.correct_option, false, 1, fixture.question_revision_token
  )
  on conflict (student_id, plan_day_id, attempt_sequence, question_id) do update set
    selected_option = excluded.selected_option,
    uncertain = excluded.uncertain,
    duration_sec = excluded.duration_sec,
    revision_token = excluded.revision_token;

  perform public.chem_finalize_learning_attempt(
    success_attempt,
    fixture.student_id,
    fixture.plan_id,
    attempt_kind,
    sequence_no,
    fixture.mode,
    now() - interval '1 minute',
    now(),
    1,
    jsonb_build_array(answer_payload),
    jsonb_build_array(valid_state_payload)
  );
  if not exists (select 1 from public.chem_learning_attempts where id = success_attempt)
    or (select count(*) from public.chem_attempt_answers where attempt_id = success_attempt) <> 1
    or exists (
      select 1
      from app_private.chem_question_answer_locks
      where student_id = fixture.student_id
        and plan_day_id = fixture.plan_id
        and attempt_sequence = sequence_no
    )
  then
    raise exception 'successful finalize did not persist one complete attempt or clear its locks';
  end if;
end;
$$;

rollback;
