import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'

import { zeroForgettingCards } from './zero-forgetting-content.mjs'

const output = process.argv[2]
if (!output) throw new Error('请传入迁移文件路径。')

const targetSkillIds = ['H3_INORGANIC', 'H3_EXPERIMENT']
const targets = zeroForgettingCards.filter((card) => targetSkillIds.includes(card.skillId))
if (targets.length !== targetSkillIds.length) throw new Error(`课程缺口目标卡数量不符：${targets.length}/${targetSkillIds.length}`)

const requiredExperimentLabels = [
  '配制一定物质的量浓度的溶液',
  '铁及其化合物的性质',
  '不同价态含硫物质的转化',
  '用化学沉淀法去除粗盐中的杂质离子',
  '同周期、同主族元素性质的递变',
  '化学反应速率的影响因素',
  '化学能转化成电能',
  '搭建球棍模型认识有机分子结构',
  '乙醇、乙酸的主要性质',
  '简单的电镀实验',
  '制作简单的燃料电池',
  '探究影响化学平衡移动的因素',
  '强酸与强碱的中和滴定',
  '盐类水解的应用',
  '简单配合物的制备',
  '乙酸乙酯的制备与性质',
  '有机化合物中常见官能团的检验',
  '糖类的性质',
]

const experimentCard = targets.find((card) => card.skillId === 'H3_EXPERIMENT')
const labels = new Set(experimentCard.sections.flatMap((section) => section.items.map((item) => item.label)))
const missingExperimentLabels = requiredExperimentLabels.filter((label) => !labels.has(label))
if (missingExperimentLabels.length) throw new Error(`缺少必做实验入口：${missingExperimentLabels.join('、')}`)

for (const card of targets) {
  for (const section of card.sections) {
    for (const point of section.items) {
      if (!point.examples?.some((entry) => entry.startsWith('【示范：')) || (point.visualSteps?.length ?? 0) < 2) {
        throw new Error(`${card.skillId}/${section.title}/${point.label} 缺少就地示范或图像流程。`)
      }
    }
  }
}

const lines = [
  '-- 补齐福建高中复习系统中的Mg/Cu、氮循环、无机材料和课程标准18项学生必做实验。',
  '-- 仅更新REVIEW知识卡；不修改独立小测站、quiz_sessions或学生作答记录。',
  'begin;',
  '',
]

for (const card of targets) {
  const tag = `$curriculum_gap_${card.skillId.toLowerCase()}$`
  lines.push(`update public.chem_knowledge_cards
set structured_content = ${tag}${JSON.stringify(card)}${tag}::jsonb,
    review_status = 'approved',
    updated_at = now()
where id = 'KC_${card.skillId}' and skill_id = '${card.skillId}';`, '')
}

lines.push(`do $verify$
declare
  target_count integer;
  named_experiment_count integer;
  invalid_point_count integer;
begin
  select count(*) into target_count
  from public.chem_knowledge_cards
  where id in ('KC_H3_INORGANIC', 'KC_H3_EXPERIMENT')
    and review_status = 'approved'
    and coalesce((structured_content->>'version')::integer, 0) >= 2;

  select count(*) into named_experiment_count
  from public.chem_knowledge_cards c
  cross join lateral jsonb_array_elements(c.structured_content->'sections') s
  cross join lateral jsonb_array_elements(s->'items') i
  where c.id = 'KC_H3_EXPERIMENT'
    and i->>'label' = any(array[${requiredExperimentLabels.map((label) => `'${label.replaceAll("'", "''")}'`).join(',')}]);

  select count(*) into invalid_point_count
  from public.chem_knowledge_cards c
  cross join lateral jsonb_array_elements(c.structured_content->'sections') s
  cross join lateral jsonb_array_elements(s->'items') i
  where c.id in ('KC_H3_INORGANIC', 'KC_H3_EXPERIMENT')
    and (
      jsonb_array_length(coalesce(i->'examples','[]'::jsonb)) = 0
      or jsonb_array_length(coalesce(i->'visualSteps','[]'::jsonb)) < 2
    );

  if target_count <> 2 then
    raise exception 'Expected two approved curriculum-gap cards, found %', target_count;
  end if;
  if named_experiment_count <> 18 then
    raise exception 'Expected 18 named mandatory experiments, found %', named_experiment_count;
  end if;
  if invalid_point_count <> 0 then
    raise exception 'Curriculum-gap points missing examples/visual steps: %', invalid_point_count;
  end if;
end
$verify$;

commit;`, '')

writeFileSync(resolve(output), `${lines.join('\n')}\n`, 'utf8')
console.log(JSON.stringify({
  output: resolve(output),
  updatedCards: targetSkillIds,
  namedExperiments: requiredExperimentLabels.length,
}, null, 2))
