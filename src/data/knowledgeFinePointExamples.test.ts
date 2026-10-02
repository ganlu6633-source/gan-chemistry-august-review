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

  it('keeps each of the 44 authored ion/redox leaves on its own example', () => {
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
    expect(leafCount).toBe(44)
  })

  it('appends five independent electrolyte points without moving the released addresses', () => {
    const content = (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === 'H1_ELECTROLYTE')!
    const card: KnowledgeCard = { id: 'KC_H1_ELECTROLYTE', skillId: content.skillId, title: content.skillId,
      core: content.intro, detail: '', steps: [], commonMistakes: [], microExample: '',
      reviewStatus: 'approved', structuredContent: content }
    const splitItem = content.sections[2].items[1]
    expect(getKnowledgeReviewLeaves(splitItem).map((leaf) => leaf.pointIndex)).toEqual([50, 51, 52, 53, 54, 55, 56, 57, 58, 59])
    expect(splitItem.children?.slice(0, 8).map((node) => node.label)).toEqual([
      '可溶性强电解质盐怎样拆', '难溶盐为什么不拆', '强酸怎样拆', '可溶性强碱怎样拆',
      '弱电解质为什么不拆', '气体在离子式中怎样写', '水在离子式中怎样写', '单质在离子式中怎样写',
    ])
    expect(content.sections[6].items.slice(0, 4).map((node) => node.label)).toEqual([
      '先确认是不是化合物', '能导电的单质不是电解质', '盐酸为什么不是电解质', '氯化钠溶液为什么不是电解质',
    ])
    const points = getKnowledgeReviewPoints(card)
    const additions = [
      ['s2:i1:p58', '难溶碱为什么不拆'], ['s2:i1:p59', '氧化物在离子式中怎样写'],
      ['s6:i4:p0', '溶液导电是否来自物质自身电离'], ['s6:i5:p0', '电解质一定处处都导电吗'],
      ['s6:i6:p0', '强电解质溶液一定更导电吗'],
    ]
    for (const [address, title] of additions) {
      const matches = points.filter((point) => point.id === `${card.id}:${address}`)
      expect(matches).toHaveLength(1)
      expect(matches[0].title).toBe(title)
      expect(matches[0].examples).toHaveLength(1)
      expect(matches[0].examples[0]).toMatch(/^教学例子：/)
    }
    for (const node of content.sections[6].items.slice(4)) expect(node.visualSteps?.length).toBeGreaterThanOrEqual(2)
  })
})
