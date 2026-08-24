import { compactBlankRowSlices, findTopBlueCitationBounds } from './compactImageCore'

type CompactImageWorkerRequest = { dataUrl?: unknown }
type CompactImageWorkerResponse = { ok: boolean; dataUrl?: string }
type CompactImageWorkerScope = {
  onmessage: ((event: MessageEvent<CompactImageWorkerRequest>) => void) | null
  postMessage: (message: CompactImageWorkerResponse) => void
}

const workerScope = globalThis as unknown as CompactImageWorkerScope

function imageBlobToDataUrl(blob: Blob) {
  return blob.arrayBuffer().then((buffer) => {
    const bytes = new Uint8Array(buffer)
    const chunkSize = 0x8000
    let binary = ''
    for (let offset = 0; offset < bytes.length; offset += chunkSize) {
      binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize))
    }
    return `data:${blob.type || 'image/png'};base64,${btoa(binary)}`
  })
}

async function compactImage(dataUrl: string) {
  if (typeof OffscreenCanvas === 'undefined' || typeof createImageBitmap !== 'function') return dataUrl

  const response = await fetch(dataUrl)
  if (!response.ok) return dataUrl
  const bitmap = await createImageBitmap(await response.blob())
  if (!bitmap.width || !bitmap.height) {
    bitmap.close()
    return dataUrl
  }

  const source = new OffscreenCanvas(bitmap.width, bitmap.height)
  const context = source.getContext('2d', { willReadFrequently: true })
  if (!context) {
    bitmap.close()
    return dataUrl
  }
  context.drawImage(bitmap, 0, 0)
  bitmap.close()

  let imageData = context.getImageData(0, 0, source.width, source.height)
  const citation = findTopBlueCitationBounds(imageData.data, source.width, source.height)
  if (citation) {
    const padX = Math.max(3, Math.round(source.width * 0.004))
    const padY = Math.max(2, Math.round(source.height * 0.01))
    const left = Math.max(0, citation.left - padX)
    const right = Math.min(source.width, citation.right + padX)
    const top = Math.max(0, citation.top - padY)
    const bottom = Math.min(source.height, citation.bottom + padY)
    const shift = right - left
    context.drawImage(source, right, top, source.width - right, bottom - top, left, top, source.width - right, bottom - top)
    context.fillStyle = '#fff'
    context.fillRect(source.width - shift, top, shift, bottom - top)
    imageData = context.getImageData(0, 0, source.width, source.height)
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

  if (compactHeight >= source.height - 4) {
    return citation ? imageBlobToDataUrl(await source.convertToBlob({ type: 'image/png' })) : dataUrl
  }

  const output = new OffscreenCanvas(source.width, compactHeight)
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
  return imageBlobToDataUrl(await output.convertToBlob({ type: 'image/png' }))
}

workerScope.onmessage = (event) => {
  const dataUrl = event.data?.dataUrl
  if (typeof dataUrl !== 'string' || !dataUrl.startsWith('data:image/')) {
    workerScope.postMessage({ ok: false })
    return
  }

  void compactImage(dataUrl)
    .then((result) => workerScope.postMessage({ ok: true, dataUrl: result }))
    .catch(() => workerScope.postMessage({ ok: false }))
}
