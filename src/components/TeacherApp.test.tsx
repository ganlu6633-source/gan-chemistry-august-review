import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { TeacherDashboardData } from '../domain/types'
import { StudentTable } from './TeacherApp'

const dashboard: TeacherDashboardData = {
  students: [
    { id: 'h1-student', displayName: '高一同学', gradeBand: '高一', status: 'active', needsInitialDiagnostic: false, guardianNames: ['高一妈妈'], curriculumCohort: 'high1', planDays: 40 },
    { id: 'h2-student', displayName: '高二同学', gradeBand: '高二', status: 'active', needsInitialDiagnostic: false, guardianNames: ['高二妈妈', '高二爸爸'], curriculumCohort: 'high2', planDays: 32 },
    { id: 'h3-student', displayName: '高三同学', gradeBand: '高三', status: 'active', needsInitialDiagnostic: true, guardianNames: [], curriculumCohort: 'high3', planDays: 28 },
  ],
  alerts: [],
  dailySummary: { generatedAt: null, classQuizCount: 0, quizCompletedStudentCount: 0, quizRosterCount: 0, reviewCount: 0, interventionCount: 0 },
  recentQuizSessions: [],
  pendingCourseNodes: 0,
  pendingQuestions: 0,
}

describe('Teacher student directory', () => {
  afterEach(cleanup)

  it('filters students by grade and keeps all registered guardian names visible', () => {
    render(<StudentTable dashboard={dashboard} onPreview={() => undefined} />)

    fireEvent.click(within(screen.getByRole('group', { name: '按年级筛选学生' })).getByRole('button', { name: /高二/ }))

    expect(screen.queryByText('高一同学')).not.toBeInTheDocument()
    expect(screen.getByText('高二同学')).toBeInTheDocument()
    expect(screen.getByText('高二妈妈、高二爸爸')).toBeInTheDocument()
    expect(screen.queryByText('高三同学')).not.toBeInTheDocument()
  })

  it('opens a read-only student preview for the selected student id', () => {
    const onPreview = vi.fn()
    render(<StudentTable dashboard={dashboard} onPreview={onPreview} />)

    fireEvent.click(screen.getByRole('button', { name: '模拟查看高三同学的学生端' }))

    expect(onPreview).toHaveBeenCalledOnce()
    expect(onPreview).toHaveBeenCalledWith('h3-student')
  })
})
