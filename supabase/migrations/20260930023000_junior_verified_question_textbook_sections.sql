-- The reviewed 科粤版 junior questions already have exact source and answer checks,
-- yet most were absent from the teacher's selectable textbook tree. Link each
-- reviewed question to its evidenced textbook section. Three knowledge groups
-- span multiple sections; keep those at their shared unit rather than guessing
-- a narrower section for an individual question.
with textbook_map(knowledge_id, topic_id) as (
  values
    ('J_KY_1_1_K01', 'CHEM.J.KY.U01.S01'),
    ('J_KY_1_1_K02', 'CHEM.J.KY.U01.S01'),
    ('J_KY_1_1_K03', 'CHEM.J.KY.U01.S01'),
    ('J_KY_LAB_BASICS', 'CHEM.J.KY.U01.S02'),
    ('J_KY_CHANGE_PROPERTY', 'CHEM.J.KY.U01'),
    ('J_KY_AIR', 'CHEM.J.KY.U02.S01'),
    ('J_KY_PARTICLES', 'CHEM.J.KY.U02'),
    ('J_KY_ELEMENTS', 'CHEM.J.KY.U02.S04'),
    ('J_KY_OXY_PROPERTIES', 'CHEM.J.KY.U03.S01'),
    ('J_KY_OXY_H2O2', 'CHEM.J.KY.U03.S02'),
    ('J_KY_OXY_KMNO4', 'CHEM.J.KY.U03.S02'),
    ('J_KY_OXY_SYMBOLS', 'CHEM.J.KY.U03.S02'),
    ('J_KY_COMBUSTION', 'CHEM.J.KY.U03.S03'),
    ('J_KY_FORMULA', 'CHEM.J.KY.U03.S04'),
    ('J_KY_WATER', 'CHEM.J.KY.U04'),
    ('J_KY_CONSERVATION', 'CHEM.J.KY.U04.S03'),
    ('J_KY_EQUATIONS', 'CHEM.J.KY.U04.S04')
), inserted as (
  insert into app_private.chem_teaching_question_topics(question_id, topic_id, evidence)
  select q.id, m.topic_id,
    jsonb_build_object(
      'kind', 'reviewed_textbook_knowledge_section',
      'textbookVersion', q.textbook_version,
      'knowledgeId', q.knowledge_id,
      'questionRevisionToken', q.question_revision_token,
      'mappingScope', case when position('.S' in m.topic_id)=0 then 'unit' else 'section' end,
      'source', '科粤版课程目录及已复核知识点'
    )
  from app_private.chem_teaching_ready_questions q
  join textbook_map m on m.knowledge_id=q.knowledge_id
  join app_private.chem_teaching_topics t on t.id=m.topic_id and '初三'=any(t.grade_bands)
  where q.grade_band='初三' and q.textbook_version='科粤版'
  on conflict (question_id, topic_id) do nothing
  returning topic_id
)
update app_private.chem_teaching_topics t
set updated_at=now()
where t.id in (select distinct topic_id from inserted);
