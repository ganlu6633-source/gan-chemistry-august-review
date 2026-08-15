import { describe, expect, it } from 'vitest'
import { compactBlankRowSlices, findTopBlueCitationBounds } from './compactImageWhitespace'

describe('compactBlankRowSlices', () => {
  it('reduces a large internal white band but preserves both content regions', () => {
    const rows = [...Array(40).fill(false), ...Array(180).fill(true), ...Array(50).fill(false)]
    expect(compactBlankRowSlices(rows)).toEqual([{ start: 0, end: 54 }, { start: 206, end: 270 }])
  })

  it('does not compress ordinary line spacing', () => {
    const rows = [...Array(20).fill(false), ...Array(20).fill(true), ...Array(20).fill(false)]
    expect(compactBlankRowSlices(rows)).toEqual([{ start: 0, end: 60 }])
  })
})

describe('findTopBlueCitationBounds', () => {
  it('finds a source-blue text cluster in the first line', () => {
    const width = 120
    const height = 60
    const pixels = new Uint8ClampedArray(width * height * 4).fill(255)
    for (let y = 4; y < 12; y += 1) for (let x = 20; x < 58; x += 1) {
      const offset = (y * width + x) * 4
      pixels[offset] = 0
      pixels[offset + 1] = 112
      pixels[offset + 2] = 205
      pixels[offset + 3] = 255
    }
    expect(findTopBlueCitationBounds(pixels, width, height)).toEqual({ left: 20, top: 4, right: 58, bottom: 12 })
  })

  it('ignores black text and isolated blue pixels', () => {
    const pixels = new Uint8ClampedArray(80 * 40 * 4).fill(255)
    expect(findTopBlueCitationBounds(pixels, 80, 40)).toBeNull()
  })
})
