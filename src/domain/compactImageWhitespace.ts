export { compactBlankRowSlices, findTopBlueCitationBounds } from './compactImageCore'
export type { ImageBounds, ImageRowSlice } from './compactImageCore'

type CompactImageWorkerResponse = {
  ok: boolean
  dataUrl?: string
}

const WORKER_TIMEOUT_MS = 12_000

function supportsOffThreadImageCompaction() {
  return typeof Worker !== 'undefined' && typeof OffscreenCanvas !== 'undefined'
}

/**
 * Compacts source-image whitespace without running pixel scans or PNG encoding
 * on the browser's main thread. Unsupported browsers and any worker failure keep
 * the audited original image unchanged; they never fall back to synchronous work.
 */
export function compactImageWhitespaceOffThread(dataUrl: string): Promise<string> {
  if (!supportsOffThreadImageCompaction() || !dataUrl.startsWith('data:image/')) {
    return Promise.resolve(dataUrl)
  }

  return new Promise((resolve) => {
    let worker: Worker
    try {
      worker = new Worker(new URL('./compactImageWhitespace.worker.ts', import.meta.url), { type: 'module' })
    } catch {
      resolve(dataUrl)
      return
    }

    let settled = false
    let timeoutId = 0
    const finish = (result: string) => {
      if (settled) return
      settled = true
      window.clearTimeout(timeoutId)
      worker.terminate()
      resolve(result)
    }
    timeoutId = window.setTimeout(() => finish(dataUrl), WORKER_TIMEOUT_MS)

    worker.onmessage = (event: MessageEvent<CompactImageWorkerResponse>) => {
      const response = event.data
      finish(response?.ok && typeof response.dataUrl === 'string' && response.dataUrl.startsWith('data:image/')
        ? response.dataUrl
        : dataUrl)
    }
    worker.onerror = () => finish(dataUrl)
    worker.onmessageerror = () => finish(dataUrl)

    try {
      worker.postMessage({ dataUrl })
    } catch {
      finish(dataUrl)
    }
  })
}

/** Backward-compatible entrypoint used by the existing question-media component. */
export function compactImageWhitespace(dataUrl: string): Promise<string> {
  return compactImageWhitespaceOffThread(dataUrl)
}
