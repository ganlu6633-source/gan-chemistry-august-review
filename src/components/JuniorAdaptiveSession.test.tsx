import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { IssuedJuniorQuestion, JuniorAdaptivePayload, KnowledgeCard, LearningPlanDay, QuestionFeedback, SessionIdentity } from '../domain/types'
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

function question(id: string, stem: string): IssuedJuniorQuestion {
  return {
    id, motherId: `mother-${id}`, skillId: 'J3_MASS_CONSERVATION', level: 1, gradeBand: '初三', stem,
    options: ['原子种类和数目不变', '物质种类完全不变'], reviewStatus: 'approved', scopeStatus: 'IN', sourceKind: 'licensed_local', sourceInfo: null,
  }
}

function payload(currentQuestion: IssuedJuniorQuestion | null, answeredCount = 0): JuniorAdaptivePayload {
  return {
    deliveryMode: 'junior_adaptive', plan, cards: [card],
    session: { id: 'adaptive-session', status: currentQuestion ? 'active' : 'completed', initialQuestionTarget: 12, hardQuestionCap: 15, issuedCount: answeredCount + (currentQuestion ? 1 : 0), answeredCount, correctCount: answeredCount },
    currentStepId: currentQuestion ? `step-${currentQuestion.id}` : undefined,
    currentQuestion,
    completed: currentQuestion === null,
  }
}

const feedback: QuestionFeedback = {
  questionId: 'question-1', selectedOption: 0, correct: true, correctOption: 0, uncertain: false, durationSec: 4,
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
    const uncertain = screen.getByRole('checkbox')
    fireEvent.click(firstOption)
    fireEvent.keyDown(window, { key: 'Enter' })

    expect(await screen.findByText(/判断正确/)).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(firstOption).toBeDisabled()
    expect(secondOption).toBeDisabled()
    expect(uncertain).toBeDisabled()
    secondOption.click()
    uncertain.click()
    expect(firstOption).toHaveClass('selected')
    expect(secondOption).not.toHaveClass('selected')
    expect(uncertain).not.toBeChecked()

    const nextButton = screen.getByRole('button', { name: /下一题/ })
    expect(nextButton).toHaveAttribute('aria-keyshortcuts', 'Enter')
    fireEvent.keyDown(window, { key: 'Enter' })
    expect(await screen.findByRole('heading', { name: '第二题：反应前后哪一项保持不变？' })).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)
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
