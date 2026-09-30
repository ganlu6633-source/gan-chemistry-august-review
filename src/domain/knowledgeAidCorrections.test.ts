import { describe, expect, it } from 'vitest'
import type { StructuredKnowledgeContent } from './types'
// @ts-expect-error Authored JavaScript content generator has no declarations.
import { zeroForgettingCards } from '../../scripts/zero-forgetting-content.mjs'
// @ts-expect-error Data-only correction overlay has no declarations.
import { applyReviewedKnowledgeNodeAids, reviewedNodeAidCorrections } from '../../scripts/knowledge-node-aid-corrections.mjs'

const cards = zeroForgettingCards as Array<StructuredKnowledgeContent & { skillId: string }>
const card = (id: string) => cards.find((entry) => entry.skillId === id)!

describe('reviewed knowledge aid generation', () => {
  it('keeps the reviewed equation aid on the verified C61 card without accepting unrelated card identities', () => {
    const patch = reviewedNodeAidCorrections.find((entry: { cardId: string; rootTreePath?: number[] }) => entry.cardId === 'KC_J_KY_EQUATIONS' && !entry.rootTreePath)
    const source = {
      version: 1, intro: '',
      sections: Array.from({ length: patch.sectionIndex + 1 }, (_, index) => ({
        title: index === patch.sectionIndex ? patch.sectionTitle : '其他章节',
        items: Array.from({ length: patch.itemIndex + 1 }, (_, itemIndex) => ({
          label: itemIndex === patch.itemIndex ? patch.expectedLabel : '其他节点',
          rule: itemIndex === patch.itemIndex ? patch.expectedRule : '其他规则',
          examples: ['原来的例子。'],
        })),
      })),
    }
    const revised = applyReviewedKnowledgeNodeAids(source, patch.skillId, 'KC_J_KY_EQUATIONS_C61')
    expect(revised.sections[patch.sectionIndex].items[patch.itemIndex].examples).toEqual(patch.examples)
    expect(applyReviewedKnowledgeNodeAids(source, patch.skillId, 'UNRELATED_CARD')).toEqual(source)
  })

  it('explains each process operation without borrowing the next operation', () => {
    const items = card('H3_PROCESS').sections.flatMap((section) => section.items)
    const grind = items.find((item) => item.label === '粉碎/研磨')!
    const roast = items.find((item) => item.label === '焙烧/煅烧')!
    const leach = items.find((item) => item.label === '酸浸/碱浸/水浸')!
    expect(grind.examples?.join('')).toContain('接触面积')
    expect(grind.visualSteps?.join('')).not.toMatch(/焙烧|浸取剂/)
    expect(roast.visualSteps?.join('')).toContain('气氛')
    expect(roast.visualSteps?.join('')).not.toContain('浸取剂')
    expect(leach.examples?.join('')).toContain('Al₂O₃')
    expect(leach.visualSteps?.join('')).not.toContain('焙烧')
    expect(new Set(items.map((item) => JSON.stringify(item.visualSteps))).size).toBe(items.length)
  })

  it('retains the scientific conditions that the old shared examples omitted', () => {
    const rate = card('H2_RATE')
    expect(rate.sections[1].items[1].rule).toContain('同一反应')
    expect(rate.sections[1].items[1].examples?.join('')).toContain('N₂+3H₂⇌2NH₃')
    expect(rate.sections[1].items[1].examples?.join('')).toContain('mol·L⁻¹·min⁻¹')
    expect(rate.sections[4].items[1].rule).toContain('与反应物能量之差')
    const thermo = card('H2_THERMO')
    expect(thermo.sections[4].items[0].rule).toContain('质量相同且比热容近似相同')
    const catalyst = card('H2_EQUIL').sections[3].items[3].examples?.join('')
    expect(catalyst).toContain('在已平衡的体系中')
    expect(catalyst).toContain('平衡不移动')
    expect(catalyst).toContain('相等')
  })

  it('cannot apply an index-keyed correction to a renamed or changed node', () => {
    const source = structuredClone(card('H3_PROCESS'))
    const item = source.sections[0].items[0]
    item.label = '新编知识点'
    item.examples = ['老师重新编写的例子。']
    const after = applyReviewedKnowledgeNodeAids(source, source.skillId)
    expect(after.sections[0].items[0].examples).toEqual(item.examples)
    const changed = structuredClone(card('H3_PROCESS'))
    changed.sections[0].items[0].rule = '另一条未经审查的规则。'
    expect(() => applyReviewedKnowledgeNodeAids(changed, changed.skillId)).toThrow(/rule guard failed/)
  })

  it('is idempotent and leaves source card and stable node identities intact', () => {
    const source = card('H3_PROCESS')
    const before = structuredClone(source)
    const once = applyReviewedKnowledgeNodeAids(source, source.skillId)
    const twice = applyReviewedKnowledgeNodeAids(once, source.skillId)
    expect(twice).toEqual(once)
    expect(source).toEqual(before)
    expect(once.sections.map((section: StructuredKnowledgeContent['sections'][number]) => section.items.map((item) => item.label)))
      .toEqual(source.sections.map((section) => section.items.map((item) => item.label)))
  })
})
