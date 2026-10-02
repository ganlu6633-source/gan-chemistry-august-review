import patches from '../content/knowledge/h1-ions-redox-fine-points-20261002.json' with { type: 'json' }

/** Retain existing node addresses. Each new leaf owns its rule and example. */
export function applyH1IonsRedoxFinePoints(source) {
  const patch = patches.find((entry) => entry.skillId === source.skillId)
  if (!patch) return source
  const content = structuredClone(source)
  for (const entry of patch.children) {
    const section = content.sections[entry.sectionIndex]
    const node = section?.items[entry.itemIndex]
    if (section?.title !== entry.sectionTitle || node?.label !== entry.expectedLabel || node.rule !== entry.expectedRule) {
      throw new Error(`Fine-point source guard failed: ${patch.skillId}/${entry.expectedLabel}`)
    }
    node.children = structuredClone(entry.children)
  }
  for (const section of patch.appendSections) {
    const previous = content.sections.find((entry) => entry.title === section.title)
    if (previous) {
      if (JSON.stringify(previous) !== JSON.stringify(section)) throw new Error(`Fine-point section collision: ${patch.skillId}/${section.title}`)
    } else content.sections.push(structuredClone(section))
  }
  return content
}
