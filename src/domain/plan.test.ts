import { describe, expect, it } from 'vitest'
import { appendAttempt, planDayStatus, scoreComparison } from './plan'
import type { LearningAttempt, LearningPlanDay } from './types'

const plan: LearningPlanDay = { id: 'p', studentId: 's', date: '2026-08-10', mode: 'REVIEW', title: '复习', skillIds: [], estimatedMinutes: 5, source: 'memory', isScheduled: true }
const attempt = (id: string, kind: 'scheduled'|'review', sequence: number, score: number): LearningAttempt => ({ id, studentId: 's', planDayId: 'p', attemptKind: kind, sequence, mode: 'REVIEW', startedAt: '2026-08-10T08:00:00Z', completedAt: '2026-08-10T08:05:00Z', answers: [], firstScore: score })

describe('learning plan history', () => {
  it('marks pre-enrollment days as optional rather than unfinished', () => {
    expect(planDayStatus(plan, '2026-08-11', [], '2026-08-12')).toBe('before_enrollment')
  })
  it('keeps the first scheduled result and appends review attempts', () => {
    const first = attempt('a1','scheduled',0,3)
    const next = appendAttempt([first], attempt('a2','scheduled',0,5))
    expect(next[0]).toEqual(first)
    expect(next[1].attemptKind).toBe('review')
    expect(scoreComparison(next, 'p')).toEqual({ first: 3, latest: 5, improvedBy: 2 })
  })
})
