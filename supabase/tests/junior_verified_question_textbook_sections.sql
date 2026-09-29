begin;
do $$
declare
  v_ready integer;
  v_linked integer;
  v_wrong integer;
begin
  select count(*) into v_ready
  from app_private.chem_teaching_ready_questions
  where grade_band='初三' and textbook_version='科粤版';
  select count(*) into v_linked
  from app_private.chem_teaching_ready_questions q
  where q.grade_band='初三' and q.textbook_version='科粤版'
    and exists (
      select 1 from app_private.chem_teaching_question_topics m
      where m.question_id=q.id and m.evidence->>'kind'='reviewed_textbook_knowledge_section'
        and m.evidence->>'questionRevisionToken'=q.question_revision_token
    );
  if v_ready <> 289 or v_linked <> v_ready then
    raise exception 'Expected 289 ready and correctly linked junior questions, got % ready and % linked', v_ready, v_linked;
  end if;
  select count(*) into v_wrong
  from app_private.chem_teaching_question_topics m
  join public.chem_questions q on q.id=m.question_id
  join app_private.chem_teaching_topics t on t.id=m.topic_id
  where m.evidence->>'kind'='reviewed_textbook_knowledge_section'
    and (q.grade_band<>'初三' or q.textbook_version<>'科粤版'
      or m.evidence->>'knowledgeId'<>q.knowledge_id
      or not ('初三'=any(t.grade_bands)));
  if v_wrong <> 0 then
    raise exception 'Found % incorrect junior textbook topic links', v_wrong;
  end if;
end $$;
rollback;
