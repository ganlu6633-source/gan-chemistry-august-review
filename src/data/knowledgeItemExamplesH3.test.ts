import { describe, expect, it } from 'vitest'
import { knowledgeItemExamplesH3 } from './knowledgeItemExamplesH3'
// @ts-expect-error The authored content generator is an ESM JavaScript module without declarations.
import { zeroForgettingCards } from '../../scripts/zero-forgetting-content.mjs'

type OutlineCard = {
  skillId: string
  sections: Array<{ items: Array<{ label: string; rule: string; examples?: string[] }> }>
}

const highThreeCards = (zeroForgettingCards as OutlineCard[]).filter((card) => card.skillId.startsWith('H3_'))

describe('high-three item-specific examples', () => {
  it('covers every current high-three section item with a distinct example', () => {
    const itemKeys = highThreeCards.flatMap((card) => card.sections.flatMap((section, sectionIndex) =>
      section.items.map((_item, itemIndex) => `${card.skillId}:${sectionIndex}:${itemIndex}`)))
    expect(highThreeCards).toHaveLength(11)
    expect(itemKeys).toHaveLength(308)
    expect(Object.keys(knowledgeItemExamplesH3).sort()).toEqual(itemKeys.sort())

    for (const card of highThreeCards) {
      for (const [sectionIndex, section] of card.sections.entries()) {
        const examplesInSection: string[] = []
        for (const [itemIndex, item] of section.items.entries()) {
          const key = `${card.skillId}:${sectionIndex}:${itemIndex}`
          const examples = knowledgeItemExamplesH3[key]
          expect(examples, key).toBeDefined()
          expect(examples.length, key).toBeGreaterThan(0)
          for (const example of examples) {
            expect(example.trim().length, key).toBeGreaterThan(12)
            expect(example, key).not.toMatch(/^【示范：/)
            expect(item.examples ?? [], key).not.toContain(example)
            examplesInSection.push(example)
          }
        }
        expect(new Set(examplesInSection).size, `${card.skillId} section ${sectionIndex}`).toBe(examplesInSection.length)
      }
    }
  })
})
