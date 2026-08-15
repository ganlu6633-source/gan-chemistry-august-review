import { describe, expect, it } from 'vitest'
import { compactBlankRowSlices } from './compactImageWhitespace'

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
