import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
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

function openedPayload(planId: string) {
  return { deliveryMode: 'junior_adaptive', plan: plans.find(plan => plan.id === planId), cards: [],
    session: { id: `session-${planId}`, status: 'active', initialQuestionTarget: 8, hardQuestionCap: 30,
      issuedCount: 0, answeredCount: 0, correctCount: 0 }, currentQuestion: null, completed: false }
}

function renderMobileStudent(previewMode = false) {
  vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date('2026-09-29T04:00:00Z'))
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {})
  const fetchMock = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
    const request = JSON.parse(String(init?.body))
    if (request.action === 'learning_record' || request.action === 'student_learning_record') return new Promise<Response>(() => {})
    return new Response(JSON.stringify(request.action === 'self_study_catalog' ? { catalog: { topics: [] } } : { payload: openedPayload(request.data.planId) }), { status: 200 })
  })
  vi.stubGlobal('fetch', fetchMock)
  const session: SessionIdentity = { role: previewMode ? 'teacher' : 'student', token: 'session', displayName: '测试', expiresAt: '2099-01-01T00:00:00Z' }
  const result = render(<StudentApp session={session} initialDashboard={dashboard} onDashboard={vi.fn()} previewMode={previewMode} />)
  return { ...result, fetchMock }
}

describe('assigned September and October calendar access', () => {
  afterEach(() => { cleanup(); vi.useRealTimers(); vi.unstubAllGlobals(); vi.restoreAllMocks() })

  it.each([false, true])('shows the same 61 real days and opens a missed September lesson (teacher preview=%s)', async (previewMode) => {
    vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date('2026-09-29T04:00:00Z'))
    const requests: Array<{ action: string; data: { planId?: string; studentId?: string } }> = []
    vi.stubGlobal('fetch', vi.fn(async (_url, init) => {
      const request = JSON.parse(String(init?.body)); requests.push(request)
      return new Response(JSON.stringify(request.action === 'self_study_catalog' ? { catalog: { topics: [] } } : { payload: openedPayload(request.data.planId) }), { status: 200 })
    }))
    const session: SessionIdentity = { role: previewMode ? 'teacher' : 'student', token: 'session', displayName: '测试', expiresAt: '2099-01-01T00:00:00Z' }
    render(<StudentApp session={session} initialDashboard={dashboard} onDashboard={vi.fn()} previewMode={previewMode} />)
    fireEvent.click(screen.getByRole('button', { name: /学习日历 老师排好的题在这里/ }))
    expect(screen.getByRole('button', { name: '全部日期' })).toBeInTheDocument()
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
      return new Response(JSON.stringify(request.action === 'self_study_catalog' ? { catalog: { topics: [] } } : { payload: openedPayload(request.data.planId) }), { status: 200 })
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

  it('keeps four mobile tabs and restores keyboard focus when More closes', async () => {
    renderMobileStudent()
    const navigation = screen.getByRole('navigation', { name: '手机学习导航' })
    expect(within(navigation).getAllByRole('button')).toHaveLength(4)
    const more = within(navigation).getByRole('button', { name: '手机导航：更多' })
    fireEvent.click(more)
    expect(document.body.style.overflow).toBe('hidden')
    const dialog = screen.getByRole('dialog', { name: '更多学习入口' })
    const close = within(dialog).getByRole('button', { name: '关闭更多学习入口' })
    expect(close).toHaveFocus()
    fireEvent.keyDown(close, { key: 'Tab', shiftKey: true })
    const last = within(dialog).getByRole('button', { name: '账户设置' })
    expect(last).toHaveFocus()
    fireEvent.keyDown(last, { key: 'Tab' })
    expect(close).toHaveFocus()
    fireEvent.keyDown(close, { key: 'Escape' })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(more).toHaveFocus()
    expect(more).toHaveAttribute('aria-expanded', 'false')
    expect(document.body.style.overflow).toBe('')
    await waitFor(() => expect(screen.queryByText('正在读取原题目录…')).not.toBeInTheDocument())
  })

  it.each(['跟着进度走', '题型训练场', '复习雷达', '能力地图', '我的战绩', '账户设置'])('can reach %s from More and closes the sheet', async (label) => {
    renderMobileStudent()
    fireEvent.click(screen.getByRole('button', { name: '手机导航：更多' }))
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: label }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(within(screen.getByLabelText('学生导航')).getByRole('button', { name: label })).toHaveClass('active')
    expect(screen.getByRole('button', { name: '手机导航：更多' })).toHaveAttribute('aria-expanded', 'false')
    expect(window.scrollTo).toHaveBeenCalledWith({ top: 0, left: 0, behavior: 'auto' })
    await waitFor(() => expect(screen.getByRole('button', { name: '手机导航：更多' })).toHaveClass('active'))
  })

  it('keeps account changes out of the teacher preview menu', async () => {
    renderMobileStudent(true)
    fireEvent.click(screen.getByRole('button', { name: '手机导航：更多' }))
    expect(within(screen.getByRole('dialog')).queryByRole('button', { name: '账户设置' })).not.toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('dialog')).toBeInTheDocument())
  })

  it('closes a mobile sheet on a desktop resize and restores the existing scroll setting', async () => {
    const events = document.createElement('div')
    const viewport = { matches: true, addEventListener: events.addEventListener.bind(events), removeEventListener: events.removeEventListener.bind(events) }
    vi.stubGlobal('matchMedia', vi.fn(() => viewport))
    document.body.style.overflow = 'clip'
    renderMobileStudent()
    fireEvent.click(screen.getByRole('button', { name: '手机导航：更多' }))
    expect(document.body.style.overflow).toBe('hidden')
    viewport.matches = false
    const change = new Event('change')
    Object.defineProperty(change, 'matches', { value: false })
    fireEvent(events, change)
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(document.body.style.overflow).toBe('clip')
    document.body.style.overflow = ''
  })

  it('opens the current week on mobile and lets an earlier week expand for real makeup study', async () => {
    const { container, fetchMock } = renderMobileStudent()
    // Apply the responsive visibility contract without pretending jsdom lays out
    // a viewport. Desktop tests above still see all 61 day buttons.
    const visibility = document.createElement('style')
    visibility.textContent = '.week-grid[data-mobile-expanded="false"] { display: none; }'
    container.append(visibility)
    fireEvent.click(screen.getByRole('button', { name: '手机导航：学习日历' }))
    expect(container.querySelectorAll('.plan-day')).toHaveLength(61)
    expect(container.querySelectorAll('.week-grid[data-mobile-expanded="true"]')).toHaveLength(1)
    expect(screen.getByRole('button', { name: /2026-09-29 · 化学课程/ })).toBeVisible()
    expect(screen.queryByRole('button', { name: /2026-09-01 · 化学课程/ })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /^9月1日—9月6日/ }))
    const missed = screen.getByRole('button', { name: /2026-09-01 · 化学课程/ })
    expect(missed.querySelector('.plan-day-mobile-status')).toHaveTextContent('可补学')
    fireEvent.click(missed)
    await waitFor(() => expect(screen.getByTestId('opened-junior-lesson')).toBeInTheDocument())
    expect(fetchMock.mock.calls.some(([, init]) => {
      const request = JSON.parse(String(init?.body))
      return request.action === 'junior_open_session' && request.data.planId === 'plan-2026-09-01'
    })).toBe(true)
  })

  it('opens the first week after changing months and returns to today without losing old dates', async () => {
    const { container } = renderMobileStudent()
    expect(container.querySelector('.role-content')).toHaveClass('has-study-choice')
    fireEvent.click(screen.getByRole('button', { name: '手机导航：学习日历' }))
    expect(container.querySelector('.role-content')).not.toHaveClass('has-study-choice')
    fireEvent.click(screen.getByRole('button', { name: '10 月' }))
    const firstWeek = container.querySelector('.mobile-week-toggle')
    expect(firstWeek).toHaveAttribute('aria-expanded', 'true')
    expect(container.querySelectorAll('.week-grid[data-mobile-expanded="true"]')).toHaveLength(1)
    fireEvent.click(screen.getByRole('button', { name: '回到今天' }))
    expect(screen.getByRole('button', { name: '全部日期' })).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByRole('button', { name: /2026-09-29 · 化学课程/ }).parentElement).toHaveAttribute('data-mobile-expanded', 'true')
    expect(container.querySelectorAll('.plan-day')).toHaveLength(61)
    await waitFor(() => expect(container.querySelectorAll('.week-grid[data-mobile-expanded="true"]')).toHaveLength(1))
  })
})
