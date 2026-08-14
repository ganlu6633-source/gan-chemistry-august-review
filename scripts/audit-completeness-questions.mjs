import { completenessQuestions } from './completeness-question-bank.mjs'

const errors = []
const expectedCounts = {
  H1_PERIODIC: 16,
  H1_NACL: 6,
  H2_EQUIL: 6,
  H2_ELECTRO: 5,
  H3_INORGANIC: 7,
  H3_THERMO_RATE: 4,
  H3_ELECTRO: 5,
  H3_EXPERIMENT: 7,
  H3_STRUCTURE: 8,
  H3_ORGANIC: 12,
  H1_REDOX: 2,
  H1_ELECTROLYTE: 1,
  H1_MOLE: 1,
  H3_STOICH: 1,
  H2_RATE: 1,
  H2_PH_HYDRO: 2,
  H3_AQ: 1,
  H3_EQUILIBRIUM: 2,
}

const ids = new Set()
const motherIds = new Set()
const counts = {}
const answerPositions = [0, 0, 0, 0]

for (const question of completenessQuestions) {
  if (ids.has(question.id)) errors.push(`${question.id}：题目ID重复`)
  if (motherIds.has(question.motherId)) errors.push(`${question.id}：母题ID重复`)
  ids.add(question.id)
  motherIds.add(question.motherId)
  counts[question.skillId] = (counts[question.skillId] ?? 0) + 1

  if (question.reviewStatus !== 'approved' || question.scopeStatus !== 'IN' || question.sourceKind !== 'teacher_original') {
    errors.push(`${question.id}：审核、范围或来源状态不合格`)
  }
  if (!Array.isArray(question.options) || question.options.length !== 4 || new Set(question.options).size !== 4 || question.options.some((option) => !option.trim())) {
    errors.push(`${question.id}：必须有4个互不相同的非空选项`)
  }
  if (!Number.isInteger(question.correctOption) || question.correctOption < 0 || question.correctOption > 3) {
    errors.push(`${question.id}：正确选项索引越界`)
  } else answerPositions[question.correctOption] += 1
  if (question.stem.trim().length < 12 || question.explanation.trim().length < 32 || question.scaffold.trim().length < 18) {
    errors.push(`${question.id}：题干、解析或支架过短`)
  }
}

if (completenessQuestions.length !== 87) errors.push(`补充题总数应为87，实际为${completenessQuestions.length}`)
for (const [skillId, expected] of Object.entries(expectedCounts)) {
  if (counts[skillId] !== expected) errors.push(`${skillId}：应有${expected}题，实际${counts[skillId] ?? 0}题`)
}
for (const skillId of Object.keys(counts)) {
  if (!(skillId in expectedCounts)) errors.push(`${skillId}：出现未审计的题目模块`)
}

const allQuestionText = completenessQuestions.map((question) => `${question.stem}\n${question.options.join('\n')}\n${question.explanation}\n${question.scaffold}`).join('\n')
const requiredCoverage = [
  ['最高价氧化物对应水化物', '周期律最高价含氧体系'],
  ['气态氢化物的热稳定性', '周期律氢化物稳定性'],
  ['水溶液酸性', '稳定性、酸性、还原性边界'],
  ['透过蓝色钴玻璃', '焰色试验'],
  ['冷的稀NaOH', '氯气歧化条件'],
  ['焓变、熵变', '反应方向定性'],
  ['热力学上有方向不等于动力学上速率快', '自发与速率边界'],
  ['适量CuO', '电解液复原'],
  ['吸氧腐蚀', '钢铁腐蚀双路径'],
  ['白色Fe(OH)₂', '氢氧化亚铁时间链'],
  ['可逆漂白', '二氧化硫漂白边界'],
  ['2NO+O₂=2NO₂', '氮氧化物主线'],
  ['蒸馏', '蒸馏分离操作'],
  ['萃取剂', '萃取分液操作'],
  ['电子吸收能量可由低能级跃迁到高能级', '激发与发射光谱'],
  ['第一电离能存在局部例外', '电离能局部例外'],
  ['水分子之间能形成较强的氢键', '分子间氢键'],
  ['X射线衍射可研究晶体结构', '结构测定证据'],
  ['质谱估计相对分子质量', '有机三谱证据'],
  ['存在顺反异构', '顺反异构识别'],
  ['含有连接四种不同原子或原子团的手性碳原子', '手性碳识别'],
  ['苯与液溴在FeBr₃催化', '芳香烃取代'],
  ['乙酸乙酯在NaOH水溶液中加热', '酯碱性水解'],
  ['生物大分子', '生命有机物'],
  ['歧化反应', '歧化'],
  ['归中反应', '归中'],
  ['排除CO₃²⁻对AgNO₃检验的干扰', '离子检验干扰'],
  ['质量分数为36.5%', '质量分数密度浓度换算'],
  ['诱导期', '反应速率诱导期'],
  ['甲基橙作指示剂', '滴定指示剂误差'],
  ['分布随pH变化', '酸碱分布曲线'],
  ['均瞬间增大为原来的2倍', '平衡浓度图像'],
  ['v正和v逆同时', '平衡速率图像'],
]
for (const [needle, label] of requiredCoverage) {
  if (!allQuestionText.includes(needle)) errors.push(`${label}：题库缺少覆盖证据“${needle}”`)
}

for (const forbidden of ['ΔG=', 'RTlnK', '能斯特方程', 'Henderson', 'R/S构型', '分子轨道', '群论', '反应级数']) {
  if (allQuestionText.includes(forbidden)) errors.push(`福建高中范围边界：出现禁用内容“${forbidden}”`)
}

const expectedCorrectText = {
  QCOMP_H3_THERMO_RATE_03: '0.20 mol·L⁻¹·min⁻¹',
  QCOMP_H2_ELECTRO_05: '适量CuO',
  QCOMP_H3_EXPERIMENT_05: '蒸馏；水银球上端与蒸馏烧瓶支管口下沿相平',
  QCOMP_H2_PH_HYDRO_02: '偏低',
  QCOMP_H3_AQ_01: 'HA⁻',
}
for (const [id, correctText] of Object.entries(expectedCorrectText)) {
  const question = completenessQuestions.find((entry) => entry.id === id)
  if (!question || question.options[question.correctOption] !== correctText) errors.push(`${id}：高风险题正确答案未锁定为“${correctText}”`)
}

const answerSpread = Math.max(...answerPositions) - Math.min(...answerPositions)
if (answerSpread > 5) errors.push(`正确答案位置分布失衡：A/B/C/D=${answerPositions.join('/')}`)

if (errors.length) {
  console.error(`补充题库校验失败（${errors.length}项）\n- ${errors.join('\n- ')}`)
  process.exit(1)
}

console.log(JSON.stringify({
  status: 'PASS',
  questions: completenessQuestions.length,
  coveredSkills: Object.keys(counts).length,
  answerPositions,
  uniqueIds: ids.size,
  uniqueMotherIds: motherIds.size,
  scopeViolations: 0,
}, null, 2))
