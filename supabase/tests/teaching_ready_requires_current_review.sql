-- Run after the 20260929043000 migration. Read-only assertions inside a
-- transaction; no student records or questions are changed.
begin;

do $test$
begin
  if exists (
    select 1
    from app_private.chem_teaching_ready_questions ready
    where not app_private.chem_question_item_delivery_review_ready(ready.id)
  ) then
    raise exception 'Unreviewed question escaped into the student-ready pool';
  end if;

  if exists (
    select 1
    from app_private.chem_teaching_ready_questions ready
    where not exists (
      select 1
      from app_private.chem_question_item_visual_reviews review
      where review.question_id = ready.id
    )
  ) then
    raise exception 'Legacy no-review compatibility path is still open';
  end if;

  if exists (
    select 1
    from app_private.chem_future_plan_source_qa_audit
    where qa_status <> 'source_reviewed'
  ) then
    raise exception 'A future fixed assignment needs source correction';
  end if;
end
$test$;

rollback;
