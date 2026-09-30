-- Open high-three leaf topics only where an already approved original option tests that exact point.
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
    ('QH3FZ26_H3GAP_B1_FIX_54396e71164243a6','CHEM.B05-K02',0,'A/D',
     '双键参与光加成，D项直接用乙烯生成环丁烷判断不饱和键反应。'),
    ('QH3FZ26_H3PR5_FIX_e226164b5265d864','CHEM.E03-K04',3,'B',
     'B项指出先用硝酸酸化可把亚硫酸根氧化为硫酸根，干扰硫酸根检验。'),
    ('QH3ION20260925_011_R2','CHEM.F05-K01',1,'B',
     'B项直接考碳酸根使硫酸钙转为碳酸钙沉淀及原沉淀不能拆写。'),
    ('QH3FZ26_TOPIC09_304_389_FIX_8dc63eef6542a2c1','CHEM.S06-K03',3,'A-D',
     '实验直接比较FeCl₄、Fe(SCN)与FeF₆配合物的形成和平衡，颜色见题图。'),
    ('QH3FZ26_TOPIC10_B2_FIX_470938a7e9997930','CHEM.R11-K02',2,'A/C/D',
     '盐MCl、NaR、MR稀释曲线的初始酸碱性对应强酸弱碱盐等类别。'),
    ('QH3FZ26_TOPIC10_B2_FIX_470938a7e9997930','CHEM.R11-K03',2,'B',
     'B项直接比较同一盐溶液稀释前后的水解程度。'),
    ('QH3FZ26_H3GAP_B5_FIX_d09177d8369e9c05','CHEM.O09-K05',0,'D',
     'D项用新制氢氧化铜生成砖红色Cu₂O，辨别还原糖而非只凭现象认葡萄糖。'),
    ('QH3FZ26_H3GAP_B1_FIX_06814d8f16152c14','CHEM.O10-K05',2,'A-D',
     '题图从单体Ⅰ生成聚合物Ⅱ，四项依次考官能团、材料遇水表现、固态及加聚类型。');

  select count(*) into v_ready
  from exact_option_topic_map m
  join app_private.chem_teaching_ready_questions q
    on q.id=m.question_id and q.grade_band='高三'
   and q.correct_option=m.answer_index
  join app_private.chem_teaching_topics t
    on t.id=m.topic_id and '高三'=any(t.grade_bands)
  where length(btrim(q.explanation))>0 and q.question_revision_token is not null;
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
