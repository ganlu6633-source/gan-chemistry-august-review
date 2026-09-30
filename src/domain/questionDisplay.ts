/**
 * Some older source imports put the complete A–D block in both the stem and
 * the four option fields. Remove that block from the displayed stem only when
 * every imported option matches exactly, so incomplete original text remains
 * visible for review instead of being silently hidden.
 */
export function displayQuestionStem(stem: string, options: string[]): string {
  if (options.length !== 4) return stem
  const withNewlines = stem.replace(/\\n/g, '\n').replace(/\\t/g, '\t')
  const compact = (value: string) => value.replace(/\s+/g, '')
  const starts = [...withNewlines.matchAll(/(^|[\r\n\t])\s*A[.．、]\s*/gm)]
  for (const first of starts.reverse()) {
    const optionBlockStart = (first.index ?? 0) + first[1].length
    const block = withNewlines.slice(optionBlockStart)
    const markers = [...block.matchAll(/(^|[\r\n\t])\s*([A-D])[.．、]\s*/gm)]
    if (markers.length !== 4 || markers.some((match, index) => match[2] !== 'ABCD'[index])) continue
    let exact = true
    for (let index = 0; index < markers.length; index += 1) {
      const start = (markers[index].index ?? 0) + markers[index][0].length
      const end = index + 1 < markers.length ? markers[index + 1].index ?? block.length : block.length
      if (compact(block.slice(start, end)) !== compact(options[index])) exact = false
    }
    if (exact) return withNewlines.slice(0, optionBlockStart).trimEnd()
  }
  return stem
}
