import { zeroForgettingCards } from './zero-forgetting-content.mjs'
import { getP1KnowledgeCompletenessPatch } from './knowledge-completeness-p1-patches.mjs'

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

const requiredContent = [
  ['Na₂O→MgO→Al₂O₃→SiO₂→P₄O₁₀→SO₃→Cl₂O₇', '第三周期最高价氧化物'],
  ['NaOH→Mg(OH)₂→Al(OH)₃→H₂SiO₃→H₃PO₄→H₂SO₄→HClO₄', '第三周期对应水化物'],
  ['SiH₄＜PH₃＜H₂S＜HCl', '同周期气态氢化物热稳定性'],
  ['HF＞HCl＞HBr＞HI', '同主族气态氢化物热稳定性'],
  ['热稳定性≠水溶液酸性≠还原性', '气态氢化物三指标边界'],
  ['7个周期、18个纵列和16个族', '周期表基本结构'],
  ['透过蓝色钴玻璃', '钾的焰色试验'],
  ['3Cl₂+6OH⁻=5Cl⁻+ClO₃⁻+3H₂O', '氯气与热浓碱'],
  ['ClO⁻+Cl⁻+2H⁺=Cl₂↑+H₂O', '含氯消毒剂混用风险'],
  ['反应方向：焓变与熵变共同影响', '反应方向定性'],
  ['CuO+2H⁺=Cu²⁺+H₂O', 'CuSO₄电解液复原'],
  ['Al(OH)₃+OH⁻=[Al(OH)₄]⁻', '氢氧化铝两性'],
  ['4Fe(OH)₂+O₂+2H₂O=4Fe(OH)₃', '氢氧化亚铁氧化时间链'],
  ['SO₂使品红褪色', '二氧化硫漂白边界'],
  ['2NO+O₂=2NO₂', '一氧化氮转二氧化氮'],
  ['蒸馏、分馏、萃取和分液', '四种分离操作'],
  ['电子云表示电子在核外空间出现概率密度', '电子云模型'],
  ['Mg的3s²全充满', '第一电离能局部例外'],
  ['分子间与分子内氢键', '氢键位置边界'],
  ['X射线衍射', '晶体结构测定证据'],
  ['质谱、红外和氢谱', '有机三谱证据链'],
  ['顺反异构的条件', '顺反异构识别'],
  ['苯与液溴在FeBr₃', '芳香烃取代条件'],
  ['1 mol甘油三酯完全皂化通常消耗3 mol OH⁻', '油脂皂化计量'],
  ['歧化、归中与缺项配平', '氧化还原P1补充'],
  ['c=1000ρw/M', '质量分数密度浓度换算'],
  ['自催化与诱导期', '反应速率图像'],
  ['滴定操作链从查漏到平行测定', '酸碱滴定完整操作'],
  ['分布曲线从零读图', '水溶液分布曲线'],
  ['真实c—t与v—t图像', '化学平衡真实图像'],
]
requiredContent.forEach(([text, label]) => requireText(text, label))

const classificationP1Patch = getP1KnowledgeCompletenessPatch('H1_CLASSIFY')
if (!classificationP1Patch?.sections?.some((section) => section.title === '四类基本反应与横向分类' && section.items.length >= 4)) {
  errors.push('H1_CLASSIFY：缺少四类基本反应与氧化还原交叉分类补丁')
}

forbidText('左右总电荷均+24', '离子方程式电荷')
forbidText('温度和催化剂通常同时改变正逆速率，但程度可能不同', '催化剂与平衡')
forbidText('正负/阴阳角色可能随过程改变', '充放电电极命名')
forbidText('如卤代、酯化/水解', '有机反应类型')
forbidText('若配成500 mL溶液且不反应', '物质的量浓度示范')
for (const forbidden of ['ΔG=', 'ΔG =', 'RTlnK', 'RT ln K', '能斯特方程', 'Henderson', 'R/S构型', '分子轨道', '群论', '反应级数']) {
  forbidText(forbidden, '福建高中范围边界')
}

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

verifyReaction('氯气与冷稀碱', [
  { coefficient: 1, atoms: { Cl: 2 } },
  { coefficient: 2, atoms: { O: 1, H: 1 } },
], [
  { coefficient: 1, atoms: { Cl: 1 } },
  { coefficient: 1, atoms: { Cl: 1, O: 1 } },
  { coefficient: 1, atoms: { H: 2, O: 1 } },
], -2, -2)

verifyReaction('氢氧化亚铁吸氧', [
  { coefficient: 4, atoms: { Fe: 1, O: 2, H: 2 } },
  { coefficient: 1, atoms: { O: 2 } },
  { coefficient: 2, atoms: { H: 2, O: 1 } },
], [
  { coefficient: 4, atoms: { Fe: 1, O: 3, H: 3 } },
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
if (pointCount !== 578 || pointWithExampleCount !== pointCount || pointWithVisualCount !== pointCount) {
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
  balancedEquationChecks: 5,
  electronBookkeepingChecks: 1,
  knownMisstatementHits: 0,
}, null, 2))
