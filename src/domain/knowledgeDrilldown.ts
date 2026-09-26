import type { KnowledgeCard, KnowledgeTreeNode, StructuredKnowledgeContent } from './types'
import { isStructuredKnowledgeContent } from './knowledgeContent'
import { getKnowledgeReviewPoints } from './knowledgeReviewPoints'
import { knowledgeItemExamplesH1 } from '../data/knowledgeItemExamplesH1'
import { knowledgeItemExamplesH2 } from '../data/knowledgeItemExamplesH2'
import { knowledgeItemExamplesH3 } from '../data/knowledgeItemExamplesH3'
import { knowledgeFinePointExamples } from '../data/knowledgeFinePointExamples'
import { knowledgeLegacyLeafExamples } from '../data/knowledgeLegacyLeafExamples'
import { knowledgeExampleSource } from './knowledgeExampleApplicability'

const SECTION_DEMO_PREFIX = '【示范：'

function uniqueExamples(examples: string[]): string[] {
  return [...new Set(examples.map((example) => example.trim()).filter(Boolean))]
}

function sectionRule(content: StructuredKnowledgeContent, summary?: string): string {
  // Both fields are teacher-authored. An absent section summary must not cause
  // the UI to invent a chemical definition for the section heading.
  return summary?.trim() || content.intro
}

/**
 * Show all authored sections as a drill-down tree, regardless of whether a
 * separate overview tree is also present on the card.
 */
export function knowledgeSectionTree(content: StructuredKnowledgeContent, title?: string, card?: KnowledgeCard): KnowledgeTreeNode {
  const reviewedPoints = card && isStructuredKnowledgeContent(card.structuredContent)
    ? getKnowledgeReviewPoints(card)
    : []
  const exampleSource = card ? knowledgeExampleSource(card, content) : null

  return {
    label: title?.trim() || content.visualSummary?.title || content.sections[0]?.title || content.intro,
    rule: content.intro,
    ...(content.workedExamples?.length ? {
      examples: content.workedExamples.map((example) => `${example.substance}：${example.path}`),
    } : {}),
    children: content.sections.map((section, sectionIndex) => {
      const demonstrationCounts = new Map<string, number>()
      for (const example of section.items.flatMap((item) => item.examples ?? [])) {
        if (example.startsWith(SECTION_DEMO_PREFIX)) demonstrationCounts.set(example, (demonstrationCounts.get(example) ?? 0) + 1)
      }
      const sharedDemonstrations = [...demonstrationCounts].filter(([, count]) => count > 1).map(([example]) => example)
      return {
        label: section.title,
        rule: sectionRule(content, section.summary),
        ...(sharedDemonstrations.length ? { examples: sharedDemonstrations } : {}),
        children: section.items.map((item, itemIndex) => {
          const directExamples = (item.examples ?? []).filter((example) => !sharedDemonstrations.includes(example))
          const exampleKey = card ? `${card.skillId}:${sectionIndex}:${itemIndex}` : ''
          const extraExamples = exampleSource === 'generated' ? (knowledgeItemExamplesH1[exampleKey]
            ?? knowledgeItemExamplesH2[exampleKey]
            ?? knowledgeItemExamplesH3[exampleKey]
            ?? []) : []
          const examples = uniqueExamples([...directExamples, ...extraExamples])
          const point = { ...item, examples: examples.length ? examples : undefined }
          if (item.children?.length || !card) return point
          const prefix = `${card.id}:s${sectionIndex}:i${itemIndex}:p`
          const finePoints = reviewedPoints.filter((point) => point.id.startsWith(prefix))
          if (finePoints.length < 2) return point
          return {
            ...point,
            // A general item example stays on its parent. Only an exact
            // fine-point key may supply an example to a deeper leaf.
            children: finePoints.map((finePoint, partIndex) => {
              const fineKey = `${card.skillId}:${sectionIndex}:${itemIndex}:${partIndex}`
              const fineExamples = exampleSource ? knowledgeFinePointExamples[fineKey] : undefined
              return { label: finePoint.title, rule: finePoint.rule,
                ...(fineExamples ? { examples: fineExamples } : {}) }
            }),
          }
        }),
      }
    }),
  }
}

/** A card's authored overview tree takes priority; sections remain available separately. */
export function knowledgeTreeFromStructuredContent(content: StructuredKnowledgeContent, title?: string): KnowledgeTreeNode {
  return content.rootTree ?? knowledgeSectionTree(content, title)
}

/**
 * Legacy cards have no structured tree. Reuse the audited fine knowledge
 * points where available; keep a card-wide example at the card level instead
 * of falsely attaching it to every smaller point.
 */
export function buildKnowledgeCardDrilldown(card: KnowledgeCard): KnowledgeTreeNode {
  if (isStructuredKnowledgeContent(card.structuredContent)) {
    return card.structuredContent.rootTree
      ?? knowledgeSectionTree(card.structuredContent, card.title, card)
  }

  const points = getKnowledgeReviewPoints(card)
  if (points.length === 1 && points[0].title === card.title) {
    return {
      label: card.title,
      rule: points[0].rule || card.detail || card.core,
      ...(points[0].examples.length ? { examples: points[0].examples } : {}),
      ...(points[0].caution ? { caution: points[0].caution } : {}),
    }
  }

  return {
    label: card.title,
    rule: card.core || card.detail || points[0].rule,
    ...(card.microExample ? { examples: [card.microExample] } : {}),
    children: points.map((point) => ({
      label: point.title,
      rule: point.rule,
      ...((point.examples.length || knowledgeLegacyLeafExamples[point.id])
        ? { examples: uniqueExamples([...point.examples, ...(knowledgeLegacyLeafExamples[point.id] ?? [])]) } : {}),
      ...(point.caution ? { caution: point.caution } : {}),
    })),
  }
}
