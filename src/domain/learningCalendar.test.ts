import { describe, expect, it } from 'vitest'
import type { LearningPlanDay } from './types'
import { calendarPlanStatus, isKnowledgeOnlyFuturePlan, splitCalendarWeeks } from './learningCalendar'

const plan = (date: string, overrides: Partial<LearningPlanDay> = {}): LearningPlanDay => ({
  id: date, studentId: 'student', date, mode: 'REVIEW', title: '化学学习', skillIds: ['J_KY_OXY_H2O2'], knowledgeSummaries: ['氧气制备'],
  estimatedMinutes: 20, isScheduled: true, attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null,
  questionCount: 8, roundLimit: 4, maxQuestionLevel: null, isResolved: false, isComplete: false, roundsRemaining: 4,
  deliveryMode: 'junior_adaptive', juniorSessionStatus: 'not_started', ...overrides,
})

describe('real learning calendar evidence', () => {
  it('does not infer prior learning from an old date or enrollment date', () => {
    expect(calendarPlanStatus(plan('2026-09-01'), '2026-09-12', '2026-09-29')).toBe('还没学过 · 可补学')
    expect(calendarPlanStatus(plan('2026-09-20'), '2026-09-12', '2026-09-29')).toBe('还没学过 · 开始补学')
  })
  it('keeps actual started/completed state ahead of pre-enrollment labels', () => {
    expect(calendarPlanStatus(plan('2026-09-01', { juniorSessionStatus: 'active' }), '2026-09-12', '2026-09-29')).toBe('学习进行中 · 接着练')
    expect(calendarPlanStatus(plan('2026-09-01', { juniorSessionStatus: 'completed', isComplete: true }), '2026-09-12', '2026-09-29')).toBe('学习已完成')
  })
  it('opens only server-authorized future lessons as practice', () => {
    expect(isKnowledgeOnlyFuturePlan(plan('2026-10-31'), '2026-09-29')).toBe(true)
    expect(isKnowledgeOnlyFuturePlan(plan('2026-10-31', { canStudyAhead: true }), '2026-09-29')).toBe(false)
    expect(calendarPlanStatus(plan('2026-10-31', { canStudyAhead: true }), '2026-09-12', '2026-09-29')).toBe('还没学过 · 可提前学习')
  })
  it('groups sparse schedules by calendar week without fabricating missing dates', () => {
    const groups = splitCalendarWeeks([plan('2026-09-29'), plan('2026-09-01'), plan('2026-10-01'), plan('2026-09-06')])
    expect(groups.map((week) => week.map((day) => day.date))).toEqual([['2026-09-01', '2026-09-06'], ['2026-09-29', '2026-10-01']])
  })
})
