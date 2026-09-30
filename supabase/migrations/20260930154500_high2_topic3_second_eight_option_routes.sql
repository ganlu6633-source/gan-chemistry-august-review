-- Tie each verified source question's fine-topic route to the original answer
-- options. A wrong answer can then lead to the specific concept it tests.
do $audit$
declare
  v_release uuid := '1e86e449-a91a-557f-b84a-057653ca3c88';
  v_count integer;
begin
  select count(*) into v_count
  from app_private.chem_teaching_ready_questions q
  where q.source_release_id = v_release and q.grade_band = '高二';
  if v_count <> 8 then
    raise exception 'Topic 3 second release requires eight ready originals, found %', v_count;
  end if;

  create temporary table option_evidence(
    question_id text not null,
    topic_id text not null,
    evidence_option text not null,
    evidence_text text not null,
    primary key(question_id,topic_id)
  ) on commit drop;
  insert into option_evidence values
    ('QH2T3SRC30_EB604AE7C1FC0474','CHEM.R10-K03','A–D','四项都围绕两种NaOH溶液等体积混合，须先由pH求OH⁻浓度，再求混合后的H⁺浓度；不能直接平均pH或H⁺浓度。'),
    ('QH2T3SRC30_E3555D582207463A','CHEM.R11-K02','A–D','四项首先判断醋酸被NaOH恰好中和后，乙酸根水解使溶液呈碱性。'),
    ('QH2T3SRC30_E3555D582207463A','CHEM.R13-K03','A–D','四项再判断滴定终点和变色范围：甲基橙、石蕊、酚酞中应选酚酞。'),
    ('QH2T3SRC30_AD7B5F7A5D7F5F26','CHEM.R13-K02','A','A项考滴定管水洗后还须用所装NaOH标准液润洗。'),
    ('QH2T3SRC30_AD7B5F7A5D7F5F26','CHEM.R13-K03','B/C','B项判断中和过程pH变化；C项判断酚酞由无色到浅红色的终点。'),
    ('QH2T3SRC30_AD7B5F7A5D7F5F26','CHEM.R13-K04','D','D项考尖嘴悬滴使记录的标准液用量偏大，计算的待测酸浓度偏大。'),
    ('QH2T3SRC30_252D7F66C4D2CEE8','CHEM.R13-K03','A/C','A项由等量点体积比较三种酸的浓度；C项用等量点判断Na⁺、Cl⁻浓度相等。'),
    ('QH2T3SRC30_252D7F66C4D2CEE8','CHEM.R13-K05','B/D','B项由三条曲线比较NaOH浓度；D项辨别pH突跃与H⁺浓度的关系。'),
    ('QH2T3SRC30_195610B3534896C2','CHEM.R13-K03','A/B','A项由初始pH判断HA为弱酸；B项判断弱酸强碱滴定的等量点位置。'),
    ('QH2T3SRC30_195610B3534896C2','CHEM.R13-K05','C/D','C项合用物料守恒和电荷守恒；D项在过量NaOH时比较Na⁺与OH⁻浓度。'),
    ('QH2T3SRC30_B456969D222CC62A','CHEM.R11-K01','A–D','区分酸自身电离、盐的水解及强酸强碱盐：只有CuCl₂因水解而呈酸性。'),
    ('QH2T3SRC30_B456969D222CC62A','CHEM.R11-K02','B/C/D','Cu²⁺水解呈酸性，CO₃²⁻水解呈碱性，NaCl通常无明显水解。'),
    ('QH2T3SRC30_C5DB51DCC8EC56E8','CHEM.R11-K03','A–D','四项逐一考稀释、水解常数、通CO₂、加NaOH和升温对碳酸根水解平衡的影响。'),
    ('QH2T3SRC30_B6785BB3E8B25F63','CHEM.R11-K02','A/B/D','明矾溶液水解呈酸性，醋酸钠和小苏打溶液水解呈碱性，对应酚酞颜色不同。'),
    ('QH2T3SRC30_B6785BB3E8B25F63','CHEM.R11-K03','B/C/D','加热促进醋酸根水解；加NH₄Cl抑制氨水电离；少量NaCl对小苏打水解影响很小。');

  update app_private.chem_teaching_question_topics link
  set evidence = link.evidence || jsonb_build_object(
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
  if v_count <> 15 then
    raise exception 'Topic 3 second release needs 15 option/topic routes, found %', v_count;
  end if;
end;
$audit$;
