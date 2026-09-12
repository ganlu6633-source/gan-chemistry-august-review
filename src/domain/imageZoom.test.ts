import { describe, expect, it } from 'vitest'
import { zoomImageAt } from './imageZoom'

describe('continuous image zoom', () => {
  it('keeps an off-centre image point under the fingers as they spread and move', () => {
    const next = zoomImageAt({ scale: 1.2, x: 40, y: -20 }, 2.34, { x: 100, y: 80 }, { x: 110, y: 95 })
    expect(next.scale).toBe(2.34)
    expect((110 - next.x) / next.scale).toBeCloseTo((100 - 40) / 1.2)
    expect((95 - next.y) / next.scale).toBeCloseTo((80 + 20) / 1.2)
  })
  it('clamps extreme wheel/pinch input while preserving its focal point', () => {
    const current = { scale: 2, x: 10, y: 20 }
    for (const [requested, expected] of [[10000, 8], [0.001, 0.5]]) {
      const next = zoomImageAt(current, requested, { x: 70, y: -30 })
      expect(next.scale).toBe(expected)
      expect((70 - next.x) / next.scale).toBeCloseTo(30)
      expect((-30 - next.y) / next.scale).toBeCloseTo(-25)
    }
  })
})
