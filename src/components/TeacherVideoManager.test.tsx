import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { TeacherDashboardData, VideoRecommendation } from '../domain/types'

const apiMocks = vi.hoisted(() => ({
  listVideoRecommendations: vi.fn(),
  createVideoRecommendation: vi.fn(),
  publishVideoRecommendation: vi.fn(),
  withdrawVideoRecommendation: vi.fn(),
  recordVideoEngagement: vi.fn(),
  teacherApi: vi.fn(),
}))

vi.mock('../lib/api', () => apiMocks)

import { TeacherVideoManager } from './VideoLearning'

const dashboard: TeacherDashboardData = {
  students: [{ id: 'student-1', displayName: '测试同学', gradeBand: '高一', status: 'active', needsInitialDiagnostic: false, guardianNames: ['测试妈妈'], curriculumCohort: 'high1', planDays: 40 }],
  alerts: [],
  dailySummary: { generatedAt: null, classQuizCount: 0, quizCompletedStudentCount: 0, quizRosterCount: 0, reviewCount: 0, interventionCount: 0 },
  recentQuizSessions: [],
  pendingCourseNodes: 0,
  pendingQuestions: 0,
}

const recommendation = (status: VideoRecommendation['status']): VideoRecommendation => ({
  id: `video-${status}`,
  studentId: 'student-1',
  skillId: 'H1_PERIODIC',
  skillTitle: '元素周期律',
  title: `${status}讲解`,
  provider: '甘老师录屏',
  url: `https://example.com/${status}`,
  teacherReason: '依据课堂进度补上这条逻辑。',
  status,
  publishedAt: status === 'published' ? '2026-08-14T08:00:00.000Z' : null,
  progress: {
    openedAt: status === 'published' ? '2026-08-14T09:00:00.000Z' : null,
    lastEngagedAt: status === 'published' ? '2026-08-14T09:00:00.000Z' : null,
    progressSeconds: 0,
    durationSeconds: null,
    completionPercent: null,
    completedAt: null,
    trackingMethod: status === 'published' ? 'link_open_only' : null,
    eventCount: status === 'published' ? 1 : 0,
  },
})

describe('TeacherVideoManager', () => {
  beforeEach(() => {
    apiMocks.listVideoRecommendations.mockResolvedValue({ recommendations: [recommendation('draft'), recommendation('published'), recommendation('withdrawn')] })
    apiMocks.teacherApi.mockResolvedValue({ dashboard: { skillDefinitions: [{ id: 'H1_PERIODIC', title: '元素周期律', moduleId: 'H1-F02', gradeBand: '高一', maxLevel: 7, examImportance: 5, examDepth: 5, prerequisites: [], levelCriteria: [] }] } })
    apiMocks.createVideoRecommendation.mockResolvedValue({ ok: true })
    apiMocks.publishVideoRecommendation.mockResolvedValue({ ok: true })
    apiMocks.withdrawVideoRecommendation.mockResolvedValue({ ok: true })
  })

  afterEach(() => {
    cleanup()
    vi.clearAllMocks()
  })

  it('keeps drafts, published items and withdrawn items visibly distinct and actionable', async () => {
    render(<TeacherVideoManager dashboard={dashboard} />)

    expect(await screen.findByText('draft讲解')).toBeInTheDocument()
    expect(screen.getByText('published讲解')).toBeInTheDocument()
    expect(screen.getByText('withdrawn讲解')).toBeInTheDocument()
    expect(screen.getByText(/已记录 1 次观看动作/)).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: '发布' }))
    await waitFor(() => expect(apiMocks.publishVideoRecommendation).toHaveBeenCalledWith('video-draft'))
  }, 15_000)

  it('creates an HTTPS recommendation as a draft with the teacher reason intact', async () => {
    render(<TeacherVideoManager dashboard={dashboard} />)
    await waitFor(() => expect(screen.getByLabelText('对应知识点')).toHaveValue('H1_PERIODIC'))

    fireEvent.change(screen.getByLabelText('讲解标题'), { target: { value: '把周期趋势连起来' } })
    fireEvent.change(screen.getByLabelText('来源平台'), { target: { value: '甘老师录屏' } })
    fireEvent.change(screen.getByLabelText('视频链接'), { target: { value: 'https://example.com/lesson' } })
    fireEvent.change(screen.getByLabelText('为什么安排给这名学生'), { target: { value: '课堂上最高价含氧酸的趋势还需要再接一次。' } })
    fireEvent.click(screen.getByRole('button', { name: '保存为待审核' }))

    await waitFor(() => expect(apiMocks.createVideoRecommendation).toHaveBeenCalledWith({
      studentId: 'student-1',
      skillId: 'H1_PERIODIC',
      title: '把周期趋势连起来',
      provider: '甘老师录屏',
      url: 'https://example.com/lesson',
      teacherReason: '课堂上最高价含氧酸的趋势还需要再接一次。',
    }))
  }, 15_000)
})
