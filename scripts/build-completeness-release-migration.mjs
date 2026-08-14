import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { zeroForgettingCards } from './zero-forgetting-content.mjs'
import { completenessQuestions } from './completeness-question-bank.mjs'
import { getP1KnowledgeCompletenessPatch } from './knowledge-completeness-p1-patches.mjs'

const output = process.argv[2]
if (!output) throw new Error('请传入由 supabase migration new 创建的迁移文件路径。')

const generatedCardSkillIds = [
  'H1_PERIODIC', 'H1_NACL', 'H1_REDOX', 'H1_ELECTROLYTE', 'H1_MOLE',
  'H2_RATE', 'H2_EQUIL', 'H2_PH_HYDRO', 'H2_ELECTRO',
  'H3_STOICH', 'H3_INORGANIC', 'H3_THERMO_RATE', 'H3_EQUILIBRIUM', 'H3_AQ',
  'H3_ELECTRO', 'H3_EXPERIMENT', 'H3_STRUCTURE', 'H3_ORGANIC',
]
const targetCards = zeroForgettingCards.filter((card) => generatedCardSkillIds.includes(card.skillId))
if (targetCards.length !== generatedCardSkillIds.length) throw new Error(`补全卡数量不符：${targetCards.length}/${generatedCardSkillIds.length}`)
const classificationPatch = getP1KnowledgeCompletenessPatch('H1_CLASSIFY')
if (!classificationPatch) throw new Error('缺少 H1_CLASSIFY 四类反应交叉分类补丁。')

const literal = (value) => `'${String(value).replaceAll("'", "''")}'`
const lines = [
  '-- 补齐福建高中复习卡的周期律、课程级P0/P1知识，并加入对应原创母题。',
  '-- 仅更新review复习系统；不修改独立小测链接或其内容。',
  '',
  `alter table public.chem_questions
  add column if not exists usable_for_class_quiz boolean not null default true,
  add column if not exists usable_for_review boolean not null default true,
  add column if not exists usable_for_exam_sprint boolean not null default true;`,
  '',
  `update public.chem_knowledge_cards
set structured_content = jsonb_set(
  jsonb_set(
    jsonb_set(
      jsonb_set(
        structured_content,
        '{overview}',
        coalesce(structured_content->'overview', '[]'::jsonb) || $classify_overview$${JSON.stringify(classificationPatch.overview)}$classify_overview$::jsonb
      ),
      '{sections}',
      coalesce(structured_content->'sections', '[]'::jsonb) || $classify_sections$${JSON.stringify(classificationPatch.sections)}$classify_sections$::jsonb
    ),
    '{workedExamples}',
    coalesce(structured_content->'workedExamples', '[]'::jsonb) || $classify_examples$${JSON.stringify(classificationPatch.workedExamples)}$classify_examples$::jsonb
  ),
  '{checkpoints}',
  coalesce(structured_content->'checkpoints', '[]'::jsonb) || $classify_checks$${JSON.stringify(classificationPatch.checkpoints)}$classify_checks$::jsonb
),
    review_status = 'approved',
    updated_at = now()
where id = 'KC_H1_CLASSIFY' and skill_id = 'H1_CLASSIFY'
  and not exists (
    select 1 from jsonb_array_elements(coalesce(structured_content->'sections', '[]'::jsonb)) entry
    where entry->>'title' = '四类基本反应与横向分类'
  );`,
  '',
]

for (const card of targetCards) {
  const tag = `$card_${card.skillId.toLowerCase()}$`
  lines.push(`update public.chem_knowledge_cards
set structured_content = ${tag}${JSON.stringify(card)}${tag}::jsonb,
    review_status = 'approved',
    updated_at = now()
where id = 'KC_${card.skillId}' and skill_id = '${card.skillId}';`, '')
}

for (const question of completenessQuestions) {
  const options = JSON.stringify(question.options)
  lines.push(`insert into public.chem_questions(
  id,mother_id,skill_id,level,grade_band,stem,options,correct_option,explanation,scaffold,review_status,scope_status,source_kind,
  usable_for_class_quiz,usable_for_review,usable_for_exam_sprint
) values (
  ${literal(question.id)},${literal(question.motherId)},${literal(question.skillId)},${question.level},${literal(question.gradeBand)},
  ${literal(question.stem)},${literal(options)}::jsonb,${question.correctOption},${literal(question.explanation)},${literal(question.scaffold ?? '')},
  'approved','IN','teacher_original',false,true,true
)
on conflict(id) do update set
  mother_id=excluded.mother_id,skill_id=excluded.skill_id,level=excluded.level,grade_band=excluded.grade_band,
  stem=excluded.stem,options=excluded.options,correct_option=excluded.correct_option,explanation=excluded.explanation,
  scaffold=excluded.scaffold,review_status='approved',scope_status='IN',source_kind='teacher_original',
  usable_for_class_quiz=false,usable_for_review=true,usable_for_exam_sprint=true,updated_at=now();`, '')
}

lines.push(`do $verify$
declare
  complete_cards integer;
  classification_complete boolean;
  complete_questions integer;
  invalid_questions integer;
begin
  select exists (
    select 1
    from public.chem_knowledge_cards
    where id = 'KC_H1_CLASSIFY' and skill_id = 'H1_CLASSIFY' and review_status = 'approved'
      and exists (
        select 1 from jsonb_array_elements(coalesce(structured_content->'sections', '[]'::jsonb)) entry
        where entry->>'title' = '四类基本反应与横向分类'
          and jsonb_array_length(coalesce(entry->'items', '[]'::jsonb)) >= 4
      )
  ) into classification_complete;

  select count(*) into complete_cards
  from public.chem_knowledge_cards
  where skill_id = any(array[${generatedCardSkillIds.map(literal).join(',')}])
    and id = 'KC_' || skill_id
    and review_status = 'approved'
    and jsonb_array_length(coalesce(structured_content->'sections','[]'::jsonb)) >= 5
    and not exists (
      select 1
      from jsonb_array_elements(structured_content->'sections') section_value
      cross join lateral jsonb_array_elements(section_value->'items') item_value
      where jsonb_array_length(coalesce(item_value->'examples','[]'::jsonb)) = 0
         or jsonb_array_length(coalesce(item_value->'visualSteps','[]'::jsonb)) < 2
    );

  select count(*), count(*) filter (
    where jsonb_array_length(options) <> 4
       or correct_option < 0 or correct_option > 3
       or review_status <> 'approved' or scope_status <> 'IN'
       or usable_for_class_quiz or not usable_for_review or not usable_for_exam_sprint
  ) into complete_questions, invalid_questions
  from public.chem_questions
  where id = any(array[${completenessQuestions.map((question) => literal(question.id)).join(',')}]);

  if complete_cards <> ${targetCards.length} then
    raise exception 'Expected ${targetCards.length} complete cards, found %', complete_cards;
  end if;
  if not classification_complete then
    raise exception 'H1_CLASSIFY P1 verification failed';
  end if;
  if complete_questions <> ${completenessQuestions.length} or invalid_questions <> 0 then
    raise exception 'Question verification failed: found %, invalid %', complete_questions, invalid_questions;
  end if;
end
$verify$;`, '')

writeFileSync(resolve(output), `${lines.join('\n').trimEnd()}\n`, 'utf8')
console.log(JSON.stringify({ output: resolve(output), updatedCards: targetCards.length + 1, insertedQuestions: completenessQuestions.length }, null, 2))
