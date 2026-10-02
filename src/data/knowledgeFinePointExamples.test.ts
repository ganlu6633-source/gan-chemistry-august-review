import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import type { KnowledgeCard, StructuredKnowledgeContent } from '../domain/types'
import { getKnowledgeReviewLeaves, getKnowledgeReviewPoints } from '../domain/knowledgeReviewPoints'
import { knowledgeFinePointExamples } from './knowledgeFinePointExamples'
import openingCards from '../../content/knowledge/h1_opening_knowledge_cards.json'
// @ts-expect-error The authored content generator is an ESM JavaScript module without declarations.
import { zeroForgettingCards } from '../../scripts/zero-forgetting-content.mjs'

type GeneratedContent = StructuredKnowledgeContent & { skillId: string }
type OpeningRecord = { id: string; skill_id: string; title: string; core: string;
  structured_content: StructuredKnowledgeContent }

function compositePartKeys(card: KnowledgeCard): string[] {
  const groups = new Map<string, string[]>()
  for (const point of getKnowledgeReviewPoints(card)) {
    const match = point.id.match(/:s(\d+):i(\d+):p(\d+)$/)
    if (!match) continue
    // Authored child leaves keep their examples on the node; p50–p99 are
    // independent addresses, not legacy composite parts in the static map.
    if (Number(match[3]) >= 50) continue
    const parentKey = `${card.skillId}:${match[1]}:${match[2]}`
    const keys = groups.get(parentKey) ?? []
    keys.push(`${parentKey}:${match[3]}`)
    groups.set(parentKey, keys)
  }
  return [...groups.values()].filter((keys) => keys.length > 1).flat()
}

describe('examples for reviewed fine knowledge points', () => {
  it('covers every currently generated composite split and the released high-one opening card', () => {
    const generatedCards = (zeroForgettingCards as GeneratedContent[]).map((content) => ({
      id: `KC_${content.skillId}`, skillId: content.skillId, title: content.skillId,
      core: content.intro, detail: '', steps: [], commonMistakes: [], microExample: '',
      reviewStatus: 'approved' as const, structuredContent: content,
    }))
    const opening = (openingCards as unknown as OpeningRecord[]).map((record) => ({
      id: record.id, skillId: record.skill_id, title: record.title,
      core: record.core, detail: '', steps: [], commonMistakes: [], microExample: '',
      reviewStatus: 'approved' as const, structuredContent: record.structured_content,
    }))
    const gasSql = readFileSync('supabase/migrations/20260814125818_high_school_review_five_rounds.sql', 'utf8')
    const gasContent = JSON.parse(gasSql.split('$gas_card$')[1]) as StructuredKnowledgeContent
    const gasCard: KnowledgeCard = { id: 'KC_H1_GAS_MOLAR_VOLUME_ZERO', skillId: 'H1_GAS_MOLAR_VOLUME', title: '气体摩尔体积',
      core: gasContent.intro, detail: '', steps: [], commonMistakes: [], microExample: '',
      reviewStatus: 'approved', structuredContent: gasContent }
    const generatedKeys = generatedCards.flatMap(compositePartKeys)
    const openingKeys = opening.flatMap(compositePartKeys)
    const gasKeys = compositePartKeys(gasCard)
    expect(generatedKeys).toHaveLength(17)
    expect(openingKeys).toHaveLength(7)
    expect(gasKeys).toHaveLength(2)
    expect(Object.keys(knowledgeFinePointExamples).sort()).toEqual([...generatedKeys, ...openingKeys, ...gasKeys].sort())
    for (const [key, examples] of Object.entries(knowledgeFinePointExamples)) {
      expect(examples.length, key).toBeGreaterThan(0)
      expect(examples.every((example) => example.trim().length > 12), key).toBe(true)
    }
  })

  it('keeps each of the 42 authored ion/redox leaves on its own example', () => {
    const contents = (zeroForgettingCards as GeneratedContent[])
      .filter((content) => ['H1_ELECTROLYTE', 'H1_REDOX'].includes(content.skillId))
    expect(contents).toHaveLength(2)
    let leafCount = 0
    for (const content of contents) {
      const card: KnowledgeCard = {
        id: `KC_${content.skillId}`, skillId: content.skillId, title: content.skillId,
        core: content.intro, detail: '', steps: [], commonMistakes: [], microExample: '',
        reviewStatus: 'approved', structuredContent: content,
      }
      const points = getKnowledgeReviewPoints(card)
      content.sections.forEach((section, sectionIndex) => section.items.forEach((item, itemIndex) => {
        const leaves = getKnowledgeReviewLeaves(item)
        const siblingExamples = new Set<string>()
        for (const { node, pointIndex } of leaves) {
          leafCount += 1
          const id = `${card.id}:s${sectionIndex}:i${itemIndex}:p${pointIndex}`
          const point = points.find((candidate) => candidate.id === id)
          expect(node.examples?.length, id).toBeGreaterThan(0)
          expect(node.examples?.every((example) => example.trim().length > 12), id).toBe(true)
          expect(point?.examples, id).toEqual(node.examples)
          for (const example of node.examples ?? []) {
            expect(item.examples ?? [], id).not.toContain(example)
            expect(siblingExamples.has(example), id).toBe(false)
            siblingExamples.add(example)
          }
          const staticKey = `${card.skillId}:${sectionIndex}:${itemIndex}:${pointIndex}`
          expect(knowledgeFinePointExamples, id).not.toHaveProperty(staticKey)
        }
      }))
    }
    expect(leafCount).toBe(42)
  })
})
