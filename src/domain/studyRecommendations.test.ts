import { describe, expect, it } from 'vitest'
import { recommendStudyTopics } from '../../supabase/functions/chemistry-access/study-recommendations'

const topics = [
  { skillId: 'ions', conceptKey: 'sulfate', freshCount: 3, title: '硫酸根离子' },
  { skillId: 'ions', conceptKey: 'chloride', freshCount: 2, title: '氯离子' },
]

describe('personal study recommendations', () => {
  it('never treats an untouched concept as due review', () => {
    const result = recommendStudyTopics(topics, [], [], new Date('2026-09-25T00:00:00Z'))
    expect(result.map((topic) => topic.reviewPriority)).toEqual([0, 0])
    expect(result[0].answeredCount).toBe(0)
  })

  it('prioritizes an incorrect fine concept without resetting its stable neighbor', () => {
    const result = recommendStudyTopics(topics, [
      { skill_id: 'ions', concept_key: 'sulfate', correct: false, uncertain: false, completed_at: '2026-09-23T00:00:00Z' },
      { skill_id: 'ions', concept_key: 'chloride', correct: true, uncertain: false, completed_at: '2026-09-23T00:00:00Z' },
    ], [{ skill_id: 'ions', next_review_at: '2026-09-24T00:00:00Z', review_interval_index: 2 }], new Date('2026-09-25T00:00:00Z'))
    expect(result[0].reviewPriority).toBeGreaterThan(0)
    expect(result[0].reviewReason).toContain('答错')
    expect(result[1].reviewPriority).toBe(0)
    expect(result[1].reviewDueAt).toBe('2026-09-30T00:00:00.000Z')
  })

  it('uses the recent answer curve and marks review due at the interval', () => {
    const result = recommendStudyTopics([topics[0]], [
      { skill_id: 'ions', concept_key: 'sulfate', correct: true, uncertain: false, completed_at: '2026-09-18T00:00:00Z' },
      { skill_id: 'ions', concept_key: 'sulfate', correct: false, uncertain: false, completed_at: '2026-09-10T00:00:00Z' },
    ], [{ skill_id: 'ions', review_interval_index: 2 }], new Date('2026-09-25T00:00:00Z'))
    expect(result[0].reviewDueAt).toBe('2026-09-25T00:00:00.000Z')
    expect(result[0].reviewPriority).toBeGreaterThan(0)
    expect(result[0].reviewReason).toContain('未稳')
  })
})
