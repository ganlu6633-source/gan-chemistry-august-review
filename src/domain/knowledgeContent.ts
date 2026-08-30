import type { StructuredKnowledgeContent } from './types'

const VISUAL_KINDS = new Set(['tree', 'flow', 'cycle', 'compare', 'network', 'balance'])
const MAX_STRING_LENGTH = 20_000
const MAX_LIST_ITEMS = 100
const MAX_TREE_NODES = 1_000

function nonEmpty(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= MAX_STRING_LENGTH
}

function validTreeNode(value: unknown, depth = 0, state: { nodes: number } = { nodes: 0 }): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value) || depth > 8) return false
  state.nodes += 1
  if (state.nodes > MAX_TREE_NODES) return false
  const node = value as Record<string, unknown>
  if (!nonEmpty(node.label) || !nonEmpty(node.rule)) return false
  for (const key of ['examples', 'visualSteps'] as const) {
    if (node[key] !== undefined
      && (!Array.isArray(node[key])
        || node[key].length > MAX_LIST_ITEMS
        || !(node[key] as unknown[]).every(nonEmpty))) return false
  }
  if (node.caution !== undefined && !nonEmpty(node.caution)) return false
  if (node.children !== undefined
    && (!Array.isArray(node.children)
      || node.children.length > MAX_LIST_ITEMS
      || !node.children.every((child) => validTreeNode(child, depth + 1, state)))) return false
  return true
}

function validVisualTree(value: unknown, depth = 0, state: { nodes: number } = { nodes: 0 }): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value) || depth > 8) return false
  state.nodes += 1
  if (state.nodes > MAX_TREE_NODES) return false
  const branch = value as Record<string, unknown>
  if (!nonEmpty(branch.label)) return false
  if (branch.children === undefined) return true
  return Array.isArray(branch.children)
    && branch.children.length <= MAX_LIST_ITEMS
    && branch.children.every((child) => validVisualTree(child, depth + 1, state))
}

function validVisualStep(value: unknown): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false
  const step = value as Record<string, unknown>
  return nonEmpty(step.label) && (step.caption === undefined || nonEmpty(step.caption))
}

function validVisualGroup(value: unknown): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false
  const row = value as Record<string, unknown>
  return nonEmpty(row.label)
    && Array.isArray(row.items) && row.items.length > 0
    && row.items.length <= MAX_LIST_ITEMS
    && (row.items as unknown[]).every(nonEmpty)
}

function validPresentVisualList(value: unknown, itemGuard: (item: unknown) => boolean) {
  return Array.isArray(value)
    && value.length > 0
    && value.length <= MAX_LIST_ITEMS
    && value.every(itemGuard)
}

function validVisual(value: unknown): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false
  const visual = value as Record<string, unknown>
  const kind = String(visual.kind || '')
  if (!VISUAL_KINDS.has(kind) || !nonEmpty(visual.title)) return false
  if (visual.center !== undefined && !nonEmpty(visual.center)) return false
  if (visual.steps !== undefined && !validPresentVisualList(visual.steps, validVisualStep)) return false
  if (visual.groups !== undefined && !validPresentVisualList(visual.groups, validVisualGroup)) return false
  if (visual.axes !== undefined && !validPresentVisualList(visual.axes, validVisualGroup)) return false
  if (visual.tree !== undefined && !validVisualTree(visual.tree)) return false
  if (kind === 'tree' && visual.tree === undefined) return false
  if ((kind === 'flow' || kind === 'cycle') && visual.steps === undefined) return false
  if ((kind === 'compare' || kind === 'network' || kind === 'balance') && visual.groups === undefined) return false
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
  if (!Array.isArray(content.sections) || !content.sections.length || content.sections.length > MAX_LIST_ITEMS) return false
  const treeState = { nodes: 0 }
  if (!content.sections.every((section) => {
    if (!section || typeof section !== 'object' || Array.isArray(section)) return false
    const row = section as Record<string, unknown>
    return nonEmpty(row.title)
      && Array.isArray(row.items) && row.items.length > 0 && row.items.length <= MAX_LIST_ITEMS
      && row.items.every((item) => validTreeNode(item, 0, treeState))
  })) return false
  if (content.rootTree !== undefined && !validTreeNode(content.rootTree, 0, treeState)) return false
  if (content.visualSummary !== undefined && !validVisual(content.visualSummary)) return false
  if (content.overview !== undefined
    && (!Array.isArray(content.overview)
      || content.overview.length > MAX_LIST_ITEMS
      || !(content.overview as unknown[]).every(nonEmpty))) return false
  if (content.checkpoints !== undefined
    && (!Array.isArray(content.checkpoints)
      || content.checkpoints.length > MAX_LIST_ITEMS
      || !(content.checkpoints as unknown[]).every(nonEmpty))) return false
  if (content.workedExamples !== undefined
    && (!Array.isArray(content.workedExamples)
      || !(content.workedExamples as unknown[]).every((example) => {
        if (!example || typeof example !== 'object' || Array.isArray(example)) return false
        const row = example as Record<string, unknown>
        return nonEmpty(row.substance)
          && nonEmpty(row.path)
          && Array.isArray(row.labels) && row.labels.length <= MAX_LIST_ITEMS
          && (row.labels as unknown[]).every(nonEmpty)
      }))) return false
  return true
}
