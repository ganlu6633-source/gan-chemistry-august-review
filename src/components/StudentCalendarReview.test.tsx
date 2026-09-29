import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { GradeBand, KnowledgeCard, LearningPlanDay, SessionIdentity, StudentDashboardData } from '../domain/types'
import type { StudyTopic } from './StudyLibrary'
import { StudentApp } from './StudentApp'

vi.mock('./JuniorAdaptiveSession', () => ({ JuniorAdaptiveSession: () => <div data-testid="opened-junior-lesson">已打开指定日期</div> }))

function fixture(grade: GradeBand, completed = true) {
  const plan: LearningPlanDay = { id: 'earlier-plan', studentId: 'student', date: '2026-09-01', mode: 'REVIEW',
    title: '9月1日 · 物质的分类与分散系', skillIds: ['same-day-skill'], knowledgeSummaries: ['物质分类'],
    estimatedMinutes: 12, isScheduled: true, attemptCount: completed ? 1 : 0, firstScore: completed ? 3 : null,
    latestScore: completed ? 3 : null, latestCompletedAt: null, questionCount: 4, roundLimit: 1,
    maxQuestionLevel: 2, isResolved: false, isComplete: completed, roundsRemaining: completed ? 0 : 1,
    deliveryMode: grade === '初三' ? 'junior_adaptive' : 'legacy_round',
    juniorSessionStatus: grade === '初三' ? completed ? 'completed' : 'not_started' : null }
  const card: KnowledgeCard = { id: 'day-card', skillId: plan.skillIds[0], title: '物质分类', core: '纯净物只有一种物质。',
    detail: '先数物质种类。', steps: ['先数物质种类'], commonMistakes: ['一种物质可以含多种元素。'],
    microExample: '水是纯净物。', reviewStatus: 'approved' }
  const topic: StudyTopic = { skillId: plan.skillIds[0], skillTitle: card.title, conceptKey: 'classify', title: '判断混合物和纯净物',
    sequence: 1, originalCount: 5, freshCount: 4, releaseId: 'release', releaseKind: 'primary', answeredCount: 1,
    recentCorrect: 1, reviewDueAt: null, reviewPriority: 0, reviewReason: null }
  const otherTopic = { ...topic, skillId: 'unrelated', conceptKey: 'unrelated', title: '不属于这一天的练习' }
  const dashboard: StudentDashboardData = { profile: { id: 'student', displayName: '测试学生', gradeBand: grade,
    enrollmentStartDate: '2026-09-12', needsInitialDiagnostic: false }, plans: [plan], skillStates: [],
    skillDefinitions: [topic, otherTopic].map(t => ({ id: t.skillId, title: t.skillTitle, gradeBand: grade, moduleId: 'module',
      maxLevel: 2, examImportance: 1, examDepth: 1, prerequisites: [], levelCriteria: [] })), todayQuestionCount: 4, achievements: [] }
  const question = { id: 'question', motherId: 'mother', skillId: topic.skillId, level: 1, gradeBand: grade,
    stem: '下列物质属于纯净物的是', options: ['水', '空气', '海水', '泥水'], sourceKind: 'teacher_original',
    correctOption: 0, explanation: '水只有一种物质。', reviewStatus: 'approved', scopeStatus: 'IN' }
  return { plan, dashboard, topic, otherTopic, card, question }
}

describe('date-specific learning and review across grades', () => {
  afterEach(() => { cleanup(); vi.useRealTimers(); vi.unstubAllGlobals(); vi.restoreAllMocks() })
  const cases = (['初三', '高一', '高二', '高三'] as const).flatMap(grade => [false, true].map(previewMode => ({ grade, previewMode })))

  it.each(cases)('opens the completed date itself and routes its review without changing records ($grade, preview=$previewMode)', async ({ grade, previewMode }) => {
    vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date('2026-09-29T04:00:00Z'))
    const f = fixture(grade)
    const requests: Array<{ action: string; data: Record<string, unknown> }> = []
    vi.stubGlobal('fetch', vi.fn(async (_url, init) => {
      const request = JSON.parse(String(init?.body)); requests.push(request)
      if (request.action === 'self_study_catalog') return Response.json({ catalog: { topics: [f.topic, f.otherTopic] } })
      if (request.action === 'knowledge_skill_tree') return Response.json({ card: f.card })
      if (['open_self_study', 'preview_self_study'].includes(request.action)) return Response.json({ payload: {
        plan: { ...f.plan, id: 'review-practice', deliveryMode: 'self_study', isComplete: false, attemptCount: 0 },
        cards: [f.card], questions: [f.question], roundNumber: 1, attemptSequence: 0, roundLimit: 1, questionCount: 1 } })
      return Response.json({ error: `Unexpected action ${request.action}` }, { status: 422 })
    }))
    const session: SessionIdentity = { role: previewMode ? 'teacher' : 'student', token: 'token', displayName: '测试', expiresAt: '2099-01-01' }
    const onDashboard = vi.fn()
    render(<StudentApp session={session} initialDashboard={f.dashboard} onDashboard={onDashboard} previewMode={previewMode} />)
    fireEvent.click(screen.getByRole('button', { name: /学习日历 老师排好的题在这里/ }))
    fireEvent.click(screen.getByRole('button', { name: /2026-09-01 · .*可复习/ }))
    expect(screen.getByRole('heading', { name: f.plan.title })).toBeInTheDocument()
    expect(within(screen.getByLabelText('这一天已有的学习记录')).getAllByText('3 题')).toHaveLength(2)
    expect(await screen.findByText(f.topic.title)).toBeInTheDocument()
    expect(screen.queryByText(f.otherTopic.title)).not.toBeInTheDocument()
    expect(requests.some(r => /start_plan|junior_open_session/.test(r.action))).toBe(false)
    fireEvent.click(screen.getByRole('button', { name: /物质分类 点开大知识点/ }))
    await waitFor(() => expect(requests.some(r => r.action === 'knowledge_skill_tree')).toBe(true))
    const knowledgeRequest = requests.find(r => r.action === 'knowledge_skill_tree')!
    expect(knowledgeRequest.data.skillId).toBe(f.topic.skillId)
    if (previewMode) expect(knowledgeRequest.data.studentId).toBe('student')
    fireEvent.click(screen.getByRole('button', { name: '开始练题' }))
    expect(await screen.findByRole('heading', { name: f.question.stem })).toBeInTheDocument()
    expect(requests.find(r => r.action === (previewMode ? 'preview_self_study' : 'open_self_study'))?.data)
      .toMatchObject({ skillId: f.topic.skillId, conceptKey: f.topic.conceptKey, releaseId: 'release' })
    if (previewMode) expect(requests.every(r => !['open_self_study', 'start_plan', 'junior_open_session', 'submit_attempt', 'submit_question'].includes(r.action))).toBe(true)
    expect(onDashboard).not.toHaveBeenCalled()
  })

  it.each(cases)('opens an unlearned past date as first study ($grade, preview=$previewMode)', async ({ grade, previewMode }) => {
    vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date('2026-09-29T04:00:00Z'))
    const f = fixture(grade, false)
    const requests: Array<{ action: string; data: Record<string, unknown> }> = []
    vi.stubGlobal('fetch', vi.fn(async (_url, init) => {
      const request = JSON.parse(String(init?.body)); requests.push(request)
      if (request.action === 'self_study_catalog') return Response.json({ catalog: { topics: [] } })
      return Response.json({ payload: grade === '初三' ? { deliveryMode: 'junior_adaptive', plan: f.plan, cards: [],
        session: { id: 'session', status: 'active' }, currentQuestion: f.question, completed: false }
        : { plan: f.plan, cards: [f.card], questions: [f.question], attemptSequence: 0, roundNumber: 1, roundLimit: 1, questionCount: 1 } })
    }))
    render(<StudentApp session={{ role: previewMode ? 'teacher' : 'student', token: 'token', displayName: '测试', expiresAt: '2099-01-01' }}
      initialDashboard={f.dashboard} onDashboard={vi.fn()} previewMode={previewMode} />)
    fireEvent.click(screen.getByRole('button', { name: /学习日历 老师排好的题在这里/ }))
    fireEvent.click(screen.getByRole('button', { name: /2026-09-01 · .*还没学过 · 可补学/ }))
    if (grade === '初三') expect(await screen.findByTestId('opened-junior-lesson')).toBeInTheDocument()
    else expect(await screen.findByRole('heading', { name: f.card.title })).toBeInTheDocument()
    const expected = grade === '初三' ? previewMode ? 'preview_junior_open_session' : 'junior_open_session' : previewMode ? 'preview_start_plan' : 'start_plan'
    expect(requests.find(r => r.action === expected)?.data.planId).toBe(f.plan.id)
    expect(requests.some(r => /submit|save_|record_/.test(r.action))).toBe(false)
  })

  it('shows saved partial high-school progress on reload and in reminders', async () => {
    vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date('2026-09-29T04:00:00Z'))
    const f = fixture('高二', false); f.plan.hasStarted = true
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ catalog: { topics: [] } })))
    render(<StudentApp session={{ role: 'student', token: 'token', displayName: '测试', expiresAt: '2099-01-01' }} initialDashboard={f.dashboard} onDashboard={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /学习日历 老师排好的题在这里/ }))
    expect(screen.getByRole('button', { name: /2026-09-01 · .*学习进行中 · 接着练/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '接着学习' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '复习雷达' }))
    expect(screen.getByText('2026-09-01 · 接着做')).toBeInTheDocument()
    await waitFor(() => expect(screen.queryByText('正在读取原题目录…')).not.toBeInTheDocument())
  })

  it.each([false, true].flatMap(previewMode => ['knowledge', 'type'].flatMap(axis => ['null', 'missing', 'empty-questions', 'wrong-student'].map(bad => ({ previewMode, axis, bad })))))('keeps malformed self-study visible and retries the selected topic ($axis, $bad, preview=$previewMode)', async ({ previewMode, axis, bad }) => {
      const f = fixture('高一')
      const validPayload = { plan: { ...f.plan, id: 'self-plan', deliveryMode: 'self_study', isComplete: false, attemptCount: 0 },
        cards: [f.card], questions: [f.question], roundNumber: 1, attemptSequence: 0, roundLimit: 1, questionCount: 1 }
      const requests: Array<{ action: string; data: Record<string, unknown> }> = []
      vi.stubGlobal('fetch', vi.fn(async (_url, init) => {
        const request = JSON.parse(String(init?.body))
        if (request.action === 'self_study_catalog') return Response.json({ catalog: { topics: [f.topic] } })
        requests.push(request)
        if (requests.length > 1) return Response.json({ payload: validPayload })
        return Response.json(bad === 'null' ? { payload: null } : bad === 'missing' ? {} : bad === 'empty-questions'
          ? { payload: { ...validPayload, questions: [] } }
          : { payload: { ...validPayload, plan: { ...validPayload.plan, studentId: 'another-student' } } })
      }))
      const onDashboard = vi.fn()
      render(<StudentApp session={{ role: previewMode ? 'teacher' : 'student', token: 'token', displayName: '测试', expiresAt: '2099-01-01' }}
        initialDashboard={f.dashboard} onDashboard={onDashboard} previewMode={previewMode} />)
      fireEvent.click(screen.getByRole('button', { name: axis === 'type' ? /题型训练场 想练哪类/ : /知识点任选 今天想攻/ }))
      fireEvent.click(await screen.findByRole('button', { name: '开始练题' }))
      expect(await screen.findByRole('alert')).toHaveTextContent('这组原题没有完整送达')
      expect(screen.getByLabelText('自主练习没有打开')).toHaveClass('plan-opening-overlay')
      expect(screen.getByRole('heading', { name: axis === 'type' ? '题型训练场' : '知识点任选' })).toBeInTheDocument()
      expect(onDashboard).not.toHaveBeenCalled()
      fireEvent.click(screen.getByRole('button', { name: '重新打开这组原题' }))
      expect(await screen.findByRole('heading', { name: f.question.stem })).toBeInTheDocument()
      expect(screen.queryByLabelText('自主练习没有打开')).not.toBeInTheDocument()
      expect(requests).toHaveLength(2)
      expect(requests[1]).toEqual(requests[0])
      expect(requests[0]).toMatchObject({ action: previewMode ? 'preview_self_study' : 'open_self_study',
        data: { skillId: f.topic.skillId, conceptKey: f.topic.conceptKey, releaseId: f.topic.releaseId } })
      expect(onDashboard).not.toHaveBeenCalled()
    })
})
