import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import type { KnowledgeCard, KnowledgeTreeNode, StructuredKnowledgeContent } from './types'
import { knowledgeSectionTree } from './knowledgeDrilldown'
import openingCards from '../../content/knowledge/h1_opening_knowledge_cards.json'
// @ts-expect-error The authored content generator is an ESM JavaScript module without declarations.
import { zeroForgettingCards } from '../../scripts/zero-forgetting-content.mjs'

function missingLeafExamples(node: KnowledgeTreeNode, trail: string[] = []): string[] {
  const path = [...trail, node.label]
  if (!node.children?.length) return node.examples?.length ? [] : [path.join(' → ')]
  return node.children.flatMap((child) => missingLeafExamples(child, path))
}

type GeneratedCard = StructuredKnowledgeContent & { skillId: string }
type OpeningCard = { id: string; skill_id: string; title: string; core: string;
  structured_content: StructuredKnowledgeContent }

describe('every released terminal knowledge point has its own example', () => {
  it('covers all generated high-school knowledge sections, including deeper composite leaves', () => {
    const cards = zeroForgettingCards as GeneratedCard[]
    expect(cards).toHaveLength(26)
    for (const content of cards) {
      const card: KnowledgeCard = { id: `KC_${content.skillId}`, skillId: content.skillId, title: content.skillId,
        core: content.intro, detail: '', steps: [], commonMistakes: [], microExample: '',
        reviewStatus: 'approved', structuredContent: content }
      expect(missingLeafExamples(knowledgeSectionTree(content, card.title, card)), content.skillId).toEqual([])
    }
  })

  it('covers the published high-one opening knowledge cards', () => {
    for (const record of openingCards as OpeningCard[]) {
      const card: KnowledgeCard = { id: record.id, skillId: record.skill_id, title: record.title,
        core: record.core, detail: '', steps: [], commonMistakes: [], microExample: '',
        reviewStatus: 'approved', structuredContent: record.structured_content }
      expect(missingLeafExamples(knowledgeSectionTree(record.structured_content, record.title, card)), record.skill_id).toEqual([])
    }
  })

  it('covers the separately authored gas-molar-volume card, including both directions of conversion', () => {
    const sql = readFileSync('supabase/migrations/20260814125818_high_school_review_five_rounds.sql', 'utf8')
    const content = JSON.parse(sql.split('$gas_card$')[1]) as StructuredKnowledgeContent
    const card: KnowledgeCard = { id: 'KC_H1_GAS_MOLAR_VOLUME_ZERO', skillId: 'H1_GAS_MOLAR_VOLUME',
      title: '气体摩尔体积', core: content.intro, detail: '', steps: [], commonMistakes: [], microExample: '',
      reviewStatus: 'approved', structuredContent: content }
    expect(missingLeafExamples(knowledgeSectionTree(content, card.title, card))).toEqual([])
  })
})
