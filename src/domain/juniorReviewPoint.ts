import type { KnowledgeCard } from './types'
import { getKnowledgeReviewPoints } from './knowledgeReviewPoints'

/** Reviewed option bindings use the exact authored leaf label. Similar broad
 * topic names must never substitute another leaf's rule or example. */
export function juniorReviewPoint(card: KnowledgeCard | readonly KnowledgeCard[] | null, knowledgePoint: string) {
  if (!card || !knowledgePoint.trim()) return null
  const cards: readonly KnowledgeCard[] = Array.isArray(card) ? card : [card as KnowledgeCard]
  const normalize = (value: string) => value.normalize('NFKC').replace(/\s+/gu, '').trim()
  const label = normalize(knowledgePoint)
  const matches = cards.flatMap(getKnowledgeReviewPoints).filter((point) => normalize(point.title) === label)
  return matches.length === 1 ? matches[0] : null
}
