import { describe, expect, it } from 'vitest'
import { LECTURE_BOOKS, LECTURE_SECTIONS, lectureUrl } from './lectureCatalog'

describe('lecture navigation', () => {
  it('indexes every handout inside its actual PDF page range', () => {
    const pages = { h1: 209, 'h2-basic': 143, 'h2-hard': 145, h3: 325 }
    expect(new Set(LECTURE_SECTIONS.map((item) => item.book))).toEqual(new Set(Object.keys(LECTURE_BOOKS)))
    for (const item of LECTURE_SECTIONS) {
      expect(item.page).toBeGreaterThanOrEqual(1)
      expect(item.endPage).toBeGreaterThanOrEqual(item.page)
      expect(item.endPage).toBeLessThanOrEqual(pages[item.book])
      expect(lectureUrl(item)).toContain(`${LECTURE_BOOKS[item.book].file}#page=${item.page}`)
    }
    expect(LECTURE_SECTIONS.filter((item) => item.grade === '高一')).toHaveLength(16)
    expect(LECTURE_SECTIONS.filter((item) => item.grade === '高二')).toHaveLength(20)
    expect(LECTURE_SECTIONS.filter((item) => item.grade === '高三')).toHaveLength(14)
  })
})
