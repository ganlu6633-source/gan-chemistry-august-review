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

export async function compactImageWhitespace(dataUrl: string): Promise<string> {
  if (typeof document === 'undefined' || typeof Image === 'undefined') return dataUrl
  const image = new Image()
  image.src = dataUrl
  try { await image.decode() } catch { return dataUrl }
  if (!image.naturalWidth || !image.naturalHeight) return dataUrl

  const source = document.createElement('canvas')
  source.width = image.naturalWidth
  source.height = image.naturalHeight
  const context = source.getContext('2d', { willReadFrequently: true })
  if (!context) return dataUrl
  context.drawImage(image, 0, 0)
  const imageData = context.getImageData(0, 0, source.width, source.height)
  const citation = findTopBlueCitationBounds(imageData.data, source.width, source.height)
  if (citation) {
    const padX = Math.max(3, Math.round(source.width * 0.004))
    const padY = Math.max(2, Math.round(source.height * 0.01))
    const left = Math.max(0, citation.left - padX)
    const right = Math.min(source.width, citation.right + padX)
    const top = Math.max(0, citation.top - padY)
    const bottom = Math.min(source.height, citation.bottom + padY)
    const shift = right - left
    // Remove only the citation's line band, then close the gap so the stem starts
    // naturally after the question number. Other rows and diagrams are untouched.
    context.drawImage(source, right, top, source.width - right, bottom - top, left, top, source.width - right, bottom - top)
    context.fillStyle = '#fff'
    context.fillRect(source.width - shift, top, shift, bottom - top)
    imageData.data.set(context.getImageData(0, 0, source.width, source.height).data)
  }
  const pixels = imageData.data
  const blankRows = Array.from({ length: source.height }, (_, y) => {
    let inkPixels = 0
    for (let x = 0; x < source.width; x += 2) {
      const offset = (y * source.width + x) * 4
      if (pixels[offset + 3] > 16 && (pixels[offset] < 242 || pixels[offset + 1] < 242 || pixels[offset + 2] < 242)) {
        inkPixels += 1
        if (inkPixels > 2) return false
      }
    }
    return true
  })
  const slices = compactBlankRowSlices(blankRows)
  const compactHeight = slices.reduce((sum, slice) => sum + slice.end - slice.start, 0)
  if (compactHeight >= source.height - 4) return citation ? source.toDataURL('image/png') : dataUrl

  const output = document.createElement('canvas')
  output.width = source.width
  output.height = compactHeight
  const outputContext = output.getContext('2d')
  if (!outputContext) return dataUrl
  outputContext.fillStyle = '#fff'
  outputContext.fillRect(0, 0, output.width, output.height)
  let targetY = 0
  slices.forEach((slice) => {
    const height = slice.end - slice.start
    outputContext.drawImage(source, 0, slice.start, source.width, height, 0, targetY, source.width, height)
    targetY += height
  })
  return output.toDataURL('image/png')
}
