import { describe, expect, it } from 'vitest'
import { HIGH1_SEMESTER_REMAINING_DAYS } from './high1SemesterRoadmap'

describe('高一必修一学期后段进度', () => {
  it('从已发布的 61 天后连续排到 12 月 11 日，并留出全册回看', () => {
    expect(HIGH1_SEMESTER_REMAINING_DAYS).toHaveLength(30)
    expect(HIGH1_SEMESTER_REMAINING_DAYS[0].date).toBe('2026-11-12')
    expect(HIGH1_SEMESTER_REMAINING_DAYS.at(-1)?.date).toBe('2026-12-11')
    expect(HIGH1_SEMESTER_REMAINING_DAYS.slice(-5).every((day) => day.unit === '全册综合回看')).toBe(true)
    expect(new Set(HIGH1_SEMESTER_REMAINING_DAYS.map((day) => day.date)).size).toBe(30)
  })
})
