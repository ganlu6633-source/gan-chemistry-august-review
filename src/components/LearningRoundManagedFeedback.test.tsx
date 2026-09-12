import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { QuestionFeedback, SessionIdentity, StudentDashboardData } from '../domain/types'
import { loadQuestionFeedback, previewQuestionFeedback, submitAttempt } from '../lib/api'
import { LearningRound, type PlanPayload } from './StudentApp'

vi.mock('../lib/api', () => ({
  accessApi: vi.fn(), loadLearningRecord: vi.fn(), teacherApi: vi.fn(),
  loadQuestionAsset: vi.fn(), loadQuestionFeedback: vi.fn(),
  previewQuestionFeedback: vi.fn(), submitAttempt: vi.fn(),
}))

const session: SessionIdentity = { role: 'student', token: 'unit-test-session', displayName: '同学', expiresAt: '2099-01-01T00:00:00Z' }
const dashboard: StudentDashboardData = {
  profile: { id: 's', displayName: '同学', gradeBand: '高一', enrollmentStartDate: '2026-09-12', needsInitialDiagnostic: false },
  plans: [], skillStates: [], skillDefinitions: [], todayQuestionCount: 1, achievements: [],
}
const payload: PlanPayload = {
  plan: { id: 'managed-plan', studentId: 's', date: '2026-09-12', mode: 'REVIEW', title: '化学入门复习', skillIds: ['J_CHEM'], knowledgeSummaries: [], estimatedMinutes: 5, isScheduled: true, attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null, questionCount: 1, roundLimit: 1, maxQuestionLevel: 1, isResolved: false, isComplete: false, roundsRemaining: 1, teachingManaged: true, teachingSourceGrade: '初三' },
  cards: [], questions: [{ id: 'junior-source-q', motherId: 'junior-source-m', skillId: 'J_CHEM', gradeBand: '初三', level: 1, stem: '属于化学研究内容的是', options: ['物体运动', '物质组成', '语言表达', '图形关系'], reviewStatus: 'approved', scopeStatus: 'IN', sourceKind: 'user_provided_local', renderMode: 'native', secureFeedbackRequired: true, revisionToken: 'junior-revision' }],
  attemptSequence: 0, roundNumber: 1, roundLimit: 1, questionCount: 1, isResolved: false, isComplete: false, roundsRemaining: 1,
}
const feedback: QuestionFeedback = { questionId: 'junior-source-q', selectedOption: 1, correct: true, correctOption: 1, uncertain: false, durationSec: 2, explanation: '化学研究物质的组成、结构、性质和变化。', analysisAssetRefs: [], revisionToken: 'junior-revision' }

function open(activeSession = session, practice = false) {
  render(<LearningRound session={activeSession} payload={payload} practiceMode={practice} practiceDashboard={practice ? dashboard : undefined} onExit={vi.fn()} onContinue={vi.fn(async () => undefined)} onComplete={vi.fn()} />)
  fireEvent.click(screen.getByRole('button', { name: '开始练习' }))
  fireEvent.click(screen.getByRole('button', { name: 'B. 物质组成' }))
}

describe('teacher-managed native source feedback', () => {
  beforeEach(() => {
    vi.mocked(loadQuestionFeedback).mockResolvedValue({ feedback, simulated: false })
    vi.mocked(previewQuestionFeedback).mockResolvedValue({ feedback, simulated: true })
    vi.mocked(submitAttempt).mockResolvedValue({ dashboard, achievements: [], feedback: [feedback] })
  })
  afterEach(() => { cleanup(); vi.resetAllMocks() })

  it('locks a junior native choice on the server before revealing feedback for a cross-grade plan', async () => {
    let resolve!: (result: { feedback: QuestionFeedback; simulated: boolean }) => void
    vi.mocked(loadQuestionFeedback).mockReturnValue(new Promise((done) => { resolve = done }))
    open()
    expect(screen.queryByText(feedback.explanation)).not.toBeInTheDocument()
    expect(loadQuestionFeedback).not.toHaveBeenCalled()
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(screen.getByRole('button', { name: 'B. 物质组成' })).toBeDisabled()
    expect(screen.queryByText('回答正确')).not.toBeInTheDocument()
    resolve({ feedback, simulated: false })
    expect(await screen.findByText('回答正确')).toBeInTheDocument()
    expect(screen.getByText(feedback.explanation)).toBeInTheDocument()
    expect(loadQuestionFeedback).toHaveBeenCalledWith(session, expect.objectContaining({ planId: 'managed-plan', questionId: 'junior-source-q', selectedOption: 1, revisionToken: 'junior-revision' }))
    fireEvent.click(screen.getByRole('button', { name: '完成今日题组' }))
    await waitFor(() => expect(submitAttempt).toHaveBeenCalledTimes(1))
    expect(vi.mocked(submitAttempt).mock.calls[0][1].answers).toEqual([expect.objectContaining({ questionId: 'junior-source-q', correct: true, selectedOption: 1 })])
  })

  it('keeps the answer ungraded when feedback fails, then allows a retry', async () => {
    vi.mocked(loadQuestionFeedback).mockRejectedValueOnce(new Error('连接中断，请重试。'))
    open()
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('连接中断')
    expect(screen.queryByText(/回答错误|回答正确/)).not.toBeInTheDocument()
    expect(submitAttempt).not.toHaveBeenCalled()
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByText('回答正确')).toBeInTheDocument()
    expect(loadQuestionFeedback).toHaveBeenCalledTimes(2)
  })

  it('uses the read-only teacher feedback route and never submits a student attempt', async () => {
    const teacher: SessionIdentity = { ...session, role: 'teacher' }
    open(teacher, true)
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByText('回答正确')).toBeInTheDocument()
    expect(previewQuestionFeedback).toHaveBeenCalledWith(expect.objectContaining({ studentId: 's', previewRound: 1, previewAnswers: [], questionId: 'junior-source-q', selectedOption: 1 }))
    expect(loadQuestionFeedback).not.toHaveBeenCalled()
    fireEvent.click(screen.getByRole('button', { name: '完成第 1 轮' }))
    expect(await screen.findByRole('heading', { name: '本组全部回答正确。' })).toBeInTheDocument()
    expect(submitAttempt).not.toHaveBeenCalled()
  })
})
