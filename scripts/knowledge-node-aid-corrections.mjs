import reviewedCorrections from '../content/knowledge/node-aids-reviewed-20261001.json' with { type: 'json' }

export const reviewedNodeAidCorrections = reviewedCorrections

/** Apply reviewed aids only to the original, named node. A re-ordered or newly
 * authored hierarchy must never inherit another item's example by index alone.
 * The old and corrected rule are accepted so this overlay is idempotent.
 */
export function applyReviewedKnowledgeNodeAids(source, skillId, cardId) {
  const content = structuredClone(source)
  for (const patch of reviewedNodeAidCorrections) {
    if (patch.skillId !== skillId || (cardId && patch.cardId !== cardId)) continue
    let node
    if (patch.rootTreePath) {
      node = content.rootTree
      for (const index of patch.rootTreePath) node = node?.children?.[index]
    } else {
      const section = content.sections?.[patch.sectionIndex]
      if (section?.title !== patch.sectionTitle) continue
      node = section.items?.[patch.itemIndex]
      for (const index of patch.nodePath ?? []) node = node?.children?.[index]
    }
    if (node?.label !== patch.expectedLabel) continue
    if (node.rule !== patch.expectedRule && node.rule !== patch.nextRule && !patch.acceptedSourceRules?.includes(node.rule)) {
      throw new Error(`Reviewed aid rule guard failed: ${skillId}/${node.label}`)
    }
    node.examples = [...patch.examples]
    node.visualSteps = [...patch.visualSteps]
    if (patch.nextRule) node.rule = patch.nextRule
  }
  return content
}
