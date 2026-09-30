import type { KnowledgeTreeNode, StructuredKnowledgeContent } from './types'
import { knowledgeExampleSource } from './knowledgeExampleApplicability'
import { knowledgeItemExamplesH1 } from '../data/knowledgeItemExamplesH1'
import { knowledgeItemExamplesH2 } from '../data/knowledgeItemExamplesH2'
import { knowledgeItemExamplesH3 } from '../data/knowledgeItemExamplesH3'

const SECTION_DEMO_PREFIX = '【示范：'

/** Old cards copied a chapter demonstration and its route onto every sibling.
 * Keep that demonstration at chapter level; never let it masquerade as a
 * leaf's own explanation. This also protects cached cards after a correction.
 */
function cleanSiblingAids(nodes: KnowledgeTreeNode[]): KnowledgeTreeNode[] {
  const demos = new Map<string, number>()
  const routes = new Map<string, number>()
  for (const node of nodes) {
    for (const example of node.examples ?? []) {
      if (example.startsWith(SECTION_DEMO_PREFIX)) demos.set(example, (demos.get(example) ?? 0) + 1)
    }
    if (node.visualSteps && node.visualSteps.length > 2 && node.visualSteps[0] === node.label) {
      const route = JSON.stringify(node.visualSteps.slice(1))
      routes.set(route, (routes.get(route) ?? 0) + 1)
    }
  }
  return nodes.map((node) => {
    const examples = [...new Set((node.examples ?? []).map((example) => example.trim())
      .filter((example) => example && (demos.get(example) ?? 0) < 2))]
    const copiedRoute = node.visualSteps && node.visualSteps[0] === node.label
      && (routes.get(JSON.stringify(node.visualSteps.slice(1))) ?? 0) > 1
    const copy = { ...node }
    delete copy.examples
    delete copy.visualSteps
    return {
      ...copy,
      ...(examples.length ? { examples } : {}),
      ...(!copiedRoute && node.visualSteps?.length ? { visualSteps: [...node.visualSteps] } : {}),
      ...(node.children ? { children: cleanSiblingAids(node.children) } : {}),
    }
  })
}

/** One set of item aids for the knowledge tree and the full explanation. */
export function knowledgeSectionsWithFocusedAids(content: StructuredKnowledgeContent, skillId?: string) {
  const canUseReviewedExamples = skillId && knowledgeExampleSource({ skillId }, content) === 'generated'
  return content.sections.map((section, sectionIndex) => ({
    ...section,
    items: cleanSiblingAids(section.items).map((item, itemIndex) => {
      if (item.examples?.length || !canUseReviewedExamples) return item
      const key = `${skillId}:${sectionIndex}:${itemIndex}`
      const examples = knowledgeItemExamplesH1[key] ?? knowledgeItemExamplesH2[key] ?? knowledgeItemExamplesH3[key]
      return examples?.length ? { ...item, examples: [...examples] } : item
    }),
  }))
}
