import type { KnowledgeCard, StructuredKnowledgeContent } from './types'
import { generatedKnowledgeSignatures, knowledgeExampleSignature, openingKnowledgeSignatures, specialKnowledgeSignatures } from '../data/knowledgeExampleSignatures'

/** Avoid attaching an index-keyed teaching example to a revised, rearranged card. */
export function knowledgeExampleSource(card: KnowledgeCard, content: StructuredKnowledgeContent): 'generated' | 'opening' | 'special' | null {
  const signature = knowledgeExampleSignature(content)
  if (generatedKnowledgeSignatures[card.skillId] === signature) return 'generated'
  if (openingKnowledgeSignatures[card.skillId] === signature) return 'opening'
  if (specialKnowledgeSignatures[card.skillId] === signature) return 'special'
  return null
}
