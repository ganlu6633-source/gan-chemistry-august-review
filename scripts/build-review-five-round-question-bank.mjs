import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { high1ReviewQuestionBank } from './review-question-bank-high1.mjs';
import { high2ReviewQuestionBank } from './review-question-bank-high2.mjs';
import { high3ReviewQuestionBank } from './review-question-bank-high3.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(
  root,
  'supabase',
  'migrations',
  '20260814155056_high_school_review_exam_question_bank.sql',
);

const bank = {
  ...high1ReviewQuestionBank,
  ...high2ReviewQuestionBank,
  ...high3ReviewQuestionBank,
};

const expectedSkills = [
  'H1_CLASSIFY',
  'H1_GAS_MOLAR_VOLUME',
  'H1_MOLE_INTRO',
  'H1_PERIODIC',
  'H1_REDOX',
  'H2_ELECTRO',
  'H2_EQUIL',
  'H2_K',
  'H2_KSP',
  'H2_PH_HYDRO',
  'H2_RATE',
  'H2_THERMO',
  'H2_WEAK',
  'H3_AQ',
  'H3_ELECTRO',
  'H3_EQUILIBRIUM',
  'H3_EXPERIMENT',
  'H3_INORGANIC',
  'H3_ION_REDOX',
  'H3_ORGANIC',
  'H3_PROCESS',
  'H3_STOICH',
  'H3_STRUCTURE',
  'H3_THERMO_RATE',
];

const scaffolds = {
  H1_CLASSIFY: '先锁定研究对象和分类标准，再沿组成树逐层判断。',
  H1_GAS_MOLAR_VOLUME: '先检查物态和温压条件，再用V↔n连接N或m。',
  H1_MOLE_INTRO: '把已知量先换成n，并写清所数微粒及化学式下标。',
  H1_PERIODIC: '先确定同周期或同主族，再从层数、核吸引和半径解释。',
  H1_REDOX: '标出变化元素的反应前后化合价，再核对电子得失。',
  H2_THERMO: '区分始态、终态、反应路径，注意方程式倍乘和物态。',
  H2_RATE: '只比较被改变的条件，并从浓度、碰撞或活化能解释。',
  H2_EQUIL: '写出外界改变后瞬间Q、K或正逆速率的相对关系。',
  H2_K: '先配平方程式，再写Q或K表达式并检查固液项。',
  H2_WEAK: '列出弱电解质分子和离子，追踪同离子或稀释影响。',
  H2_PH_HYDRO: '先列溶液粒子，再用Kw、水解和守恒关系判断。',
  H2_KSP: '写溶解平衡并计算Qsp，再与Ksp比较。',
  H2_ELECTRO: '先定阳极氧化、阴极还原，再画电子和离子通道。',
  H3_STOICH: '把质量、体积、浓度或微粒数统一换成n，再用守恒。',
  H3_ION_REDOX: '先按介质写粒子形式，再检查原子、电荷和电子守恒。',
  H3_INORGANIC: '锁定中心元素的价态、物质类别和题给反应条件。',
  H3_THERMO_RATE: '分清ΔH、活化能、速率和平衡限度四个量。',
  H3_EQUILIBRIUM: '用改变后瞬间的Q与K或v正与v逆判断净方向。',
  H3_AQ: '列全粒子并联立平衡关系、电荷守恒和物料守恒。',
  H3_ELECTRO: '把两个电极反应配到电子数相等，再检查膜和离子方向。',
  H3_EXPERIMENT: '把操作与实验目的对应，并检查安全、对照和误差方向。',
  H3_PROCESS: '沿原料—转化—分离—结晶追踪目标元素和杂质去向。',
  H3_STRUCTURE: '从电子排布、成键和空间结构逐层连接到宏观性质。',
  H3_ORGANIC: '标出碳骨架与官能团，再核对反应类型和原子去向。',
};

const forbiddenSource = /(核心规律|最可靠.{0,8}第一步|处理.{0,20}(第一步|优先)|优先检查|最先做)/u;
const unicodeSubscriptA = `N${String.fromCodePoint(0x2090)}`;
const actualSkills = Object.keys(bank).sort();
const requiredSkills = [...expectedSkills].sort();

if (JSON.stringify(actualSkills) !== JSON.stringify(requiredSkills)) {
  throw new Error(`Skill mismatch: ${JSON.stringify(actualSkills)}`);
}

const allStems = new Set();
const conceptCounts = new Map();
for (const skillId of expectedSkills) {
  const entries = bank[skillId];
  if (!Array.isArray(entries) || entries.length !== 25) {
    throw new Error(`${skillId} must contain exactly 25 authored mothers`);
  }
  if (!scaffolds[skillId]) throw new Error(`Missing scaffold for ${skillId}`);
  for (const [index, entry] of entries.entries()) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      throw new Error(`${skillId} item ${index + 1} must be an authored question object`);
    }
    const {
      concept_key: conceptKey,
      format,
      statement,
      options,
      correct_option: correctOption,
      explanation,
    } = entry;
    if (!conceptKey?.startsWith(`${skillId}__`)) {
      throw new Error(`${skillId} item ${index + 1} has an invalid concept_key`);
    }
    if (!['combo', 'tf'].includes(format)) throw new Error(`${skillId} item ${index + 1} has an invalid format`);
    if (typeof statement !== 'string' || statement.length < 8) {
      throw new Error(`${skillId} item ${index + 1} has an invalid statement`);
    }
    if (typeof explanation !== 'string' || explanation.length < 8) {
      throw new Error(`${skillId} item ${index + 1} lacks a substantive explanation`);
    }
    const expectedOptionCount = format === 'combo' ? 4 : 2;
    if (!Array.isArray(options) || options.length !== expectedOptionCount) {
      throw new Error(`${skillId} item ${index + 1} has invalid options`);
    }
    if (!['A', 'B', 'C', 'D'].slice(0, expectedOptionCount).includes(correctOption)) {
      throw new Error(`${skillId} item ${index + 1} has an invalid correct option`);
    }
    if (forbiddenSource.test(`${statement} ${explanation}`)
      || `${statement} ${explanation}`.includes(unicodeSubscriptA)) {
      throw new Error(`${skillId} item ${index + 1} contains forbidden meta/notation text`);
    }
    if (allStems.has(statement)) throw new Error(`Duplicate authored statement: ${statement}`);
    allStems.add(statement);
    const summary = conceptCounts.get(conceptKey) ?? { skillId, total: 0, combo: 0, tf: 0 };
    summary.total += 1;
    summary[format] += 1;
    conceptCounts.set(conceptKey, summary);
  }
}

for (const skillId of expectedSkills) {
  const concepts = [...conceptCounts.entries()].filter(([, summary]) => summary.skillId === skillId);
  if (concepts.length !== 5) throw new Error(`${skillId} must contain exactly five concept_key groups`);
  for (const [conceptKey, summary] of concepts) {
    if (summary.total !== 5 || summary.combo !== 2 || summary.tf !== 3) {
      throw new Error(`${conceptKey} must contain five variants: two combo MCQ and three true/false`);
    }
  }
}

const sqlLiteral = (value) => `'${String(value).replaceAll("'", "''")}'`;
const gradeFor = (skillId) => (skillId.startsWith('H1_') ? '高一' : skillId.startsWith('H2_') ? '高二' : '高三');
const levelFor = (skillId, index) => {
  if (skillId.startsWith('H1_')) return index < 8 ? 1 : index < 17 ? 2 : 3;
  if (skillId.startsWith('H2_')) return index < 6 ? 1 : index < 16 ? 2 : 3;
  return index < 5 ? 2 : index < 15 ? 3 : 4;
};

const records = [];
let comboSequence = 0;
for (const skillId of expectedSkills) {
  bank[skillId].forEach((entry, index) => {
    const answerIndex = entry.correct_option.charCodeAt(0) - 65;
    const rotation = entry.format === 'combo' ? comboSequence++ % 4 : 0;
    const options = [...entry.options.slice(rotation), ...entry.options.slice(0, rotation)];
    const correctOption = (answerIndex - rotation + entry.options.length) % entry.options.length;
    const sequence = String(index + 1).padStart(2, '0');
    const questionId = `Q5R_${skillId}_${sequence}`;
    const motherId = `M5R_${skillId}_${sequence}`;
    records.push({
      id: questionId,
      mother_id: motherId,
      skill_id: skillId,
      concept_key: entry.concept_key,
      level: levelFor(skillId, index),
      grade_band: gradeFor(skillId),
      stem: entry.format === 'combo' ? `组合判断：${entry.statement}` : `判断：${entry.statement}`,
      options,
      correct_option: correctOption,
      explanation: entry.format === 'combo' ? entry.explanation : `${entry.correct_option === 'A' ? '正确' : '错误'}。${entry.explanation}`,
      scaffold: scaffolds[skillId],
    });
  });
}

const qaBatch = process.env.REVIEW_BANK_QA_BATCH;
if (qaBatch !== undefined) {
  const batchIndex = Number.parseInt(qaBatch, 10);
  if (!Number.isInteger(batchIndex) || batchIndex < 0 || batchIndex >= expectedSkills.length) {
    throw new Error(`REVIEW_BANK_QA_BATCH must be an integer from 0 through ${expectedSkills.length - 1}`);
  }
  const skills = expectedSkills.slice(batchIndex, batchIndex + 1);
  process.stdout.write(JSON.stringify(records.filter((record) => skills.includes(record.skill_id))));
  process.exit(0);
}

const targetValues = expectedSkills
  .map((skillId) => {
    const cap = skillId.startsWith('H1_') ? 3 : skillId.startsWith('H2_') ? 3 : 4;
    return `(${sqlLiteral(skillId)},${cap})`;
  })
  .join(',\n  ');

const sql = `begin;

-- This pool is teacher-authored from curriculum concepts and examination forms.
-- Commercial books informed only the coverage categories; no stem is copied.
create temporary table review_exam_target_skills(
  skill_id text primary key,
  level_cap smallint not null
) on commit drop;

insert into review_exam_target_skills(skill_id,level_cap) values
  ${targetValues};

alter table public.chem_questions
  add column if not exists concept_key text;

alter table public.chem_attempt_answers
  add column if not exists concept_key text;

comment on column public.chem_questions.concept_key is
  'Fine-grained concept identity used to replace an uncertain answer with a new mother question of the same concept.';

comment on column public.chem_attempt_answers.concept_key is
  'Snapshot of the answered question fine-grained concept for same-concept five-round progression.';

create index if not exists chem_questions_review_concept_idx
  on public.chem_questions(skill_id,concept_key,level)
  where review_status='approved' and scope_status='IN' and usable_for_review;

create index if not exists chem_answers_attempt_concept_idx
  on public.chem_attempt_answers(attempt_id,concept_key,created_at desc)
  where concept_key is not null;

-- Retire generic content-production prompts while preserving every historical row.
update public.chem_questions q
set review_status='retired',
    usable_for_review=false,
    updated_at=now()
where q.skill_id in (select skill_id from review_exam_target_skills)
  and q.review_status='approved'
  and q.stem ~ '(核心规律|最可靠.{0,8}第一步|处理.{0,20}(第一步|优先)|优先检查|最先做)';

with authored as (
  select *
  from jsonb_to_recordset(
    $review_question_bank$${JSON.stringify(records)}$review_question_bank$::jsonb
  ) as q(
    id text,
    mother_id text,
    skill_id text,
    concept_key text,
    level smallint,
    grade_band text,
    stem text,
    options jsonb,
    correct_option smallint,
    explanation text,
    scaffold text
  )
)
insert into public.chem_questions(
  id,mother_id,skill_id,concept_key,level,grade_band,stem,options,correct_option,
  explanation,scaffold,review_status,scope_status,source_kind,image_url,
  usable_for_class_quiz,usable_for_review,usable_for_exam_sprint,updated_at
)
select
  id,mother_id,skill_id,concept_key,level,grade_band,stem,options,correct_option,
  explanation,scaffold,'approved','IN','teacher_original',null,
  false,true,true,now()
from authored
on conflict (id) do update set
  mother_id=excluded.mother_id,
  skill_id=excluded.skill_id,
  concept_key=excluded.concept_key,
  level=excluded.level,
  grade_band=excluded.grade_band,
  stem=excluded.stem,
  options=excluded.options,
  correct_option=excluded.correct_option,
  explanation=excluded.explanation,
  scaffold=excluded.scaffold,
  review_status='approved',
  scope_status='IN',
  source_kind='teacher_original',
  image_url=null,
  usable_for_class_quiz=false,
  usable_for_review=true,
  usable_for_exam_sprint=true,
  updated_at=now();

do $$
begin
  if exists (
    with used as (
      select distinct unnest(p.skill_ids) skill_id
      from public.chem_learning_plans p
      join public.chem_students_v2 s on s.id=p.student_id
      where p.mode='REVIEW'
        and s.record_status='active'
        and s.grade_band in ('高一','高二','高三')
    )
    select 1
    from (
      (select skill_id from used except select skill_id from review_exam_target_skills)
      union all
      (select skill_id from review_exam_target_skills except select skill_id from used)
    ) mismatch
  ) then
    raise exception 'The authored bank and active high-school REVIEW skill set no longer match';
  end if;

  if (select count(*) from public.chem_questions where id like 'Q5R\\_%' escape '\\') <> 600
     or (select count(distinct mother_id) from public.chem_questions where id like 'Q5R\\_%' escape '\\') <> 600
     or (select count(distinct concept_key) from public.chem_questions where id like 'Q5R\\_%' escape '\\') <> 120 then
    raise exception 'The five-round authored bank must contain 600 unique questions and mothers';
  end if;

  if exists (
    select 1
    from (
      select skill_id,concept_key,
             count(*) question_count,
             count(distinct mother_id) mother_count,
             count(*) filter (where jsonb_array_length(options)=4) four_option_count,
             count(*) filter (where jsonb_array_length(options)=2) two_option_count
      from public.chem_questions
      where id like 'Q5R\\_%' escape '\\'
      group by skill_id,concept_key
    ) concept_pool
    where concept_key is null
       or question_count<>5
       or mother_count<>5
       or four_option_count<>2
       or two_option_count<>3
  ) or exists (
    select 1
    from (
      select skill_id,count(distinct concept_key) concept_count
      from public.chem_questions
      where id like 'Q5R\\_%' escape '\\'
      group by skill_id
    ) skill_pool
    where concept_count<>5
  ) then
    raise exception 'Every REVIEW skill must contain five concepts, each with five mothers, two four-option and three true/false variants';
  end if;

  if exists (
    select 1
    from review_exam_target_skills t
    left join lateral (
      select count(*) eligible_questions,
             count(distinct q.mother_id) eligible_mothers
      from public.chem_questions q
      where q.skill_id=t.skill_id
        and q.review_status='approved'
        and q.scope_status='IN'
        and q.usable_for_review
        and q.level<=t.level_cap
    ) pool on true
    where pool.eligible_questions<25 or pool.eligible_mothers<25
  ) then
    raise exception 'At least one REVIEW skill cannot supply 25 approved IN-scope unique mothers under its level cap';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    join review_exam_target_skills t on t.skill_id=q.skill_id
    where q.review_status='approved'
      and q.scope_status='IN'
      and q.usable_for_review
      and q.level<=t.level_cap
      and q.stem ~ '(核心规律|最可靠.{0,8}第一步|处理.{0,20}(第一步|优先)|优先检查|最先做)'
  ) then
    raise exception 'A generic meta-prompt remains in the active high-school REVIEW pool';
  end if;

  if exists (
    select 1 from public.chem_questions
    where id like 'Q5R\\_%' escape '\\'
      and (review_status<>'approved' or scope_status<>'IN' or not usable_for_review
        or usable_for_class_quiz or source_kind<>'teacher_original'
        or concept_key is null or concept_key not like skill_id||'__%'
        or jsonb_array_length(options) not in (2,4)
        or correct_option<0 or correct_option>=jsonb_array_length(options)
        or scaffold is null or length(scaffold)<8
        or explanation is null or length(explanation)<8
        or position('N'||chr(8336) in stem)>0)
  ) then
    raise exception 'The authored five-round question metadata or notation contract is invalid';
  end if;
end $$;

commit;
`;

fs.writeFileSync(output, sql, 'utf8');
console.log(`Wrote ${records.length} questions across ${expectedSkills.length} skills to ${output}`);
