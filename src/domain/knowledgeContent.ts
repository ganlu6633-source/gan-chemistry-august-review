import type { StructuredKnowledgeContent } from './types'

const VISUAL_KINDS = new Set(['tree', 'flow', 'cycle', 'compare', 'network', 'balance'])

function nonEmpty(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}

function validTreeNode(value: unknown, depth = 0): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value) || depth > 8) return false
  const node = value as Record<string, unknown>
  if (!nonEmpty(node.label) || !nonEmpty(node.rule)) return false
  for (const key of ['examples', 'visualSteps'] as const) {
    if (node[key] !== undefined
      && (!Array.isArray(node[key]) || !(node[key] as unknown[]).every(nonEmpty))) return false
  }
  if (node.caution !== undefined && !nonEmpty(node.caution)) return false
  if (node.children !== undefined && (!Array.isArray(node.children) || !node.children.every((child) => validTreeNode(child, depth + 1)))) return false
  return true
}

function validVisual(value: unknown): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false
  const visual = value as Record<string, unknown>
  const kind = String(visual.kind || '')
  if (!VISUAL_KINDS.has(kind) || !nonEmpty(visual.title)) return false
  if (kind === 'tree') {
    const validVisualTree = (node: unknown, depth = 0): boolean => {
      if (!node || typeof node !== 'object' || Array.isArray(node) || depth > 8) return false
      const branch = node as Record<string, unknown>
      return nonEmpty(branch.label)
        && (branch.children === undefined
          || (Array.isArray(branch.children)
            && (branch.children as unknown[]).every((child) => validVisualTree(child, depth + 1))))
    }
    if (!validVisualTree(visual.tree)) return false
  }
  if (kind === 'flow' || kind === 'cycle') {
    if (!Array.isArray(visual.steps) || visual.steps.length === 0
      || !(visual.steps as unknown[]).every((step) => step && typeof step === 'object'
        && !Array.isArray(step) && nonEmpty((step as Record<string, unknown>).label))) return false
  }
  if (kind === 'compare' || kind === 'network' || kind === 'balance') {
    if (!Array.isArray(visual.groups) || visual.groups.length === 0
      || !(visual.groups as unknown[]).every((group) => {
        if (!group || typeof group !== 'object' || Array.isArray(group)) return false
        const row = group as Record<string, unknown>
        return nonEmpty(row.label)
          && Array.isArray(row.items) && row.items.length > 0
          && (row.items as unknown[]).every(nonEmpty)
      })) return false
  }
  return true
}

/**
 * Runtime guard for database-backed knowledge cards. TypeScript cannot protect
 * the browser from an older or malformed JSON row, so the student page must
 * verify the minimum renderable contract before mapping its sections.
 */
export function isStructuredKnowledgeContent(value: unknown): value is StructuredKnowledgeContent {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false
  const content = value as Record<string, unknown>
  if (!Number.isInteger(Number(content.version)) || Number(content.version) < 1) return false
  if (!nonEmpty(content.intro)) return false
  if (!Array.isArray(content.sections) || !content.sections.length) return false
  if (!content.sections.every((section) => {
    if (!section || typeof section !== 'object' || Array.isArray(section)) return false
    const row = section as Record<string, unknown>
    return nonEmpty(row.title)
      && Array.isArray(row.items) && row.items.length > 0
      && row.items.every((item) => validTreeNode(item))
  })) return false
  if (content.rootTree !== undefined && !validTreeNode(content.rootTree)) return false
  if (content.visualSummary !== undefined && !validVisual(content.visualSummary)) return false
  if (content.overview !== undefined
    && (!Array.isArray(content.overview) || !(content.overview as unknown[]).every(nonEmpty))) return false
  if (content.checkpoints !== undefined
    && (!Array.isArray(content.checkpoints) || !(content.checkpoints as unknown[]).every(nonEmpty))) return false
  if (content.workedExamples !== undefined
    && (!Array.isArray(content.workedExamples)
      || !(content.workedExamples as unknown[]).every((example) => {
        if (!example || typeof example !== 'object' || Array.isArray(example)) return false
        const row = example as Record<string, unknown>
        return nonEmpty(row.substance)
          && nonEmpty(row.path)
          && Array.isArray(row.labels) && (row.labels as unknown[]).every(nonEmpty)
      }))) return false
  return true
}
