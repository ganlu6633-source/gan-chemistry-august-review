import type { KnowledgeCard } from './types'
import type { KnowledgeReviewPoint } from './knowledgeReviewPoints'
import { isStructuredKnowledgeContent } from './knowledgeContent'
import { knowledgeExampleSource } from './knowledgeExampleApplicability'
import { knowledgeFinePointExamples } from '../data/knowledgeFinePointExamples'
import { knowledgeItemExamplesH1 } from '../data/knowledgeItemExamplesH1'
import { knowledgeItemExamplesH2 } from '../data/knowledgeItemExamplesH2'
import { knowledgeItemExamplesH3 } from '../data/knowledgeItemExamplesH3'
import { knowledgeLegacyLeafExamples } from '../data/knowledgeLegacyLeafExamples'

/** An exact review point receives only its own example, never a shared chapter demo. */
export function knowledgeReviewPointExamples(card: KnowledgeCard, point: KnowledgeReviewPoint): string[] {
  if (!isStructuredKnowledgeContent(card.structuredContent)) {
    return [...new Set([...point.examples, ...(knowledgeLegacyLeafExamples[point.id] ?? [])])]
  }
  const match = point.id.match(/:s(\d+):i(\d+):p(\d+)$/)
  if (!match) return point.examples.filter((example) => !example.startsWith('【示范：'))
  const [, sectionIndex, itemIndex, partIndex] = match
  const item = card.structuredContent.sections[Number(sectionIndex)]?.items[Number(itemIndex)]
  if (!item) return []
  const section = card.structuredContent.sections[Number(sectionIndex)]
  const demonstrationCounts = new Map<string, number>()
  for (const example of section.items.flatMap((entry) => entry.examples ?? [])) {
    if (example.startsWith('【示范：')) demonstrationCounts.set(example, (demonstrationCounts.get(example) ?? 0) + 1)
  }
  const source = knowledgeExampleSource(card, card.structuredContent)
  const itemKey = `${card.skillId}:${sectionIndex}:${itemIndex}`
  if (point.title !== item.label) {
    const fine = source ? knowledgeFinePointExamples[`${itemKey}:${partIndex}`] ?? [] : []
    return [...new Set(fine)]
  }
  const direct = (item.examples ?? []).filter((example) => (demonstrationCounts.get(example) ?? 0) < 2)
  const added = source === 'generated' ? (knowledgeItemExamplesH1[itemKey]
    ?? knowledgeItemExamplesH2[itemKey]
    ?? knowledgeItemExamplesH3[itemKey]
    ?? []) : []
  return [...new Set([...direct, ...added])]
}
