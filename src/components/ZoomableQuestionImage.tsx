import { useEffect, useRef, useState, type PointerEvent } from 'react'
import { MAX_IMAGE_ZOOM, MIN_IMAGE_ZOOM, zoomImageAt, type ImageTransform, type Point } from '../domain/imageZoom'

const initialTransform: ImageTransform = { scale: 1, x: 0, y: 0 }

export function ZoomableQuestionImage({ dataUrl, alt, width, height }: { dataUrl: string; alt: string; width: number; height: number }) {
  const viewport = useRef<HTMLDivElement>(null)
  const pointers = useRef(new Map<number, Point>())
  const transform = useRef(initialTransform)
  const [view, setView] = useState(initialTransform)
  const [size, setSize] = useState({ width: 0, height: 0 })
  const fit = Math.min(size.width / width, size.height / height) || 1

  function update(next: ImageTransform) {
    transform.current = next
    setView(next)
  }

  useEffect(() => {
    const element = viewport.current
    if (!element) return
    const measure = () => {
      setSize({ width: element.clientWidth, height: element.clientHeight })
      pointers.current.clear()
      transform.current = initialTransform
      setView(initialTransform)
    }
    measure()
    const observer = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(measure)
    observer?.observe(element)
    // A non-passive listener prevents page zoom/scroll while using the image.
    const wheel = (event: WheelEvent) => {
      event.preventDefault()
      const rect = element.getBoundingClientRect()
      const delta = event.deltaY * (event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? rect.height : 1)
      update(zoomImageAt(transform.current, transform.current.scale * Math.exp(-delta * 0.002),
        { x: event.clientX - rect.left - rect.width / 2, y: event.clientY - rect.top - rect.height / 2 }))
    }
    element.addEventListener('wheel', wheel, { passive: false })
    return () => { observer?.disconnect(); element.removeEventListener('wheel', wheel) }
  }, [dataUrl])

  function point(event: PointerEvent<HTMLDivElement>): Point {
    const rect = event.currentTarget.getBoundingClientRect()
    return { x: event.clientX - rect.left - rect.width / 2, y: event.clientY - rect.top - rect.height / 2 }
  }
  function move(event: PointerEvent<HTMLDivElement>) {
    if (!pointers.current.has(event.pointerId)) return
    const before = [...pointers.current.values()]
    pointers.current.set(event.pointerId, point(event))
    const after = [...pointers.current.values()]
    if (before.length === 1) {
      update({ ...transform.current, x: transform.current.x + after[0].x - before[0].x, y: transform.current.y + after[0].y - before[0].y })
    } else {
      const midpoint = (p: Point[]) => ({ x: (p[0].x + p[1].x) / 2, y: (p[0].y + p[1].y) / 2 })
      const distance = (p: Point[]) => Math.hypot(p[0].x - p[1].x, p[0].y - p[1].y)
      if (distance(before) > 0) update(zoomImageAt(transform.current, transform.current.scale * distance(after) / distance(before), midpoint(before), midpoint(after)))
    }
  }
  function release(event: PointerEvent<HTMLDivElement>) {
    pointers.current.delete(event.pointerId)
  }
  const changeZoom = (scale: number) => update(zoomImageAt(transform.current, scale, { x: 0, y: 0 }))

  return <div className="source-image-viewer">
    <div ref={viewport} className="source-image-viewport" aria-label="原题图片缩放区域"
      onPointerDown={(event) => {
        if (event.pointerType === 'mouse' && event.button !== 0) return
        event.currentTarget.setPointerCapture?.(event.pointerId)
        pointers.current.set(event.pointerId, point(event))
      }} onPointerMove={move} onPointerUp={release} onPointerCancel={release} onLostPointerCapture={release}
      onDoubleClick={() => view.scale > 1 ? update(initialTransform) : changeZoom(2)}>
      <img src={dataUrl} alt={alt} width={width} height={height} draggable={false}
        style={{ width: width * fit, height: height * fit, transform: `translate(-50%, -50%) translate(${view.x}px, ${view.y}px) scale(${view.scale})` }} />
    </div>
    <div className="source-image-tools" data-question-media-control>
      <span>双指缩放 · 拖动查看 · 滚轮缩放</span>
      <div>
        <button type="button" aria-label="缩小原题图" disabled={view.scale <= MIN_IMAGE_ZOOM} onClick={() => changeZoom(view.scale / 1.25)}>−</button>
        <input aria-label="原题图缩放比例" type="range" min={MIN_IMAGE_ZOOM} max={MAX_IMAGE_ZOOM} step="any" value={view.scale} onChange={(event) => changeZoom(Number(event.target.value))} />
        <output>{Math.round(view.scale * 100)}%</output>
        <button type="button" aria-label="放大原题图" disabled={view.scale >= MAX_IMAGE_ZOOM} onClick={() => changeZoom(view.scale * 1.25)}>＋</button>
        <button type="button" className="source-image-fit" onClick={() => update(initialTransform)}>适应屏幕</button>
      </div>
    </div>
  </div>
}
