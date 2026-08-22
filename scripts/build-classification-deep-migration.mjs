import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { classificationDeepContent, validateClassificationDeepContent } from './classification-deep-content.mjs'
import { classificationVisualSummary } from './knowledge-visual-summaries.mjs'

const output = process.argv[2]
if (!output) throw new Error('请传入由 supabase migration new 创建的迁移文件路径。')

const errors = validateClassificationDeepContent(classificationDeepContent)
if (errors.length) throw new Error(errors.join('\n'))

const content = { ...classificationDeepContent, visualSummary: classificationVisualSummary }
const requiredLabels = [
  '氧化物', '酸', '碱', '盐', '一元酸', '二元酸', '多元酸', '强酸', '弱酸',
  '一元碱', '二元碱', '三元碱与两性边界', '强碱', '弱碱', '易溶碱', '微溶碱', '难溶碱',
  '酸性氧化物', '碱性氧化物', '两性氧化物', '不成盐氧化物', '正盐', '酸式盐', '碱式盐',
  '电解质的五类常见来源', '非电解质', '强电解质', '弱电解质',
  'HCl、HBr、HI、HNO₃、H₂SO₄、HClO₄', 'HF是弱酸',
  '可溶盐在离子方程式中拆写，难溶盐保留化学式',
]

const sql = `-- Replace the H1 classification card with the fully audited, deeply expandable tree.
-- This affects only the REVIEW knowledge card; the independent class-quiz site is untouched.

update public.chem_knowledge_cards
set structured_content = $classification$${JSON.stringify(content)}$classification$::jsonb,
    review_status = 'approved',
    updated_at = now()
where id = 'KC_H1_CLASSIFY' and skill_id = 'H1_CLASSIFY';

do $$
declare
  content jsonb;
  section_value jsonb;
  item_value jsonb;
  required_label text;
begin
  select structured_content into content
  from public.chem_knowledge_cards
  where id = 'KC_H1_CLASSIFY' and skill_id = 'H1_CLASSIFY' and review_status = 'approved';

  if content is null then raise exception 'H1_CLASSIFY knowledge card missing'; end if;
  if coalesce((content->>'version')::integer, 0) < 4 then raise exception 'H1_CLASSIFY version is below 4'; end if;
  if jsonb_array_length(coalesce(content->'sections', '[]'::jsonb)) < 12 then
    raise exception 'H1_CLASSIFY has fewer than 12 detailed sections';
  end if;

  foreach required_label in array array[${requiredLabels.map((label) => `'${label.replaceAll("'", "''")}'`).join(',')}]::text[] loop
    if position(required_label in content::text) = 0 then
      raise exception 'H1_CLASSIFY missing required label: %', required_label;
    end if;
  end loop;

  for section_value in select value from jsonb_array_elements(content->'sections') loop
    if length(coalesce(section_value->>'title', '')) = 0 or length(coalesce(section_value->>'summary', '')) = 0 then
      raise exception 'H1_CLASSIFY contains a section without title or summary';
    end if;
    for item_value in select value from jsonb_array_elements(coalesce(section_value->'items', '[]'::jsonb)) loop
      if jsonb_array_length(coalesce(item_value->'examples', '[]'::jsonb)) < 2 then
        raise exception 'H1_CLASSIFY item has fewer than two examples: %', item_value->>'label';
      end if;
    end loop;
  end loop;

  if content::text like '%氧化还原%' then raise exception 'H1_CLASSIFY leaked untaught redox content'; end if;
  if content::text like '%所有金属氧化物都是%' then raise exception 'H1_CLASSIFY contains an absolute metal-oxide error'; end if;
  if content::text like '%能导电的物质都是电解质%' then raise exception 'H1_CLASSIFY contains a conductivity shortcut error'; end if;
  if content::text like '%HF是强酸%' then raise exception 'H1_CLASSIFY incorrectly classifies HF as a strong acid'; end if;
end $$;
`

writeFileSync(resolve(output), sql, 'utf8')
console.log(JSON.stringify({ output: resolve(output), version: content.version, sections: content.sections.length, requiredLabels: requiredLabels.length }, null, 2))
