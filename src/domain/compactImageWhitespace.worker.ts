import { compactBlankRowSlices, findBlankImageRows, type ImageRowSlice } from './compactImageCore'

type LayoutRequest = { dataUrl?: unknown }
type LayoutResponse = { ok: boolean; width?: number; height?: number; slices?: ImageRowSlice[] }
type WorkerScope = {
  onmessage: ((event: MessageEvent<LayoutRequest>) => void) | null
  postMessage: (message: LayoutResponse) => void
}

const workerScope = globalThis as unknown as WorkerScope

async function inspectImage(dataUrl: string): Promise<LayoutResponse> {
  if (typeof OffscreenCanvas === 'undefined' || typeof createImageBitmap !== 'function') return { ok: false }
  const response = await fetch(dataUrl)
  if (!response.ok) return { ok: false }
  const bitmap = await createImageBitmap(await response.blob())
  try {
    if (!bitmap.width || !bitmap.height) return { ok: false }
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height)
    const context = canvas.getContext('2d', { willReadFrequently: true })
    if (!context) return { ok: false }
    context.drawImage(bitmap, 0, 0)
    const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data
    const slices = compactBlankRowSlices(findBlankImageRows(pixels, canvas.width, canvas.height))
    return { ok: true, width: canvas.width, height: canvas.height, slices }
  } finally {
    bitmap.close()
  }
}

workerScope.onmessage = (event) => {
  const dataUrl = event.data?.dataUrl
  if (typeof dataUrl !== 'string' || !dataUrl.startsWith('data:image/')) {
    workerScope.postMessage({ ok: false })
    return
  }
  void inspectImage(dataUrl)
    .then((result) => workerScope.postMessage(result))
    .catch(() => workerScope.postMessage({ ok: false }))
}
