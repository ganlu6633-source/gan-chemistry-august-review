alter table public.chem_attempt_answers
  add column if not exists question_snapshot jsonb;

comment on column public.chem_attempt_answers.question_snapshot is
  'Immutable server-captured question content used to render honest historical learning evidence after the live question changes.';

update public.chem_attempt_answers as answer
set question_snapshot = jsonb_build_object(
  'version', 1,
  'source', 'migration_backfill',
  'capturedAt', answer.created_at,
  'questionId', question.id,
  'motherId', question.mother_id,
  'skillId', question.skill_id,
  'level', question.level,
  'gradeBand', question.grade_band,
  'stem', question.stem,
  'options', question.options,
  'correctOption', question.correct_option,
  'explanation', question.explanation,
  'imageUrl', question.image_url,
  'reviewStatus', question.review_status,
  'scopeStatus', question.scope_status
)
from public.chem_questions as question
where answer.question_id = question.id
  and answer.question_snapshot is null;

alter table public.chem_attempt_answers
  drop constraint if exists chem_attempt_answers_question_snapshot_object;

alter table public.chem_attempt_answers
  add constraint chem_attempt_answers_question_snapshot_object
  check (
    question_snapshot is null
    or (
      jsonb_typeof(question_snapshot) = 'object'
      and question_snapshot ?& array['questionId', 'motherId', 'skillId', 'level', 'stem', 'options', 'correctOption', 'explanation']
      and jsonb_typeof(question_snapshot -> 'options') = 'array'
    )
  );
