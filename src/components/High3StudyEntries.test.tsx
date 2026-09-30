import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { high3LearningStops, high3TaskType, HIGH3_TASK_TYPES } from '../domain/high3StudyNavigation'
import type { LearningPlanDay, StudentDashboardData } from '../domain/types'
import { High3LearningRoute } from './High3LearningRoute'
import { StudyLibrary, type StudyTopic } from './StudyLibrary'

function plan(id: string, date: string, focus: string, overrides: Partial<LearningPlanDay> = {}): LearningPlanDay {
  return { id, studentId: 'student', date, mode: 'REVIEW', title: `题组${id}`, skillIds: ['H3_STOICH', 'H3_ELECTRO'],
    targetConceptKeys: [focus], knowledgeSummaries: ['只练当前细点'], estimatedMinutes: 12, isScheduled: true,
    attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null, questionCount: 8, roundLimit: 4,
    maxQuestionLevel: null, isResolved: false, isComplete: false, roundsRemaining: 4,
    choiceTrainingPolicy: 'choice_8_3_30_v1', ...overrides }
}

function dashboard(plans: LearningPlanDay[] = []): StudentDashboardData {
  return { profile: { id: 'student', displayName: '测试学生', gradeBand: '高三', enrollmentStartDate: '2026-09-12', needsInitialDiagnostic: false },
    plans, skillStates: [], skillDefinitions: [], achievements: [], todayQuestionCount: 0 }
}

function topic(skillId: string, conceptKey: string, title: string, releaseId = 'release-1'): StudyTopic {
  return { skillId, skillTitle: skillId === 'H3_STOICH' ? '化学计量' : '电化学', conceptKey, title, sequence: 1,
    originalCount: 4, freshCount: 3, releaseId, releaseKind: 'primary', answeredCount: 0,
    recentCorrect: 0, reviewDueAt: null, reviewPriority: 0, reviewReason: null }
}

afterEach(cleanup)

describe('high-three learning route', () => {
  it('uses actual lesson focus and sequence, preserves revisits, and excludes hidden/self-study plans', () => {
    const early = plan('early', '2026-09-01', 'H3_STOICH__C01')
    const middle = plan('middle', '2026-09-04', 'H3_ELECTRO__C01')
    const revisit = plan('revisit', '2026-10-01', 'H3_STOICH__C05')
    const hidden = plan('hidden', '2026-09-02', 'H3_STRUCTURE__C01', { isScheduled: false })
    const selfStudy = plan('self', '2026-09-03', 'H3_ORGANIC__C01', { deliveryMode: 'self_study' })
    const stops = high3LearningStops([revisit, middle, hidden, selfStudy, early], [])
    expect(stops.map((stop) => stop.title)).toEqual(['化学计量', '电化学', '化学计量'])
    expect(stops.flatMap((stop) => stop.plans)).toEqual([early, middle, revisit])
  })

  it('does not mark past dates as learned and opens original plans for first learning, continuation and review', () => {
    const untouched = plan('first', '2026-09-01', 'H3_STOICH__C01')
    const completed = plan('done', '2026-09-02', 'H3_STOICH__C05', { isComplete: true, attemptCount: 1 })
    const partial = plan('partial', '2026-09-03', 'H3_ELECTRO__C01', { hasStarted: true })
    const onOpenPlan = vi.fn().mockResolvedValue(true)
    render(<High3LearningRoute dashboard={dashboard([untouched, completed, partial])} today="2026-10-01" onOpenPlan={onOpenPlan} busy={false} />)
    expect(onOpenPlan).not.toHaveBeenCalled()
    expect(screen.getByText('上次练到这里')).toBeInTheDocument()
    expect(screen.queryByText('已挑战')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '接着练' }))
    expect(onOpenPlan).toHaveBeenLastCalledWith(partial)
    fireEvent.click(screen.getByRole('button', { name: /化学计量.*2 组练习.*已完成 1 组/ }))
    expect(screen.getByText('还没学过')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '开始这一组' }))
    expect(onOpenPlan).toHaveBeenLastCalledWith(untouched)
    fireEvent.click(screen.getByRole('button', { name: '回顾与复习' }))
    expect(onOpenPlan).toHaveBeenLastCalledWith(completed)
  })

  it('lets students choose a later station freely while respecting its server-authorised preview mode', () => {
    const future = plan('future', '2026-10-20', 'H3_ELECTRO__C01')
    const advance = plan('advance', '2026-10-21', 'H3_STOICH__C01', { canStudyAhead: true })
    const onOpenPlan = vi.fn().mockResolvedValue(true)
    render(<High3LearningRoute dashboard={dashboard([future, advance])} today="2026-10-01" onOpenPlan={onOpenPlan} busy={false} />)
    fireEvent.click(screen.getByRole('button', { name: /化学计量.*1 组练习/ }))
    fireEvent.click(screen.getByRole('button', { name: '开始这一组' }))
    expect(onOpenPlan).toHaveBeenLastCalledWith(advance)
    fireEvent.click(screen.getByRole('button', { name: /电化学.*1 组练习/ }))
    const futureLesson = screen.getByRole('heading', { name: future.title }).closest('li')!
    fireEvent.click(within(futureLesson).getByRole('button', { name: '先预习这一组' }))
    expect(onOpenPlan).toHaveBeenLastCalledWith(future)
  })

  it('opens matching lessons for search and still lets their station collapse', () => {
    render(<High3LearningRoute dashboard={dashboard([plan('match', '2026-09-01', 'H3_STOICH__C01')])} today="2026-10-01" onOpenPlan={vi.fn()} busy={false} />)
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'match' } })
    const stop = screen.getByRole('button', { name: /化学计量.*1 组练习/ })
    expect(stop).toHaveAttribute('aria-expanded', 'true')
    fireEvent.click(stop)
    expect(stop).toHaveAttribute('aria-expanded', 'false')
    expect(screen.queryByRole('heading', { name: '题组match' })).not.toBeInTheDocument()
  })
})

describe('high-three question-task picker', () => {
  const counting = topic('H3_STOICH', 'H3_STOICH__C01', '阿伏加德罗常数与微粒数')
  const electroCounting = topic('H3_ELECTRO', 'H3_ELECTRO__C05', '电化学定量与联用装置', 'release-2')
  const electrode = topic('H3_ELECTRO', 'H3_ELECTRO__C01', '原电池放电原理')

  it('offers task choices first, combines matching tasks across chapters, and keeps original source IDs when opening', () => {
    const onStart = vi.fn().mockResolvedValue(undefined)
    render(<StudyLibrary axis="type" dashboard={dashboard()} topics={[counting, electroCounting, electrode]} loading={false} error="" onStart={onStart} busy={false} />)
    expect(screen.queryByText(counting.title)).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: '开始练题' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /计数与定量计算.*2 个训练方向.*2 个专题/ }))
    expect(screen.getByText(counting.title)).toBeInTheDocument()
    expect(screen.getByText(electroCounting.title)).toBeInTheDocument()
    expect(screen.queryByText(electrode.title)).not.toBeInTheDocument()
    fireEvent.click(within(screen.getByText(electroCounting.title).closest('article')!).getByRole('button', { name: '开始练题' }))
    expect(onStart).toHaveBeenCalledWith('H3_ELECTRO', 'H3_ELECTRO__C05', 'release-2')
    fireEvent.click(screen.getByRole('button', { name: '← 换一种题型' }))
    fireEvent.click(screen.getByRole('button', { name: /电化学装置判断/ }))
    expect(screen.getByText(electrode.title)).toBeInTheDocument()
    expect(screen.queryByText(electroCounting.title)).not.toBeInTheDocument()
  })

  it('does not guess a task from an unfamiliar key or lose newly released content', () => {
    const unknown = topic('H3_ELECTRO', 'H3_ELECTRO__NEW', '后来补充的新题')
    expect(high3TaskType(unknown.conceptKey).id).toBe('unclassified')
    render(<StudyLibrary axis="type" dashboard={dashboard()} topics={[unknown]} loading={false} error="" onStart={vi.fn()} busy={false} />)
    fireEvent.click(screen.getByRole('button', { name: /其他已开放练习/ }))
    expect(screen.getByText(unknown.title)).toBeInTheDocument()
    const keys = HIGH3_TASK_TYPES.flatMap((type) => [...type.concepts])
    expect(new Set(keys).size).toBe(keys.length)
  })

  it('keeps the knowledge directory organised by subject rather than by question task', () => {
    render(<StudyLibrary axis="knowledge" dashboard={dashboard()} topics={[counting, electroCounting, electrode]} loading={false} error="" onStart={vi.fn()} onLoadKnowledge={vi.fn()} busy={false} />)
    expect(screen.getByRole('button', { name: /电化学.*点开大知识点/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /化学计量.*点开大知识点/ })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /计数与定量计算/ })).not.toBeInTheDocument()
    expect(screen.getByText(electrode.title)).toBeInTheDocument()
    expect(screen.getByText(electroCounting.title)).toBeInTheDocument()
  })
})
