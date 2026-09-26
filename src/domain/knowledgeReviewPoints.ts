import type { KnowledgeCard, KnowledgeTreeNode } from './types'
import { isStructuredKnowledgeContent } from './knowledgeContent'

export type KnowledgeReviewPoint = {
  id: string
  cardId: string
  skillId: string
  section: string
  title: string
  rule: string
  examples: string[]
  caution?: string
}

type PointPart = Pick<KnowledgeReviewPoint, 'title' | 'rule'>

/** Older approved cards predate structured sections. These points are transcribed from their audited core/detail. */
const LEGACY_POINTS: Record<string, PointPart[]> = {
  KC_H1_MATERIAL_ATOM: [
    { title: '中性原子的质子数与电子数', rule: '中性原子中，质子数等于核外电子数。' },
    { title: '由质量数求中子数', rule: '质量数=质子数+中子数，因此中子数=质量数−质子数。' },
    { title: '氕的中子数', rule: '氕是氢的核素之一，核内没有中子。' },
    { title: '同位素怎样判断', rule: '质子数相同、中子数不同的原子互为同位素；离子不能另算一种同位素。' },
    { title: '原子模型的发展顺序', rule: '常见模型依次经历道尔顿、汤姆生、卢瑟福、玻尔等阶段。' },
  ],
  KC_H1_MATERIAL_DISPERSION: [
    { title: '溶液的分散质粒径', rule: '溶液的分散质粒径小于 1 nm。' },
    { title: '胶体的分散质粒径', rule: '胶体的分散质粒径约为 1～100 nm。' },
    { title: '浊液的分散质粒径', rule: '浊液的分散质粒径大于 100 nm。' },
    { title: '丁达尔效应的用途', rule: '可用丁达尔效应区分胶体和溶液。' },
    { title: '胶体粒子能通过什么', rule: '胶体粒子能透过滤纸，但一般不能透过半透膜。' },
  ],
  KC_H1_MATERIAL_EXPERIMENT: [
    { title: '过滤分离什么', rule: '过滤用于分离不溶性固体和液体。' },
    { title: '分液分离什么', rule: '分液用于分离互不相溶的液体。' },
    { title: '萃取剂怎样选择', rule: '萃取剂须与原溶剂不互溶，并能较好溶解目标物。' },
    { title: '蒸馏冷凝水怎样流', rule: '蒸馏时冷凝水下进上出。' },
    { title: '蒸馏温度计测哪里', rule: '温度计测的是馏出蒸气的温度。' },
    { title: '物质检验怎样排除干扰', rule: '物质检验要考虑干扰离子以及所加试剂可能引入的杂质。' },
  ],
  KC_H1_MATERIAL_SEAWATER: [
    { title: '粗盐中 Mg²⁺ 用什么除', rule: '加入 NaOH，使 Mg²⁺生成沉淀。' },
    { title: '粗盐中 SO₄²⁻ 用什么除', rule: '加入 BaCl₂，使 SO₄²⁻生成沉淀。' },
    { title: '粗盐中 Ca²⁺和过量 Ba²⁺ 用什么除', rule: '加入 Na₂CO₃，使 Ca²⁺和过量 Ba²⁺生成沉淀；Na₂CO₃应在 BaCl₂之后加入。' },
    { title: '粗盐提纯中盐酸何时加', rule: '过滤后加盐酸，除去过量 OH⁻和 CO₃²⁻。' },
    { title: '海水提溴先发生什么', rule: '先把 Br⁻氧化为 Br₂。' },
    { title: '海水提溴怎样富集', rule: '利用 Br₂的挥发性吹出，再吸收富集。' },
  ],
  KC_J_CHEM_LANG: [
    { title: '先分清宏观物质与微观粒子', rule: '看到化学符号，先说清它表示的是物质还是分子、原子等微粒。' },
    { title: '化学符号还要看数量', rule: '解释化学用语时，既要说清“是什么”，也要说清“有多少”。' },
    { title: '物理变化与化学变化的分界', rule: '判断变化过程中有没有生成新物质；冰融化没有新物质生成，属于物理变化。' },
  ],
  KC_J_EXPERIMENT: [
    { title: '实验先明确目的', rule: '判断操作是否合适前，先明确实验想得到什么结果。' },
    { title: '实验安全与气密性', rule: '操作前检查必要的安全条件和装置气密性。' },
    { title: '量筒怎样读数', rule: '读数时视线应与液体凹液面最低处相平。' },
    { title: '错误操作如何影响结果', rule: '先找操作改变了哪个测量量，再判断最终结果偏大还是偏小。' },
  ],
  'KC-J_KY_1_1_K01': [
    { title: '化学研究物质的组成', rule: '研究物质由什么组成，是化学研究的内容。' },
    { title: '化学研究物质的结构', rule: '研究物质内部怎样构成，是化学研究的内容。' },
    { title: '化学研究物质的性质', rule: '研究物质有什么性质，是化学研究的内容。' },
    { title: '化学研究物质的变化规律', rule: '研究物质会发生什么变化以及变化规律，是化学研究的内容。' },
  ],
  'KC-J_KY_1_1_K02': [
    { title: '化学与衣食住行', rule: '衣料、食物、药物和交通材料的研究与应用都与化学有关。' },
    { title: '化学与材料、能源', rule: '新材料的研制和能源的开发利用都涉及化学。' },
    { title: '化学与环境、资源', rule: '化学帮助人们保护环境、利用资源。' },
  ],
  'KC-J_KY_1_1_K03': [
    { title: '绿色化学从哪里减少污染', rule: '绿色化学强调从源头减少和消除污染，而不只是污染产生后再处理。' },
    { title: '绿色化学怎样提高原料利用', rule: '设计反应时尽量让原料转化为产品，减少废物。' },
    { title: '绿色化学怎样降低危害', rule: '尽量采用无毒无害原料，并开发环境友好产品。' },
  ],
  CARD_J_ATOM: [
    { title: '质子、电子、中子各带什么电', rule: '质子带正电，电子带负电，中子不带电。' },
    { title: '中性原子的质子数与电子数', rule: '中性原子的质子数等于核外电子数。' },
    { title: '由质量数求中子数', rule: '中子数=质量数−质子数。' },
  ],
  KC_J09_ATOM: [
    { title: '哪一个数决定元素种类', rule: '质子数决定元素种类。' },
    { title: '电子得失与离子电荷', rule: '原子得失电子后形成离子，电子得失决定离子所带的电荷。' },
    { title: '先判原子还是离子', rule: '比较质子数与电子数，再判断微粒是原子还是离子。' },
  ],
}

/** Split authored compound rules into separately assessable steps without changing their chemistry. */
function splitCompositeNode(card: KnowledgeCard, item: KnowledgeTreeNode): PointPart[] | null {
  if (['H1_MOLE_INTRO', 'H1_MOLE'].includes(card.skillId) && ['质量—物质的量', '质量桥m↔n'].includes(item.label)) {
    return [
      { title: '已知质量 m，求物质的量 n', rule: 'n=m/M。m 用 g，M 用 g·mol⁻¹，算得 n 的单位是 mol。' },
      { title: '已知物质的量 n，求质量 m', rule: 'm=nM。n 用 mol，M 用 g·mol⁻¹，算得 m 的单位是 g。' },
    ]
  }
  if (card.skillId === 'H1_MOLE' && item.label === '粒子桥N↔n') {
    return [
      { title: '已知物质的量 n，求微粒数 N', rule: 'N=nN_A。先写清数的是哪一种微粒，再按化学式下标处理倍数。' },
      { title: '已知微粒数 N，求物质的量 n', rule: 'n=N/N_A。N 与 n 必须指同一种微粒。' },
    ]
  }
  if (card.skillId === 'H1_MOLE' && item.label === '溶液桥c、V↔n') {
    return [
      { title: '已知浓度 c 和体积 V，求物质的量 n', rule: 'n=cV。V 是溶液体积，计算前换成 L。' },
      { title: '已知物质的量 n 和体积 V，求浓度 c', rule: 'c=n/V。V 是溶液体积，计算前换成 L。' },
    ]
  }
  if (card.skillId === 'H1_GAS_MOLAR_VOLUME' && item.label === 'V与n互换') {
    return [
      { title: '已知气体体积 V，求物质的量 n', rule: 'n=V/Vₘ。V 用 L，Vₘ 用 L·mol⁻¹；先核对气体所处温度和压强。' },
      { title: '已知物质的量 n，求气体体积 V', rule: 'V=nVₘ。n 用 mol，Vₘ 用 L·mol⁻¹；先核对气体所处温度和压强。' },
    ]
  }
  if (card.skillId === 'H1_SOLUTION_CONCENTRATION' && item.label === '物质的量浓度概念、溶液体积与离子浓度') {
    return [
      { title: '物质的量浓度的定义与单位', rule: 'c(B)=n(B)/V(溶液)，常用单位 mol·L⁻¹。' },
      { title: '浓度公式中的 V 指什么', rule: 'V 指最终溶液体积，不是水或溶剂的体积；代入公式前先换成 L。' },
      { title: '取出部分均一溶液，浓度变不变', rule: '均一溶液取出一部分时，所取部分的浓度与原溶液相同。' },
      { title: '由溶质浓度求离子浓度', rule: '强电解质的离子浓度按电离方程式的计量数换算，并检查电荷守恒。' },
    ]
  }
  if (card.skillId === 'H1_SOLUTION_CONCENTRATION' && item.label === '稀释、混合与体积边界') {
    return [
      { title: '无反应稀释时溶质的量', rule: '同一溶质只加水稀释且无损失时，溶质的量守恒：c₁V₁=c₂V₂。' },
      { title: '同一溶质混合后的浓度', rule: '先把各份溶质的物质的量相加，再除以混合后的总体积。' },
      { title: '不同溶液混合时先查什么', rule: '先判断溶质是否反应；若反应，先按方程式处理物质的量，不能直接套稀释公式。' },
    ]
  }
  if (card.skillId === 'H2_THERMO' && item.label === '核心关系') {
    return [
      { title: '反应前的初始温度 T₁ 怎样取', rule: '分别测量酸溶液和碱溶液的反应前温度，取二者平均值作为 T₁。' },
      { title: '反应后的温度 T₂ 怎样取', rule: '测量酸碱混合后的最高温度作为 T₂。' },
      { title: '温度差 ΔT 怎样算', rule: 'ΔT=T₂−T₁。先弄清 T₁、T₂，再代入。' },
      { title: '由温度差求热量 q', rule: '在题目给定的近似条件下，q=mcΔT。' },
      { title: '由热量换算摩尔反应热', rule: '按实际发生反应的物质的量，把本次测得的热量换算为每摩尔反应的热效应。' },
    ]
  }
  if (card.skillId === 'H3_STOICH' && item.label === '质量分数、密度和c的双向桥') {
    return [
      { title: '由质量分数和密度求浓度 c', rule: 'ρ 用 g·cm⁻³、w 用小数、M 用 g·mol⁻¹时，c=1000ρw/M；先以 1 L 溶液计算。' },
      { title: '由浓度 c 反求质量分数 w', rule: 'w=cM/(1000ρ)。分母用的是溶液质量，不是溶剂质量。' },
    ]
  }
  if (card.skillId === 'H3_STOICH' && item.label === 'c与溶液体积') {
    return [
      { title: '由浓度与溶液体积求物质的量', rule: 'n=cV。V 用 L，且指溶液的总体积。' },
      { title: '无反应稀释时守恒什么', rule: '稀释且无反应、无损失时，溶质的物质的量 n 守恒。' },
    ]
  }
  return null
}

export function getKnowledgeReviewPoints(card: KnowledgeCard): KnowledgeReviewPoint[] {
  if (!isStructuredKnowledgeContent(card.structuredContent) || !card.structuredContent.sections.length) {
    const legacy = LEGACY_POINTS[card.id]
    if (legacy) return legacy.map((point, index) => ({ id: `${card.id}:s0:i${index}:p0`, cardId: card.id,
      skillId: card.skillId, section: card.title, title: point.title, rule: point.rule, examples: [] }))
    return [{ id: `${card.id}:core`, cardId: card.id, skillId: card.skillId, section: card.title,
      title: card.title, rule: card.core, examples: card.microExample ? [card.microExample] : [] }]
  }
  return card.structuredContent.sections.flatMap((section, sectionIndex) => section.items.flatMap((item, itemIndex) => {
    const parts = splitCompositeNode(card, item) ?? [{ title: item.label, rule: item.rule }]
    return parts.map((part, partIndex) => ({
      id: `${card.id}:s${sectionIndex}:i${itemIndex}:p${partIndex}`,
      cardId: card.id,
      skillId: card.skillId,
      section: section.title,
      title: part.title,
      rule: part.rule,
      examples: item.examples ?? [],
      caution: item.caution,
    }))
  }))
}
