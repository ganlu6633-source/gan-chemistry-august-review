export type ImageRowSlice = { start: number; end: number }
export type ImageBounds = { left: number; top: number; right: number; bottom: number }

export function findTopBlueCitationBounds(
  pixels: Uint8ClampedArray,
  width: number,
  height: number,
): ImageBounds | null {
  const searchHeight = Math.max(1, Math.floor(height * 0.28))
  let left = width
  let right = -1
  let top = searchHeight
  let bottom = -1
  let matches = 0
  for (let y = 0; y < searchHeight; y += 1) {
    for (let x = 0; x < Math.floor(width * 0.62); x += 1) {
      const offset = (y * width + x) * 4
      const red = pixels[offset]
      const green = pixels[offset + 1]
      const blue = pixels[offset + 2]
      const alpha = pixels[offset + 3]
      // Source labels in the original worksheets are printed in a saturated blue.
      // Keep the threshold deliberately narrow so blue chemistry diagrams are not
      // altered unless they appear in the first line and form a text-sized cluster.
      if (alpha > 32 && blue > 105 && blue - red > 45 && blue - green > 12 && green > 55) {
        left = Math.min(left, x)
        right = Math.max(right, x)
        top = Math.min(top, y)
        bottom = Math.max(bottom, y)
        matches += 1
      }
    }
  }
  if (matches < 24 || right - left < 28 || bottom - top < 5) return null
  return { left, top, right: right + 1, bottom: bottom + 1 }
}

export function compactBlankRowSlices(blankRows: readonly boolean[], maximumBlankRows = 28, minimumCompressibleRows = 64): ImageRowSlice[] {
  const slices: ImageRowSlice[] = []
  let cursor = 0
  let index = 0
  while (index < blankRows.length) {
    if (!blankRows[index]) { index += 1; continue }
    const start = index
    while (index < blankRows.length && blankRows[index]) index += 1
    const end = index
    const length = end - start
    if (start === 0 || end === blankRows.length || length < minimumCompressibleRows || length <= maximumBlankRows) continue
    const keepBefore = Math.ceil(maximumBlankRows / 2)
    const keepAfter = Math.floor(maximumBlankRows / 2)
    if (start + keepBefore > cursor) slices.push({ start: cursor, end: start + keepBefore })
    cursor = end - keepAfter
  }
  if (cursor < blankRows.length) slices.push({ start: cursor, end: blankRows.length })
  return slices.length > 0 ? slices : [{ start: 0, end: blankRows.length }]
}
