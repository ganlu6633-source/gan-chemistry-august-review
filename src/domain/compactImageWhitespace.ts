export type ImageRowSlice = { start: number; end: number }

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
  const pixels = context.getImageData(0, 0, source.width, source.height).data
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
  if (compactHeight >= source.height - 4) return dataUrl

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
