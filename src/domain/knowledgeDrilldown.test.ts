import { describe, expect, it } from 'vitest'
import type { KnowledgeCard, StructuredKnowledgeContent } from './types'
import { buildKnowledgeCardDrilldown, knowledgeSectionTree, knowledgeTreeFromStructuredContent } from './knowledgeDrilldown'
// @ts-expect-error The authored content generator is an ESM JavaScript module without declarations.
import { zeroForgettingCards } from '../../scripts/zero-forgetting-content.mjs'

const content: StructuredKnowledgeContent = {
  version: 2,
  intro: '先看反应条件，再作判断。',
  visualSummary: { kind: 'tree', title: '只作图解的标签', tree: { label: '没有规则的标签' } },
  sections: [
    { title: '第一关', summary: '先问是否发生反应。', items: [
      { label: '反应条件', rule: '核对题给条件。', examples: ['CuO不能直接与水反应生成Cu(OH)₂。'],
        caution: '不能只看箭头。', children: [{ label: '温度', rule: '看题给温度。', examples: ['加热条件要写明。'] }] },
    ] },
    { title: '第二关', items: [{ label: '反应类型', rule: '按反应物与生成物判断。' }] },
  ],
  workedExamples: [{ substance: 'CaO→Ca(OH)₂', path: 'CaO与水反应。', labels: ['化合'] }],
}

const legacyCard: KnowledgeCard = {
  id: 'KC_J09_ATOM', skillId: 'J09_ATOM', title: '原子结构与元素',
  core: '质子数决定元素种类。', detail: '比较质子数和电子数。', steps: [],
  commonMistakes: [], microExample: 'Na失电子形成Na⁺。', reviewStatus: 'approved',
}

describe('knowledge drill-down data', () => {
  it('builds a clickable section and item hierarchy from authored text only', () => {
    const tree = knowledgeSectionTree(content, '反应分类')
    expect(tree.label).toBe('反应分类')
    expect(tree.rule).toBe(content.intro)
    expect(tree.children?.map((node) => node.label)).toEqual(['第一关', '第二关'])
    expect(tree.children?.[0].rule).toBe('先问是否发生反应。')
    expect(tree.children?.[1].rule).toBe(content.intro)
    expect(tree.children?.[0].children?.[0]).toEqual(content.sections[0].items[0])
    expect(tree.children?.[0].children?.[0].children?.[0].examples).toEqual(['加热条件要写明。'])
    expect(tree.children?.[0].children?.[0].caution).toBe('不能只看箭头。')
    expect(tree.examples).toEqual(['CaO→Ca(OH)₂：CaO与水反应。'])
    expect(JSON.stringify(tree)).not.toContain('没有规则的标签')
  })

  it('keeps an authored root tree as the main tree without duplicating its sections', () => {
    const rootTree = { label: '物质', rule: '判断物质种类。', children: [{ label: '纯净物', rule: '只含一种物质。' }] }
    const withRoot = { ...content, rootTree }
    expect(knowledgeTreeFromStructuredContent(withRoot)).toBe(rootTree)
    expect(knowledgeSectionTree(withRoot).children?.map((node) => node.label)).toEqual(['第一关', '第二关'])
  })

  it('uses sections as the main tree when no authored root tree exists', () => {
    const card: KnowledgeCard = { ...legacyCard, structuredContent: content, title: '反应分类' }
    const tree = buildKnowledgeCardDrilldown(card)
    expect(tree.label).toBe('反应分类')
    expect(tree.children?.map((node) => node.label)).toEqual(['第一关', '第二关'])
    expect(tree.children?.[0].children?.[0].examples).toEqual(['CuO不能直接与水反应生成Cu(OH)₂。'])
  })

  it('adds only reviewed composite micro-splits and keeps broad examples on their parent', () => {
    const moleContent: StructuredKnowledgeContent = { version: 2, intro: '先认清换算方向。', sections: [
      { title: '质量与物质的量', items: [{ label: '质量—物质的量', rule: 'n=m/M，m=nM。',
        examples: ['已知质量与摩尔质量时先确定要求哪个量。'] }] },
    ] }
    const moleCard: KnowledgeCard = { ...legacyCard, id: 'mole-card', title: '物质的量换算',
      skillId: 'H1_MOLE_INTRO', structuredContent: moleContent }
    const tree = buildKnowledgeCardDrilldown(moleCard)
    const parent = tree.children?.[0].children?.[0]
    expect(parent?.children?.map((node) => node.label)).toEqual([
      '已知质量 m，求物质的量 n', '已知物质的量 n，求质量 m',
    ])
    expect(parent?.children?.[0].rule).toContain('n=m/M')
    expect(parent?.children?.[1].rule).toContain('m=nM')
    expect(parent?.examples).toEqual(['已知质量与摩尔质量时先确定要求哪个量。'])
    expect(parent?.children?.[0].examples).toBeUndefined()
    expect(parent?.children?.[1].examples).toBeUndefined()
  })

  it('attaches exact examples only to the matching published hierarchy', () => {
    const source = (zeroForgettingCards as Array<StructuredKnowledgeContent & { skillId: string }>)
      .find((item) => item.skillId === 'H1_MOLE_INTRO')!
    const card: KnowledgeCard = { ...legacyCard, id: 'KC_H1_MOLE_INTRO', skillId: 'H1_MOLE_INTRO',
      structuredContent: source }
    const tree = buildKnowledgeCardDrilldown(card)
    const parent = tree.children?.[2].children?.[2]
    expect(parent?.children?.[0].examples?.[0]).toContain('36 g H₂O')
    expect(parent?.children?.[1].examples?.[0]).toContain('2 mol H₂O')
    const revised = structuredClone(source)
    revised.sections[2].items[2].label += '（新版）'
    const revisedTree = buildKnowledgeCardDrilldown({ ...card, structuredContent: revised })
    expect(revisedTree.children?.[2].children?.[2].children?.[0].examples).toBeUndefined()
  })

  it('shows a repeated section demo on its parent while retaining each leaf’s own illustration', () => {
    const demo = '【示范：反应热综合】先明确体系，再区分能量差。'
    const source: StructuredKnowledgeContent = { version: 2, intro: '反应热', sections: [{ title: '旧缓存小节', items: [
      { label: '体系', rule: '明确研究对象。', examples: ['燃烧的H₂、O₂和生成的水构成体系。', demo] },
      { label: '环境', rule: '体系以外的部分。', examples: ['周围吸收热量的水是环境。', demo] },
    ] }] }
    const card: KnowledgeCard = { ...legacyCard, id: 'KC_H2_THERMO', skillId: 'H2_THERMO', structuredContent: source }
    const section = knowledgeSectionTree(source, '反应热', card).children?.[0]
    const shared = section?.examples?.[0]
    expect(shared).toMatch(/^【示范：/)
    expect(section?.children?.every((leaf) => leaf.examples?.length && !leaf.examples.includes(shared!))).toBe(true)
  })

  it('uses audited fine points for older cards without copying a generic example onto every leaf', () => {
    const tree = buildKnowledgeCardDrilldown(legacyCard)
    expect(tree.label).toBe('原子结构与元素')
    expect(tree.children?.map((node) => node.label)).toEqual(['哪一个数决定元素种类', '电子得失与离子电荷', '先判原子还是离子'])
    expect(tree.examples).toEqual(['Na失电子形成Na⁺。'])
    expect(tree.children?.map((node) => node.examples?.length)).toEqual([1, 1, 1])
    expect(tree.children?.[0].examples?.[0]).toContain('Na原子与Na⁺')
  })

  it('leaves an unsplit card as one honest endpoint with its own example', () => {
    const tree = buildKnowledgeCardDrilldown({ ...legacyCard, id: 'unmapped', title: '只确定一个知识点' })
    expect(tree.children).toBeUndefined()
    expect(tree.rule).toBe(legacyCard.core)
    expect(tree.examples).toEqual([legacyCard.microExample])
  })
})
