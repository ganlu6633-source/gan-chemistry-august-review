import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import type { StructuredKnowledgeContent } from '../domain/types'
import { generatedKnowledgeSignatures, knowledgeExampleSignature, openingKnowledgeSignatures, specialKnowledgeSignatures } from './knowledgeExampleSignatures'
import openingCards from '../../content/knowledge/h1_opening_knowledge_cards.json'
// @ts-expect-error The authored content generator is an ESM JavaScript module without declarations.
import { zeroForgettingCards } from '../../scripts/zero-forgetting-content.mjs'

type GeneratedCard = StructuredKnowledgeContent & { skillId: string }
type OpeningCard = { skill_id: string; structured_content: StructuredKnowledgeContent }

describe('knowledge example source signatures', () => {
  it('matches every generated hierarchy used to attach item examples', () => {
    const cards = zeroForgettingCards as GeneratedCard[]
    expect(Object.keys(generatedKnowledgeSignatures).sort()).toEqual(cards.map((card) => card.skillId).sort())
    for (const card of cards) {
      expect(knowledgeExampleSignature(card), card.skillId).toBe(generatedKnowledgeSignatures[card.skillId])
    }
  })

  it('matches released high-one opening hierarchies and changes if an item is rearranged', () => {
    const cards = openingCards as OpeningCard[]
    expect(Object.keys(openingKnowledgeSignatures).sort()).toEqual(cards.map((card) => card.skill_id).sort())
    for (const card of cards) {
      const source = card.structured_content
      expect(knowledgeExampleSignature(source), card.skill_id).toBe(openingKnowledgeSignatures[card.skill_id])
      const revised = structuredClone(source)
      revised.sections[0].items[0].label += '（新版）'
      expect(knowledgeExampleSignature(revised)).not.toBe(openingKnowledgeSignatures[card.skill_id])
    }
  })

  it('matches the separately authored gas-molar-volume knowledge card', () => {
    const sql = readFileSync('supabase/migrations/20260814125818_high_school_review_five_rounds.sql', 'utf8')
    const source = JSON.parse(sql.split('$gas_card$')[1]) as StructuredKnowledgeContent
    expect(knowledgeExampleSignature(source)).toBe(specialKnowledgeSignatures.H1_GAS_MOLAR_VOLUME)
  })
})
