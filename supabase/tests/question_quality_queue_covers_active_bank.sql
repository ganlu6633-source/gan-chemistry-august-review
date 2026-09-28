-- The repair queue must include unreviewed questions even though the student
-- delivery view intentionally excludes them. Read-only contract check.
begin;

do $test$
begin
  if exists (
    with active_unreviewed as materialized (
      select q.id
      from public.chem_questions q
      join app_private.chem_question_source_releases release
        on release.id = q.source_release_id
      where release.status = 'active'
        and q.review_status = 'approved'
        and q.scope_status = 'IN'
        and q.usable_for_review
        and not app_private.chem_question_item_delivery_review_ready(q.id)
    ), queued as materialized (
      select question_id
      from app_private.chem_question_quality_audit_queue
      where needs_manual_visual_review
    )
    select 1
    from active_unreviewed a
    left join queued q on q.question_id = a.id
    where q.question_id is null
  ) then
    raise exception 'Unreviewed active question disappeared from the repair queue';
  end if;

  if exists (
    select 1
    from app_private.chem_teaching_ready_questions ready
    join app_private.chem_question_quality_audit_queue audit
      on audit.question_id = ready.id
    where audit.needs_manual_visual_review
  ) then
    raise exception 'Unreviewed question escaped into student delivery';
  end if;
end
$test$;

rollback;
