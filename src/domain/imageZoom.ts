export type ImageTransform = { scale: number; x: number; y: number }
export type Point = { x: number; y: number }
export const MIN_IMAGE_ZOOM = 0.5
export const MAX_IMAGE_ZOOM = 8

/** Keep the image coordinate under the gesture midpoint stationary while zooming. */
export function zoomImageAt(current: ImageTransform, scale: number, from: Point, to = from): ImageTransform {
  const next = Math.min(MAX_IMAGE_ZOOM, Math.max(MIN_IMAGE_ZOOM, scale))
  const ratio = next / current.scale
  return { scale: next, x: to.x - (from.x - current.x) * ratio, y: to.y - (from.y - current.y) * ratio }
}
