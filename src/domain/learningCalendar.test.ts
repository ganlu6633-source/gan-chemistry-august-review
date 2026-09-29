import { describe, expect, it } from 'vitest'
import type { LearningPlanDay } from './types'
import { calendarPlanProgress, calendarPlanShortStatus, calendarPlanStatus, isKnowledgeOnlyFuturePlan, splitCalendarWeeks } from './learningCalendar'

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
    expect(calendarPlanStatus(plan('2026-09-01', { juniorSessionStatus: 'completed', isComplete: true }), '2026-09-12', '2026-09-29')).toBe('学习已完成 · 可复习')
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
  it('uses saved partial answers to label unfinished high-school rounds without inventing completion', () => {
    const partial = plan('2026-09-01', { deliveryMode: 'legacy_round', hasStarted: true })
    expect(calendarPlanProgress(partial)).toBe('in_progress')
    expect(calendarPlanStatus(partial, '2026-09-12', '2026-09-29')).toBe('学习进行中 · 接着练')
    expect(calendarPlanShortStatus(partial, '2026-09-29')).toBe('继续学')
    expect(calendarPlanProgress({ ...partial, hasStarted: false })).toBe('not_started')
  })
  it.each(['junior_adaptive', 'legacy_round'] as const)('gives mobile and desktop the same confirmed completion state for %s', (deliveryMode) => {
    const completed = plan('2026-09-01', { deliveryMode, isComplete: true })
    expect(calendarPlanProgress(completed)).toBe('completed')
    expect(calendarPlanStatus(completed, '2026-09-12', '2026-09-29')).toContain('可复习')
    expect(calendarPlanShortStatus(completed, '2026-09-29')).toBe('可复习')
  })
  it('keeps suspended junior progress visible without claiming the lesson was completed', () => {
    const blocked = plan('2026-09-01', { hasStarted: true, juniorSessionStatus: 'blocked' })
    expect(calendarPlanProgress(blocked)).toBe('blocked')
    expect(calendarPlanStatus(blocked, '2026-09-12', '2026-09-29')).toContain('进度已保留')
    expect(calendarPlanShortStatus(blocked, '2026-09-29')).toBe('待修复')
  })
})
