import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { KnowledgeCard, QuestionAssetRef, SessionIdentity, StudentDashboardData } from '../domain/types'
import { loadQuestionAsset, loadQuestionFeedback, submitAttempt } from '../lib/api'
import { LearningRound, type PlanPayload } from './StudentApp'

vi.mock('../lib/api', () => ({
  accessApi: vi.fn(),
  loadLearningRecord: vi.fn(),
  teacherApi: vi.fn(),
  loadQuestionAsset: vi.fn(),
  loadQuestionFeedback: vi.fn(),
  previewQuestionFeedback: vi.fn(),
  submitAttempt: vi.fn(),
}))

const session: SessionIdentity = { role: 'student', token: 'h3-session', displayName: '高三学生', expiresAt: '2099-01-01T00:00:00Z' }
const dashboard: StudentDashboardData = {
  profile: { id: 'student-h3', displayName: '高三学生', gradeBand: '高三', enrollmentStartDate: '2026-08-01', needsInitialDiagnostic: false },
  plans: [], skillStates: [], skillDefinitions: [], todayQuestionCount: 1, achievements: [],
}
const assetRef = (assetId: string, kind: string, alt: string) => ({ assetId, kind, alt, sha256: `${assetId}-sha`, width: 800, height: 500 }) as unknown as QuestionAssetRef
const sourceQuestion: PlanPayload['questions'][number] = {
  id: 'licensed-h3-q1', motherId: 'licensed-h3-m1', skillId: 'H3_STOICH', level: 3, gradeBand: '高三',
  stem: '原题逐字转写题干', options: ['1 mol·L-1 OCR原文', '原题选项乙', '原题选项丙', '原题选项丁'],
  reviewStatus: 'approved', scopeStatus: 'IN', sourceKind: 'licensed_local', renderMode: 'image_primary', revisionToken: 'sha256-question-revision',
  sourceInfo: { title: '高考真题分类汇编', exam: '2025年福建省质检', year: 2025, questionNo: '第8题', locator: '第3页' },
  assetRefs: [assetRef('problem-image', 'question_image', '第8题原题题面')],
}
const answerFeedback = {
  questionId: sourceQuestion.id, selectedOption: 0, correct: true, correctOption: 0,
  uncertain: false, durationSec: 8, explanation: '原题文字解析。', scaffold: null,
  analysisAssetRefs: [assetRef('analysis-image', 'analysis_image', '第8题原题解析')],
  revisionToken: sourceQuestion.revisionToken,
}
const card: KnowledgeCard = { id: 'card', skillId: 'H3_STOICH', title: '计量', core: '守恒', detail: '守恒', steps: [], commonMistakes: [], microExample: '', reviewStatus: 'approved' }

const payload: PlanPayload = {
  plan: { id: 'h3-plan', studentId: 'student-h3', date: '2026-08-17', mode: 'REVIEW', title: '高三原题复习', skillIds: ['H3_STOICH'], knowledgeSummaries: ['物质的量'], estimatedMinutes: 8, source: 'exam', isScheduled: true, attemptCount: 1, firstScore: 0, latestScore: 0, latestCompletedAt: null, questionCount: 1, roundLimit: 5, maxQuestionLevel: 4, isResolved: false, isComplete: false, roundsRemaining: 4 },
  cards: [card], questions: [sourceQuestion], attemptSequence: 1, roundNumber: 2, roundLimit: 5, questionCount: 1, isResolved: false, isComplete: false, roundsRemaining: 4,
}

describe('LearningRound licensed source question', () => {
  beforeEach(() => {
    vi.mocked(loadQuestionAsset).mockImplementation(async (_session, _questionId, assetId) => ({ asset: { dataUrl: `data:image/png;base64,${assetId}`, mimeType: 'image/png', sha256: `${assetId}-sha`, width: 800, height: 500 } }))
    vi.mocked(loadQuestionFeedback).mockResolvedValue({ feedback: answerFeedback, simulated: false })
    vi.mocked(submitAttempt).mockResolvedValue({ dashboard, achievements: [], feedback: [answerFeedback] })
  })
  afterEach(() => { cleanup(); vi.clearAllMocks() })

  it('highlights every option synchronously without reloading the protected image', async () => {
    render(<LearningRound session={session} payload={payload} onExit={vi.fn()} onContinue={vi.fn(async () => undefined)} onComplete={vi.fn()} />)

    expect(await screen.findByAltText('本题原题题面图')).toBeInTheDocument()
    const options = screen.getByRole('article').querySelector<HTMLElement>('.option-list')!
    const answerA = within(options).getByRole('button', { name: 'A 选项，内容见原题图' })
    const answerB = within(options).getByRole('button', { name: 'B 选项，内容见原题图' })
    const answerC = within(options).getByRole('button', { name: 'C 选项，内容见原题图' })

    fireEvent.click(answerA)
    expect(answerA).toHaveClass('selected')
    fireEvent.click(answerB)
    expect(answerB).toHaveClass('selected')
    expect(answerA).not.toHaveClass('selected')
    fireEvent.click(answerC)
    expect(answerC).toHaveClass('selected')
    expect(loadQuestionAsset).toHaveBeenCalledTimes(1)
    expect(loadQuestionFeedback).not.toHaveBeenCalled()
    expect(submitAttempt).not.toHaveBeenCalled()
  })

  it('uses the exact source image without student-facing source or analysis artwork, and submits the revision token', async () => {
    render(<LearningRound session={session} payload={payload} onExit={vi.fn()} onContinue={vi.fn(async () => undefined)} onComplete={vi.fn()} />)

    expect(await screen.findByAltText('本题原题题面图')).toBeInTheDocument()
    expect(screen.queryByLabelText('原题来源')).not.toBeInTheDocument()
    expect(sourceQuestion).not.toHaveProperty('correctOption')
    expect(sourceQuestion).not.toHaveProperty('explanation')
    const context = { planId: 'h3-plan', attemptSequence: 1, revisionToken: 'sha256-question-revision' }
    expect(loadQuestionAsset).toHaveBeenCalledWith(session, 'licensed-h3-q1', 'problem-image', 'question', context)
    expect(loadQuestionAsset).not.toHaveBeenCalledWith(session, 'licensed-h3-q1', 'analysis-image', 'analysis', context)
    const options = screen.getByRole('article').querySelector<HTMLElement>('.option-list')!
    const answerA = within(options).getByRole('button', { name: 'A 选项，内容见原题图' })
    expect(answerA).toHaveTextContent(/^A$/)
    expect(answerA).not.toHaveAccessibleName(/mol|OCR|原题选项/)

    fireEvent.click(answerA)
    fireEvent.click(screen.getByRole('button', { name: '放大查看本题原题题面图' }))
    fireEvent.click(screen.getByRole('button', { name: '关闭原题大图' }))
    await waitFor(() => expect(screen.getByRole('button', { name: '提交答案' })).toHaveFocus())
    fireEvent.keyDown(window, { key: 'Enter' })
    expect(await screen.findByText(/判断正确/)).toBeInTheDocument()
    expect(loadQuestionFeedback).toHaveBeenCalledWith(session, expect.objectContaining({ planId: 'h3-plan', questionId: 'licensed-h3-q1', selectedOption: 0, revisionToken: 'sha256-question-revision' }))
    expect(screen.queryByRole('heading', { name: '原题解析图' })).not.toBeInTheDocument()
    expect(screen.queryByAltText('第8题原题解析')).not.toBeInTheDocument()
    expect(loadQuestionAsset).not.toHaveBeenCalledWith(session, 'licensed-h3-q1', 'analysis-image', 'analysis', context)
    fireEvent.click(screen.getByRole('button', { name: '完成第 2 轮' }))

    await waitFor(() => expect(submitAttempt).toHaveBeenCalledTimes(1))
    const submitted = vi.mocked(submitAttempt).mock.calls[0][1]
    expect(submitted.answers[0]).toMatchObject({ questionId: 'licensed-h3-q1', selectedOption: 0, revisionToken: 'sha256-question-revision' })
  })

  it('restores a server-locked first answer after refresh without allowing a new choice', async () => {
    render(<LearningRound session={session} payload={{ ...payload, lockedFeedback: [answerFeedback] }} onExit={vi.fn()} onContinue={vi.fn(async () => undefined)} onComplete={vi.fn()} />)

    expect(await screen.findByText(/判断正确/)).toBeInTheDocument()
    const answerA = screen.getByRole('button', { name: 'A 选项，内容见原题图' })
    expect(answerA).toBeDisabled()
    expect(loadQuestionFeedback).not.toHaveBeenCalled()
    expect(screen.queryByAltText('第8题原题解析')).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: '完成第 2 轮' }))
    await waitFor(() => expect(submitAttempt).toHaveBeenCalledTimes(1))
    expect(vi.mocked(submitAttempt).mock.calls[0][1].answers).toEqual([
      expect.objectContaining({ questionId: 'licensed-h3-q1', selectedOption: 0, correct: true }),
    ])
  })

  it('presents a formal one-package day as today, not as another same-day round', async () => {
    const dailyPayload: PlanPayload = {
      ...payload,
      plan: { ...payload.plan, attemptCount: 0, roundLimit: 1, roundsRemaining: 1 },
      attemptSequence: 0,
      roundNumber: 1,
      roundLimit: 1,
      roundsRemaining: 1,
    }
    render(<LearningRound session={session} payload={dailyPayload} onExit={vi.fn()} onContinue={vi.fn(async () => undefined)} onComplete={vi.fn()} />)

    fireEvent.click(screen.getByRole('button', { name: /我理解了，开始练习/ }))
    expect(await screen.findByAltText('本题原题题面图')).toBeInTheDocument()
    expect(screen.getByLabelText('今日复习题组')).toBeInTheDocument()
    expect(screen.getByText(/今日题组 · 1\/1/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'A 选项，内容见原题图' }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByText('判断正确，下次复习可提高难度')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '完成今日题组' }))

    expect(await screen.findByRole('heading', { name: '今天全部答对；下次复习可以提高难度。' })).toBeInTheDocument()
    expect(screen.queryByText(/进入第 2 轮/)).not.toBeInTheDocument()
  })
})
