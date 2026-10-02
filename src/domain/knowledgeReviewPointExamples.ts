import type { KnowledgeCard } from './types'
import type { KnowledgeReviewPoint } from './knowledgeReviewPoints'
import { getKnowledgeReviewLeaves } from './knowledgeReviewPoints'
import { isStructuredKnowledgeContent } from './knowledgeContent'
import { knowledgeExampleSource } from './knowledgeExampleApplicability'
import { knowledgeFinePointExamples } from '../data/knowledgeFinePointExamples'
import { knowledgeSectionsWithFocusedAids } from './knowledgeNodeAids'
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
  if (Number(partIndex) >= 50) {
    const leaf = getKnowledgeReviewLeaves(item).find(({ pointIndex }) => pointIndex === Number(partIndex))
    return leaf?.node.label === point.title ? leaf.node.examples ?? [] : []
  }
  const source = knowledgeExampleSource(card, card.structuredContent)
  const itemKey = `${card.skillId}:${sectionIndex}:${itemIndex}`
  if (point.title !== item.label) {
    const fine = source ? knowledgeFinePointExamples[`${itemKey}:${partIndex}`] ?? [] : []
    return [...new Set(fine)]
  }
  const sections = knowledgeSectionsWithFocusedAids(card.structuredContent, card.skillId)
  return sections[Number(sectionIndex)].items[Number(itemIndex)].examples ?? []
}
