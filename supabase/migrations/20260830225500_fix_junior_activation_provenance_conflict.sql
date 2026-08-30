begin;

-- The activation function returns a column named textbook_version.  Using
-- an unqualified ON CONFLICT column list inside PL/pgSQL therefore becomes
-- ambiguous at runtime.  Name the existing primary-key constraint instead.

create or replace function public.chem_activate_junior_source_release(
  p_release_id uuid,
  p_manifest_sha256 text
)
returns table (
  release_id uuid,
  activated_questions integer,
  textbook_version text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_textbook_version text;
  v_knowledge_ids text[];
  v_expected integer;
  v_activated integer;
  v_status_count integer;
begin
  perform app_private.chem_assert_junior_source_release(
    p_release_id,
    p_manifest_sha256,
    true
  );

  select
    spec.textbook_version,
    spec.knowledge_ids,
    release_row.expected_question_count
  into v_textbook_version, v_knowledge_ids, v_expected
  from app_private.chem_question_source_releases as release_row
  join app_private.chem_junior_source_release_specs as spec
    on spec.release_id = release_row.id
   and spec.textbook_version = release_row.textbook_version
  where release_row.id = p_release_id
    and release_row.grade_band = '初三'
    and release_row.status = 'staged'
    and release_row.manifest_sha256 = p_manifest_sha256
  for update of release_row, spec;

  if not found then
    raise exception 'junior release changed after preflight';
  end if;

  -- Serialize with atomic issue/resume: those RPCs SHARE-lock the active
  -- release and UPDATE-lock the learner session.  Whichever transaction wins
  -- determines whether the old step is issued or this switch proceeds; there
  -- is no check-to-retire window that can strand a freshly issued question.
  perform session.id
  from public.chem_junior_daily_sessions as session
  where session.textbook_version = v_textbook_version
    and session.status = 'active'
  order by session.id
  for update;

  perform old_release.id
  from app_private.chem_question_source_releases as old_release
  where old_release.grade_band = '初三'
    and old_release.textbook_version = v_textbook_version
    and old_release.status = 'active'
    and old_release.id <> p_release_id
  order by old_release.id
  for update;

  -- Do not strand a learner who has already received an original from the old
  -- active batch.  A zero-step active session may safely select from the new
  -- batch after this transaction commits.
  if exists (
    select 1
    from public.chem_junior_daily_sessions as session
    join public.chem_junior_session_steps as step on step.session_id = session.id
    join public.chem_questions as question on question.id = step.question_id
    join app_private.chem_question_source_releases as old_release
      on old_release.id = question.source_release_id
    where session.status = 'active'
      and session.textbook_version = v_textbook_version
      and old_release.grade_band = '初三'
      and old_release.status = 'active'
      and old_release.id <> p_release_id
  ) then
    raise exception 'junior activation is blocked while an old-release session has issued steps';
  end if;

  perform pg_catalog.set_config('app.chem_junior_release_lifecycle', 'on', true);
  perform pg_catalog.set_config('app.chem_release_activation', 'on', true);

  update public.chem_questions as question
  set usable_for_review = false,
      updated_at = now()
  where question.grade_band = '初三'
    and question.textbook_version = v_textbook_version
    and question.source_kind = 'user_provided_local'
    and question.usable_for_review
    and question.source_release_id is distinct from p_release_id;

  update app_private.chem_question_source_releases as old_release
  set status = 'retired',
      retired_at = now()
  where old_release.grade_band = '初三'
    and old_release.textbook_version = v_textbook_version
    and old_release.status = 'active'
    and old_release.id <> p_release_id;

  update app_private.chem_junior_knowledge_provenance as old_provenance
  set verification_status = 'retired'
  where old_provenance.textbook_version = v_textbook_version
    and old_provenance.source_release_id <> p_release_id;

  insert into app_private.chem_junior_knowledge_provenance (
    textbook_version,
    knowledge_id,
    source_release_id,
    source_id,
    source_locator,
    source_sha256,
    verification_status,
    reviewed_at
  )
  select
    provenance.textbook_version,
    provenance.knowledge_id,
    provenance.release_id,
    provenance.source_id,
    provenance.source_locator,
    provenance.source_sha256,
    'verified',
    provenance.reviewed_at
  from app_private.chem_junior_source_release_provenance as provenance
  where provenance.release_id = p_release_id
    and provenance.textbook_version = v_textbook_version
    and provenance.knowledge_id = any(v_knowledge_ids)
    and provenance.verification_status = 'verified'
  on conflict on constraint chem_junior_knowledge_provenance_pkey do update set
    source_release_id = excluded.source_release_id,
    source_id = excluded.source_id,
    source_locator = excluded.source_locator,
    source_sha256 = excluded.source_sha256,
    verification_status = 'verified',
    reviewed_at = excluded.reviewed_at;

  update public.chem_questions as question
  set usable_for_review = true,
      updated_at = now()
  where question.source_release_id = p_release_id
    and question.grade_band = '初三'
    and question.textbook_version = v_textbook_version
    and question.skill_id = question.knowledge_id
    and question.knowledge_id = any(v_knowledge_ids);
  get diagnostics v_activated = row_count;
  if v_activated <> v_expected then
    raise exception 'junior activation enabled %, expected %', v_activated, v_expected;
  end if;

  update app_private.chem_question_source_releases as release_row
  set status = 'active',
      activated_at = now(),
      retired_at = null
  where release_row.id = p_release_id
    and release_row.grade_band = '初三'
    and release_row.textbook_version = v_textbook_version
    and release_row.status = 'staged'
    and release_row.verification_status = 'full_visual_verified'
    and release_row.verification_manifest_sha256 = p_manifest_sha256;
  get diagnostics v_status_count = row_count;
  if v_status_count <> 1 then
    raise exception 'junior activation status update affected %, expected 1', v_status_count;
  end if;

  if (
    select count(*)
    from app_private.chem_question_source_releases as release_row
    where release_row.grade_band = '初三'
      and release_row.textbook_version = v_textbook_version
      and release_row.status = 'active'
  ) <> 1 then
    raise exception 'junior textbook must have exactly one active source release';
  end if;
  if (
    select count(*)
    from public.chem_questions as question
    where question.grade_band = '初三'
      and question.textbook_version = v_textbook_version
      and question.source_kind = 'user_provided_local'
      and question.usable_for_review
      and question.source_release_id = p_release_id
  ) <> v_expected
    or exists (
      select 1
      from public.chem_questions as question
      where question.grade_band = '初三'
        and question.textbook_version = v_textbook_version
        and question.source_kind = 'user_provided_local'
        and question.usable_for_review
        and question.source_release_id is distinct from p_release_id
    )
  then
    raise exception 'junior activation postcondition did not expose only the new exact batch';
  end if;
  if (
    select count(*)
    from app_private.chem_junior_knowledge_provenance as provenance
    where provenance.textbook_version = v_textbook_version
      and provenance.knowledge_id = any(v_knowledge_ids)
      and provenance.source_release_id = p_release_id
      and provenance.verification_status = 'verified'
  ) <> cardinality(v_knowledge_ids) then
    raise exception 'junior activation postcondition did not bind all verified provenance rows';
  end if;

  perform pg_catalog.set_config('app.chem_release_activation', 'off', true);
  perform pg_catalog.set_config('app.chem_junior_release_lifecycle', 'off', true);

  return query select p_release_id, v_activated, v_textbook_version;
end;
$$;

revoke all on function public.chem_activate_junior_source_release(uuid, text)
  from public, anon, authenticated;
grant execute on function public.chem_activate_junior_source_release(uuid, text)
  to service_role;

commit;
