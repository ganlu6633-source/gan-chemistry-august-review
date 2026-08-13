import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'
import { zeroForgettingCards } from './zero-forgetting-content.mjs'
import { classificationVisualSummary } from './knowledge-visual-summaries.mjs'

const scriptDir = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(scriptDir, '..')
const expected = [
  'H1_ELECTROLYTE_INTRO', 'H1_PERIODIC', 'H1_REDOX', 'H1_ELECTROLYTE', 'H1_MOLE', 'H1_MOLE_INTRO', 'H1_NACL',
  'H2_THERMO', 'H2_RATE', 'H2_EQUIL', 'H2_K', 'H2_WEAK', 'H2_PH_HYDRO', 'H2_KSP', 'H2_ELECTRO',
  'H3_STOICH', 'H3_ION_REDOX', 'H3_INORGANIC', 'H3_THERMO_RATE', 'H3_EQUILIBRIUM', 'H3_AQ', 'H3_ELECTRO', 'H3_EXPERIMENT', 'H3_PROCESS', 'H3_STRUCTURE', 'H3_ORGANIC',
]

const errors = []
let sectionCount = 0
let knowledgePointCount = 0
let inlineExampleCount = 0
let visualAidCount = 0
let quickVisualCount = 0
const ids = zeroForgettingCards.map((entry) => entry.skillId)
const missing = expected.filter((id) => !ids.includes(id))
const unexpected = ids.filter((id) => !expected.includes(id))
const duplicates = ids.filter((id, index) => ids.indexOf(id) !== index)
if (missing.length) errors.push(`缺少模块：${missing.join(', ')}`)
if (unexpected.length) errors.push(`出现计划外模块：${unexpected.join(', ')}`)
if (duplicates.length) errors.push(`模块重复：${[...new Set(duplicates)].join(', ')}`)
if (classificationVisualSummary.kind !== 'tree' || !classificationVisualSummary.tree || (classificationVisualSummary.axes?.length ?? 0) < 4) errors.push('H1_CLASSIFY: 物质分类总树或横向分类轴不完整')

for (const entry of zeroForgettingCards) {
  if (entry.version !== 2) errors.push(`${entry.skillId}: version 必须为 2`)
  if (entry.intro.length < 45) errors.push(`${entry.skillId}: intro 过短`)
  if (entry.overview.length < 4) errors.push(`${entry.skillId}: overview 少于 4 条`)
  if (!entry.visualSummary?.kind || !entry.visualSummary?.title) errors.push(`${entry.skillId}: 缺少30秒关系图`)
  else {
    quickVisualCount += 1
    const visual = entry.visualSummary
    if ((visual.kind === 'flow' || visual.kind === 'cycle') && (visual.steps?.length ?? 0) < 4) errors.push(`${entry.skillId}: 流程图节点不足`)
    if ((visual.kind === 'compare' || visual.kind === 'network' || visual.kind === 'balance') && (visual.groups?.length ?? 0) < 2) errors.push(`${entry.skillId}: 关系图分组不足`)
    if (visual.kind === 'tree' && !visual.tree) errors.push(`${entry.skillId}: 树状图缺少根节点`)
  }
  if (entry.sections.length < 4) errors.push(`${entry.skillId}: sections 少于 4 节`)
  if (entry.workedExamples.length < 2) errors.push(`${entry.skillId}: 完整例题少于 2 个`)
  if (entry.checkpoints.length < 4) errors.push(`${entry.skillId}: 自查点少于 4 个`)
  entry.sections.forEach((section, sectionIndex) => {
    sectionCount += 1
    if (!section.title || !section.summary) errors.push(`${entry.skillId}: 第 ${sectionIndex + 1} 节标题或摘要为空`)
    if (section.items.length < 3) errors.push(`${entry.skillId}: ${section.title} 少于 3 个讲解节点`)
    section.items.forEach((node, itemIndex) => {
      knowledgePointCount += 1
      inlineExampleCount += node.examples?.length ?? 0
      if (node.visualSteps?.length) visualAidCount += 1
      if (!node.label || !node.rule || node.rule.length < 18) errors.push(`${entry.skillId}: ${section.title} 第 ${itemIndex + 1} 项内容过短`)
      if (!node.examples?.length) errors.push(`${entry.skillId}: ${section.title}/${node.label} 缺少就地示范`)
      if (!node.examples?.some((example) => example.startsWith('【示范：'))) errors.push(`${entry.skillId}: ${section.title}/${node.label} 缺少经过小节校准的完整示范`)
      if (!node.visualSteps?.length || node.visualSteps.length < 2) errors.push(`${entry.skillId}: ${section.title}/${node.label} 缺少图像记忆步骤`)
    })
  })
}

function parseCsvLine(line) {
  const values = []
  let value = ''
  let quoted = false
  for (let i = 0; i < line.length; i += 1) {
    const char = line[i]
    if (char === '"') {
      if (quoted && line[i + 1] === '"') { value += '"'; i += 1 } else quoted = !quoted
    } else if (char === ',' && !quoted) {
      values.push(value); value = ''
    } else value += char
  }
  values.push(value)
  return values
}

const scopePath = resolve(repoRoot, '..', 'g_fujian_filter', 'out_of_scope_patterns.csv')
const patternLines = readFileSync(scopePath, 'utf8').replace(/^\uFEFF/, '').split(/\r?\n/).filter(Boolean).slice(1)
const publicContent = JSON.stringify(zeroForgettingCards)
for (const line of patternLines) {
  const [patternId, category, trigger] = parseCsvLine(line)
  if (!trigger) continue
  let expression
  try { expression = new RegExp(trigger, 'iu') } catch (error) { errors.push(`${patternId}: 范围正则无法编译 (${error.message})`); continue }
  const match = publicContent.match(expression)
  if (match) errors.push(`${patternId}/${category}: 学生内容命中超纲召回词“${match[0]}”`)
}

if (errors.length) {
  console.error(`零遗忘知识卡校验失败（${errors.length} 项）\n- ${errors.join('\n- ')}`)
  process.exit(1)
}

const summary = zeroForgettingCards.reduce((acc, entry) => {
  const grade = entry.skillId.slice(0, 2)
  acc[grade] = (acc[grade] ?? 0) + 1
  return acc
}, {})
console.log(JSON.stringify({
  status: 'PASS',
  cards: zeroForgettingCards.length,
  grades: summary,
  sections: sectionCount,
  knowledgePoints: knowledgePointCount,
  inlineExamples: inlineExampleCount,
  visualAids: visualAidCount,
  quickVisuals: quickVisualCount + 1,
  scopePatternHits: 0,
}, null, 2))
