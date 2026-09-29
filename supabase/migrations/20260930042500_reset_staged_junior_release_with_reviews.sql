-- A staged 初三 release can acquire pending per-question visual rows and
-- source-document bindings before a second reviewer finds an error.  The
-- original prepare RPC could not restage it because those rows RESTRICT the
-- staged questions.  Reset only unpublished, unused releases, in one atomic
-- statement, so corrected originals can be checked again.
create or replace function app_private.chem_reset_staged_junior_source_release(
  p_release_id uuid
)
returns void
language plpgsql security definer set search_path=''
as $function$
declare
  v_release app_private.chem_question_source_releases%rowtype;
  v_spec app_private.chem_junior_source_release_specs%rowtype;
  v_question_count integer;
begin
  if p_release_id is null then
    raise exception 'a staged junior release id is required';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release',0));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release',0));

  select * into v_release
  from app_private.chem_question_source_releases
  where id=p_release_id for update;
  select * into v_spec
  from app_private.chem_junior_source_release_specs
  where release_id=p_release_id for update;
  if v_release.id is null or v_spec.release_id is null
    or v_release.grade_band is distinct from '初三'
    or v_release.textbook_version is distinct from '科粤版'
    or v_spec.textbook_version is distinct from '科粤版'
    or v_release.status is distinct from 'staged'
    or v_release.activated_at is not null
    or v_release.retired_at is not null
  then
    raise exception 'only an unpublished 科粤版 junior batch may be reset';
  end if;

  select count(*) into v_question_count
  from public.chem_questions q
  where q.source_release_id=p_release_id;
  if v_question_count<1
    or exists (select 1 from app_private.chem_junior_active_release_routes r
               where r.source_release_id=p_release_id)
    or exists (select 1 from app_private.chem_junior_knowledge_provenance p
               where p.source_release_id=p_release_id)
    or exists (select 1 from public.chem_learning_plans p
               where p.self_study_release_id=p_release_id)
    or exists (select 1 from public.chem_attempt_answers a
               join public.chem_questions q on q.id=a.question_id
               where q.source_release_id=p_release_id)
    or exists (select 1 from public.chem_junior_session_steps s
               join public.chem_questions q on q.id=s.question_id
               where q.source_release_id=p_release_id)
  then
    raise exception 'staged batch is linked to live learner work or is no longer isolated';
  end if;

  -- Event rows also RESTRICT question deletion.  They belong only to the
  -- staged versions being discarded, and cannot be student attempt records.
  delete from app_private.chem_question_item_visual_review_events e
  using public.chem_questions q
  where q.id=e.question_id and q.source_release_id=p_release_id;
  delete from app_private.chem_question_item_visual_reviews v
  where v.source_release_id=p_release_id;
  delete from app_private.chem_junior_question_source_documents d
  where d.source_release_id=p_release_id;

  -- The existing prepare routine handles staged items, questions, rights,
  -- cards, and provenance and recreates an empty release with the same spec.
  perform public.chem_prepare_junior_source_release(
    p_release_id,
    v_release.manifest_sha256,
    v_release.textbook_version,
    v_spec.knowledge_ids,
    v_release.expected_question_count
  );
end;
$function$;

revoke all on function app_private.chem_reset_staged_junior_source_release(uuid)
  from public,anon,authenticated,service_role;
