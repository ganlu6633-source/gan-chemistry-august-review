import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { JuniorAdaptivePayload, LearningPlanDay, SessionIdentity, StudentDashboardData } from '../domain/types'
import { StudentApp } from './StudentApp'

const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
const plan: LearningPlanDay = {
  id: 'first-question-plan', studentId: 'isolated-test', date: today, mode: 'REVIEW', title: '制氧原理练习',
  skillIds: ['J_KY_OXY_H2O2'], knowledgeSummaries: ['过氧化氢制氧气'], estimatedMinutes: 20,
  source: 'course', isScheduled: true, attemptCount: 0, firstScore: null, latestScore: null,
  latestCompletedAt: null, questionCount: 8, roundLimit: 4, maxQuestionLevel: null,
  isResolved: false, isComplete: false, roundsRemaining: 4,
  deliveryMode: 'junior_adaptive', juniorSessionStatus: 'not_started',
}
const dashboard: StudentDashboardData = {
  profile: { id: 'isolated-test', displayName: '离线同学', gradeBand: '初三',
    enrollmentStartDate: '2026-09-01', needsInitialDiagnostic: false },
  plans: [plan], skillStates: [], skillDefinitions: [], todayQuestionCount: 8, achievements: [],
}
const payload: JuniorAdaptivePayload = {
  deliveryMode: 'junior_adaptive', plan, cards: [],
  session: { id: 'first-session', status: 'active', initialQuestionTarget: 8, hardQuestionCap: 30,
    recoveryRoundLimit: 3, issuedCount: 1, answeredCount: 0, correctCount: 0 },
  currentStepId: 'first-step', completed: false,
  currentQuestion: { skillId: 'J_KY_OXY_H2O2',
    level: 1, gradeBand: '初三', stem: '过氧化氢分解生成哪两种物质？',
    options: ['水和氧气', '水和氢气', '氢气和氧气', '水和二氧化碳'],
    revisionToken: 'first-revision' },
}

describe('first junior question independent of dashboard and catalog refresh', () => {
  afterEach(() => { cleanup(); vi.unstubAllGlobals(); vi.restoreAllMocks() })

  it.each([false, true])('shows the server-issued first question while unrelated reads stay unresolved (preview=%s)', async previewMode => {
    const actions: string[] = []
    const session: SessionIdentity = { role: previewMode ? 'teacher' : 'student', token: 'offline',
      displayName: '离线同学', expiresAt: '2099-01-01T00:00:00Z' }
    const onDashboard = vi.fn()
    vi.stubGlobal('fetch', vi.fn<typeof fetch>(async (_input, init) => {
      const body = JSON.parse(String(init?.body))
      actions.push(body.action)
      if (body.action === (previewMode ? 'preview_junior_open_session' : 'junior_open_session')) {
        if (previewMode) expect(body.data.studentId).toBe(dashboard.profile.id)
        return new Response(JSON.stringify({ payload }), { status: 200, headers: { 'content-type': 'application/json' } })
      }
      // A stalled directory/dashboard request must not hold the issued question.
      return new Promise<Response>(() => {})
    }))
    render(<StudentApp session={session} initialDashboard={dashboard} onDashboard={onDashboard} previewMode={previewMode} />)
    fireEvent.click(screen.getByRole('button', { name: /学习日历 老师排好的题在这里/ }))
    fireEvent.click(screen.getByRole('button', { name: '开始今日学习' }))
    expect(await screen.findByRole('heading', { name: payload.currentQuestion!.stem })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'A. 水和氧气' })).toBeEnabled()
    expect(screen.queryByLabelText('正在打开题组')).not.toBeInTheDocument()
    expect(actions.filter(action => action.endsWith('junior_open_session'))).toHaveLength(1)
    expect(actions).not.toContain('student_dashboard')
    expect(onDashboard).not.toHaveBeenCalled()
    fireEvent.click(screen.getByRole('button', { name: 'A. 水和氧气' }))
    expect(screen.getByRole('button', { name: '提交答案' })).toBeEnabled()
    expect(actions.some(action => action.includes('submit'))).toBe(false)
  })
})
