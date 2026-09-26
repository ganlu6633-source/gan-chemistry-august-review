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
