import { StrictMode } from 'react'
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { KnowledgeCard, LearningPlanDay, Question, SessionIdentity, StudentDashboardData } from '../domain/types'
import { StudentApp, type PlanPayload } from './StudentApp'

const session: SessionIdentity = { role: 'student', token: 'student-session', displayName: '测试学生', expiresAt: '2099-01-01T00:00:00Z' }
const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })

const plan: LearningPlanDay = {
  id: 'plan-today', studentId: 'student-1', date: today, mode: 'REVIEW', title: '今天的氧化还原复习',
  skillIds: ['H1_REDOX'], knowledgeSummaries: ['化合价升降与电子转移'], estimatedMinutes: 10, source: 'course', isScheduled: true,
  attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null, questionCount: 1, roundLimit: 2,
  maxQuestionLevel: 2, isResolved: false, isComplete: false, roundsRemaining: 2,
}

const dashboard: StudentDashboardData = {
  profile: { id: 'student-1', displayName: '测试学生', gradeBand: '高一', enrollmentStartDate: '2026-08-01', needsInitialDiagnostic: false, isDemo: true },
  plans: [plan], skillStates: [], skillDefinitions: [], todayQuestionCount: 1, achievements: [],
}

const card: KnowledgeCard = {
  id: 'card-1', skillId: 'H1_REDOX', title: '氧化还原知识卡', core: '升价失电子，被氧化，发生氧化反应。',
  detail: '先标化合价，再看电子转移。', steps: ['标价', '看升降'], commonMistakes: ['不要漏写发生氧化反应。'],
  microExample: 'Na由0价升至+1价。', reviewStatus: 'approved',
}

const question: Question = {
  id: 'question-1', motherId: 'mother-1', skillId: 'H1_REDOX', level: 1, gradeBand: '高一',
  stem: 'Na由0价升至+1价时发生什么变化？', options: ['失电子，被氧化', '得电子，被还原'], correctOption: 0,
  explanation: 'Na升价并失电子，被氧化，发生氧化反应。', reviewStatus: 'approved', scopeStatus: 'IN', sourceKind: 'teacher_original',
}

function payload(roundNumber = 1): PlanPayload {
  return {
    plan, cards: [card], questions: [{ ...question, id: `question-${roundNumber}`, motherId: `mother-${roundNumber}` }],
    attemptSequence: roundNumber - 1, roundNumber, roundLimit: 2, questionCount: 1,
    isResolved: false, isComplete: false, roundsRemaining: 3 - roundNumber,
  }
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

function renderStudent() {
  render(<StudentApp session={session} initialDashboard={dashboard} onDashboard={vi.fn()} />)
}

describe('StudentApp plan opening resilience', () => {
  afterEach(() => {
    cleanup()
    vi.useRealTimers()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it('prefetches today once and reuses the same in-flight request when clicked', async () => {
    let resolveRequest: ((response: Response) => void) | undefined
    const fetchMock = vi.fn<typeof fetch>(() => new Promise<Response>((resolve) => { resolveRequest = resolve }))
    vi.stubGlobal('fetch', fetchMock)
    renderStudent()

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))
    const prefetchedRequest = JSON.parse(String((fetchMock.mock.calls[0][1] as RequestInit).body))
    expect(prefetchedRequest).toMatchObject({ action: 'start_plan', data: { planId: plan.id } })

    fireEvent.click(screen.getByRole('button', { name: /开始第一轮/ }))
    const overlay = document.querySelector('.plan-opening-overlay')
    expect(overlay).toBeInTheDocument()
    expect(overlay).toHaveTextContent('已经收到点击')
    expect(overlay).toHaveTextContent('页面没有卡住')
    expect(fetchMock).toHaveBeenCalledTimes(1)

    await act(async () => { resolveRequest?.(jsonResponse({ payload: payload(1) })) })
    expect(await screen.findByRole('heading', { name: '氧化还原知识卡' })).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('does not duplicate the today prefetch during StrictMode effect replay', async () => {
    const fetchMock = vi.fn((_input: RequestInfo | URL, init?: RequestInit) => new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener('abort', () => reject(new DOMException('The operation was aborted.', 'AbortError')))
    }))
    vi.stubGlobal('fetch', fetchMock)
    render(<StrictMode><StudentApp session={session} initialDashboard={dashboard} onDashboard={vi.fn()} /></StrictMode>)

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))
    await act(async () => { await new Promise((resolve) => window.setTimeout(resolve, 10)) })
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('keeps a failed prefetch silent and retries only after the student clicks', async () => {
    let rejectPrefetch: ((reason: Error) => void) | undefined
    let resolveRetry: ((response: Response) => void) | undefined
    const fetchMock = vi.fn()
      .mockImplementationOnce(() => new Promise<Response>((_resolve, reject) => { rejectPrefetch = reject }))
      .mockImplementationOnce(() => new Promise<Response>((resolve) => { resolveRetry = resolve }))
    vi.stubGlobal('fetch', fetchMock)
    renderStudent()

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))
    await act(async () => { rejectPrefetch?.(new Error('prefetch failed')); await Promise.resolve() })
    expect(document.querySelector('.plan-opening-overlay')).not.toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: /开始第一轮/ }))
    expect(document.querySelector('.plan-opening-overlay')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(2)
    await act(async () => { resolveRetry?.(jsonResponse({ payload: payload(1) })) })
    expect(await screen.findByRole('heading', { name: '氧化还原知识卡' })).toBeInTheDocument()
  })

  it('does not prefetch a future fallback or a write-producing junior session', async () => {
    const fetchMock = vi.fn(() => new Promise<Response>(() => undefined))
    vi.stubGlobal('fetch', fetchMock)
    const tomorrow = new Date(`${today}T12:00:00+08:00`)
    tomorrow.setDate(tomorrow.getDate() + 1)
    const tomorrowText = tomorrow.toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
    const futureDashboard = { ...dashboard, plans: [{ ...plan, id: 'future-plan', date: tomorrowText }] }
    const juniorDashboard = { ...dashboard, plans: [{ ...plan, deliveryMode: 'junior_adaptive' as const }] }

    const futureView = render(<StudentApp session={session} initialDashboard={futureDashboard} onDashboard={vi.fn()} />)
    await act(async () => { await Promise.resolve() })
    expect(fetchMock).not.toHaveBeenCalled()
    futureView.unmount()
    render(<StudentApp session={session} initialDashboard={juniorDashboard} onDashboard={vi.fn()} />)
    await act(async () => { await Promise.resolve() })
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('never opens a mutating junior session from teacher read-only preview', async () => {
    const fetchMock = vi.fn<typeof fetch>()
    vi.stubGlobal('fetch', fetchMock)
    const teacherSession: SessionIdentity = { ...session, role: 'teacher', token: 'teacher-session', displayName: '甘老师' }
    const juniorDashboard: StudentDashboardData = {
      ...dashboard,
      profile: { ...dashboard.profile, gradeBand: '初三', isDemo: false },
      plans: [{ ...plan, deliveryMode: 'junior_adaptive', juniorSessionStatus: 'active', hardQuestionCap: 15 }],
    }
    render(<StudentApp session={teacherSession} initialDashboard={juniorDashboard} onDashboard={vi.fn()} previewMode onExitPreview={vi.fn()} />)

    expect(screen.getByText(/教师只读模拟不会启动或提交这类会话/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '查看只读说明' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('不会启动或提交这类会话')
    expect(screen.getByRole('alert')).toHaveTextContent('不会向学生作答接口发送请求')
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('keeps a real student future plan locked until its scheduled date', () => {
    const fetchMock = vi.fn<typeof fetch>()
    vi.stubGlobal('fetch', fetchMock)
    const tomorrow = new Date(Date.now() + 86_400_000).toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
    const futureDashboard: StudentDashboardData = {
      ...dashboard,
      profile: { ...dashboard.profile, isDemo: false },
      plans: [{ ...plan, id: 'plan-future', date: tomorrow }],
    }
    render(<StudentApp session={session} initialDashboard={futureDashboard} onDashboard={vi.fn()} />)

    expect(screen.getByRole('button', { name: '按日期开放' })).toBeDisabled()
    expect(screen.getByRole('button', { name: /今天的氧化还原复习，按日期开放/ })).toBeDisabled()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('passes an AbortSignal to junior_open_session and aborts it after the open timeout', async () => {
    vi.useFakeTimers()
    const fetchMock = vi.fn((_input: RequestInfo | URL, init?: RequestInit) => new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener('abort', () => reject(new DOMException('The operation was aborted.', 'AbortError')))
    }))
    vi.stubGlobal('fetch', fetchMock)
    const juniorDashboard: StudentDashboardData = {
      ...dashboard,
      profile: { ...dashboard.profile, gradeBand: '初三', isDemo: false },
      plans: [{ ...plan, deliveryMode: 'junior_adaptive', juniorSessionStatus: 'not_started', hardQuestionCap: 15 }],
    }
    render(<StudentApp session={session} initialDashboard={juniorDashboard} onDashboard={vi.fn()} />)

    fireEvent.click(screen.getByRole('button', { name: '开始今日学习' }))
    expect(fetchMock).toHaveBeenCalledTimes(1)
    const request = JSON.parse(String((fetchMock.mock.calls[0][1] as RequestInit).body))
    const requestSignal = (fetchMock.mock.calls[0][1] as RequestInit).signal as AbortSignal
    expect(request).toEqual({ action: 'junior_open_session', data: { planId: plan.id } })
    expect(requestSignal).toBeInstanceOf(AbortSignal)
    expect(requestSignal.aborted).toBe(false)

    await act(async () => { await vi.advanceTimersByTimeAsync(15_000) })
    expect(requestSignal.aborted).toBe(true)
    expect(screen.getByRole('alert')).toHaveTextContent('连接复习服务已超过15秒')
  })

  it('shows timed progress immediately, stops safely after 15 seconds, and retries only after a click', async () => {
    vi.useFakeTimers()
    const fetchMock = vi.fn((_input: RequestInfo | URL, init?: RequestInit) => new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener('abort', () => reject(new DOMException('The operation was aborted.', 'AbortError')))
    }))
    vi.stubGlobal('fetch', fetchMock)
    renderStudent()

    fireEvent.click(screen.getByRole('button', { name: /开始第一轮/ }))
    expect(screen.getByText('第1步/3 · 正在连接复习服务')).toBeInTheDocument()
    expect(screen.getByText('请求已经发出，请稍候。')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)

    await act(async () => { await vi.advanceTimersByTimeAsync(6_000) })
    expect(screen.getByText('第3步/3 · 正在安全装入所选题组')).toBeInTheDocument()
    expect(screen.getByText('已等待 6 秒，请不要重复点击。')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)

    await act(async () => { await vi.advanceTimersByTimeAsync(9_000) })
    expect(screen.getByRole('alert')).toHaveTextContent('连接复习服务已超过15秒')
    expect(screen.getByRole('heading', { name: /测试学生，今天先把/ })).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)

    fireEvent.click(screen.getByRole('button', { name: /重试开始第一轮/ }))
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('将正式单题组复习准确显示为今日原题，不再显示旧的多轮口径', () => {
    const formalPlan = { ...plan, roundLimit: 1, roundsRemaining: 1 }
    const formalDashboard = {
      ...dashboard,
      profile: { ...dashboard.profile, isDemo: false },
      plans: [formalPlan],
    }
    render(<StudentApp session={session} initialDashboard={formalDashboard} onDashboard={vi.fn()} />)

    expect(screen.getByText('今日原题')).toBeInTheDocument()
    expect(screen.getByText('今日 1 道原题 · 1 个题组 · 错题次日换原题')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /开始今日题组/ })).toBeInTheDocument()
    expect(screen.queryByText('每轮题目')).not.toBeInTheDocument()
  })

  it('明确告知演示学生每天可打开已审核原题，且练习不写入正式记录', () => {
    renderStudent()

    expect(screen.getByRole('heading', { name: '每一天都可以打开完整学习链路' })).toBeInTheDocument()
    expect(screen.getByText(/只读取已审核、当前范围内、可用于复习的真实原题/)).toBeInTheDocument()
    expect(screen.getByText(/不写入任何正式学生记录/)).toBeInTheDocument()
  })

  it('keeps the server error visible beside the original action', async () => {
    const fetchMock = vi.fn(async () => jsonResponse({ message: '服务器具体错误：本轮原题数量不足。' }, 422))
    vi.stubGlobal('fetch', fetchMock)
    renderStudent()

    fireEvent.click(screen.getByRole('button', { name: /开始第一轮/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent('服务器具体错误：本轮原题数量不足。')
    expect(screen.getByRole('heading', { name: /测试学生，今天先把/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /重试开始第一轮/ })).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('keeps the completed-round result when the next round fails and retries the same plan and round', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(jsonResponse({ payload: payload(1) }))
      .mockResolvedValueOnce(jsonResponse({ message: '下一轮暂时读取失败，请重试。' }, 503))
      .mockResolvedValueOnce(jsonResponse({ payload: payload(2) }))
    vi.stubGlobal('fetch', fetchMock)
    renderStudent()

    fireEvent.click(screen.getByRole('button', { name: /开始第一轮/ }))
    expect(await screen.findByRole('heading', { name: '氧化还原知识卡' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /开始练习/ }))
    fireEvent.click(screen.getByRole('button', { name: /A.*失电子/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    fireEvent.click(screen.getByRole('button', { name: /完成第 1 轮/ }))
    expect(await screen.findByText('演示第 1 轮完成')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: /进入第 2 轮/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent('下一轮暂时读取失败，请重试。')
    expect(screen.getByText('演示第 1 轮完成')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: '重试进入第 2 轮' }))
    await waitFor(() => expect(screen.getByRole('heading', { name: question.stem })).toBeInTheDocument())
    expect(fetchMock).toHaveBeenCalledTimes(3)
    const failedRequest = JSON.parse(String((fetchMock.mock.calls[1][1] as RequestInit).body))
    const retriedRequest = JSON.parse(String((fetchMock.mock.calls[2][1] as RequestInit).body))
    expect(retriedRequest).toEqual(failedRequest)
    expect(retriedRequest).toMatchObject({ action: 'start_plan', data: { planId: plan.id, previewRound: 2 } })
  })
})
