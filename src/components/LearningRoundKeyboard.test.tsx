import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { KnowledgeCard, Question, SessionIdentity, StudentDashboardData } from '../domain/types'
import { LearningRound, type PlanPayload } from './StudentApp'

const session: SessionIdentity = { role: 'student', token: 'test-token', displayName: '测试学生', expiresAt: '2099-01-01T00:00:00Z' }

const card = (id: string, title: string): KnowledgeCard => ({
  id,
  skillId: 'H1_REDOX',
  title,
  core: '升价、失电子、被氧化、发生氧化反应。',
  detail: '从化合价和电子转移一起判断。',
  steps: ['标价', '看升降'],
  commonMistakes: ['不要漏写发生氧化反应。'],
  microExample: 'Na由0价升至+1价。',
  reviewStatus: 'approved',
})

const question: Question = {
  id: 'question-1',
  motherId: 'mother-1',
  skillId: 'H1_REDOX',
  level: 1,
  gradeBand: '高一',
  stem: 'Na在反应中发生什么变化？',
  options: ['升价并失电子', '降价并得电子'],
  correctOption: 0,
  explanation: 'Na化合价升高，失电子，被氧化，发生氧化反应。',
  reviewStatus: 'approved',
  scopeStatus: 'IN',
  sourceKind: 'teacher_original',
}

const dashboard: StudentDashboardData = {
  profile: { id: 'student-1', displayName: '测试学生', gradeBand: '高一', enrollmentStartDate: '2026-08-01', needsInitialDiagnostic: false, isDemo: true },
  plans: [],
  skillStates: [],
  skillDefinitions: [],
  todayQuestionCount: 1,
  achievements: [],
}

function payload(roundLimit = 2): PlanPayload {
  return {
    plan: {
      id: 'plan-1', studentId: 'student-1', date: '2026-08-15', mode: 'REVIEW', title: '氧化还原复习',
      skillIds: ['H1_REDOX'], knowledgeSummaries: ['氧化还原'], estimatedMinutes: 5, source: 'course', isScheduled: true,
      attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null, questionCount: 1, roundLimit,
      maxQuestionLevel: 1, isResolved: false, isComplete: false, roundsRemaining: roundLimit,
    },
    cards: [card('card-1', '第一张知识卡'), card('card-2', '第二张知识卡')],
    questions: [question],
    attemptSequence: 0,
    roundNumber: 1,
    roundLimit,
    questionCount: 1,
    isResolved: false,
    isComplete: false,
    roundsRemaining: roundLimit,
  }
}

function renderRound(roundLimit = 2) {
  const onContinue = vi.fn(async () => undefined)
  const onComplete = vi.fn()
  render(<LearningRound session={session} payload={payload(roundLimit)} practiceMode practiceDashboard={dashboard} onExit={vi.fn()} onContinue={onContinue} onComplete={onComplete} />)
  return { onContinue, onComplete }
}

async function finishOneQuestion() {
  fireEvent.keyDown(window, { key: 'Enter' })
  fireEvent.keyDown(window, { key: 'Enter' })
  fireEvent.click(screen.getByRole('button', { name: /A.*升价并失电子/ }))
  fireEvent.keyDown(window, { key: 'Enter' })
  expect(screen.getByText('判断正确')).toBeInTheDocument()
  fireEvent.keyDown(window, { key: 'Enter' })
  await screen.findByText('演示第 1 轮完成')
}

describe('LearningRound Enter shortcut', () => {
  afterEach(cleanup)

  it('moves through cards, submits a selected answer, advances feedback, then enters the next round', async () => {
    const { onContinue } = renderRound(2)

    fireEvent.keyDown(window, { key: 'Enter', repeat: true })
    fireEvent.keyDown(window, { key: 'Enter', ctrlKey: true })
    expect(screen.getByRole('heading', { name: '第一张知识卡' })).toBeInTheDocument()

    fireEvent.keyDown(window, { key: 'Enter' })
    expect(screen.getByRole('heading', { name: '第二张知识卡' })).toBeInTheDocument()
    fireEvent.keyDown(window, { key: 'Enter' })
    expect(screen.getByRole('button', { name: '提交答案' })).toBeDisabled()

    fireEvent.keyDown(window, { key: 'Enter' })
    expect(screen.queryByText('判断正确')).not.toBeInTheDocument()
    const uncertain = screen.getByRole('checkbox')
    fireEvent.click(screen.getByRole('button', { name: /A.*升价并失电子/ }))
    fireEvent.keyDown(uncertain, { key: 'Enter' })
    expect(screen.queryByText('判断正确')).not.toBeInTheDocument()

    fireEvent.keyDown(window, { key: 'Enter' })
    expect(screen.getByText('判断正确')).toBeInTheDocument()
    fireEvent.keyDown(window, { key: 'Enter' })
    await screen.findByText('演示第 1 轮完成')

    const nextRound = screen.getByRole('button', { name: /进入第 2 轮/ })
    expect(nextRound).toHaveAttribute('aria-keyshortcuts', 'Enter')
    fireEvent.keyDown(window, { key: 'Enter' })
    await waitFor(() => expect(onContinue).toHaveBeenCalledWith(dashboard, 'plan-1', 2))
  })

  it('uses Enter to return from the final result when no next round exists', async () => {
    const { onComplete } = renderRound(1)
    await finishOneQuestion()

    const returnButton = screen.getByRole('button', { name: /返回演示计划/ })
    expect(returnButton).toHaveAttribute('aria-keyshortcuts', 'Enter')
    fireEvent.keyDown(window, { key: 'Enter' })
    expect(onComplete).toHaveBeenCalledWith(dashboard)
  })

  it('does not activate the main Enter shortcut from source-media controls or while its dialog is open', () => {
    renderRound(2)
    const mediaButton = document.createElement('button')
    mediaButton.setAttribute('data-question-media-control', '')
    document.body.append(mediaButton)
    mediaButton.focus()
    fireEvent.keyDown(mediaButton, { key: 'Enter' })
    expect(screen.getByRole('heading', { name: '第一张知识卡' })).toBeInTheDocument()
    mediaButton.remove()

    const dialog = document.createElement('dialog')
    dialog.setAttribute('data-question-media-dialog', '')
    dialog.setAttribute('open', '')
    document.body.append(dialog)
    fireEvent.keyDown(window, { key: 'Enter' })
    expect(screen.getByRole('heading', { name: '第一张知识卡' })).toBeInTheDocument()
    dialog.remove()
  })
})
