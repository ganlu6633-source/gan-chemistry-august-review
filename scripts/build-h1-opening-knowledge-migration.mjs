import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const sourcePath = path.join(repoRoot, 'content', 'knowledge', 'h1_opening_knowledge_cards.json')
const migrationPath = path.join(repoRoot, 'supabase', 'migrations', '20260829173000_publish_h1_opening_knowledge_cards.sql')
const expectedIds = [
  'KC_H1_REACTION_CLASSIFICATION_ZERO',
  'KC_H1_SOLUTION_CONCENTRATION_ZERO',
]

const cards = JSON.parse(readFileSync(sourcePath, 'utf8'))
if (!Array.isArray(cards) || cards.length !== expectedIds.length) {
  throw new Error(`H1 opening source must contain exactly ${expectedIds.length} cards`)
}
for (const [index, card] of cards.entries()) {
  if (card.id !== expectedIds[index]) throw new Error(`Unexpected H1 card id at index ${index}: ${card.id}`)
  if (card.review_status !== 'approved') throw new Error(`${card.id} must remain approved`)
  if (card.structured_content?.version !== 4) throw new Error(`${card.id} must use structured contract v4`)
  if (card.asset?.contractVersion !== 4 || card.asset?.studentSourceHidden !== true) {
    throw new Error(`${card.id} must retain the source-hidden v4 asset contract`)
  }
  if (card.structured_content?.sections?.length !== 5 || card.concept_manifest?.length !== 5) {
    throw new Error(`${card.id} must contain five reviewed sections and five concept entries`)
  }
  if (card.structured_content?.workedExamples?.length < 2 || card.structured_content?.checkpoints?.length !== 5) {
    throw new Error(`${card.id} is missing reviewed examples or checkpoints`)
  }
}

const canonicalHash = createHash('sha256').update(JSON.stringify(cards)).digest('hex')
const payload = JSON.stringify(cards, null, 2)

const sql = `-- Generated from content/knowledge/h1_opening_knowledge_cards.json.
-- Canonical JSON SHA-256: ${canonicalHash}
-- Contains only reviewed, student-facing knowledge content; no source paths,
-- question text, answer assets, access data, or unpublished release metadata.

begin;

insert into public.chem_skills (
  id, title, module_id, grade_band, max_level, exam_importance, exam_depth,
  prerequisites, level_criteria, active
)
values
  (
    'H1_REACTION_CLASSIFICATION', '物质转化与化学反应分类', 'H1-SUJIAO-B1-U1',
    '高一', 3, 5, 3, array[]::text[],
    '[{"level":1,"studentFacingGoal":"能辨认物质类别与基本反应类型","requiredAbility":"依据组成和反应物、生成物特征完成基础分类"},{"level":2,"studentFacingGoal":"能在新情境中判断转化与反应分类","requiredAbility":"结合反应条件、价态和离子变化迁移分类规则"},{"level":3,"studentFacingGoal":"能综合判断多步转化及分类依据","requiredAbility":"同时核对物质类别、反应类型和边界条件并说明理由"}]'::jsonb,
    true
  ),
  (
    'H1_SOLUTION_CONCENTRATION', '物质的量浓度、配制、稀释与误差', 'H1-SUJIAO-B1-U1',
    '高一', 3, 5, 3, array[]::text[],
    '[{"level":1,"studentFacingGoal":"能辨认物质的量浓度及配制步骤","requiredAbility":"能用c=n/V完成基础换算并识别规范操作"},{"level":2,"studentFacingGoal":"能处理稀释、混合与配制误差","requiredAbility":"能用溶质守恒和误差方向分析变化情境"},{"level":3,"studentFacingGoal":"能综合解决浓度配制与实验评价","requiredAbility":"能串联计算、实验步骤和误差判断完成综合分析"}]'::jsonb,
    true
  )
on conflict (id) do update set
  title = excluded.title,
  module_id = excluded.module_id,
  grade_band = excluded.grade_band,
  max_level = excluded.max_level,
  exam_importance = excluded.exam_importance,
  exam_depth = excluded.exam_depth,
  prerequisites = excluded.prerequisites,
  level_criteria = excluded.level_criteria,
  active = true,
  updated_at = now();

with reviewed_cards as (
  select value as card
  from jsonb_array_elements($h1_opening_cards$${payload}$h1_opening_cards$::jsonb)
)
insert into public.chem_knowledge_cards (
  id, skill_id, title, core, detail, steps, common_mistakes, micro_example,
  asset, review_status, structured_content
)
select
  card->>'id',
  card->>'skill_id',
  card->>'title',
  card->>'core',
  card->>'detail',
  card->'steps',
  card->'common_mistakes',
  card->>'micro_example',
  card->'asset',
  card->>'review_status',
  card->'structured_content'
from reviewed_cards
on conflict (id) do update set
  skill_id = excluded.skill_id,
  title = excluded.title,
  core = excluded.core,
  detail = excluded.detail,
  steps = excluded.steps,
  common_mistakes = excluded.common_mistakes,
  micro_example = excluded.micro_example,
  asset = excluded.asset,
  review_status = excluded.review_status,
  structured_content = excluded.structured_content,
  updated_at = now();

do $h1_opening_contract$
begin
  if exists (
    select 1
    from public.chem_skills as skill
    where skill.id in ('H1_REACTION_CLASSIFICATION', 'H1_SOLUTION_CONCENTRATION')
      and (
        jsonb_typeof(skill.level_criteria) is distinct from 'array'
        or jsonb_array_length(skill.level_criteria) <> skill.max_level
        or exists (
          select 1
          from jsonb_array_elements(skill.level_criteria) with ordinality as criterion(value, ordinal)
          where case
              when coalesce(criterion.value->>'level', '') ~ '^[1-9][0-9]*$'
                then (criterion.value->>'level')::integer
              else -1
            end <> criterion.ordinal
            or length(btrim(coalesce(criterion.value->>'studentFacingGoal', ''))) = 0
            or length(btrim(coalesce(criterion.value->>'requiredAbility', ''))) = 0
        )
      )
  ) then
    raise exception 'H1 opening skill level criteria do not match the typed three-level contract';
  end if;

  if (
    select count(*)
    from public.chem_knowledge_cards
    where id in ('KC_H1_REACTION_CLASSIFICATION_ZERO', 'KC_H1_SOLUTION_CONCENTRATION_ZERO')
  ) <> 2 then
    raise exception 'H1 opening knowledge cards were not both stored';
  end if;

  if exists (
    select 1
    from public.chem_knowledge_cards
    where id in ('KC_H1_REACTION_CLASSIFICATION_ZERO', 'KC_H1_SOLUTION_CONCENTRATION_ZERO')
      and (
        review_status <> 'approved'
        or coalesce((structured_content->>'version')::integer, 0) <> 4
        or jsonb_array_length(coalesce(structured_content->'sections', '[]'::jsonb)) <> 5
        or jsonb_array_length(coalesce(structured_content->'workedExamples', '[]'::jsonb)) < 2
        or jsonb_array_length(coalesce(structured_content->'checkpoints', '[]'::jsonb)) <> 5
        or coalesce((asset->>'contractVersion')::integer, 0) <> 4
        or coalesce((asset->>'studentSourceHidden')::boolean, false) is not true
      )
  ) then
    raise exception 'H1 opening knowledge-card v4 contract failed';
  end if;

  if exists (
    select skill_id
    from public.chem_knowledge_cards
    where skill_id in ('H1_REACTION_CLASSIFICATION', 'H1_SOLUTION_CONCENTRATION')
      and review_status = 'approved'
    group by skill_id
    having count(*) <> 1
  ) then
    raise exception 'H1 opening skill has more than one approved knowledge card';
  end if;

  if exists (
    select expected.skill_id
    from (values
      ('H1_REACTION_CLASSIFICATION'),
      ('H1_SOLUTION_CONCENTRATION')
    ) as expected(skill_id)
    where not exists (
      select 1
      from public.chem_knowledge_cards card
      where card.skill_id = expected.skill_id and card.review_status = 'approved'
    )
  ) then
    raise exception 'H1 opening skill is missing its approved knowledge card';
  end if;
end;
$h1_opening_contract$;

commit;
`

if (process.argv.includes('--check')) {
  const current = readFileSync(migrationPath, 'utf8').replaceAll('\r\n', '\n')
  if (current !== sql) throw new Error('H1 opening migration is stale; regenerate it from the reviewed JSON source')
  console.log(`H1 opening migration is reproducible (${cards.length} cards, ${canonicalHash})`)
} else {
  process.stdout.write(sql)
}
