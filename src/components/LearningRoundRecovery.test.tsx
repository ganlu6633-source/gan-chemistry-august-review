import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { KnowledgeCard, Question, SessionIdentity, StudentDashboardData } from '../domain/types'
import { submitAttempt } from '../lib/api'
import { LearningRound, type PlanPayload } from './StudentApp'

vi.mock('../lib/api', () => ({
  accessApi: vi.fn(), loadLearningRecord: vi.fn(), teacherApi: vi.fn(), loadQuestionAsset: vi.fn(),
  loadQuestionFeedback: vi.fn(), previewQuestionFeedback: vi.fn(), submitAttempt: vi.fn(),
}))

const session: SessionIdentity = { role: 'student', token: 'test-session', displayName: '学生', expiresAt: '2099-01-01T00:00:00Z' }
const dashboard: StudentDashboardData = { profile: { id: 'student', displayName: '学生', gradeBand: '高三',
  enrollmentStartDate: '2026-09-12', needsInitialDiagnostic: false }, plans: [], skillStates: [], skillDefinitions: [],
  todayQuestionCount: 1, achievements: [] }
const card: KnowledgeCard = { id: 'card-electro', skillId: 'H3_ELECTRO', title: '电化学综合', core: '先判电极', detail: '先看装置',
  steps: [], commonMistakes: [], microExample: '', reviewStatus: 'approved', structuredContent: { version: 2,
    intro: '先拆开每一步', sections: [
      { title: '电极判断', items: [{ label: '判正负极', rule: '放电时负极发生氧化反应。' }] },
      { title: '电子转移方向', items: [{ label: '电子走外电路', rule: '电子由负极经外电路流向正极。' }] },
    ] } }
const question: Question = { id: 'electro-q', motherId: 'electro-m', skillId: 'H3_ELECTRO', conceptKey: 'H3_ELECTRO__C01',
  level: 2, gradeBand: '高三', stem: '判断放电时的电极', options: ['甲', '乙', '丙', '丁'], correctOption: 0,
  explanation: '负极氧化，电子经外电路流向正极。', reviewStatus: 'approved', scopeStatus: 'IN', sourceKind: 'teacher_original' }
const payload: PlanPayload = { plan: { id: 'plan', studentId: 'student', date: '2026-09-12', mode: 'REVIEW', title: '电化学练习',
  skillIds: ['H3_ELECTRO'], knowledgeSummaries: ['电化学'], estimatedMinutes: 8, isScheduled: true, attemptCount: 0,
  firstScore: null, latestScore: null, latestCompletedAt: null, questionCount: 1, roundLimit: 1, maxQuestionLevel: 3,
  isResolved: false, isComplete: false, roundsRemaining: 1 }, cards: [card], questions: [question],
  attemptSequence: 0, roundNumber: 1, roundLimit: 1, questionCount: 1, isResolved: false, isComplete: false, roundsRemaining: 1 }

describe('wrong-answer recovery', () => {
  afterEach(() => { cleanup(); vi.resetAllMocks() })

  it('offers knowledge self-rating, a small-point repair path and a real same-concept question action', async () => {
    vi.mocked(submitAttempt).mockResolvedValue({ dashboard, achievements: [] })
    const openFocused = vi.fn(async () => undefined)
    render(<LearningRound session={session} payload={payload} studyTopics={[{ skillId: 'H3_ELECTRO', skillTitle: '电化学',
      conceptKey: 'H3_ELECTRO__C01', title: '原电池与燃料电池放电原理', sequence: 1, originalCount: 5,
      freshCount: 2, releaseId: 'release', releaseKind: 'primary', answeredCount: 1, recentCorrect: 0,
      reviewDueAt: null, reviewPriority: 100, reviewReason: '最近答错' }]}
      onOpenFocusedTopic={openFocused} onExit={vi.fn()} onContinue={vi.fn(async () => undefined)} onComplete={vi.fn()} />)

    fireEvent.click(screen.getByRole('button', { name: /不知道/ }))
    fireEvent.click(screen.getByRole('button', { name: '开始练习' }))
    fireEvent.click(screen.getByRole('button', { name: 'B. 乙' }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    fireEvent.click(screen.getByRole('button', { name: '完成今日题组' }))
    expect(await screen.findByRole('heading', { name: '本组答对 0/1 题。' })).toBeInTheDocument()
    expect(screen.getByText('原电池与燃料电池放电原理')).toBeInTheDocument()
    fireEvent.click(within(screen.getByText('原电池与燃料电池放电原理').closest('article')!).getByRole('button', { name: '复习这块' }))
    expect(screen.getByRole('heading', { name: '先找卡住的那一环' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /电极判断/ }))
    expect(screen.getByText('放电时负极发生氧化反应。')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /眼熟/ }))
    expect(screen.getByRole('heading', { name: '这块复习完，拿原题检验一下' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /原电池与燃料电池放电原理.*2 道未做原题/ }))
    await waitFor(() => expect(openFocused).toHaveBeenCalledWith('H3_ELECTRO', 'H3_ELECTRO__C01'))
  })
})
