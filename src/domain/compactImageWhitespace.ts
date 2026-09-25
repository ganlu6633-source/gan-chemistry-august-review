export { compactBlankRowSlices, findBlankImageRows, findTopBlueCitationBounds } from './compactImageCore'
export type { ImageRowSlice } from './compactImageCore'

import type { ImageRowSlice } from './compactImageCore'

export type CompactImageLayout = { width: number; height: number; slices: ImageRowSlice[] }

type LayoutWorkerResponse = { ok: boolean; width?: number; height?: number; slices?: ImageRowSlice[] }

const WORKER_TIMEOUT_MS = 12_000

function validLayout(response: LayoutWorkerResponse): response is LayoutWorkerResponse & CompactImageLayout {
  if (!response.ok || !Number.isInteger(response.width) || !Number.isInteger(response.height)
    || !response.width || !response.height || !Array.isArray(response.slices) || response.slices.length < 2) return false
  const slices = response.slices
  return slices[0].start === 0 && slices[slices.length - 1].end === response.height
    && slices.every((slice, index) => Number.isInteger(slice.start) && Number.isInteger(slice.end)
      && slice.start >= 0 && slice.end <= response.height! && slice.end > slice.start
      && (index === 0 || slice.start >= slices[index - 1].end))
}

/** Find removable internal blank bands off-thread. The audited source pixels
 * stay unchanged; the UI only masks rows certified blank by the worker. */
export function inspectImageWhitespaceOffThread(dataUrl: string): Promise<CompactImageLayout | null> {
  if (typeof Worker === 'undefined' || typeof OffscreenCanvas === 'undefined' || !dataUrl.startsWith('data:image/')) {
    return Promise.resolve(null)
  }

  return new Promise((resolve) => {
    let worker: Worker
    try {
      worker = new Worker(new URL('./compactImageWhitespace.worker.ts', import.meta.url), { type: 'module' })
    } catch {
      resolve(null)
      return
    }

    let settled = false
    let timeoutId = 0
    const finish = (result: CompactImageLayout | null) => {
      if (settled) return
      settled = true
      window.clearTimeout(timeoutId)
      worker.terminate()
      resolve(result)
    }
    timeoutId = window.setTimeout(() => finish(null), WORKER_TIMEOUT_MS)
    worker.onmessage = (event: MessageEvent<LayoutWorkerResponse>) => {
      const response = event.data
      finish(response && validLayout(response) ? { width: response.width, height: response.height, slices: response.slices } : null)
    }
    worker.onerror = () => finish(null)
    worker.onmessageerror = () => finish(null)
    try {
      worker.postMessage({ dataUrl })
    } catch {
      finish(null)
    }
  })
}
