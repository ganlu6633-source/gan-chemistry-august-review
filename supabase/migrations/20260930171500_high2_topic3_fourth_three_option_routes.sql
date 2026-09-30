do $audit$
declare
  v_release uuid := '008bc613-9fb5-5dc1-8289-2c03793d20f0';
  v_count integer;
begin
  select count(*) into v_count
  from app_private.chem_teaching_ready_questions
  where source_release_id=v_release and grade_band='高二';
  if v_count <> 3 then
    raise exception 'Topic 3 fourth batch needs three ready originals, found %', v_count;
  end if;

  create temporary table option_evidence(
    question_id text not null,
    topic_id text not null,
    evidence_option text not null,
    evidence_text text not null,
    primary key(question_id,topic_id)
  ) on commit drop;
  insert into option_evidence values
    ('QH2T3SRC30_47F1C2F54C577EA7','CHEM.R09-K02','B/C','B项用氨水电离常数判断浓度比值；C项区分醋酸与醋酸根的物质的量守恒和浓度变化。'),
    ('QH2T3SRC30_47F1C2F54C577EA7','CHEM.R10-K04','A','A项考滴入氨水从酸性经中和到碱性时，水电离受抑制程度并非始终单向变化。'),
    ('QH2T3SRC30_47F1C2F54C577EA7','CHEM.R11-K04','D','D项在同浓度等体积时结合中性与电荷守恒判断NH₄⁺、CH₃COO⁻浓度相等。'),
    ('QH2T3SRC30_4AAEDDCBD61E5A69','CHEM.R09-K02','B/C/D','四图曲线的反应中段需考虑弱酸不断电离补充H⁺，不能只用初始pH判断全部速率。'),
    ('QH2T3SRC30_4AAEDDCBD61E5A69','CHEM.R09-K04','A–D','相同体积与pH下，强酸①和弱酸②起始速率相近，弱酸总酸量与最终H₂量更大；对比四张原图。'),
    ('QH2T3SRC30_C8C00E9A99517465','CHEM.R11-K01','B/C/D','B项明矾铝离子水解形成胶体，C项FeCl₃在沸水中水解，D项加盐酸抑制Fe³⁺水解。'),
    ('QH2T3SRC30_C8C00E9A99517465','CHEM.R11-K05','A–D','逐项辨别雨水酸化、明矾净水、Fe(OH)₃胶体制备和FeCl₃溶液保存的实际原因。');

  update app_private.chem_teaching_question_topics link
  set evidence=link.evidence || jsonb_build_object(
    'kind','visually_verified_option_knowledge_match',
    'sourceReleaseId',v_release,
    'questionRevisionToken',q.question_revision_token,
    'evidenceOption',e.evidence_option,
    'evidenceText',e.evidence_text,
    'sameTypeClaim',false)
  from option_evidence e
  join app_private.chem_teaching_ready_questions q on q.id=e.question_id
  where link.question_id=e.question_id and link.topic_id=e.topic_id
    and q.source_release_id=v_release;

  select count(*) into v_count
  from app_private.chem_teaching_question_topics link
  join public.chem_questions q on q.id=link.question_id
  where q.source_release_id=v_release
    and link.evidence->>'kind'='visually_verified_option_knowledge_match'
    and link.evidence->>'questionRevisionToken'=q.question_revision_token
    and length(coalesce(link.evidence->>'evidenceOption',''))>0;
  if v_count <> 7 then
    raise exception 'Topic 3 fourth batch needs seven exact option/topic routes, found %', v_count;
  end if;
end;
$audit$;
