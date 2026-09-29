import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { LearningPlanDay, SessionIdentity, StudentDashboardData } from '../domain/types'
import { StudentApp } from './StudentApp'

vi.mock('./JuniorAdaptiveSession', () => ({ JuniorAdaptiveSession: () => <div data-testid="opened-junior-lesson">课程已打开</div> }))

const plans: LearningPlanDay[] = Array.from({ length: 61 }, (_, offset) => {
  const date = new Date(Date.UTC(2026, 8, 1 + offset)).toISOString().slice(0, 10)
  return { id: `plan-${date}`, studentId: 'student-1', date, mode: 'REVIEW', title: `化学课程 ${date}`, skillIds: ['J_KY_OXY_H2O2'], knowledgeSummaries: ['氧气制备'],
    estimatedMinutes: 20, isScheduled: true, attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null,
    questionCount: 8, roundLimit: 4, maxQuestionLevel: null, isResolved: false, isComplete: false, roundsRemaining: 4,
    deliveryMode: 'junior_adaptive', juniorSessionStatus: 'not_started', canStudyAhead: true }
})
const dashboard: StudentDashboardData = {
  profile: { id: 'student-1', displayName: '测试学生', gradeBand: '初三', enrollmentStartDate: '2026-09-12', needsInitialDiagnostic: false },
  plans, skillStates: [], skillDefinitions: [], todayQuestionCount: 8, achievements: [],
}

describe('assigned September and October calendar access', () => {
  afterEach(() => { cleanup(); vi.useRealTimers(); vi.unstubAllGlobals(); vi.restoreAllMocks() })

  it.each([false, true])('shows the same 61 real days and opens a missed September lesson (teacher preview=%s)', async (previewMode) => {
    vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date('2026-09-29T04:00:00Z'))
    const requests: Array<{ action: string; data: { planId?: string; studentId?: string } }> = []
    vi.stubGlobal('fetch', vi.fn(async (_url, init) => {
      const request = JSON.parse(String(init?.body)); requests.push(request)
      return new Response(JSON.stringify(request.action === 'self_study_catalog' ? { catalog: { topics: [] } } : { payload: {} }), { status: 200 })
    }))
    const session: SessionIdentity = { role: previewMode ? 'teacher' : 'student', token: 'session', displayName: '测试', expiresAt: '2099-01-01T00:00:00Z' }
    render(<StudentApp session={session} initialDashboard={dashboard} onDashboard={vi.fn()} previewMode={previewMode} />)
    fireEvent.click(screen.getByRole('button', { name: /学习日历 老师排好的题在这里/ }))
    expect(screen.getByRole('button', { name: '全部日期 · 61 天' })).toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: /^2026-\d\d-\d\d · 化学课程/ })).toHaveLength(61)
    fireEvent.click(screen.getByRole('button', { name: /2026-09-01 · 化学课程 .*还没学过 · 可补学/ }))
    await waitFor(() => expect(screen.getByTestId('opened-junior-lesson')).toBeInTheDocument())
    const open = requests.find((request) => request.action === (previewMode ? 'preview_junior_open_session' : 'junior_open_session'))
    expect(open?.data.planId).toBe('plan-2026-09-01')
    if (previewMode) expect(open?.data.studentId).toBe('student-1')
    expect(requests.some((request) => request.action === 'future_plan_preview')).toBe(false)
  })

  it.each([false, true])('lets the student choose an authorized October lesson (teacher preview=%s)', async (previewMode) => {
    vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date('2026-09-29T04:00:00Z'))
    const actions: string[] = []
    vi.stubGlobal('fetch', vi.fn(async (_url, init) => {
      const request = JSON.parse(String(init?.body)); actions.push(request.action)
      if (request.action !== 'self_study_catalog') expect(request.data.planId).toBe('plan-2026-10-31')
      return new Response(JSON.stringify(request.action === 'self_study_catalog' ? { catalog: { topics: [] } } : { payload: {} }), { status: 200 })
    }))
    const session: SessionIdentity = { role: previewMode ? 'teacher' : 'student', token: 'session', displayName: '测试', expiresAt: '2099-01-01T00:00:00Z' }
    render(<StudentApp session={session} initialDashboard={dashboard} onDashboard={vi.fn()} previewMode={previewMode} />)
    fireEvent.click(screen.getByRole('button', { name: /学习日历 老师排好的题在这里/ }))
    fireEvent.click(screen.getByRole('button', { name: '10 月' }))
    expect(screen.queryByRole('button', { name: /2026-09-01 · 化学课程/ })).not.toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: /^2026-10-\d\d · 化学课程/ })).toHaveLength(31)
    fireEvent.click(screen.getByRole('button', { name: /2026-10-31 · 化学课程 .*可提前学习/ }))
    await waitFor(() => expect(screen.getByTestId('opened-junior-lesson')).toBeInTheDocument())
    expect(actions).toContain(previewMode ? 'preview_junior_open_session' : 'junior_open_session')
    expect(actions).not.toContain('future_plan_preview')
  })
})
