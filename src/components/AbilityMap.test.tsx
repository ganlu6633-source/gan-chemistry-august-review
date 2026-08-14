import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { ABILITY_MAP_BLUEPRINTS } from '../data/abilityMap'
import type { SkillDefinition, StudentDashboardData, StudentSkillState } from '../domain/types'
import { AbilityMap } from './AbilityMap'

const titles: Record<string, string> = {
  H1_CLASSIFY: '物质的分类', H1_PERIODIC: '元素周期律', H1_ELECTROLYTE_INTRO: '电解质基础', H1_REDOX: '氧化还原',
  H1_MOLE_INTRO: '物质的量基础', H1_ELECTROLYTE: '离子反应', H1_MOLE: '物质的量计算', H1_NACL: '钠和氯',
}

const skillIds = ABILITY_MAP_BLUEPRINTS['高一'].stages.flatMap((stage) => stage.skillIds)
const definitions: SkillDefinition[] = skillIds.map((id) => ({
  id, title: titles[id], moduleId: `module-${id}`, gradeBand: '高一', maxLevel: 4, examImportance: 5, examDepth: 4, prerequisites: [], levelCriteria: [],
}))

const state = (skillId: string, verifiedLevel: number, stability: StudentSkillState['stability']): StudentSkillState => ({
  studentId: 'student-1', skillId, verifiedLevel, candidateLevel: null, maxLevel: 4, stability, evidence: [], consecutiveErrors: 0,
  nextReviewAt: null, reviewIntervalIndex: 1, lastReviewedAt: '2026-08-12T08:00:00Z', teacherIntervention: false,
})

const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
const dashboard: StudentDashboardData = {
  profile: { id: 'student-1', displayName: '测试学生', gradeBand: '高一', enrollmentStartDate: '2026-08-01', needsInitialDiagnostic: false },
  plans: [{ id: 'today-plan', studentId: 'student-1', date: today, mode: 'REVIEW', title: '今天复习氧化还原与计量', skillIds: ['H1_REDOX', 'H1_MOLE'], knowledgeSummaries: ['电子转移', '物质的量'], estimatedMinutes: 15, source: 'memory', isScheduled: true, attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null }],
  skillDefinitions: definitions,
  skillStates: [state('H1_CLASSIFY', 2, 'stable'), state('H1_PERIODIC', 1, 'forgotten'), state('H1_REDOX', 1, 'learning')],
  todayQuestionCount: 6,
  achievements: [],
}

describe('AbilityMap', () => {
  afterEach(cleanup)

  it('renders one integrated map with every high-one node and today location', () => {
    const { container } = render(<AbilityMap dashboard={dashboard} />)

    expect(container.querySelectorAll('.ability-atlas')).toHaveLength(1)
    expect(container.querySelectorAll('.ability-node')).toHaveLength(8)
    expect(screen.getByRole('heading', { name: '高一化学基础主干' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /氧化还原，正在形成/ })).toHaveTextContent('你在这里')
    expect(screen.getByRole('button', { name: /物质的量计算，待建立证据/ })).toHaveTextContent('你在这里')
    expect(container.querySelectorAll('.ability-node[aria-current="step"]')).toHaveLength(2)
    expect(container.querySelectorAll('.galaxy-zone')).toHaveLength(0)
  })

  it('opens node detail and filtering dims rather than removes nodes', () => {
    const { container } = render(<AbilityMap dashboard={dashboard} />)

    fireEvent.click(screen.getByRole('button', { name: /元素周期律，该复习了/ }))
    expect(screen.getByRole('heading', { name: '元素周期律' })).toBeInTheDocument()
    expect(screen.getAllByText('该复习了')).toHaveLength(2)

    fireEvent.click(screen.getByRole('button', { name: '需要复习' }))
    expect(container.querySelectorAll('.ability-node')).toHaveLength(8)
    expect(container.querySelectorAll('.ability-node.is-dimmed')).toHaveLength(7)
    expect(screen.getByRole('button', { name: /元素周期律，该复习了/ })).not.toHaveClass('is-dimmed')
  })

  it('opens the related plan from the selected node', () => {
    const onOpenPlan = vi.fn()
    render(<AbilityMap dashboard={dashboard} onOpenPlan={onOpenPlan} />)

    fireEvent.click(screen.getByRole('button', { name: '打开关联学习' }))
    expect(onOpenPlan).toHaveBeenCalledWith(dashboard.plans[0])
  })

  it('labels a finished schedule as recent review instead of next step', () => {
    const yesterday = new Date(Date.now() - 86_400_000).toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
    const finishedDashboard = { ...dashboard, plans: [{ ...dashboard.plans[0], date: yesterday }] }
    render(<AbilityMap dashboard={finishedDashboard} />)

    expect(screen.getByRole('button', { name: /氧化还原，正在形成.*最近复习/ })).toHaveTextContent('最近复习')
    expect(screen.queryByText('下一步')).not.toBeInTheDocument()
  })
})
