-- Run after 20260814121753_snapshot_learning_record_questions.sql.
-- Read-only verification: historical evidence must remain renderable after question edits.
begin;
set local lock_timeout = '5s';

do $verify$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'chem_attempt_answers'
      and column_name = 'question_snapshot'
      and data_type = 'jsonb'
  ) then
    raise exception 'chem_attempt_answers.question_snapshot jsonb is missing';
  end if;

  if exists (
    select 1
    from public.chem_attempt_answers
    where question_snapshot is null
  ) then
    raise exception 'existing attempt answers were not backfilled with question snapshots';
  end if;

  if exists (
    select 1
    from public.chem_attempt_answers
    where jsonb_typeof(question_snapshot) <> 'object'
       or nullif(question_snapshot ->> 'questionId', '') is null
       or nullif(question_snapshot ->> 'stem', '') is null
       or jsonb_typeof(question_snapshot -> 'options') <> 'array'
       or nullif(question_snapshot ->> 'correctOption', '') is null
  ) then
    raise exception 'a historical question snapshot is incomplete';
  end if;
end
$verify$;

rollback;
