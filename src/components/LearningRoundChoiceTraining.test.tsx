import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { GradeBand, KnowledgeCard, OptionPracticeProgress, Question, QuestionFeedback, StudentDashboardData } from '../domain/types'
import { loadQuestionFeedback, previewQuestionFeedback, saveKnowledgeRating, submitAttempt, type QuestionFeedbackInput } from '../lib/api'
import { LearningRound, type PlanPayload } from './StudentApp'

vi.mock('../lib/api', () => ({ accessApi: vi.fn(), loadLearningRecord: vi.fn(), teacherApi: vi.fn(), loadQuestionAsset: vi.fn(),
  loadQuestionFeedback: vi.fn(), previewQuestionFeedback: vi.fn(), submitAttempt: vi.fn(), saveKnowledgeRating: vi.fn() }))

const point = '由电荷守恒判断离子个数'
function fixture(grade: GradeBand = '高三', unrelatedFirst = false) {
  const skillId = `${grade}-skill`
  const card: KnowledgeCard = { id: 'card', skillId, title: '离子关系判断', core: '按电荷守恒分析。', detail: '正负电荷总数相等。', steps: [], commonMistakes: [], microExample: '先列电荷守恒关系。', reviewStatus: 'approved',
    structuredContent: { version: 1, intro: '一个小点一次检查。', sections: [{ title: '数量判断', items: [
      ...(unrelatedFirst ? [{ label: '不相关的第一个小点', rule: '这个小点不对应刚才的错项。' }] : []),
      { label: point, rule: '由正负电荷总数相等列出离子数量关系。', examples: ['每个离子的电荷数必须计入。'] },
    ] }] } }
  const base = (index: number): Question => ({ id: `q${index}`, motherId: `mother-${index}`, skillId, conceptKey: 'concept',
    gradeBand: grade, level: 1, stem: `选择题 ${index + 1}`, options: ['甲', '乙', '丙', '丁'],
    reviewStatus: 'approved', scopeStatus: 'IN', sourceKind: 'licensed_local', renderMode: 'native', revisionToken: `rev-${index}`,
    choiceContext: { recoveryRound: index < 8 ? 0 : Math.floor((index - 8) / 3) + 1 },
    ...(index < 8 ? {} : { optionPractice: { anchorQuestionId: index < 11 ? 'q0' : index < 14 ? 'q10' : 'q13', optionIndex: 1, knowledgePoint: point,
      position: (index - 8) % 3 + 1, total: 3, recoveryRound: Math.floor((index - 8) / 3) + 1 } }) })
  const questions = Array.from({ length: 17 }, (_, i) => base(i))
  // Actual SQL starts a new branch at the incorrectly answered reserve in each
  // later round; reusing q0 for all rounds would hide skipped review cards.
  const branches = (count: number): OptionPracticeProgress[] => [8, 11, 14].filter(start => start < count).map((start, index) => ({
    anchorQuestionId: ['q0', 'q10', 'q13'][index], optionIndex: 1, recoveryRound: index + 1,
    knowledgePoint: point, questionIds: questions.slice(start, Math.min(start + 3, count)).map(q => q.id),
    answered: Math.max(0, Math.min(3, count - start - 3)), correct: 0, status: count > start + 3 ? 'needs_practice' : 'practicing',
  }))
  const choice = (complete = false) => ({ policyVersion: 'choice_8_3_30_v1' as const, baseQuestionCount: 8, dailyUsed: 0, dailyRemaining: 30, complete, pendingReason: null })
  const payload: PlanPayload = { plan: { id: 'plan', studentId: 'student', date: '2026-09-29', mode: 'REVIEW', title: '课堂原题', skillIds: [skillId], knowledgeSummaries: [point],
    estimatedMinutes: 15, isScheduled: true, attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null, questionCount: 8,
    roundLimit: 1, maxQuestionLevel: 2, isResolved: false, isComplete: false, roundsRemaining: 1 }, cards: [card], questions: questions.slice(0, 8),
    attemptSequence: 0, roundNumber: 1, roundLimit: 1, questionCount: 8, baseQuestionCount: 8, optionPractice: [], choiceTraining: choice(),
    isResolved: false, isComplete: false, roundsRemaining: 1 }
  const dashboard: StudentDashboardData = { profile: { id: 'student', displayName: '测试', gradeBand: grade, enrollmentStartDate: '2026-09-01', needsInitialDiagnostic: false },
    plans: [payload.plan], skillStates: [], skillDefinitions: [], todayQuestionCount: 8, achievements: [] }
  return { payload, dashboard, questions, branches, choice }
}
const feedbackFor = (id: string, selected = 0): QuestionFeedback => ({ questionId: id, selectedOption: selected, correct: selected === 0,
  correctOption: 0, uncertain: false, durationSec: 7, explanation: 'A. 判断成立。\nB. 应当按照电荷守恒列式。', analysisAssetRefs: [], revisionToken: `rev-${id.slice(1)}` })
function show(f: ReturnType<typeof fixture>, preview: boolean, extra: Partial<Parameters<typeof LearningRound>[0]> = {}) {
  return render(<LearningRound session={{ role: preview ? 'teacher' : 'student', token: 'session', displayName: '测试', expiresAt: '2099-01-01' }}
    payload={f.payload} practiceMode={preview} practiceDashboard={f.dashboard} onExit={vi.fn()} onContinue={vi.fn(async () => {})} onComplete={vi.fn()} {...extra} />)
}
describe('high-school eight-question and three-recovery-round UI', () => {
  afterEach(() => { cleanup(); vi.resetAllMocks() })
  it.each((['高一', '高二', '高三'] as const).flatMap(grade => [false, true].map(preview => ({ grade, preview }))))('keeps the first eight together and reviews each of three reserve rounds ($grade, preview=$preview)', async ({ grade, preview }) => {
      const f = fixture(grade)
      const inputs: QuestionFeedbackInput[] = []
      const response = async (input: QuestionFeedbackInput) => {
        inputs.push(input)
        const index = Number(input.questionId.slice(1))
        const count = index < 7 ? 8 : index < 10 ? 11 : index < 13 ? 14 : 17
        return { feedback: feedbackFor(input.questionId, input.selectedOption), simulated: preview,
          questions: f.questions.slice(0, count), optionPractice: index >= 7 ? f.branches(count) : [], choiceTraining: f.choice(index === 16) }
      }
      vi.mocked(loadQuestionFeedback).mockImplementation(async (_session, input) => response(input))
      vi.mocked(previewQuestionFeedback).mockImplementation(async input => ({ ...await response(input), simulated: true }))
      vi.mocked(submitAttempt).mockImplementation(async (_session, attempt) => ({ dashboard: f.dashboard, achievements: [],
        feedback: attempt.answers.map(answer => feedbackFor(answer.questionId, answer.selectedOption)) }))
      show(f, preview)
      fireEvent.click(screen.getByRole('button', { name: '开始练习' }))
      for (let index = 0; index < 17; index++) {
        expect(screen.getByRole('heading', { name: `选择题 ${index + 1}` })).toBeInTheDocument()
        fireEvent.click(screen.getByRole('button', { name: [0, 10, 13, 16].includes(index) ? 'B. 乙' : 'A. 甲' }))
        fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
        await waitFor(() => expect(inputs).toHaveLength(index + 1))
        await screen.findByText([0, 10, 13, 16].includes(index) ? '回答错误，正确选项是 A' : '回答正确')
        if (index < 16) {
          fireEvent.click(screen.getByRole('button', { name: '下一题' }))
          if ([7, 10, 13].includes(index)) {
            expect(screen.getByRole('heading', { name: point, level: 2 })).toBeInTheDocument()
            expect(screen.queryByRole('heading', { name: `选择题 ${index + 2}` })).not.toBeInTheDocument()
            expect(screen.queryByRole('button', { name: /进入第 .* 轮同类型训练/ })).not.toBeInTheDocument()
            fireEvent.click(screen.getByRole('button', { name: /不知道 需要从头/ }))
            fireEvent.click(screen.getByRole('button', { name: `进入第 ${(index - 7) / 3 + 1} 轮同类型训练` }))
          } else expect(screen.queryByText('知识点补给站')).not.toBeInTheDocument()
        }
      }
      fireEvent.click(screen.getByRole('button', { name: '完成今日题组' }))
      expect(await screen.findByRole('heading', { name: '本组答对 13/17 题。' })).toBeInTheDocument()
      expect(inputs.map(input => input.questionId)).toEqual(f.questions.map(question => question.id))
      expect(saveKnowledgeRating).not.toHaveBeenCalled()
      if (preview) {
        expect(loadQuestionFeedback).not.toHaveBeenCalled()
        expect(submitAttempt).not.toHaveBeenCalled()
        for (const [index, input] of inputs.entries()) {
          expect(input.studentId).toBe('student')
          expect(input.previewAnswers?.map(answer => answer.questionId)).toEqual(f.questions.slice(0, index).map(question => question.id))
        }
      } else {
        expect(previewQuestionFeedback).not.toHaveBeenCalled()
        expect(submitAttempt).toHaveBeenCalledTimes(1)
        expect(vi.mocked(submitAttempt).mock.calls[0][1].answers.map(answer => answer.questionId)).toEqual(f.questions.map(question => question.id))
      }
    })

  it.each([false, true])('restores an issued reserve to its exact second leaf before presenting the question (preview=%s)', async (preview) => {
    const f = fixture('高二', true)
    f.payload.questions = f.questions.slice(0, 11)
    f.payload.lockedFeedback = f.questions.slice(0, 8).map((q, i) => feedbackFor(q.id, i === 0 ? 1 : 0))
    f.payload.optionPractice = f.branches(11)
    show(f, preview)
    expect(await screen.findByRole('heading', { name: point, level: 2 })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: '不相关的第一个小点' })).not.toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: '选择题 9' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '← 回看刚才的题目' }))
    expect(screen.getByRole('heading', { name: '选择题 8' })).toBeInTheDocument()
    expect(screen.getByText('回答正确')).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: '选择题 9' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '下一题' }))
    expect(screen.getByRole('heading', { name: point, level: 2 })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /眼熟 见过/ }))
    fireEvent.click(screen.getByRole('button', { name: '进入第 1 轮同类型训练' }))
    expect(screen.getByRole('heading', { name: '选择题 9' })).toBeInTheDocument()
    expect(loadQuestionFeedback).not.toHaveBeenCalled()
    expect(previewQuestionFeedback).not.toHaveBeenCalled()
    expect(submitAttempt).not.toHaveBeenCalled()
  })

  it.each([false, true].flatMap(preview => [false, true].map(exactLeaf => ({ preview, exactLeaf }))))('keeps a reserve-gap review on the exact small point and leaves other module questions out (preview=$preview, exactLeaf=$exactLeaf)', async ({ preview, exactLeaf }) => {
    const f = fixture('高一', true)
    const gapPoint = exactLeaf ? point : '另一个已审核选项小点'
    f.payload.lockedFeedback = f.questions.slice(0, 8).map((q, i) => feedbackFor(q.id, i === 0 ? 1 : 0))
    f.payload.choiceTraining = f.choice(true)
    f.payload.optionPractice = [{ anchorQuestionId: 'q0', optionIndex: 1, knowledgePoint: gapPoint,
      questionIds: [], answered: 0, correct: 0, status: 'reserve_gap', recoveryRound: 1 }]
    vi.mocked(submitAttempt).mockResolvedValue({ dashboard: f.dashboard, achievements: [], feedback: f.payload.lockedFeedback })
    vi.mocked(saveKnowledgeRating).mockResolvedValue({ ok: true })
    show(f, preview, { onOpenFocusedTopic: vi.fn(async () => {}), studyTopics: [{ skillId: f.questions[0].skillId,
      skillTitle: '离子关系判断', conceptKey: 'concept', title: '整个模块的综合题', sequence: 1, originalCount: 6, freshCount: 4,
      releaseId: 'release', releaseKind: 'primary', answeredCount: 2, recentCorrect: 1, reviewDueAt: null,
      reviewPriority: 100, reviewReason: '最近答错' }] })
    fireEvent.click(screen.getByRole('button', { name: '完成今日题组' }))
    expect(await screen.findByRole('heading', { name: '本组答对 7/8 题。' })).toBeInTheDocument()
    expect(screen.getByText(/暂缺足量、已审核的同类型原题/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: '练同知识点原题' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '复习这块' }))
    expect(screen.getByRole('heading', { name: gapPoint, level: 2 })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: '不相关的第一个小点' })).not.toBeInTheDocument()
    if (!exactLeaf) {
      expect(screen.getByText('应当按照电荷守恒列式。')).toBeInTheDocument()
      expect(screen.queryByText('判断成立。')).not.toBeInTheDocument()
    }
    fireEvent.click(screen.getByRole('button', { name: /眼熟 见过/ }))
    expect(screen.getByRole('heading', { name: '这块复习完，拿原题检验一下' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /整个模块的综合题/ })).not.toBeInTheDocument()
    if (preview || !exactLeaf) expect(saveKnowledgeRating).not.toHaveBeenCalled()
    else await waitFor(() => expect(saveKnowledgeRating).toHaveBeenCalledWith(expect.anything(), 'plan', expect.any(String), 'card:s0:i1:p0', 'familiar'))
  })

  it.each([false, true])('reviews the small point before a reserve for a correct but uncertain saved answer (preview=%s)', async preview => {
    const f = fixture('高二', true)
    f.payload.questions = f.questions.slice(0, 11)
    f.payload.lockedFeedback = f.questions.slice(0, 8).map((q, i) => ({ ...feedbackFor(q.id), uncertain: i === 0 }))
    f.payload.optionPractice = f.branches(11).map(branch => ({ ...branch, optionIndex: 0 }))
    show(f, preview)
    expect(await screen.findByRole('heading', { name: point, level: 2 })).toBeInTheDocument()
    expect(screen.getByText(/选错或拿不准的选项/)).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: '选择题 9' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /眼熟 见过/ }))
    fireEvent.click(screen.getByRole('button', { name: '进入第 1 轮同类型训练' }))
    expect(screen.getByRole('heading', { name: '选择题 9' })).toBeInTheDocument()
    expect(submitAttempt).not.toHaveBeenCalled()
    expect(saveKnowledgeRating).not.toHaveBeenCalled()
  })
})
