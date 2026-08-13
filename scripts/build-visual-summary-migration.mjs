import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { classificationVisualSummary, knowledgeVisualSummaries } from './knowledge-visual-summaries.mjs'

const output = process.argv[2]
if (!output) throw new Error('请传入由 supabase migration new 创建的迁移文件路径。')

const summaries = { H1_CLASSIFY: classificationVisualSummary, ...knowledgeVisualSummaries }
const lines = [
  '-- 把高一、高二、高三复习卡的30秒文字梗概升级为关系图数据。',
  '-- 只更新review复习知识卡，不修改独立小测系统。',
  '',
]

for (const [skillId, visualSummary] of Object.entries(summaries)) {
  lines.push(`update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual$${JSON.stringify(visualSummary)}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_${skillId}' and skill_id = '${skillId}' and review_status = 'approved';`, '')
}

lines.push(`do $verify$
declare
  visual_card_count integer;
begin
  select count(*) into visual_card_count
  from public.chem_knowledge_cards c
  join public.chem_skills s on s.id = c.skill_id
  where s.active = true
    and s.grade_band in ('高一', '高二', '高三')
    and c.id = 'KC_' || c.skill_id
    and c.review_status = 'approved'
    and c.structured_content->'visualSummary'->>'kind' in ('tree', 'flow', 'cycle', 'compare', 'network', 'balance')
    and length(coalesce(c.structured_content->'visualSummary'->>'title', '')) > 0;

  if visual_card_count <> 27 then
    raise exception 'Expected 27 visual knowledge cards, found %', visual_card_count;
  end if;
end
$verify$;`, '')

writeFileSync(resolve(output), `${lines.join('\n')}\n`, 'utf8')
console.log(JSON.stringify({ output: resolve(output), updatedCards: Object.keys(summaries).length }, null, 2))
