import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { zeroForgettingCards } from './zero-forgetting-content.mjs'

const output = process.argv[2]
if (!output) throw new Error('请传入由 supabase migration new 创建的迁移文件路径。')

const classificationPatch = {
  version: 2,
  overview: [
    '先按“样品含几种物质”分成纯净物和混合物；这是整棵树的第一刀。',
    '纯净物再按元素种类分成单质和化合物；混合物不能直接进入这条分支。',
    '无机化合物继续分为氧化物、酸、碱、盐；每一类都有独立判断标准。',
    '酸的元数、强弱、含氧与否可同时存在；碱的元数、强弱、溶解性也可交叉。',
    '电解质/非电解质是只针对化合物的另一条横向分类线，不能用“能否导电”直接替代。',
  ],
  scopeNote: '本卡按苏教版必修内容和福建高中范围整理；分类结论始终以同一判断标准为前提。',
  sourceBasis: '依据普通高中化学课程标准和福建现行考试范围，以苏教版教材顺序校准；考法与表述参考G盘《2024版化学步步高一轮复习·新教材苏教版》及福建高考班校对资料。',
}

const lines = [
  '-- 为高一、高二、高三全部正式技能补齐“梗概—展开讲解—就地示范—图像记忆—自查”。',
  '-- 内容为原创讲解；本迁移只更新复习系统知识卡，不修改独立小测系统。',
  '',
  `update public.chem_knowledge_cards
set structured_content = structured_content
  || $class_patch$${JSON.stringify(classificationPatch)}$class_patch$::jsonb
  || jsonb_build_object(
    'rootTree',
    coalesce(structured_content->'rootTree', '{}'::jsonb)
      || jsonb_build_object(
        'examples', jsonb_build_array('空气：多种物质组成，走混合物分支', '液氯Cl₂：一种物质组成，走纯净物分支'),
        'visualSteps', jsonb_build_array('物质', '数物质种类', '一种→纯净物', '多种→混合物')
      )
  ),
  review_status = 'approved',
  updated_at = now()
where id = 'KC_H1_CLASSIFY' and skill_id = 'H1_CLASSIFY';`,
  '',
]

for (const content of zeroForgettingCards) {
  const id = `KC_${content.skillId}`
  lines.push(`update public.chem_knowledge_cards
set structured_content = $card$${JSON.stringify(content)}$card$::jsonb,
    review_status = 'approved',
    updated_at = now()
where id = '${id}' and skill_id = '${content.skillId}';`, '')
}

lines.push(
  `update public.chem_knowledge_cards
set review_status = 'retired', updated_at = now()
where id in ('CARD_PERIODIC_01', 'CARD_REDOX_01', 'CARD_ION_01', 'CARD_H2_RATE', 'CARD_H3_EQ');`,
  '',
  `do $verify$
declare
  formal_skill_count integer;
  complete_card_count integer;
  approved_duplicate_count integer;
begin
  select count(*) into formal_skill_count
  from public.chem_skills
  where active = true and grade_band in ('高一', '高二', '高三');

  select count(*) into complete_card_count
  from public.chem_knowledge_cards c
  join public.chem_skills s on s.id = c.skill_id
  where s.active = true
    and s.grade_band in ('高一', '高二', '高三')
    and c.id = 'KC_' || c.skill_id
    and c.review_status = 'approved'
    and coalesce((c.structured_content->>'version')::integer, 0) >= 2
    and jsonb_array_length(coalesce(c.structured_content->'overview', '[]'::jsonb)) >= 4
    and jsonb_array_length(coalesce(c.structured_content->'sections', '[]'::jsonb)) >= 4
    and jsonb_array_length(coalesce(c.structured_content->'workedExamples', '[]'::jsonb)) >= 2
    and jsonb_array_length(coalesce(c.structured_content->'checkpoints', '[]'::jsonb)) >= 4
    and not exists (
      select 1
      from jsonb_array_elements(c.structured_content->'sections') section_value
      cross join lateral jsonb_array_elements(section_value->'items') item_value
      where jsonb_array_length(coalesce(item_value->'examples', '[]'::jsonb)) = 0
    );

  select count(*) into approved_duplicate_count
  from (
    select c.skill_id
    from public.chem_knowledge_cards c
    join public.chem_skills s on s.id = c.skill_id
    where s.active = true
      and s.grade_band in ('高一', '高二', '高三')
      and c.review_status = 'approved'
    group by c.skill_id
    having count(*) <> 1
  ) duplicates;

  if formal_skill_count <> 27 then
    raise exception 'Expected 27 active H1-H3 skills, found %', formal_skill_count;
  end if;
  if complete_card_count <> 27 then
    raise exception 'Expected 27 complete zero-forgetting cards, found %', complete_card_count;
  end if;
  if approved_duplicate_count <> 0 then
    raise exception 'Approved knowledge-card duplicates remain for % skills', approved_duplicate_count;
  end if;
end
$verify$;`,
  '',
)

writeFileSync(resolve(output), `${lines.join('\n')}\n`, 'utf8')
console.log(JSON.stringify({ output: resolve(output), updatedCards: 27, generatedCards: zeroForgettingCards.length, retiredDuplicates: 5 }, null, 2))
