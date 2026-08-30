export const MAX_KNOWLEDGE_STRING_LENGTH = 20_000;
export const MAX_KNOWLEDGE_LIST_ITEMS = 100;
export const MAX_KNOWLEDGE_TREE_NODES = 1_000;

const KNOWLEDGE_VISUAL_KINDS = new Set(["tree", "flow", "cycle", "compare", "network", "balance"]);

export function nonEmptyKnowledgeString(value: unknown) {
  return typeof value === "string"
    && value.trim().length > 0
    && value.length <= MAX_KNOWLEDGE_STRING_LENGTH;
}

function validKnowledgeVisualTreeNode(
  value: unknown,
  depth = 0,
  state: { nodes: number } = { nodes: 0 },
): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value) || depth > 8) return false;
  state.nodes += 1;
  if (state.nodes > MAX_KNOWLEDGE_TREE_NODES) return false;
  const branch = value as Record<string, unknown>;
  if (!nonEmptyKnowledgeString(branch.label)) return false;
  if (branch.children === undefined) return true;
  if (!Array.isArray(branch.children) || branch.children.length > MAX_KNOWLEDGE_LIST_ITEMS) return false;
  for (const child of branch.children as unknown[]) {
    if (!validKnowledgeVisualTreeNode(child, depth + 1, state)) return false;
  }
  return true;
}

function validKnowledgeVisualStep(value: unknown): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const step = value as Record<string, unknown>;
  return nonEmptyKnowledgeString(step.label)
    && (step.caption === undefined || nonEmptyKnowledgeString(step.caption));
}

function validKnowledgeVisualGroup(value: unknown): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const group = value as Record<string, unknown>;
  return nonEmptyKnowledgeString(group.label)
    && Array.isArray(group.items)
    && group.items.length > 0
    && group.items.length <= MAX_KNOWLEDGE_LIST_ITEMS
    && (group.items as unknown[]).every(nonEmptyKnowledgeString);
}

function validPresentList(
  value: unknown,
  itemValidator: (item: unknown) => boolean,
): value is unknown[] {
  return Array.isArray(value)
    && value.length > 0
    && value.length <= MAX_KNOWLEDGE_LIST_ITEMS
    && value.every(itemValidator);
}

/**
 * Every field copied by the learner-facing visual shaper is validated even
 * when it is not required by the declared kind.  This prevents a malformed or
 * over-wide "extra" field from bypassing the kind-specific checks and failing
 * later while the response DTO is being built.
 */
export function validKnowledgeVisual(value: unknown): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const visual = value as Record<string, unknown>;
  const kind = String(visual.kind || "");
  if (!KNOWLEDGE_VISUAL_KINDS.has(kind) || !nonEmptyKnowledgeString(visual.title)) return false;
  if (visual.center !== undefined && !nonEmptyKnowledgeString(visual.center)) return false;

  if (visual.steps !== undefined && !validPresentList(visual.steps, validKnowledgeVisualStep)) return false;
  if (visual.groups !== undefined && !validPresentList(visual.groups, validKnowledgeVisualGroup)) return false;
  if (visual.axes !== undefined && !validPresentList(visual.axes, validKnowledgeVisualGroup)) return false;
  if (visual.tree !== undefined && !validKnowledgeVisualTreeNode(visual.tree)) return false;

  if (kind === "tree" && visual.tree === undefined) return false;
  if (["flow", "cycle"].includes(kind) && visual.steps === undefined) return false;
  if (["compare", "network", "balance"].includes(kind) && visual.groups === undefined) return false;
  return true;
}
