import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const migrationPath = path.join(
  root,
  'supabase',
  'migrations',
  '20260814155056_high_school_review_exam_question_bank.sql',
);

const migration = fs.readFileSync(migrationPath, 'utf8');
const marker = '$review_question_bank$';
const parts = migration.split(marker);
if (parts.length !== 3) throw new Error('Generated migration must contain one dollar-quoted question bank');

const records = JSON.parse(parts[1]);
const expectedSkills = [
  'H1_CLASSIFY', 'H1_GAS_MOLAR_VOLUME', 'H1_MOLE_INTRO', 'H1_PERIODIC', 'H1_REDOX',
  'H2_ELECTRO', 'H2_EQUIL', 'H2_K', 'H2_KSP', 'H2_PH_HYDRO', 'H2_RATE', 'H2_THERMO', 'H2_WEAK',
  'H3_AQ', 'H3_ELECTRO', 'H3_EQUILIBRIUM', 'H3_EXPERIMENT', 'H3_INORGANIC', 'H3_ION_REDOX',
  'H3_ORGANIC', 'H3_PROCESS', 'H3_STOICH', 'H3_STRUCTURE', 'H3_THERMO_RATE',
];

const ids = new Set();
const mothers = new Set();
const stems = new Set();
const forbiddenMeta = /(核心规律|最可靠.{0,8}第一步|处理.{0,20}(第一步|优先)|优先检查|最先做)/u;
const unicodeSubscriptA = `N${String.fromCodePoint(0x2090)}`;
const gradeFor = (skillId) => (skillId.startsWith('H1_') ? '高一' : skillId.startsWith('H2_') ? '高二' : '高三');
const expectedLevels = {
  高一: { 1: 8, 2: 9, 3: 8 },
  高二: { 1: 6, 2: 10, 3: 9 },
  高三: { 2: 5, 3: 10, 4: 10 },
};
const comboOptionSet = new Set(['Ⅰ、Ⅱ均正确', 'Ⅰ正确、Ⅱ错误', 'Ⅰ错误、Ⅱ正确', 'Ⅰ、Ⅱ均错误']);

const perSkill = {};
const perConcept = {};
const answerLetters = { A: 0, B: 0, C: 0, D: 0 };
const fourOptionAnswerLetters = { A: 0, B: 0, C: 0, D: 0 };
for (const skillId of expectedSkills) {
  perSkill[skillId] = {
    questions: 0,
    mothers: new Set(),
    concepts: new Set(),
    twoOption: 0,
    fourOption: 0,
    levels: {},
  };
}

for (const record of records) {
  if (!perSkill[record.skill_id]) throw new Error(`Unexpected skill ${record.skill_id}`);
  if (record.grade_band !== gradeFor(record.skill_id)) throw new Error(`Grade mismatch for ${record.id}`);
  if (!/^Q5R_[A-Z0-9_]+_\d{2}$/.test(record.id)) throw new Error(`Invalid question id ${record.id}`);
  if (!/^M5R_[A-Z0-9_]+_\d{2}$/.test(record.mother_id)) throw new Error(`Invalid mother id ${record.mother_id}`);
  if (!record.concept_key?.startsWith(`${record.skill_id}__`)) throw new Error(`Invalid concept_key for ${record.id}`);
  if (ids.has(record.id)) throw new Error(`Duplicate id ${record.id}`);
  if (mothers.has(record.mother_id)) throw new Error(`Duplicate mother ${record.mother_id}`);
  if (stems.has(record.stem)) throw new Error(`Duplicate stem ${record.stem}`);
  ids.add(record.id);
  mothers.add(record.mother_id);
  stems.add(record.stem);

  if (!/^(判断|组合判断)：/.test(record.stem) || record.stem.length < 12) {
    throw new Error(`Non-exam stem ${record.id}`);
  }
  if (forbiddenMeta.test(record.stem)) throw new Error(`Meta prompt ${record.id}`);
  if (`${record.stem} ${record.explanation} ${record.scaffold}`.includes(unicodeSubscriptA)) {
    throw new Error(`Forbidden Unicode subscript a in ${record.id}`);
  }
  if (![2, 4].includes(record.options?.length)) throw new Error(`Invalid options for ${record.id}`);
  if (!Number.isInteger(record.correct_option)
    || record.correct_option < 0
    || record.correct_option >= record.options.length) {
    throw new Error(`Invalid answer for ${record.id}`);
  }

  if (record.options.length === 2) {
    if (JSON.stringify(record.options) !== JSON.stringify(['正确', '错误'])) {
      throw new Error(`Invalid true/false options for ${record.id}`);
    }
    const expectedPrefix = record.correct_option === 0 ? '正确。' : '错误。';
    if (!record.explanation.startsWith(expectedPrefix)) throw new Error(`Bad true/false explanation ${record.id}`);
  } else {
    if (record.options.some((option) => !comboOptionSet.has(option))
      || new Set(record.options).size !== 4
      || !record.stem.includes('Ⅰ.')
      || !record.stem.includes('Ⅱ.')
      || !/^Ⅰ(正确|错误)，Ⅱ正确。/.test(record.explanation)) {
      throw new Error(`Invalid four-option combination question ${record.id}`);
    }
  }

  if (record.explanation.length < 12) throw new Error(`Explanation is too short for ${record.id}`);
  if (typeof record.scaffold !== 'string' || record.scaffold.length < 8) {
    throw new Error(`Missing scaffold for ${record.id}`);
  }

  answerLetters[String.fromCharCode(65 + record.correct_option)] += 1;
  if (record.options.length === 4) {
    fourOptionAnswerLetters[String.fromCharCode(65 + record.correct_option)] += 1;
  }
  const summary = perSkill[record.skill_id];
  summary.questions += 1;
  summary.mothers.add(record.mother_id);
  summary.concepts.add(record.concept_key);
  summary[record.options.length === 4 ? 'fourOption' : 'twoOption'] += 1;
  summary.levels[record.level] = (summary.levels[record.level] ?? 0) + 1;

  const conceptSummary = perConcept[record.concept_key] ?? {
    skillId: record.skill_id,
    questions: 0,
    mothers: new Set(),
    twoOption: 0,
    fourOption: 0,
  };
  conceptSummary.questions += 1;
  conceptSummary.mothers.add(record.mother_id);
  conceptSummary[record.options.length === 4 ? 'fourOption' : 'twoOption'] += 1;
  perConcept[record.concept_key] = conceptSummary;
}

if (records.length !== 600 || ids.size !== 600 || mothers.size !== 600 || stems.size !== 600) {
  throw new Error('Bank must contain 600 globally unique questions, mothers, and stems');
}
if (Object.keys(perConcept).length !== 120) throw new Error('Bank must contain 120 fine-grained concepts');

for (const [skillId, summary] of Object.entries(perSkill)) {
  if (summary.questions !== 25 || summary.mothers.size !== 25 || summary.concepts.size !== 5) {
    throw new Error(`${skillId} must contain 25 unique mothers across five concepts`);
  }
  if (summary.fourOption !== 10 || summary.twoOption !== 15) {
    throw new Error(`${skillId} must contain 10 four-option and 15 true/false variants`);
  }
  const expected = expectedLevels[gradeFor(skillId)];
  if (JSON.stringify(summary.levels) !== JSON.stringify(expected)) {
    throw new Error(`${skillId} level distribution mismatch: ${JSON.stringify(summary.levels)}`);
  }
}

for (const [conceptKey, summary] of Object.entries(perConcept)) {
  if (summary.questions !== 5
    || summary.mothers.size !== 5
    || summary.fourOption !== 2
    || summary.twoOption !== 3) {
    throw new Error(`${conceptKey} must contain five unique mothers: two four-option and three true/false`);
  }
}

// A changed inequality sign, negation, reagent label, or heat-effect word does
// not make a new mother question. Compare punctuation-insensitive character
// trigrams inside each fine-grained concept and reject template-flipped pairs.
const similarityGrams = (value) => {
  const normalized = value.replace(/[^\p{L}\p{N}]/gu, '');
  const grams = new Set();
  for (let index = 0; index < normalized.length - 2; index += 1) {
    grams.add(normalized.slice(index, index + 3));
  }
  return grams;
};
const trigramSimilarity = (left, right) => {
  const leftGrams = similarityGrams(left);
  const rightGrams = similarityGrams(right);
  let intersection = 0;
  for (const gram of leftGrams) if (rightGrams.has(gram)) intersection += 1;
  return intersection / (leftGrams.size + rightGrams.size - intersection || 1);
};
const conceptRecords = Object.groupBy(records, (record) => record.concept_key);
const nearDuplicatePairs = [];
for (const [conceptKey, variants] of Object.entries(conceptRecords)) {
  for (let left = 0; left < variants.length; left += 1) {
    for (let right = left + 1; right < variants.length; right += 1) {
      const similarity = trigramSimilarity(variants[left].stem, variants[right].stem);
      if (similarity >= 0.72) {
        nearDuplicatePairs.push({
          conceptKey,
          left: variants[left].id,
          right: variants[right].id,
          similarity: Number(similarity.toFixed(3)),
        });
      }
    }
  }
}
if (nearDuplicatePairs.length) {
  throw new Error(`Near-duplicate mother questions detected: ${JSON.stringify(nearDuplicatePairs)}`);
}

if (Math.min(...Object.values(fourOptionAnswerLetters)) < 50) {
  throw new Error(`Four-option correct positions are too predictable: ${JSON.stringify(fourOptionAnswerLetters)}`);
}

const gasText = records
  .filter((record) => record.skill_id === 'H1_GAS_MOLAR_VOLUME')
  .map((record) => `${record.stem} ${record.explanation}`)
  .join(' ');
if (/(物质的量浓度|溶液配制|反应计量|理想气体方程)/u.test(gasText)) {
  throw new Error('H1 gas bank leaks content outside the confirmed classroom boundary');
}

for (const requiredFragment of [
  'add column if not exists concept_key text',
  'chem_answers_attempt_concept_idx',
  "review_status='retired'",
  'usable_for_review=false',
  "q.scope_status='IN'",
  'count(distinct q.mother_id)',
  'eligible_mothers<25',
  "source_kind='teacher_original'",
  'four_option_count<>2',
  'two_option_count<>3',
]) {
  if (!migration.includes(requiredFragment)) throw new Error(`Migration lacks QA contract: ${requiredFragment}`);
}

const report = {
  status: 'PASS',
  skills: expectedSkills.length,
  concepts: Object.keys(perConcept).length,
  questions: records.length,
  uniqueQuestionIds: ids.size,
  uniqueMotherIds: mothers.size,
  uniqueStems: stems.size,
  twoOptionQuestions: records.filter((record) => record.options.length === 2).length,
  fourOptionQuestions: records.filter((record) => record.options.length === 4).length,
  correctOptionDistribution: answerLetters,
  fourOptionCorrectDistribution: fourOptionAnswerLetters,
  metaPromptHits: 0,
  nearDuplicatePairs: nearDuplicatePairs.length,
  forbiddenNotationHits: 0,
  perSkill: Object.fromEntries(
    Object.entries(perSkill).map(([skillId, summary]) => [skillId, {
      questions: summary.questions,
      uniqueMothers: summary.mothers.size,
      concepts: summary.concepts.size,
      twoOption: summary.twoOption,
      fourOption: summary.fourOption,
      levels: summary.levels,
    }]),
  ),
};

console.log(JSON.stringify(report, null, 2));
