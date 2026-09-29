-- Junior source questions already have reviewed option-to-micro-topic bindings,
-- but none of those exact links reached the shared teaching topic catalogue.
-- Restore only bindings whose question revision is still ready for students.
with topic_evidence as (
  select t.id as topic_id, evidence_item.value->>'sameTypeKey' as same_type_key
  from app_private.chem_teaching_topics t
  cross join lateral jsonb_array_elements(
    coalesce(t.evidence->'sourceEvidence', '[]'::jsonb)
  ) evidence_item(value)
  where '初三'=any(t.grade_bands)
    and evidence_item.value->>'kind'='reviewed_option_binding'
    and evidence_item.value->>'sameTypeKey' is not null
    and not exists (
      select 1 from app_private.chem_teaching_topics child
      where child.parent_id=t.id
    )
), exact_matches as (
  select distinct e.topic_id, q.id as question_id, e.same_type_key
  from topic_evidence e
  join app_private.chem_option_practice_bindings b
    on b.same_type_key=e.same_type_key and b.review_status='verified'
  join app_private.chem_teaching_ready_questions q
    on q.id=b.anchor_question_id
   and q.grade_band='初三'
   and q.question_revision_token=b.anchor_revision_token
  union
  select distinct e.topic_id, q.id as question_id, e.same_type_key
  from topic_evidence e
  join app_private.chem_option_practice_bindings b
    on b.same_type_key=e.same_type_key and b.review_status='verified'
  cross join lateral jsonb_array_elements(coalesce(b.candidates,'[]'::jsonb)) candidate(value)
  join app_private.chem_teaching_ready_questions q
    on q.id=candidate.value->>'questionId'
   and q.grade_band='初三'
   and q.question_revision_token=candidate.value->>'revisionToken'
), inserted as (
  insert into app_private.chem_teaching_question_topics(question_id,topic_id,evidence)
  select question_id,topic_id,
    jsonb_build_object(
      'kind','reviewed_option_binding_current_revision',
      'sameTypeKey',same_type_key,
      'source','chem_option_practice_bindings'
    )
  from exact_matches
  on conflict (question_id,topic_id) do nothing
  returning topic_id
)
update app_private.chem_teaching_topics t
set updated_at=now()
where t.id in (select distinct topic_id from inserted);
