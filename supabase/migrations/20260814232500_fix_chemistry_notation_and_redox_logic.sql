-- 统一阿伏加德罗常数符号并补全氧化还原概念链。
-- 只修复复习系统的知识卡、题目、复习计划与历史题面快照；不接触独立小测表。

create or replace function pg_temp.fix_chem_notation(value text)
returns text
language sql
immutable
strict
as $function$
  select replace(
    replace(
      replace(value, 'N' || chr(8336), 'N_A'),
      'N' || 'A判断题', 'N_A判断题'
    ),
    'N' || 'A选择题', 'N_A选择题'
  )
$function$;

update public.chem_knowledge_cards
set title = pg_temp.fix_chem_notation(title),
    core = pg_temp.fix_chem_notation(core),
    detail = pg_temp.fix_chem_notation(detail),
    steps = pg_temp.fix_chem_notation(steps::text)::jsonb,
    common_mistakes = pg_temp.fix_chem_notation(common_mistakes::text)::jsonb,
    micro_example = pg_temp.fix_chem_notation(micro_example),
    structured_content = pg_temp.fix_chem_notation(structured_content::text)::jsonb,
    updated_at = now();

update public.chem_questions
set stem = pg_temp.fix_chem_notation(stem),
    options = pg_temp.fix_chem_notation(options::text)::jsonb,
    explanation = pg_temp.fix_chem_notation(explanation),
    scaffold = case when scaffold is null then null else pg_temp.fix_chem_notation(scaffold) end,
    updated_at = now();

update public.chem_learning_plans
set title = pg_temp.fix_chem_notation(title),
    knowledge_summaries = array(
      select pg_temp.fix_chem_notation(summary)
      from unnest(knowledge_summaries) with ordinality as item(summary, position)
      order by position
    );

update public.chem_attempt_answers
set question_snapshot = pg_temp.fix_chem_notation(question_snapshot::text)::jsonb
where question_snapshot is not null;

-- 基础卡也必须能独立说明过程、反应物身份和生成物身份。
update public.chem_knowledge_cards
set core = '升价→失电子→被氧化→发生氧化反应；反应物是还原剂，生成氧化产物。降价→得电子→被还原→发生还原反应；反应物是氧化剂，生成还原产物。',
    detail = '先标反应前后化合价，再把两条链逐项说完整。还原剂自身发生氧化反应并生成氧化产物；氧化剂自身发生还原反应并生成还原产物。同一反应中总失电子数等于总得电子数。',
    steps = '["标出反应前后化合价","确定升降与电子得失","写被氧化/被还原及发生的反应","确认氧化剂/还原剂与对应产物","用电子守恒校验"]'::jsonb,
    micro_example = 'Zn+Cu²⁺=Zn²⁺+Cu：Zn升价、失电子、被氧化并发生氧化反应；Zn是还原剂，Zn²⁺是氧化产物。Cu²⁺降价、得电子、被还原并发生还原反应；Cu²⁺是氧化剂，Cu是还原产物。',
    structured_content = jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(
              jsonb_set(
                jsonb_set(
                  structured_content,
                  '{version}', '3'::jsonb, true
                ),
                '{overview,1}',
                '"升价=失电子=被氧化=发生氧化反应；发生变化的反应物是还原剂，生成氧化产物。"'::jsonb,
                true
              ),
              '{overview,2}',
              '"降价=得电子=被还原=发生还原反应；发生变化的反应物是氧化剂，生成还原产物。"'::jsonb,
              true
            ),
            '{visualSummary}',
            $redox_visual${"kind":"balance","title":"氧化还原电子天平","center":"失电子总数＝得电子总数","groups":[{"label":"升价链","items":["化合价升高","失电子","被氧化","发生氧化反应","反应物是还原剂","生成氧化产物"]},{"label":"降价链","items":["化合价降低","得电子","被还原","发生还原反应","反应物是氧化剂","生成还原产物"]}]}$redox_visual$::jsonb,
            true
          ),
          '{sections,1,items,0,visualSteps}',
          '["化合价升高","失电子","被氧化","发生氧化反应","反应物是还原剂","生成氧化产物"]'::jsonb,
          true
        ),
        '{sections,1,items,1,visualSteps}',
        '["化合价降低","得电子","被还原","发生还原反应","反应物是氧化剂","生成还原产物"]'::jsonb,
        true
      ),
      '{sections,1,items,2,visualSteps}',
      '["升价→失电子→被氧化→发生氧化反应","还原剂→氧化产物","降价→得电子→被还原→发生还原反应","氧化剂→还原产物"]'::jsonb,
      true
    ),
    updated_at = now()
where id = 'KC_H1_REDOX' and skill_id = 'H1_REDOX';

update public.chem_knowledge_cards
set structured_content = replace(
  replace(
    structured_content::text,
    $old_fe$Fe²⁺→Fe³⁺+e⁻：升价、失电子、被氧化，Fe²⁺是还原剂；Cl₂+2e⁻→2Cl⁻：降价、得电子、被还原，Cl₂是氧化剂。$old_fe$,
    $new_fe$Fe²⁺→Fe³⁺+e⁻：Fe元素升价，Fe²⁺失电子、被氧化并发生氧化反应；Fe²⁺是还原剂，Fe³⁺是氧化产物。Cl₂+2e⁻→2Cl⁻：Cl元素降价，Cl₂得电子、被还原并发生还原反应；Cl₂是氧化剂，Cl⁻是还原产物。$new_fe$
  ),
  $old_na$Na由0升到+1，每个Na失1e⁻，2个Na共失2e⁻；Cl由0降到-1，一个Cl₂含2个Cl，共得2e⁻。Na是还原剂，Cl₂是氧化剂。$old_na$,
  $new_na$Na由0升到+1并失电子，被氧化、发生氧化反应，Na是还原剂；就Na元素的变化看，NaCl是氧化产物。Cl由0降到-1并得电子，被还原、发生还原反应，Cl₂是氧化剂；就Cl元素的变化看，NaCl也是还原产物。同一生成物可以同时承接两条变价链。2个Na共失2e⁻，1个Cl₂共得2e⁻。$new_na$
)::jsonb,
updated_at = now()
where id = 'KC_H1_REDOX' and skill_id = 'H1_REDOX';

-- 物质的量入门把“对象”完整列出，并给核素与离子晶体两个就地示范。
update public.chem_knowledge_cards
set structured_content = jsonb_set(
  jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            structured_content,
            '{version}', '3'::jsonb, true
          ),
          '{overview,1}',
          '"1 mol指定微粒约含N_A=6.02×10²³个微粒；必须写清对象是分子、原子、离子、电子、质子、中子，还是离子晶体的化学式单位。"'::jsonb,
          true
        ),
        '{visualSummary}',
        $mole_visual${"kind":"network","title":"物质的量把宏观与微观接起来","center":"物质的量 n","groups":[{"label":"微观","items":["微粒数 N","N=nN_A"]},{"label":"宏观","items":["质量 m","n=m/M"]},{"label":"对象","items":["分子/原子","离子/电子","质子/中子","离子晶体的化学式单位"]}]}$mole_visual$::jsonb,
        true
      ),
      '{sections,0,items,2,rule}',
      '"同样1 mol物质，所问分子、原子、离子、电子、质子、中子或离子晶体化学式单位的数目可能不同；先把对象名称完整写出，再计算倍数。"'::jsonb,
      true
    ),
    '{sections,0,items,2,examples}',
    '["1 mol H₂O含1 mol水分子、2 mol H原子、1 mol O原子。","1 mol ²³Na原子含11 mol质子、12 mol中子；若为中性原子，还含11 mol电子。","1 mol NaCl表示1 mol NaCl化学式单位，其中含1 mol Na⁺和1 mol Cl⁻；NaCl晶体中不存在独立的NaCl分子。"]'::jsonb,
    true
  ),
  '{sections,3,items,0}',
  $object_step${"label":"1. 圈对象","rule":"题目问的是分子、原子、离子、电子、质子、中子，还是离子晶体的化学式单位；对象名称必须写全。","examples":["²³Na：质子数11，中子数23−11=12；中性原子的电子数11。","NaCl晶体按NaCl化学式单位计数，不写‘NaCl分子’。"],"visualSteps":["圈完整对象名称","分子/原子/离子/电子","质子/中子","离子晶体化学式单位"]}$object_step$::jsonb,
  true
),
updated_at = now()
where id = 'KC_H1_MOLE_INTRO' and skill_id = 'H1_MOLE_INTRO';

-- 高三复习卡也沿用同一对象边界，避免年级切换后出现口径倒退。
update public.chem_knowledge_cards
set structured_content = jsonb_set(
  structured_content,
  '{sections,0,items,0,rule}',
  '"物质的量n以mol计；微粒数N=nN_A；对象必须明确到分子、原子、离子、电子、质子、中子、离子晶体的化学式单位或题目指定的化学键。"'::jsonb,
  true
),
updated_at = now()
where id = 'KC_H3_STOICH' and skill_id = 'H3_STOICH';

do $verify$
declare
  bad_notation text := 'N' || chr(8336);
  bad_plain_judgment text := 'N' || 'A判断题';
  bad_plain_choice text := 'N' || 'A选择题';
  bad_count integer;
  canonical_count integer;
begin
  select count(*) into bad_count
  from (
    select title || core || detail || steps::text || common_mistakes::text || micro_example || structured_content::text as body
    from public.chem_knowledge_cards
    union all
    select stem || options::text || explanation || coalesce(scaffold, '') from public.chem_questions
    union all
    select coalesce(question_snapshot::text, '') from public.chem_attempt_answers
  ) content
  where position(bad_notation in body) > 0
     or position(bad_plain_judgment in body) > 0
     or position(bad_plain_choice in body) > 0;

  if bad_count <> 0 then
    raise exception '阿伏加德罗常数旧写法仍有 % 条记录', bad_count;
  end if;

  select count(*) into canonical_count
  from public.chem_questions
  where stem like '%N_A%' or options::text like '%N_A%' or explanation like '%N_A%';
  if canonical_count < 1 then
    raise exception '题库中没有规范的N_A公式，修复结果异常';
  end if;

  if not exists (
    select 1 from public.chem_knowledge_cards
    where id = 'KC_H1_REDOX'
      and structured_content::text like '%发生氧化反应%'
      and structured_content::text like '%生成氧化产物%'
      and structured_content::text like '%发生还原反应%'
      and structured_content::text like '%生成还原产物%'
  ) then
    raise exception 'H1_REDOX完整氧化还原链校验失败';
  end if;

  if not exists (
    select 1 from public.chem_knowledge_cards
    where id = 'KC_H1_MOLE_INTRO'
      and structured_content::text like '%质子%'
      and structured_content::text like '%中子%'
      and structured_content::text like '%²³Na%'
      and structured_content::text like '%离子晶体的化学式单位%'
      and structured_content::text like '%NaCl晶体中不存在独立的NaCl分子%'
  ) then
    raise exception 'H1_MOLE_INTRO对象清单或示范校验失败';
  end if;
end
$verify$;
