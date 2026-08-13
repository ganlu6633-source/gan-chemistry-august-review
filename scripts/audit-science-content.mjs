import { zeroForgettingCards } from './zero-forgetting-content.mjs'

const errors = []
const strings = []
const visit = (value) => {
  if (typeof value === 'string') strings.push(value)
  else if (Array.isArray(value)) value.forEach(visit)
  else if (value && typeof value === 'object') Object.values(value).forEach(visit)
}
visit(zeroForgettingCards)
const allText = strings.join('\n')

const requireText = (text, label) => {
  if (!allText.includes(text)) errors.push(`${label}：缺少已复核的关键表述“${text}”`)
}
const forbidText = (text, label) => {
  if (allText.includes(text)) errors.push(`${label}：仍含错误或易误导表述“${text}”`)
}

requireText('4FeS₂+15O₂+2H₂O=4Fe³⁺+8SO₄²⁻+4H⁺', 'FeS₂酸性氧化方程式')
requireText('MnO₄⁻+5Fe²⁺+8H⁺=Mn²⁺+5Fe³⁺+4H₂O', '酸性高锰酸根氧化Fe²⁺')
requireText('左右总电荷均+17', '高锰酸根方程式电荷复核')
requireText('2Na+2H₂O=2NaOH+H₂↑', '钠与水')
requireText('2NaHCO₃→Na₂CO₃+CO₂↑+H₂O', '碳酸氢钠热分解')
requireText('Cl₂+H₂O⇌HCl+HClO', '氯气与水')
requireText('H₂+2OH⁻−2e⁻=2H₂O', '碱性氢氧燃料电池阳极')
requireText('O₂+2H₂O+4e⁻=4OH⁻', '碱性氢氧燃料电池阴极')

forbidText('左右总电荷均+24', '离子方程式电荷')
forbidText('温度和催化剂通常同时改变正逆速率，但程度可能不同', '催化剂与平衡')
forbidText('正负/阴阳角色可能随过程改变', '充放电电极命名')
forbidText('如卤代、酯化/水解', '有机反应类型')
forbidText('若配成500 mL溶液且不反应', '物质的量浓度示范')

const sumAtoms = (species) => species.reduce((totals, current) => {
  for (const [element, count] of Object.entries(current.atoms)) totals[element] = (totals[element] ?? 0) + current.coefficient * count
  return totals
}, {})
const verifyReaction = (label, reactants, products, reactantCharge = 0, productCharge = 0) => {
  const left = sumAtoms(reactants)
  const right = sumAtoms(products)
  if (JSON.stringify(left, Object.keys(left).sort()) !== JSON.stringify(right, Object.keys(right).sort())) {
    errors.push(`${label}：原子不守恒 ${JSON.stringify(left)} != ${JSON.stringify(right)}`)
  }
  if (reactantCharge !== productCharge) errors.push(`${label}：电荷不守恒 ${reactantCharge} != ${productCharge}`)
}

verifyReaction('FeS₂酸性氧化', [
  { coefficient: 4, atoms: { Fe: 1, S: 2 } },
  { coefficient: 15, atoms: { O: 2 } },
  { coefficient: 2, atoms: { H: 2, O: 1 } },
], [
  { coefficient: 4, atoms: { Fe: 1 } },
  { coefficient: 8, atoms: { S: 1, O: 4 } },
  { coefficient: 4, atoms: { H: 1 } },
], 0, 4 * 3 + 8 * -2 + 4)

verifyReaction('MnO₄⁻氧化Fe²⁺', [
  { coefficient: 1, atoms: { Mn: 1, O: 4 } },
  { coefficient: 5, atoms: { Fe: 1 } },
  { coefficient: 8, atoms: { H: 1 } },
], [
  { coefficient: 1, atoms: { Mn: 1 } },
  { coefficient: 5, atoms: { Fe: 1 } },
  { coefficient: 4, atoms: { H: 2, O: 1 } },
], -1 + 5 * 2 + 8, 2 + 5 * 3)

verifyReaction('钠与水', [
  { coefficient: 2, atoms: { Na: 1 } },
  { coefficient: 2, atoms: { H: 2, O: 1 } },
], [
  { coefficient: 2, atoms: { Na: 1, O: 1, H: 1 } },
  { coefficient: 1, atoms: { H: 2 } },
])

const redoxElectronLoss = (3 - 2) * 1 + (6 - (-1)) * 2
const oxygenElectronGain = (0 - (-2)) * 2
if (redoxElectronLoss !== 15 || oxygenElectronGain !== 4 || 4 * redoxElectronLoss !== 15 * oxygenElectronGain) {
  errors.push('FeS₂电子账：应为每个FeS₂失15e⁻、每个O₂得4e⁻、总量60e⁻')
}

let pointCount = 0
let pointWithExampleCount = 0
let pointWithVisualCount = 0
for (const card of zeroForgettingCards) {
  for (const section of card.sections) {
    for (const point of section.items) {
      pointCount += 1
      if (point.examples?.some((example) => example.startsWith('【示范：'))) pointWithExampleCount += 1
      if (point.visualSteps?.length >= 2) pointWithVisualCount += 1
    }
  }
}
if (pointCount !== 455 || pointWithExampleCount !== pointCount || pointWithVisualCount !== pointCount) {
  errors.push(`知识节点覆盖不闭环：总数${pointCount}，完整示范${pointWithExampleCount}，图像流程${pointWithVisualCount}`)
}

if (errors.length) {
  console.error(`化学科学性校验失败（${errors.length}项）\n- ${errors.join('\n- ')}`)
  process.exit(1)
}

console.log(JSON.stringify({
  status: 'PASS',
  auditedCards: zeroForgettingCards.length,
  auditedKnowledgePoints: pointCount,
  balancedEquationChecks: 3,
  electronBookkeepingChecks: 1,
  knownMisstatementHits: 0,
}, null, 2))
