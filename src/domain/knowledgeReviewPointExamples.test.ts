import { describe, expect, it } from 'vitest'
import type { KnowledgeCard, StructuredKnowledgeContent } from './types'
import { getKnowledgeReviewPoints } from './knowledgeReviewPoints'
import { knowledgeReviewPointExamples } from './knowledgeReviewPointExamples'
// @ts-expect-error The authored content generator is an ESM JavaScript module without declarations.
import { zeroForgettingCards } from '../../scripts/zero-forgetting-content.mjs'

const cardBase: KnowledgeCard = {
  id: 'KC_J09_ATOM', skillId: 'J09_ATOM', title: '原子结构与元素', core: '质子数决定元素种类。',
  detail: '', steps: [], commonMistakes: [], microExample: 'Na失电子形成Na⁺。', reviewStatus: 'approved',
}

describe('exact review-point examples', () => {
  it('adds one own illustration to every reviewed junior point', () => {
    const points = getKnowledgeReviewPoints(cardBase)
    expect(points).toHaveLength(3)
    expect(points.every((point) => knowledgeReviewPointExamples(cardBase, point).length > 0)).toBe(true)
    expect(knowledgeReviewPointExamples(cardBase, points[0])[0]).toContain('11个质子')
  })

  it('keeps the shared demonstration off a composite leaf and checks its source version', () => {
    const source = (zeroForgettingCards as Array<StructuredKnowledgeContent & { skillId: string }>)
      .find((item) => item.skillId === 'H1_MOLE_INTRO')!
    const card = { ...cardBase, id: 'KC_H1_MOLE_INTRO', skillId: 'H1_MOLE_INTRO', structuredContent: source }
    const point = getKnowledgeReviewPoints(card).find((item) => item.id.endsWith(':s2:i2:p0'))!
    const examples = knowledgeReviewPointExamples(card, point)
    expect(examples[0]).toContain('36 g H₂O')
    expect(examples.some((example) => example.startsWith('【示范：'))).toBe(false)

    const revised = structuredClone(source)
    revised.sections[2].items[2].label += '（新编排）'
    expect(knowledgeReviewPointExamples({ ...card, structuredContent: revised }, point)).toEqual([])
  })
})
