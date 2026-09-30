-- Route approved high-three originals to four fine-grained practice points
-- only where a named original option directly tests that point.
do $option_topic$
declare
  v_ready integer;
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
    ('QH3FZ26_TOPIC04_EXTRA_THREE_FIX_892dd251f21337fb','CHEM.F01-K03.AMPHOTERIC',2,'B',
     '原题B项用NaOH浸取Al₂O₃和SiO₂；解析明确Al₂O₃与碱反应形成可溶铝酸盐。'),
    ('QH3FZ26_TOPIC03_FIX_909706745903b3f8','CHEM.F01-K03.NEUTRAL_PEROXIDE',2,'B',
     '原题B项直接考过氧化钠与CO₂反应放出O₂的方程式。'),
    ('QH3FZ26_TOPIC07_FIX_b7c70396e1a35405','CHEM.F01-K03.NEUTRAL_PEROXIDE',3,'A/C',
     '原题A项比较氧化钠与过氧化钠的组成粒子，C项考过氧化钠供氧的氧来源。'),
    ('QH3ION20260925_074_R2','CHEM.R04-K04',2,'A',
     '原题A项直接考电解精炼铜的阴极还原反应及电极产物。');

  select count(*) into v_ready
  from exact_option_topic_map m
  join app_private.chem_teaching_ready_questions q
    on q.id=m.question_id and q.grade_band='高三'
   and q.correct_option=m.answer_index
  join app_private.chem_teaching_topics t
    on t.id=m.topic_id and '高三'=any(t.grade_bands)
  where length(btrim(q.explanation))>0 and q.question_revision_token is not null;
  if v_ready<>4 then
    raise exception 'source-backed option topic map no longer matches ready originals: %/4',v_ready;
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
end;
$option_topic$;
