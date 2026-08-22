import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { Image as ImageIcon, RefreshCw, X, ZoomIn } from 'lucide-react'
import type { QuestionAssetRef, QuestionSourceInfo, SessionIdentity } from '../domain/types'
import { compactImageWhitespace } from '../domain/compactImageWhitespace'
import { stripLeadingQuestionSource } from '../domain/questionPresentation'
import { loadQuestionAsset, type LoadedQuestionAsset, type QuestionAssetAccessContext } from '../lib/api'
import { readAccessSession } from '../lib/session'
import { ChemText } from './ChemText'

type RenderMode = 'native' | 'image_assist' | 'image_primary'
type SourceAssetRef = QuestionAssetRef

export interface SourceBackedQuestionView {
  id: string
  stem: string
  options: string[]
  sourceInfo?: QuestionSourceInfo | null
  assetRefs?: SourceAssetRef[]
  renderMode?: RenderMode
}

interface QuestionSourceMediaProps {
  question: SourceBackedQuestionView
  /** The parent is responsible for limiting this to high-school REVIEW licensed originals. */
  enabled: boolean
  session?: SessionIdentity
  nativeContent?: ReactNode
  deferLoad?: boolean
  readOnly?: boolean
  showSource?: boolean
  /** Analysis assets are never requested or rendered before answer feedback is visible. */
  feedback?: boolean
  /** Current-round proof. Historical views omit it and rely on persisted evidence. */
  accessContext?: QuestionAssetAccessContext
  onPrimaryReadyChange?: (ready: boolean) => void
  /** Lets a learning flow restore focus to its Enter-driven primary action. */
  onZoomClose?: () => void
}

type AssetLoadState = {
  status: 'idle' | 'loading' | 'ready' | 'error'
  asset?: LoadedQuestionAsset
  message?: string
}

function CompactQuestionImage({ dataUrl, alt, width, height }: { dataUrl: string; alt: string; width?: number; height?: number }) {
  const [displayUrl, setDisplayUrl] = useState(dataUrl)
  useEffect(() => {
    let active = true
    setDisplayUrl(dataUrl)
    void compactImageWhitespace(dataUrl).then((result) => {
      if (active) setDisplayUrl(result)
    })
    return () => { active = false }
  }, [dataUrl])
  return <img src={displayUrl} alt={alt} width={width || undefined} height={displayUrl === dataUrl ? height || undefined : undefined} />
}

const emptyState = (): AssetLoadState => ({ status: 'idle' })

function sourceTitle(source: QuestionSourceInfo) {
  const main = source.exam.trim() || source.title.trim()
  const collection = source.title.trim() && source.title.trim() !== main ? source.title.trim() : ''
  return { main, collection }
}

function sourceDetails(source: QuestionSourceInfo) {
  const rawYear = source.year === null || source.year === undefined ? '' : String(source.year).trim()
  const year = rawYear && !rawYear.endsWith('年') ? `${rawYear}年` : rawYear
  return [year, source.questionNo, source.locator].filter(Boolean)
}

export function QuestionSourceMedia({ question, enabled, session, nativeContent, deferLoad = false, readOnly = false, showSource = true, feedback = false, accessContext, onPrimaryReadyChange, onZoomClose }: QuestionSourceMediaProps) {
  const incomingRefs = question.assetRefs ?? []
  const refsKey = incomingRefs.map((ref) => `${ref.assetId}:${ref.kind}:${ref.sha256}:${ref.width}:${ref.height}:${ref.alt}`).join('|')
  const refsSnapshot = useRef<{ key: string; refs: SourceAssetRef[] }>({ key: refsKey, refs: incomingRefs })
  if (refsSnapshot.current.key !== refsKey) refsSnapshot.current = { key: refsKey, refs: incomingRefs }
  const refs = refsSnapshot.current.refs
  const sourceVersionKey = `${question.id}|${refsKey}|${deferLoad ? 'deferred' : 'eager'}`
  const sourceVersionRef = useRef(sourceVersionKey)
  const problemRefs = useMemo(() => refs.filter((ref) => ref.kind !== 'analysis_image'), [refs])
  const analysisRefs = useMemo(() => refs.filter((ref) => ref.kind === 'analysis_image'), [refs])
  const [assetStates, setAssetStates] = useState<Record<string, AssetLoadState>>(
    () => Object.fromEntries(refs.map((ref) => [ref.assetId, emptyState()])),
  )
  const [loadRequested, setLoadRequested] = useState(!deferLoad)
  const [zoomedAssetId, setZoomedAssetId] = useState<string | null>(null)
  const dialogRef = useRef<HTMLDialogElement>(null)
  const zoomTriggerRef = useRef<HTMLButtonElement | null>(null)
  const renderMode = question.renderMode ?? 'native'

  useEffect(() => {
    // Parent dashboard refreshes often recreate the question/ref objects.  Keep a
    // successfully requested image when the immutable source version is unchanged.
    if (sourceVersionRef.current === sourceVersionKey) return
    sourceVersionRef.current = sourceVersionKey
    setAssetStates(Object.fromEntries(refs.map((ref) => [ref.assetId, emptyState()])))
    setLoadRequested(!deferLoad)
    setZoomedAssetId(null)
    zoomTriggerRef.current = null
  }, [deferLoad, refs, sourceVersionKey])

  const closeZoom = useCallback(() => setZoomedAssetId(null), [])

  const requestAsset = useCallback(async (ref: SourceAssetRef) => {
    const activeSession = session ?? readAccessSession()
    if (!activeSession) {
      setAssetStates((current) => ({ ...current, [ref.assetId]: { status: 'error', message: '登录状态已失效，请重新进入后再加载原题图。' } }))
      return
    }
    setAssetStates((current) => ({ ...current, [ref.assetId]: { status: 'loading' } }))
    try {
      const result = await loadQuestionAsset(activeSession, question.id, ref.assetId, ref.kind === 'analysis_image' ? 'analysis' : 'question', accessContext)
      if (result.asset.sha256 !== ref.sha256 || result.asset.width !== ref.width || result.asset.height !== ref.height || !result.asset.dataUrl.startsWith('data:image/')) {
        throw new Error('原题图片完整性校验未通过，请重试或联系甘老师。')
      }
      setAssetStates((current) => ({ ...current, [ref.assetId]: { status: 'ready', asset: result.asset } }))
    } catch (reason) {
      setAssetStates((current) => ({
        ...current,
        [ref.assetId]: { status: 'error', message: reason instanceof Error ? reason.message : '原题图暂时无法加载。' },
      }))
    }
  }, [accessContext, question.id, session])

  useEffect(() => {
    if (!enabled || !loadRequested) return
    const requestedRefs = [
      ...(loadRequested ? problemRefs : []),
      ...(feedback && (!deferLoad || loadRequested) ? analysisRefs : []),
    ]
    requestedRefs.forEach((ref) => {
      const state = assetStates[ref.assetId]
      if (!state || state.status === 'idle') void requestAsset(ref)
    })
  }, [analysisRefs, assetStates, deferLoad, enabled, feedback, loadRequested, problemRefs, requestAsset])

  const primaryReady = renderMode !== 'image_primary'
    || (problemRefs.length > 0 && problemRefs.every((ref) => assetStates[ref.assetId]?.status === 'ready'))

  useEffect(() => {
    onPrimaryReadyChange?.(primaryReady)
  }, [onPrimaryReadyChange, primaryReady, question.id])

  useEffect(() => {
    const dialog = dialogRef.current
    if (!dialog) return
    if (zoomedAssetId) {
      if (!dialog.open) {
        if (typeof dialog.showModal === 'function') dialog.showModal()
        else dialog.setAttribute('open', '')
      }
    } else if (dialog.open) {
      if (typeof dialog.close === 'function') dialog.close()
      else dialog.removeAttribute('open')
      const restoreFocus = () => {
        if (onZoomClose) onZoomClose()
        else zoomTriggerRef.current?.focus()
      }
      if (typeof requestAnimationFrame === 'function') requestAnimationFrame(restoreFocus)
      else restoreFocus()
    }
  }, [onZoomClose, zoomedAssetId])

  if (!enabled) return <>{nativeContent}</>

  const source = question.sourceInfo
  const title = source ? sourceTitle(source) : null
  const zoomedRef = refs.find((ref) => ref.assetId === zoomedAssetId)
  const zoomedAsset = zoomedAssetId ? assetStates[zoomedAssetId]?.asset : undefined

  const assetGallery = (galleryRefs: SourceAssetRef[], analysis = false) => galleryRefs.length > 0 ? <div className={`source-asset-gallery ${analysis ? 'source-analysis-gallery' : ''}`} aria-live="polite">
    {galleryRefs.map((ref, index) => {
      const state = assetStates[ref.assetId] ?? emptyState()
      const visibleAlt = showSource ? ref.alt : analysis ? '教师审核用原题解析图' : '本题原题题面图'
      if (state.status === 'ready' && state.asset) return <figure className="source-question-image" key={ref.assetId}>
        <button type="button" className="source-image-zoom" data-question-media-control onClick={(event) => { zoomTriggerRef.current = event.currentTarget; setZoomedAssetId(ref.assetId) }} aria-label={`放大查看${visibleAlt}`}>
          <CompactQuestionImage dataUrl={state.asset.dataUrl} alt={visibleAlt} width={ref.width} height={ref.height} />
          <span><ZoomIn />点击放大</span>
        </button>
        {galleryRefs.length > 1 && <figcaption>{analysis ? '原题解析图' : '原题图'} {index + 1}/{galleryRefs.length}</figcaption>}
      </figure>
      if (state.status === 'loading') return <div className="source-image-loading" role="status" key={ref.assetId}><span /><ImageIcon /><b>{analysis ? '正在安全加载原题解析图…' : '正在安全加载原题图…'}</b></div>
      if (state.status === 'error') return <div className={`source-image-error ${!analysis && renderMode === 'image_primary' ? 'is-blocking' : ''}`} role="alert" key={ref.assetId}>
        <ImageIcon /><div><b>{analysis ? '原题解析图暂时没有加载成功' : renderMode === 'image_primary' ? '原题主图加载失败，暂不能提交' : '辅助图暂时没有加载成功'}</b><p>{state.message}</p></div>
        <button type="button" className="secondary-button" data-question-media-control onClick={() => void requestAsset(ref)}><RefreshCw />重试</button>
      </div>
      return null
    })}
  </div> : !analysis && renderMode === 'image_primary' ? <div className="source-image-error is-blocking" role="alert"><ImageIcon /><div><b>原题主图尚未通过审核</b><p>为避免缺图误答，本题暂不能提交，请联系甘老师。</p></div></div> : null

  return <section className={`question-source-media mode-${renderMode} ${readOnly ? 'is-readonly' : ''}`} data-question-source-media>
    {showSource && source && title ? <header className="source-citation" aria-label="原题来源">
      <span>原题来源</span>
      <div><b>{title.main}</b>{title.collection && <p>{title.collection}</p>}<small>{sourceDetails(source).join(' · ')}</small></div>
    </header> : showSource ? <div className="source-citation source-citation-missing" role="alert"><span>来源待核</span><div><b>这道原题的来源信息尚未完整</b></div></div> : null}

    {deferLoad && !loadRequested && refs.length > 0 ? <button type="button" className="source-load-button" data-question-media-control onClick={() => setLoadRequested(true)}><ImageIcon />加载当时的原题图{analysisRefs.length > 0 ? '与解析图' : ''}</button> : null}

    {renderMode === 'image_assist' ? <>{nativeContent}{loadRequested && assetGallery(problemRefs)}</> : null}
    {renderMode === 'native' ? <>{nativeContent}{loadRequested && problemRefs.length > 0 ? assetGallery(problemRefs) : null}</> : null}
    {renderMode === 'image_primary' ? <>{loadRequested && assetGallery(problemRefs)}{showSource && <details className="source-transcription">
      <summary data-question-media-control>查看文字辅助稿（公式、图示以原题图为准）</summary>
      <div><p><ChemText>{stripLeadingQuestionSource(question.stem)}</ChemText></p>{question.options.length > 0 && <ol>{question.options.map((option, index) => <li key={`${index}-${option}`}><b>{String.fromCharCode(65 + index)}.</b><ChemText>{option}</ChemText></li>)}</ol>}</div>
    </details>}</> : null}

    {feedback && analysisRefs.length > 0 && (!deferLoad || loadRequested) ? <section className="source-analysis-media" aria-label="原题解析图"><h3>原题解析图</h3>{assetGallery(analysisRefs, true)}</section> : null}

    <dialog ref={dialogRef} className="source-image-dialog" data-question-media-dialog aria-label="放大查看原题图" onCancel={(event) => { event.preventDefault(); closeZoom() }} onClick={(event) => { if (event.target === event.currentTarget) closeZoom() }}>
      <div role="document">
        <header><b>原题大图</b><button type="button" data-question-media-control onClick={closeZoom} aria-label="关闭原题大图"><X /></button></header>
        {zoomedAsset && zoomedRef && <CompactQuestionImage dataUrl={zoomedAsset.dataUrl} alt={`放大查看：${showSource ? zoomedRef.alt : zoomedRef.kind === 'analysis_image' ? '教师审核用原题解析图' : '本题原题题面图'}`} width={zoomedRef.width} height={zoomedRef.height} />}
      </div>
    </dialog>
  </section>
}
