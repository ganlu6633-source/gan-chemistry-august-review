import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import type { KnowledgeCard, StudentDashboardData } from '../domain/types'
import { StudyLibrary, type StudyTopic } from './StudyLibrary'

const dashboard: StudentDashboardData = {
  profile: { id: 'student-1', displayName: '测试学生', gradeBand: '高二', enrollmentStartDate: '2026-09-01', needsInitialDiagnostic: false },
  plans: [], skillStates: [], skillDefinitions: [], achievements: [], todayQuestionCount: 0,
}

const topic: StudyTopic = {
  skillId: 'H2_ELECTRO', skillTitle: '电化学', conceptKey: 'electrode', title: '电极判断', sequence: 1,
  originalCount: 4, freshCount: 4, releaseId: 'release-1', releaseKind: 'primary', answeredCount: 0,
  recentCorrect: 0, reviewDueAt: null, reviewPriority: 0, reviewReason: null,
}

const card: KnowledgeCard = {
  id: 'card-1', skillId: 'H2_ELECTRO', title: '电化学', core: '先判断装置类型。', detail: '',
  steps: [], commonMistakes: [], microExample: '', reviewStatus: 'approved',
  structuredContent: {
    version: 4, intro: '从装置到电极。', sections: [
      { title: '电极判断', items: [{ label: '负极', rule: '负极发生氧化反应。', examples: ['Zn失去电子生成Zn²⁺，Zn电极是负极。'] }] },
    ],
    rootTree: { label: '电化学', rule: '先看能量转换。', children: [
      { label: '原电池', rule: '化学能转成电能。', children: [
        { label: '负极', rule: '负极发生氧化反应。', examples: ['Zn失去电子生成Zn²⁺，Zn电极是负极。'] },
      ] },
    ] },
  },
}

describe('knowledge directory drill-down', () => {
  it('loads a reviewed card only when its large point opens, then reveals finer points and an exact example', async () => {
    const onLoadKnowledge = vi.fn().mockResolvedValue(card)
    render(<StudyLibrary axis="knowledge" dashboard={dashboard} topics={[topic]} loading={false} error=""
      onStart={vi.fn().mockResolvedValue(undefined)} onLoadKnowledge={onLoadKnowledge} busy={false} />)

    expect(onLoadKnowledge).not.toHaveBeenCalled()
    const group = screen.getByRole('button', { name: /电化学.*点开大知识点/ })
    fireEvent.click(group)
    await waitFor(() => expect(onLoadKnowledge).toHaveBeenCalledWith('H2_ELECTRO'))
    await waitFor(() => expect(screen.getAllByRole('region', { name: '知识树，可横向或纵向滚动查看分支' }).length).toBeGreaterThan(0))
    const tree = screen.getAllByRole('region', { name: '知识树，可横向或纵向滚动查看分支' })[0]
    expect(within(tree).queryByRole('button', { name: '原电池' })).not.toBeInTheDocument()
    fireEvent.click(within(tree).getByRole('button', { name: '电化学' }))
    fireEvent.click(within(tree).getByRole('button', { name: '原电池' }))
    fireEvent.click(within(tree).getByRole('button', { name: '负极' }))
    expect(screen.getByText('Zn失去电子生成Zn²⁺，Zn电极是负极。')).toBeInTheDocument()

    fireEvent.click(group)
    expect(group).toHaveAttribute('aria-expanded', 'false')
    fireEvent.click(group)
    expect(onLoadKnowledge).toHaveBeenCalledTimes(1)
  })

  it('keeps a grade knowledge point available even before question-bank practice is released', async () => {
    const onLoadKnowledge = vi.fn().mockResolvedValue(card)
    const withUnreleasedSkill: StudentDashboardData = { ...dashboard, skillDefinitions: [{
      id: 'H2_ELECTRO', title: '电化学', moduleId: 'electro', gradeBand: '高二', maxLevel: 3,
      examImportance: 3, examDepth: 3, prerequisites: [], levelCriteria: [],
    }] }
    render(<StudyLibrary axis="knowledge" dashboard={withUnreleasedSkill} topics={[]} loading={false} error=""
      onStart={vi.fn().mockResolvedValue(undefined)} onLoadKnowledge={onLoadKnowledge} busy={false} />)
    expect(screen.getByText('这块原题正在逐题校对，核准后就能开练；知识树可以先点开学习。')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /电化学.*点开大知识点/ }))
    await waitFor(() => expect(onLoadKnowledge).toHaveBeenCalledWith('H2_ELECTRO'))
  })
})
