-- Evidence for each source-backed topic route in the eight verified 高二
-- Topic 3 originals. Keep the answer-option evidence with the route so
-- practice recommendations do not silently drift to a nearby topic.
do $audit$
declare
  v_release uuid := '5dc92d9d-9be3-5917-86c8-1c4df5952a19';
  v_count integer;
begin
  select count(*) into v_count
  from app_private.chem_teaching_ready_questions q
  where q.source_release_id = v_release and q.grade_band = '高二';
  if v_count <> 8 then
    raise exception 'Topic 3 original release must expose exactly eight verified questions, found %', v_count;
  end if;

  -- The B option of original Q10 uses charge conservation; it does not test
  -- strong-acid/strong-base mixing. Remove that over-broad initial route.
  delete from app_private.chem_teaching_question_topics
  where question_id = 'QH2T3SRC30_72DFA72E1BF3F34F'
    and topic_id = 'CHEM.R10-K03';

  insert into app_private.chem_teaching_question_topics(question_id,topic_id,evidence)
  select q.id,'CHEM.R11-K04',jsonb_build_object(
    'kind','visually_verified_option_knowledge_match',
    'sourceReleaseId',v_release,
    'questionRevisionToken',q.question_revision_token,
    'evidenceOption','B',
    'evidenceText','原题B项由两溶液的电荷守恒和相同的氢离子、氢氧根浓度推出氯离子与醋酸根浓度相等。',
    'sameTypeClaim',false)
  from app_private.chem_teaching_ready_questions q
  where q.id='QH2T3SRC30_72DFA72E1BF3F34F'
  on conflict (question_id,topic_id) do update set evidence=excluded.evidence;

  create temporary table option_evidence(
    question_id text not null,
    topic_id text not null,
    evidence_option text not null,
    evidence_text text not null,
    primary key(question_id,topic_id)
  ) on commit drop;
  insert into option_evidence values
    ('QH2T3SRC30_FEBDDAD91A5C008E','CHEM.R09-K02','A–D','四项分别改变同离子、酸碱、温度或醋酸浓度，需区分氢离子浓度与电离程度。'),
    ('QH2T3SRC30_6FCF80F8C39CFD8F','CHEM.R09-K02','A–D','四项分别问稀释后的电离程度、离子总数、导电性与未电离分子数。'),
    ('QH2T3SRC30_E64BBE77D5BB359F','CHEM.R09-K01','A/C/D','原题①③④⑥考盐类水解、同pH酸的总量及稀释证据。'),
    ('QH2T3SRC30_E64BBE77D5BB359F','CHEM.R09-K04','B','原题B项组合②⑤均不能单独证明亚硝酸为弱电解质。'),
    ('QH2T3SRC30_46A361070AB39D47','CHEM.R09-K01','A/C','原题A项用电离常数比较强弱，C项由电离常数算约0.4%的电离度。'),
    ('QH2T3SRC30_46A361070AB39D47','CHEM.R09-K04','B/D','原题B项比较不同溶剂区分酸强弱，D项判断冰醋酸中硫酸分步电离。'),
    ('QH2T3SRC30_E97FE07E08D9DBB2','CHEM.R09-K01','A/C/D','原题A/C/D由电离常数比较酸强弱、未电离酸浓度和同温浓度影响。'),
    ('QH2T3SRC30_E97FE07E08D9DBB2','CHEM.R09-K04','B','原题B项按酸性强弱判断HZ和Y负离子的反应方向。'),
    ('QH2T3SRC30_C713B62DFCAEA999','CHEM.R10-K01','A–D','原题四项考水离子积定义、与电离常数关系及温度影响。'),
    ('QH2T3SRC30_96EC2A5A5C88EDE9','CHEM.R10-K01','A/C','原题A项考Kw表达式，C项由X/Z两点的Kw判断温度顺序。'),
    ('QH2T3SRC30_96EC2A5A5C88EDE9','CHEM.R10-K02','B/D','原题B项比较氢离子与氢氧根浓度，D项判断不同温度的中性pH。'),
    ('QH2T3SRC30_72DFA72E1BF3F34F','CHEM.R09-K04','A/C/D','原题A/C/D比较同pH强酸弱酸的总浓度、产氢量和中和所需碱量。'),
    ('QH2T3SRC30_72DFA72E1BF3F34F','CHEM.R11-K04','B','原题B项由两溶液的电荷守恒推出c(Cl⁻)=c(CH₃COO⁻)。');

  update app_private.chem_teaching_question_topics link
  set evidence = link.evidence || jsonb_build_object(
    'kind','visually_verified_option_knowledge_match',
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
  if v_count <> 13 then
    raise exception 'Topic 3 release needs exactly 13 exact option/topic routes, found %', v_count;
  end if;
end;
$audit$;
