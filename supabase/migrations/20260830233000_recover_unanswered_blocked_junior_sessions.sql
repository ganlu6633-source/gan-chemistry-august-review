-- Recover only release-blocked junior sessions that contain no learner answer.
-- The stale unanswered step is an obsolete question capability, not learning
-- evidence.  Answered steps and every other blocked-session reason stay
-- untouched.  The normal issue RPC will re-lock and revalidate the active
-- release before it issues a replacement original.

do $migration$
declare
  candidate record;
  active_release_count integer;
  deleted_step_count integer := 0;
  recovered_session_count integer := 0;
  current_deleted integer;
begin
  -- Match the release/maintenance lock order used by issue, validate, record,
  -- activation and knowledge-card maintenance before taking a session row lock.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  select pg_catalog.count(*)
    into active_release_count
  from app_private.chem_question_source_releases as release_row
  where release_row.grade_band = '初三'
    and release_row.textbook_version = '科粤版'
    and release_row.status = 'active'
    and release_row.verification_status = 'full_visual_verified'
    and release_row.verification_manifest_sha256 = release_row.manifest_sha256
    and release_row.revision_contract = 'v3_junior_native_text'
    and release_row.activated_at is not null;

  if active_release_count <> 1 then
    raise exception 'junior unanswered-session recovery requires exactly one active verified 科粤版 release';
  end if;

  for candidate in
    select session_row.id
    from public.chem_junior_daily_sessions as session_row
    join public.chem_learning_plans as plan_row
      on plan_row.id = session_row.plan_day_id
     and plan_row.student_id = session_row.student_id
     and plan_row.delivery_mode = 'junior_adaptive'
     and plan_row.junior_curriculum_day_id = session_row.curriculum_day_id
    join public.chem_junior_curriculum_days as curriculum_row
      on curriculum_row.id = session_row.curriculum_day_id
     and curriculum_row.textbook_version = session_row.textbook_version
     and curriculum_row.release_status = 'ready'
     and curriculum_row.knowledge_skill_ids = session_row.knowledge_skill_ids
    where session_row.status = 'blocked'
      and session_row.blocked_reason_code = 'source_release_unavailable'
      and session_row.textbook_version = '科粤版'
      and pg_catalog.cardinality(session_row.knowledge_skill_ids) = 3
      and exists (
        select 1
        from public.chem_junior_session_steps as issued_step
        where issued_step.session_id = session_row.id
      )
      and not exists (
        select 1
        from public.chem_junior_session_steps as answered_step
        where answered_step.session_id = session_row.id
          and answered_step.answered_at is not null
      )
      and not exists (
        select 1
        from pg_catalog.unnest(session_row.knowledge_skill_ids) as knowledge(knowledge_id)
        where not app_private.chem_junior_knowledge_card_is_ready(
          session_row.textbook_version,
          knowledge.knowledge_id
        )
      )
    order by session_row.id
  loop
    -- Recheck the evidence boundary after the row lock.  A concurrent answer
    -- must win and make this migration fail closed instead of being removed.
    perform 1
    from public.chem_junior_daily_sessions as locked_session
    where locked_session.id = candidate.id
    for update;

    if exists (
      select 1
      from public.chem_junior_session_steps as answered_step
      where answered_step.session_id = candidate.id
        and answered_step.answered_at is not null
    ) then
      raise exception 'junior session % gained answer evidence during recovery', candidate.id;
    end if;

    delete from public.chem_junior_session_steps as stale_step
    where stale_step.session_id = candidate.id
      and stale_step.answered_at is null;
    get diagnostics current_deleted = row_count;

    if current_deleted < 1 then
      raise exception 'junior session % lost its stale unanswered step during recovery', candidate.id;
    end if;

    deleted_step_count := deleted_step_count + current_deleted;

    update public.chem_junior_daily_sessions as recovered_session
    set status = 'active',
        blocked_reason_code = null,
        blocked_reason_detail = null,
        blocked_at = null,
        updated_at = pg_catalog.now()
    where recovered_session.id = candidate.id
      and recovered_session.status = 'blocked'
      and recovered_session.blocked_reason_code = 'source_release_unavailable';

    if not found then
      raise exception 'junior session % changed state during recovery', candidate.id;
    end if;

    recovered_session_count := recovered_session_count + 1;
  end loop;

  raise notice 'recovered % unanswered junior session(s), removed % stale unanswered step(s)',
    recovered_session_count,
    deleted_step_count;
end;
$migration$;
