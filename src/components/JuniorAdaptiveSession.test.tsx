import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { IssuedJuniorQuestion, JuniorAdaptivePayload, JuniorQuestionFeedback, KnowledgeCard, LearningPlanDay, SessionIdentity } from '../domain/types'
import { JuniorAdaptiveSession } from './JuniorAdaptiveSession'

const session: SessionIdentity = { role: 'student', token: 'junior-session', displayName: '初三学生', expiresAt: '2099-01-01T00:00:00Z' }

const plan: LearningPlanDay = {
  id: 'junior-plan', studentId: 'student-junior', date: '2026-08-29', mode: 'REVIEW', title: '今日初中自适应学习',
  skillIds: ['J3_MASS_CONSERVATION'], knowledgeSummaries: ['质量守恒定律'], estimatedMinutes: 20, source: 'course', isScheduled: true,
  attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null, questionCount: 12, roundLimit: 1,
  maxQuestionLevel: 2, deliveryMode: 'junior_adaptive', juniorSessionStatus: 'active', hardQuestionCap: 15,
  isResolved: false, isComplete: false, roundsRemaining: 1,
}

const card: KnowledgeCard = {
  id: 'junior-card', skillId: 'J3_MASS_CONSERVATION', title: '质量守恒定律', core: '化学反应前后原子的种类、数目和质量不变。',
  detail: '先确认发生了化学反应，再比较反应前后。', steps: ['确认反应', '逐项比较'], commonMistakes: ['物质种类可以改变。'],
  microExample: '反应前后总质量相等。', reviewStatus: 'approved',
}

function question(revisionLabel: string, stem: string): IssuedJuniorQuestion {
  return {
    skillId: 'J3_MASS_CONSERVATION', level: 1, gradeBand: '初三', stem,
    options: ['原子种类和数目不变', '物质种类完全不变', '原子总数增加', '原子质量变小'], revisionToken: `revision-${revisionLabel}`,
  }
}

function payload(currentQuestion: IssuedJuniorQuestion | null, answeredCount = 0): JuniorAdaptivePayload {
  return {
    deliveryMode: 'junior_adaptive', plan, cards: [card],
    session: { id: 'adaptive-session', status: currentQuestion ? 'active' : 'completed', initialQuestionTarget: 12, hardQuestionCap: 15, issuedCount: answeredCount + (currentQuestion ? 1 : 0), answeredCount, correctCount: answeredCount },
    currentStepId: currentQuestion ? `step-${answeredCount + 1}` : undefined,
    currentQuestion,
    completed: currentQuestion === null,
  }
}

const feedback: JuniorQuestionFeedback = {
  stepId: 'step-1', selectedOption: 0, correct: true, correctOption: 0, uncertain: false, durationSec: 4,
  explanation: 'A. 化学反应前后原子的种类和数目不变。\nB. 物质种类可以发生改变。', analysisAssetRefs: [],
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

describe('JuniorAdaptiveSession keyboard and safe exit UX', () => {
  afterEach(() => {
    cleanup()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it('submits and advances with Enter while keeping the answered choice immutable after feedback', async () => {
    const nextPayload = payload(question('question-2', '第二题：反应前后哪一项保持不变？'), 1)
    const fetchMock = vi.fn(async () => jsonResponse({ feedback, payload: nextPayload }))
    vi.stubGlobal('fetch', fetchMock)
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1', '第一题：质量守恒的微观原因是什么？'))} onExit={vi.fn()} onComplete={vi.fn()} />)

    expect(screen.getByRole('button', { name: '稍后继续 / 返回计划' })).toBeVisible()
    const submitButton = screen.getByRole('button', { name: '提交答案' })
    expect(submitButton).toHaveAttribute('aria-keyshortcuts', 'Enter')
    expect(submitButton).toBeDisabled()
    fireEvent.keyDown(window, { key: 'Enter' })
    expect(fetchMock).not.toHaveBeenCalled()

    const firstOption = screen.getByRole('button', { name: /A\. 原子种类和数目不变/ })
    const secondOption = screen.getByRole('button', { name: /B\. 物质种类完全不变/ })
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    fireEvent.click(firstOption)
    fireEvent.keyDown(window, { key: 'Enter' })

    expect(await screen.findByText('回答正确')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(firstOption).toBeDisabled()
    expect(secondOption).toBeDisabled()
    secondOption.click()
    expect(firstOption).toHaveClass('selected')
    expect(secondOption).not.toHaveClass('selected')

    const nextButton = screen.getByRole('button', { name: /下一题/ })
    expect(nextButton).toHaveAttribute('aria-keyshortcuts', 'Enter')
    fireEvent.keyDown(window, { key: 'Enter' })
    expect(await screen.findByRole('heading', { name: '第二题：反应前后哪一项保持不变？' })).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('submits only the selected option with uncertain false and labels a wrong answer explicitly', async () => {
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) => {
      void _input
      void _init
      return jsonResponse({ feedback: { ...feedback, selectedOption: 1, correct: false, uncertain: true },
        payload: payload(question('question-2', '下一道练习'), 1) })
    })
    vi.stubGlobal('fetch', fetchMock)
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1', '当前题'))} onExit={vi.fn()} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /B\. 物质种类完全不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByText('回答错误，正确选项是 A')).toBeInTheDocument()
    const init = fetchMock.mock.calls[0][1] as RequestInit
    expect(JSON.parse(String(init.body))).toMatchObject({ action: 'junior_submit_step', data: {
      selectedOption: 1, uncertain: false, stepId: 'step-1', revisionToken: 'revision-question-1',
    } })
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
    expect(screen.queryByText(/已掌握|提高难度/)).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '下一题' }))
    expect(screen.getByRole('heading', { name: '下一道练习' })).toBeInTheDocument()
  })

  it('leaves Enter on a focused answer button to native keyboard selection without submitting the old choice', () => {
    const fetchMock = vi.fn(async () => jsonResponse({ feedback, payload: payload(null, 12) }))
    vi.stubGlobal('fetch', fetchMock)
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1', '第一题'))} onExit={vi.fn()} onComplete={vi.fn()} />)

    const firstOption = screen.getByRole('button', { name: /A\. 原子种类和数目不变/ })
    const secondOption = screen.getByRole('button', { name: /B\. 物质种类完全不变/ })
    fireEvent.click(firstOption)
    secondOption.focus()

    expect(fireEvent.keyDown(secondOption, { key: 'Enter' })).toBe(true)
    // jsdom does not synthesize the browser's native button click from Enter,
    // so model that default action after proving the global shortcut did not
    // cancel it or submit the previously selected answer.
    fireEvent.click(secondOption)

    expect(secondOption).toHaveClass('selected')
    expect(firstOption).not.toHaveClass('selected')
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('keeps the committed feedback visible and retries only the locked answer when the next question fails', async () => {
    const lockedFeedback = { ...feedback, selectedOption: 1, correct: false, uncertain: true, durationSec: 7, revisionToken: 'revision-question-1' }
    const fetchMock = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse({ feedback: lockedFeedback, payload: null, continuation: { status: 'unavailable', message: '本题答案已保存，下一题暂不可用。' } }))
      .mockRejectedValueOnce(new Error('network unavailable'))
      .mockResolvedValueOnce(jsonResponse({ feedback: lockedFeedback, payload: payload(question('question-2', '恢复后的下一题'), 1), replayed: true }))
    vi.stubGlobal('fetch', fetchMock)
    const onExit = vi.fn()
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1', '当前题'))} onExit={onExit} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /B\. 物质种类完全不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByText('回答错误，正确选项是 A')).toBeVisible()
    expect(screen.getByText('物质种类可以发生改变。')).toBeVisible()
    expect(screen.getByRole('alert')).toHaveTextContent('本题答案已保存')
    expect(screen.getByRole('button', { name: /B\. 物质种类完全不变/ })).toBeDisabled()
    expect(screen.getByRole('button', { name: '重试获取下一题' })).toBeEnabled()

    fireEvent.click(screen.getByRole('button', { name: '重试获取下一题' }))
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('解析仍可查看'))
    expect(screen.getByText('回答错误，正确选项是 A')).toBeVisible()
    expect(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ })).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: '重试获取下一题' }))
    expect(await screen.findByRole('button', { name: '下一题' })).toBeEnabled()
    for (const call of fetchMock.mock.calls.slice(1)) {
      expect(JSON.parse(String(call[1]?.body))).toMatchObject({ action: 'junior_submit_step', data: {
        stepId: 'step-1', selectedOption: 1, revisionToken: 'revision-question-1', uncertain: true, durationSec: 7,
      } })
    }
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '下一题' }))
    expect(screen.getByRole('heading', { name: '恢复后的下一题' })).toBeVisible()
    expect(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ })).toBeEnabled()
    fireEvent.click(screen.getByRole('button', { name: '稍后继续 / 返回计划' }))
    expect(onExit).toHaveBeenCalledTimes(1)
  })

  it('allows returning to the plan while the saved feedback is available but the next question is not', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => jsonResponse({ feedback, payload: null })))
    const onExit = vi.fn()
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1', '当前题'))} onExit={onExit} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByText('回答正确')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: '稍后继续 / 返回计划' }))
    expect(onExit).toHaveBeenCalledTimes(1)
  })

  it('shows an exact-option reserve in the same four-option UI and keeps a daily-limit carry visible', () => {
    const current = question('reserve-2', '具体考点补练')
    current.optionPractice = { anchorStepId: 'opaque-first-step', optionIndex: 1, knowledgePoint: '源头减污', position: 2, total: 4 }
    const initial = payload(current, 14)
    initial.optionPractice = [{ anchorStepId: 'another-opaque-step', optionIndex: 2, knowledgePoint: '物质组成', status: 'pending', answered: 1, correct: 1, total: 3, pendingReason: 'daily_limit_carry_forward' }]
    render(<JuniorAdaptiveSession session={session} initialPayload={initial} onExit={vi.fn()} onComplete={vi.fn()} />)
    expect(screen.getByText('源头减污 · 第 2/4 题')).toBeVisible()
    expect(screen.getByText('有 1 个错项考点的后续补练待准备或待续，进度已经保留。')).toBeVisible()
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
    for (const label of ['A.','B.','C.','D.']) expect(screen.getByRole('button',{name:new RegExp(`^${label}`)})).toBeEnabled()
    expect(screen.queryByText(/已掌握|需帮助/)).not.toBeInTheDocument()
  })

  it('preserves feedback and offers the plan when the honest reserve gap leaves no next question', async () => {
    const gap = { ...payload(null, 4), completed: false, session: { ...payload(null,4).session, status: 'active' as const }, pendingMessage: '已保留你的答题和补练进度，后续题目正在准备。' }
    vi.stubGlobal('fetch',vi.fn(async()=>jsonResponse({feedback,payload:gap})))
    const onExit=vi.fn()
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1','当前题'))} onExit={onExit} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button',{name:/A\. 原子种类和数目不变/}))
    fireEvent.click(screen.getByRole('button',{name:'提交答案'}))
    expect(await screen.findByText('回答正确')).toBeVisible()
    expect(screen.getByRole('alert')).toHaveTextContent('后续题目正在准备')
    fireEvent.click(screen.getByRole('button',{name:'返回学习计划'}))
    expect(onExit).toHaveBeenCalledTimes(1)
  })

  it('offers a visible non-destructive return action and supports Enter on the completed result', async () => {
    const onExit = vi.fn()
    const view = render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1', '第一题'))} onExit={onExit} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: '稍后继续 / 返回计划' }))
    expect(onExit).toHaveBeenCalledTimes(1)

    view.unmount()
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(null, 12)} onExit={onExit} onComplete={vi.fn()} />)
    const resultButton = screen.getByRole('button', { name: /查看今日成果/ })
    expect(resultButton).toHaveAttribute('aria-keyshortcuts', 'Enter')
    fireEvent.keyDown(window, { key: 'Enter' })
    await waitFor(() => expect(onExit).toHaveBeenCalledTimes(2))
  })
})
