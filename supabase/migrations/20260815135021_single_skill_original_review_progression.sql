-- One REVIEW day now contains exactly one taught module. Every released module
-- has five fine-grained concepts and five original questions per concept, so
-- round one can cover every concept once within the fixed five-question budget.
do $$
declare
  v_bad integer;
begin
  with target_students as (
    select s.id, s.grade_band,
      case
        when s.grade_band = '高一'
          and jsonb_typeof(s.metadata->'confirmedLearnedSkillIds') = 'array'
          and jsonb_array_length(s.metadata->'confirmedLearnedSkillIds') > 0
        then array(select jsonb_array_elements_text(s.metadata->'confirmedLearnedSkillIds'))
        when s.grade_band = '高一'
        then array['H1_CLASSIFY','H1_PERIODIC','H1_MOLE_INTRO','H1_GAS_MOLAR_VOLUME','H1_REDOX']::text[]
        else array['H2_THERMO','H2_RATE','H2_EQUIL','H2_K','H2_WEAK','H2_PH_HYDRO','H2_KSP','H2_ELECTRO']::text[]
      end as allowed_skills
    from public.chem_students_v2 s
    where s.record_status = 'active' and s.grade_band in ('高一','高二')
  ), numbered as (
    select p.id, t.allowed_skills,
      row_number() over (partition by p.student_id order by p.plan_date, p.id) - 1 as day_index
    from public.chem_learning_plans p
    join target_students t on t.id = p.student_id
    where p.mode = 'REVIEW'
      and p.plan_date between date '2026-08-17' and date '2026-09-25'
  ), assigned as (
    select id, allowed_skills[1 + (day_index % cardinality(allowed_skills))::integer] as skill_id
    from numbered
  )
  update public.chem_learning_plans p
  set skill_ids = array[a.skill_id],
      knowledge_summaries = array[case a.skill_id
        when 'H1_CLASSIFY' then '物质分类的五个细知识点'
        when 'H1_PERIODIC' then '元素周期律的五个细知识点'
        when 'H1_MOLE_INTRO' then '物质的量与阿伏加德罗常数的五个细知识点'
        when 'H1_GAS_MOLAR_VOLUME' then '气体摩尔体积的五个细知识点'
        when 'H1_REDOX' then '氧化还原反应的五个细知识点'
        when 'H2_THERMO' then '反应热的五个细知识点'
        when 'H2_RATE' then '化学反应速率的五个细知识点'
        when 'H2_EQUIL' then '化学平衡的五个细知识点'
        when 'H2_K' then '化学平衡常数的五个细知识点'
        when 'H2_WEAK' then '弱电解质电离的五个细知识点'
        when 'H2_PH_HYDRO' then '水的电离与盐类水解的五个细知识点'
        when 'H2_KSP' then '沉淀溶解平衡的五个细知识点'
        when 'H2_ELECTRO' then '电化学的五个细知识点'
      end],
      question_count = 5,
      round_limit = 5,
      max_question_level = 5,
      estimated_minutes = 12
  from assigned a
  where p.id = a.id;

  select count(*) into v_bad
  from public.chem_learning_plans p
  join public.chem_students_v2 s on s.id = p.student_id
  where s.record_status = 'active'
    and s.grade_band in ('高一','高二')
    and p.mode = 'REVIEW'
    and p.plan_date between date '2026-08-17' and date '2026-09-25'
    and (cardinality(p.skill_ids) <> 1 or p.question_count <> 5 or p.round_limit <> 5 or p.max_question_level <> 5);
  if v_bad <> 0 then raise exception 'single-skill original-review plan assertion failed: % rows', v_bad; end if;

  select count(*) into v_bad
  from public.chem_learning_plans p
  join public.chem_students_v2 s on s.id = p.student_id
  where s.record_status = 'active' and s.grade_band = '高一'
    and jsonb_typeof(s.metadata->'confirmedLearnedSkillIds') = 'array'
    and p.mode = 'REVIEW'
    and p.plan_date between date '2026-08-17' and date '2026-09-25'
    and not (s.metadata->'confirmedLearnedSkillIds' ? p.skill_ids[1]);
  if v_bad <> 0 then raise exception 'a High-1 plan contains an untaught module: % rows', v_bad; end if;
end $$;
