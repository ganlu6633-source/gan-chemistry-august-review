-- Match already verified high-three originals to further leaf topics tested by their options.
-- This adds routes only; it does not copy, edit, or re-answer any question.
do $option_topic$
declare
  v_expected integer := 8;
  v_ready integer;
  v_inserted integer;
begin
  create temporary table exact_option_topic_map(
    question_id text not null,
    topic_id text not null,
    answer_index smallint not null,
    evidence_option text not null,
    evidence_text text not null,
    primary key(question_id,topic_id)
  ) on commit drop;

  insert into exact_option_topic_map values
    ('QH3FZ26_RET_fc7e88f847c334835f1d206b','CHEM.F01-K08',3,'A-D',
     '四项逐一判断是否生成新物质，D项石油分馏为物理变化。'),
    ('QH3FZ26_H3GAP_B1_FIX_06814d8f16152c14','CHEM.B05-K04',2,'D',
     'D项直接区分碳碳双键加聚与缩聚，原题图显示单体到聚合物。'),
    ('QH3FZ26_H3PR5_FIX_e84d22f1885efce2','CHEM.B03-K03',2,'B',
     'B项利用铁粉、活性炭和食盐水构成微型原电池解释腐蚀加快。'),
    ('QH3FZ26_H3PR5_FIX_e84d22f1885efce2','CHEM.B03-K04',2,'C',
     'C项直接判断暖贴正极为吸氧反应而非析氢反应。'),
    ('QH3FZ26_H3PR5_FIX_e84d22f1885efce2','CHEM.B03-K06',2,'B/C',
     'B、C项分别考食盐水促进铁腐蚀及吸氧腐蚀的正极反应。'),
    ('QH3ION20260925_014_R2','CHEM.F05-K07',1,'A/C/D',
     'A、C、D项均为氧化还原型离子方程式的配平与判断。'),
    ('QH3ION20260925_014_R2','CHEM.R04-K02',1,'B',
     'B项判断氯化镁水溶液电解的阴极产物及氢氧化镁沉淀。'),
    ('QH3STSE_CULTURE_REDOX_20260930','CHEM.F01-K08',1,'A/C/D',
     'A、C、D项分别是结冰、飘荡和蒸馏，直接区分物理变化与蜡烛燃烧。');

  select count(*) into v_ready
  from exact_option_topic_map m
  join app_private.chem_teaching_ready_questions q
    on q.id=m.question_id and q.grade_band='高三'
   and q.correct_option=m.answer_index
  join app_private.chem_teaching_topics t
    on t.id=m.topic_id and '高三'=any(t.grade_bands)
  where length(btrim(q.explanation))>0
    and q.question_revision_token is not null;
  if v_ready<>v_expected then
    raise exception 'source-backed option topic map no longer matches ready originals: %/%',v_ready,v_expected;
  end if;

  insert into app_private.chem_teaching_question_topics(question_id,topic_id,evidence)
  select q.id,m.topic_id,
    jsonb_build_object(
      'kind','visually_verified_option_knowledge_match',
      'gradeBand','高三',
      'sourceReleaseId',q.source_release_id,
      'questionRevisionToken',q.question_revision_token,
      'evidenceOption',m.evidence_option,
      'evidenceText',m.evidence_text
    )
  from exact_option_topic_map m
  join app_private.chem_teaching_ready_questions q on q.id=m.question_id
  on conflict (question_id,topic_id) do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted<>v_expected then
    raise exception 'expected % new exact option links, inserted %',v_expected,v_inserted;
  end if;
end;
$option_topic$;
