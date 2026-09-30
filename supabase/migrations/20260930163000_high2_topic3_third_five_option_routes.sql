-- Every released route in the five additional 高二 source questions has a
-- traceable answer-option reason, not merely a broad chapter association.
do $audit$
declare
  v_release uuid := 'ba59cd32-9ac0-5a75-a5cf-98fb271cbd4d';
  v_count integer;
begin
  select count(*) into v_count
  from app_private.chem_teaching_ready_questions
  where source_release_id=v_release and grade_band='高二';
  if v_count <> 5 then
    raise exception 'Topic 3 third batch needs five ready originals, found %', v_count;
  end if;

  create temporary table option_evidence(
    question_id text not null,
    topic_id text not null,
    evidence_option text not null,
    evidence_text text not null,
    primary key(question_id,topic_id)
  ) on commit drop;
  insert into option_evidence values
    ('QH2T3SRC30_F807EAD1DD7BDBFB','CHEM.R11-K02','C/D','同浓度下盐溶液pH比较可反推弱酸强弱；无明显水解的X⁻与水解的Y⁻对应强酸和弱酸。'),
    ('QH2T3SRC30_F807EAD1DD7BDBFB','CHEM.R11-K04','A/B/D','A、B项比较两种盐各自的物料守恒差值；D项用a＝c(X⁻)＝c(Y⁻)＋c(HY)判断水解。'),
    ('QH2T3SRC30_782A7050F6A38EED','CHEM.R11-K02','A/B','由HClO与CO₃²⁻反应和两个阴离子的水解强弱，比较HCO₃⁻、ClO⁻、OH⁻浓度。'),
    ('QH2T3SRC30_782A7050F6A38EED','CHEM.R11-K04','C/D','C项的碳物料守恒漏掉CO₃²⁻；D项的电荷守恒漏掉CO₃²⁻前的系数2。'),
    ('QH2T3SRC30_C58AEE80918C8542','CHEM.R13-K05','A–D','读出HY为强酸、HX为弱酸，并分别在起点、半中和、等量点和pH＝7时判断。'),
    ('QH2T3SRC30_C58AEE80918C8542','CHEM.R11-K04','B/C/D','B项靠电荷守恒区分X⁻与Na⁺；C项比较等量点Na⁺和OH⁻；D项不能把两次滴定的粒子浓度直接视为相等。'),
    ('QH2T3SRC30_86CA2AB3541A1145','CHEM.R13-K05','A/B/D','由H₂A、HA⁻、A²⁻的分布曲线读取pH＝7、E点和pH＝2的相对浓度。'),
    ('QH2T3SRC30_86CA2AB3541A1145','CHEM.R11-K04','A/B/C','将二元弱酸的电荷守恒与总浓度0.10 mol·L⁻¹结合，核查三个等式或不等式。'),
    ('QH2T3SRC30_904FFC124E9AAB67','CHEM.R12-K01','B/C/D','B项同温各点Kₛₚ相同；C项加Na₂S改变离子浓度；D项降温从T₂曲线移向T₁曲线。'),
    ('QH2T3SRC30_904FFC124E9AAB67','CHEM.R12-K03','A/B','p、q在等离子浓度线上，a、b分别读作两温度的CdS溶解度；不能把同温p点的Kₛₚ抬高。');

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
  if v_count <> 10 then
    raise exception 'Topic 3 third batch needs 10 exact option/topic routes, found %', v_count;
  end if;
end;
$audit$;
