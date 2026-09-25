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
  chooseDate()
}

function chooseDate() {
  fireEvent.click(screen.getByRole('button', { name: /学习日历 老师排好的题在这里/ }))
}

describe('StudentApp plan opening resilience', () => {
  afterEach(() => {
    cleanup()
    vi.useRealTimers()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it('starts with four choices and opens a source-backed knowledge challenge catalog', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => jsonResponse({ catalog: { topics: [{ skillId: 'H1_REDOX', skillTitle: '氧化还原反应', conceptKey: 'H1_REDOX__C01', title: '化合价升降', sequence: 1, originalCount: 5, freshCount: 5 }] } })))
    render(<StudentApp session={session} initialDashboard={dashboard} onDashboard={vi.fn()} />)
    expect(screen.getByRole('heading', { name: /今天从哪儿开练/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /学习日历 老师排好的题在这里/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /跟着进度走 看看学到了哪一站/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /知识点任选 今天想攻哪一块/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /题型训练场 想练哪类选择题/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /复习雷达 到时间该回看的/ })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /知识点任选 今天想攻哪一块/ }))
    expect(await screen.findByText('化合价升降')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /演示账号只读/ })).toBeDisabled()
    expect(screen.queryByTitle(/讲义原页/)).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '题型训练场' }))
    expect(screen.getByRole('heading', { name: '题型训练场' })).toBeInTheDocument()
    expect(await screen.findByText('化合价升降')).toBeInTheDocument()
  })

  it('loads the selected student’s real catalog during teacher read-only preview', async () => {
    const studentId = '65ec6dae-8ed5-4236-9237-4f96010c1668'
    const releaseId = 'd065f146-234f-4a4b-9db6-ad473d294ca9'
    const teacherSession: SessionIdentity = { role: 'teacher', token: 'teacher-session', displayName: '老师', expiresAt: '2099-01-01T00:00:00Z' }
    const fetchMock = vi.fn<typeof fetch>(async (_input, init) => {
      const action = JSON.parse(String(init?.body)).action
      if (action === 'preview_self_study') return jsonResponse({ payload: { ...payload(),
        plan: { ...plan, id: 'topic-preview', deliveryMode: 'self_study', roundLimit: 1 }, cards: [],
        questions: [{ ...question, id: 'source-question-1', options: ['纯净物', '混合物', '单质', '化合物'],
          stem: '海水属于哪类物质？', correctOption: 1, explanation: '海水含有多种物质，属于混合物。' }],
        roundLimit: 1,
      } })
      return jsonResponse({ catalog: { topics: [{
      skillId: 'H1_CLASSIFY', skillTitle: '物质分类', conceptKey: 'H1_CLASSIFY__C01',
      title: '分类标准与分类树', sequence: 1, originalCount: 5, freshCount: 5, releaseId,
    }] } })
    })
    vi.stubGlobal('fetch', fetchMock)
    render(<StudentApp session={teacherSession} initialDashboard={{ ...dashboard, profile: {
      ...dashboard.profile, id: studentId, displayName: '叶鸿诺', isDemo: false,
    }, plans: [] }} onDashboard={vi.fn()} previewMode />)

    fireEvent.click(screen.getByRole('button', { name: /知识点任选 今天想攻哪一块/ }))
    expect(await screen.findByText('分类标准与分类树')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /开始练题/ }))
    expect(await screen.findByRole('heading', { name: '海水属于哪类物质？' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /B\. 混合物/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(screen.getByText('回答正确')).toBeInTheDocument()
    const request = JSON.parse(String((fetchMock.mock.calls[0][1] as RequestInit).body))
    expect(request).toMatchObject({ action: 'self_study_catalog', data: { studentId } })
    const previewRequest = JSON.parse(String((fetchMock.mock.calls[1][1] as RequestInit).body))
    expect(previewRequest).toMatchObject({ action: 'preview_self_study', data: { studentId, releaseId } })
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
    expect(overlay).toHaveTextContent('正在取题，马上开练')
    expect(overlay).toHaveTextContent('从题库取几道好题，马上见面')
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
    const fetchMock = vi.fn<typeof fetch>(() => new Promise<Response>(() => undefined))
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

  it('warms the oldest unfinished catch-up plan before the student clicks it', async () => {
    const yesterday = new Date(Date.now() - 86_400_000).toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
    const catchUp = { ...plan, id: 'catch-up-plan', date: yesterday }
    const fetchMock = vi.fn<typeof fetch>(() => new Promise<Response>(() => undefined))
    vi.stubGlobal('fetch', fetchMock)
    render(<StudentApp session={session} initialDashboard={{ ...dashboard, plans: [catchUp] }} onDashboard={vi.fn()} />)
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))
    expect(JSON.parse(String((fetchMock.mock.calls[0][1] as RequestInit).body))).toMatchObject({ action: 'start_plan', data: { planId: catchUp.id } })
  })

  it('opens the same junior learning screen through a non-persistent teacher route', async () => {
    const fetchMock = vi.fn<typeof fetch>(async (_input, init) => JSON.parse(String(init?.body)).action === 'self_study_catalog'
      ? jsonResponse({ catalog: { topics: [] } }) : jsonResponse({ payload: {
      deliveryMode: 'junior_adaptive', plan: { ...plan, deliveryMode: 'junior_adaptive' }, cards: [],
      session: { id: 'preview-session', status: 'completed', issuedCount: 12, answeredCount: 12,
        correctCount: 9, initialQuestionTarget: 12, hardQuestionCap: 15 }, currentQuestion: null,
      completed: true, optionPractice: [],
    } }))
    vi.stubGlobal('fetch', fetchMock)
    const teacherSession: SessionIdentity = { ...session, role: 'teacher', token: 'teacher-session', displayName: '甘老师' }
    const juniorDashboard: StudentDashboardData = {
      ...dashboard,
      profile: { ...dashboard.profile, gradeBand: '初三', isDemo: false },
      plans: [{ ...plan, deliveryMode: 'junior_adaptive', juniorSessionStatus: 'active', hardQuestionCap: 15 }],
    }
    render(<StudentApp session={teacherSession} initialDashboard={juniorDashboard} onDashboard={vi.fn()} previewMode />)
    chooseDate()

    fireEvent.click(screen.getByRole('button', { name: '继续今日学习' }))
    expect(await screen.findByRole('heading', { name: '今天的练习已完成' })).toBeInTheDocument()
    const requests = fetchMock.mock.calls.map((call) => JSON.parse(String(call[1]?.body)))
    expect(requests).toContainEqual({ action: 'preview_junior_open_session', data: { studentId: dashboard.profile.id, planId: plan.id } })
    expect(requests.some((request) => request.action === 'junior_open_session')).toBe(false)
  })

  it.each([
    { label: 'real student', isDemo: false },
    { label: 'demo student', isDemo: true },
  ])('opens a $label future plan as a separate knowledge-only preview', async ({ isDemo }) => {
    const tomorrow = new Date(Date.now() + 86_400_000).toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
    const futurePlan = { ...plan, id: 'plan-future', date: tomorrow }
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) => {
      void _input
      const request = JSON.parse(String(_init?.body))
      if (request.action === 'self_study_catalog') return jsonResponse({ catalog: { topics: [] } })
      return jsonResponse({
        preview: {
          previewMode: 'future_knowledge_only',
          plan: futurePlan,
          cards: [card],
          formalOpenDate: tomorrow,
          recordsLearningEvidence: false,
          includesQuestions: false,
        },
      })
    })
    vi.stubGlobal('fetch', fetchMock)
    const futureDashboard: StudentDashboardData = {
      ...dashboard,
      profile: { ...dashboard.profile, isDemo },
      plans: [futurePlan],
    }
    render(<StudentApp session={session} initialDashboard={futureDashboard} onDashboard={vi.fn()} />)
    chooseDate()

    expect(screen.getByRole('button', { name: '进入预习' })).toBeEnabled()
    expect(screen.getByRole('button', { name: /今天的氧化还原复习，可提前预习/ })).toBeEnabled()
    expect(fetchMock.mock.calls.filter((call) => JSON.parse(String(call[1]?.body)).action === 'future_plan_preview')).toHaveLength(0)

    fireEvent.click(screen.getByRole('button', { name: '进入预习' }))

    expect(await screen.findByTestId('future-plan-preview')).toBeInTheDocument()
    const previewCall = fetchMock.mock.calls.find((call) => JSON.parse(String(call[1]?.body)).action === 'future_plan_preview')
    const request = JSON.parse(String(previewCall?.[1]?.body))
    expect(request).toEqual({ action: 'future_plan_preview', data: { planId: futurePlan.id } })
    expect(screen.getByText('提前预习 · 只读知识页')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: '氧化还原知识卡' })).toBeInTheDocument()
    expect(screen.getByText(/不展示正式题目、答案或提示/)).toBeInTheDocument()
    expect(screen.getByText(/不创建学习会话，也不计入掌握度和正式学习记录/)).toBeInTheDocument()
    expect(screen.queryByText(question.stem)).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /提交|确认答案|开始练习/ })).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: '完成预习，返回计划' }))
    expect(screen.getByRole('button', { name: '进入预习' })).toBeInTheDocument()
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
    chooseDate()

    fireEvent.click(screen.getByRole('button', { name: '开始今日学习' }))
    const juniorCalls = fetchMock.mock.calls.filter((call) => JSON.parse(String(call[1]?.body)).action === 'junior_open_session')
    expect(juniorCalls).toHaveLength(1)
    const request = JSON.parse(String((juniorCalls[0][1] as RequestInit).body))
    const requestSignal = (juniorCalls[0][1] as RequestInit).signal as AbortSignal
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
    expect(screen.getByText('正在取题，马上开练')).toBeInTheDocument()
    expect(screen.getByText('正在把这组知识卡和原题送过来。')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)

    await act(async () => { await vi.advanceTimersByTimeAsync(6_000) })
    expect(screen.getByText('正在取题，马上开练')).toBeInTheDocument()
    expect(screen.getByText('已经等了 6 秒，题组还在路上。')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)

    await act(async () => { await vi.advanceTimersByTimeAsync(9_000) })
    expect(screen.getByRole('alert')).toHaveTextContent('连接复习服务已超过15秒')
    expect(screen.getByRole('heading', { name: /测试学生，今天的题组备好啦/ })).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)

    fireEvent.click(screen.getByRole('button', { name: /重试开始第一轮/ }))
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('将正式单题组复习准确显示为今日原题，不再显示旧的多轮口径', () => {
    vi.stubGlobal('fetch', vi.fn(async () => jsonResponse({ catalog: { topics: [] } })))
    const formalPlan = { ...plan, roundLimit: 1, roundsRemaining: 1 }
    const formalDashboard = {
      ...dashboard,
      profile: { ...dashboard.profile, isDemo: false },
      plans: [formalPlan],
    }
    render(<StudentApp session={session} initialDashboard={formalDashboard} onDashboard={vi.fn()} />)
    chooseDate()

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
    expect(screen.getByRole('heading', { name: /测试学生，今天的题组备好啦/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /重试开始第一轮/ })).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('keeps the completed-round result when the next round fails and retries the same plan and round', async () => {
    let nextRoundRequests = 0
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      const request = JSON.parse(String(init?.body))
      if (request.data?.previewRound === 2) {
        nextRoundRequests += 1
        return nextRoundRequests === 1
          ? jsonResponse({ message: '下一轮暂时读取失败，请重试。' }, 503)
          : jsonResponse({ payload: payload(2) })
      }
      return jsonResponse({ payload: payload(1) })
    })
    vi.stubGlobal('fetch', fetchMock)
    renderStudent()

    fireEvent.click(screen.getByRole('button', { name: /开始第一轮/ }))
    expect(await screen.findByRole('heading', { name: '氧化还原知识卡' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /开始练习/ }))
    fireEvent.click(screen.getByRole('button', { name: /A.*失电子/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    fireEvent.click(screen.getByRole('button', { name: /完成第 1 轮/ }))
    expect(await screen.findByText('今天第 1 轮完成')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: /进入第 2 轮/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent('下一轮暂时读取失败，请重试。')
    expect(screen.getByText('今天第 1 轮完成')).toBeInTheDocument()

    await act(async () => { await Promise.resolve() })
    fireEvent.click(screen.getByRole('button', { name: '重试进入第 2 轮' }))
    await waitFor(() => expect(screen.getByRole('heading', { name: question.stem })).toBeInTheDocument())
    const nextRoundCalls = fetchMock.mock.calls.filter((call) => JSON.parse(String(call[1]?.body)).data?.previewRound === 2)
    expect(nextRoundCalls).toHaveLength(2)
    const failedRequest = JSON.parse(String((nextRoundCalls[0][1] as RequestInit).body))
    const retriedRequest = JSON.parse(String((nextRoundCalls[1][1] as RequestInit).body))
    expect(retriedRequest).toEqual(failedRequest)
    expect(retriedRequest).toMatchObject({ action: 'start_plan', data: { planId: plan.id, previewRound: 2 } })
  })
})
