import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Question, QuestionFeedback, SessionIdentity, StudentDashboardData } from '../domain/types'
import { loadQuestionFeedback, submitAttempt } from '../lib/api'
import { LearningRound, type PlanPayload } from './StudentApp'

vi.mock('../lib/api', () => ({
  accessApi: vi.fn(), loadLearningRecord: vi.fn(), teacherApi: vi.fn(), loadQuestionAsset: vi.fn(),
  loadQuestionFeedback: vi.fn(), previewQuestionFeedback: vi.fn(), submitAttempt: vi.fn(),
}))

const session: SessionIdentity = { role: 'student', token: 'private-session', displayName: '测试学生', expiresAt: '2099-01-01T00:00:00Z' }
const dashboard: StudentDashboardData = {
  profile: { id: 'student', displayName: '测试学生', gradeBand: '高三', enrollmentStartDate: '2026-09-12', needsInitialDiagnostic: false },
  plans: [], skillStates: [], skillDefinitions: [], todayQuestionCount: 2, achievements: [],
}
const question = (id: string): Question => ({
  id, motherId: `mother-${id}`, skillId: 'H3_EQUILIBRIUM', conceptKey: 'H3_EQUILIBRIUM__C01',
  gradeBand: '高三', level: 2, stem: `练习 ${id}`, options: ['结论甲', '结论乙', '结论丙', '结论丁'],
  reviewStatus: 'approved', scopeStatus: 'IN', sourceKind: 'licensed_local', renderMode: 'native', revisionToken: `revision-${id}`,
})
const anchor = question('anchor')
const tail = question('tail')
const expandedQuestions = (count: number) => [anchor, ...Array.from({ length: count }, (_, index) => ({
  ...question(`practice-${index + 1}`), optionPractice: {
    anchorQuestionId: anchor.id, optionIndex: 1, knowledgePoint: '平衡状态的判断', position: index + 1, total: count,
  },
})), tail]
const feedbackFor = (id: string, selectedOption = 0, uncertain = false): QuestionFeedback => ({
  questionId: id, selectedOption, correct: selectedOption === 0, correctOption: 0, uncertain,
  durationSec: 8, explanation: `${id}：选项甲符合题给条件。`, analysisAssetRefs: [], revisionToken: `revision-${id}`,
})
const payload: PlanPayload = {
  plan: { id: 'plan', studentId: 'student', date: '2026-09-12', mode: 'REVIEW', title: '试卷四选一复习',
    skillIds: ['H3_EQUILIBRIUM'], knowledgeSummaries: ['平衡状态的判断'], estimatedMinutes: 15, isScheduled: true,
    attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null, questionCount: 2, roundLimit: 1,
    maxQuestionLevel: 3, isResolved: false, isComplete: false, roundsRemaining: 1 },
  cards: [], questions: [anchor, tail], attemptSequence: 0, roundNumber: 1, roundLimit: 1,
  questionCount: 2, baseQuestionCount: 2, optionPractice: [], isResolved: false, isComplete: false, roundsRemaining: 1,
}
function renderRound(value = payload) {
  return render(<LearningRound session={session} payload={value} onExit={vi.fn()} onContinue={vi.fn(async () => undefined)} onComplete={vi.fn()} />)
}
async function answerCurrent(id: string, selected = 0) {
  expect(screen.getByRole('heading', { name: `练习 ${id}` })).toBeInTheDocument()
  fireEvent.click(screen.getByRole('button', { name: `${String.fromCharCode(65 + selected)}. ${['结论甲', '结论乙', '结论丙', '结论丁'][selected]}` }))
  fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
  await screen.findByText(selected === 0 ? '回答正确' : '回答错误，正确选项是 A')
}

describe('LearningRound server-selected option practice', () => {
  beforeEach(() => {
    vi.mocked(submitAttempt).mockImplementation(async (_session, attempt) => ({
      dashboard, achievements: [], feedback: attempt.answers.map((item) => feedbackFor(item.questionId, item.selectedOption, item.uncertain)),
    }))
  })
  afterEach(() => { cleanup(); vi.resetAllMocks() })

  it('inserts three practice questions after a wrong option, extends to five, and submits the full issued order', async () => {
    let practiceExpanded = false
    vi.mocked(loadQuestionFeedback).mockImplementation(async (_session, input) => {
      if (input.questionId === 'practice-1') practiceExpanded = true
      return { feedback: feedbackFor(input.questionId, input.selectedOption), simulated: false,
        questions: expandedQuestions(practiceExpanded ? 5 : 3) }
    })
    renderRound()
    fireEvent.click(screen.getByRole('button', { name: '开始练习' }))
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
    await answerCurrent('anchor', 1)
    expect(screen.getByText('今日题组 · 1/5')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'B. 结论乙' })).toBeDisabled()
    expect(screen.queryByText(/提高难度|已掌握/)).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '下一题' }))
    expect(screen.getByText(/该选项对应考点 · 第1\/3题/)).toBeInTheDocument()
    await answerCurrent('practice-1', 1)
    expect(screen.getByRole('heading', { name: '练习 practice-1' })).toBeInTheDocument()
    expect(screen.getByText('今日题组 · 2/7')).toBeInTheDocument()
    expect(screen.getByText(/该选项对应考点 · 第1\/5题/)).toBeInTheDocument()
    for (const id of ['practice-2', 'practice-3', 'practice-4', 'practice-5', 'tail']) {
      fireEvent.click(screen.getByRole('button', { name: '下一题' }))
      await answerCurrent(id)
    }
    fireEvent.click(screen.getByRole('button', { name: '完成今日题组' }))
    expect(await screen.findByRole('heading', { name: '本组答对 5/7 题。' })).toBeInTheDocument()
    expect(submitAttempt).toHaveBeenCalledTimes(1)
    const attempt = vi.mocked(submitAttempt).mock.calls[0][1]
    expect(attempt.answers.map((item) => item.questionId)).toEqual(expandedQuestions(5).map((item) => item.id))
    expect(attempt.answers.every((item) => item.uncertain === false)).toBe(true)
    expect(vi.mocked(loadQuestionFeedback).mock.calls.map(([, input]) => input.uncertain)).toEqual(Array(7).fill(false))
    expect(payload.questions).toHaveLength(2)
  })

  it('resumes at the first unanswered practice question and preserves old immutable answers in final order', async () => {
    const issued = expandedQuestions(5)
    const lockedFeedback = [feedbackFor('anchor', 1, true), feedbackFor('practice-1', 1)]
    vi.mocked(loadQuestionFeedback).mockImplementation(async (_session, input) => ({
      feedback: feedbackFor(input.questionId, input.selectedOption), simulated: false, questions: issued,
    }))
    renderRound({ ...payload, questions: issued, lockedFeedback,
      optionPractice: [{ anchorQuestionId: 'anchor', optionIndex: 1, knowledgePoint: '平衡状态的判断',
        questionIds: issued.slice(1, 6).map((item) => item.id), answered: 1, correct: 0, status: 'practicing' }] })
    expect(screen.queryByRole('button', { name: '开始练习' })).not.toBeInTheDocument()
    expect(screen.getByText('今日题组 · 3/7')).toBeInTheDocument()
    expect(screen.getByText(/该选项对应考点 · 第2\/5题/)).toBeInTheDocument()
    for (const [index, id] of ['practice-2', 'practice-3', 'practice-4', 'practice-5', 'tail'].entries()) {
      if (index > 0) fireEvent.click(screen.getByRole('button', { name: '下一题' }))
      await answerCurrent(id)
    }
    fireEvent.click(screen.getByRole('button', { name: '完成今日题组' }))
    await waitFor(() => expect(submitAttempt).toHaveBeenCalledTimes(1))
    const attempt = vi.mocked(submitAttempt).mock.calls[0][1]
    expect(attempt.answers.map((item) => item.questionId)).toEqual(issued.map((item) => item.id))
    expect(attempt.answers[0]).toMatchObject({ selectedOption: 1, correct: false, uncertain: true, durationSec: 8 })
    expect(vi.mocked(loadQuestionFeedback).mock.calls.map(([, input]) => input.questionId)).toEqual(['practice-2', 'practice-3', 'practice-4', 'practice-5', 'tail'])
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
  })

  it.each(['anchor', 'tail'])('does not discard the %s question when an incomplete server group is returned', async (missingId) => {
    vi.mocked(loadQuestionFeedback).mockResolvedValue({ feedback: feedbackFor('practice-1'), simulated: false,
      questions: expandedQuestions(3).filter((item) => item.id !== missingId) })
    renderRound({ ...payload, questions: expandedQuestions(3), lockedFeedback: [feedbackFor('anchor', 1)] })
    fireEvent.click(screen.getByRole('button', { name: 'A. 结论甲' }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('题组不完整')
    expect(screen.getByText('今日题组 · 2/5')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: '完成今日题组' })).not.toBeInTheDocument()
    expect(submitAttempt).not.toHaveBeenCalled()
  })
})
