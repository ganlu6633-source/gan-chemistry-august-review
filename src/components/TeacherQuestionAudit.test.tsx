import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { TeacherDashboardData } from '../domain/types'
import { writeAccessSession } from '../lib/session'
import { QuestionAudit } from './TeacherApp'

const apiMocks = vi.hoisted(() => ({ teacherApi: vi.fn(), loadQuestionAsset: vi.fn() }))

vi.mock('../lib/api', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../lib/api')>()
  return { ...actual, teacherApi: apiMocks.teacherApi, loadQuestionAsset: apiMocks.loadQuestionAsset }
})

const dashboard: TeacherDashboardData = {
  students: [], alerts: [], recentQuizSessions: [], pendingCourseNodes: 0, pendingQuestions: 1,
  dailySummary: { generatedAt: null, classQuizCount: 0, quizCompletedStudentCount: 0, quizRosterCount: 0, reviewCount: 0, interventionCount: 0 },
}

describe('Teacher source-question audit', () => {
  beforeEach(() => {
    writeAccessSession({ role: 'teacher', token: 'teacher-test-token', displayName: '甘老师', expiresAt: new Date(Date.now() + 60_000).toISOString() })
    apiMocks.teacherApi.mockReset()
    apiMocks.loadQuestionAsset.mockReset()
    apiMocks.teacherApi.mockImplementation(async (action: string) => {
      if (action !== 'list_questions') return { ok: true }
      return {
        page: 1, pageSize: 20, total: 1,
        questions: [{
          id: 'QH3O_SOURCE_1', mother_id: 'MH3O_SOURCE_1', skill_id: 'H3_AQ', concept_key: 'H3_AQ__C01', level: 3,
          grade_band: '高三', stem: '原题文字辅助稿', options: ['选项甲', '选项乙', '选项丙', '选项丁'], correct_option: 1,
          explanation: '原解析文字辅助稿', scaffold: null, review_status: 'needs_review', scope_status: 'IN', source_kind: 'licensed_local',
          source_info: { title: '2025年高考化学真题分类汇编', exam: '2025·福建卷', year: 2025, questionNo: '第3题', locator: '专题10，第2页' },
          asset_refs: [
            { kind: 'question_image', path: 'opaque/source/question', alt: '原题题面', sha256: 'a'.repeat(64), width: 900, height: 500 },
            { kind: 'analysis_image', path: 'opaque/source/analysis', alt: '原题解析', sha256: 'b'.repeat(64), width: 900, height: 600 },
          ],
          render_mode: 'image_primary', content_fingerprint: 'c'.repeat(64), source_release_id: 'release-managed-id', usable_for_review: false,
        }],
      }
    })
    apiMocks.loadQuestionAsset.mockImplementation(async (_session: unknown, _questionId: string, assetId: string) => ({
      asset: {
        kind: assetId.endsWith('analysis') ? 'analysis_image' : 'question_image', mimeType: 'image/webp',
        dataUrl: 'data:image/webp;base64,AAAA', sha256: assetId.endsWith('analysis') ? 'b'.repeat(64) : 'a'.repeat(64),
        width: 900, height: assetId.endsWith('analysis') ? 600 : 500,
      },
    }))
  })

  afterEach(() => {
    cleanup()
    sessionStorage.clear()
  })

  it('shows the exact source, question image, answer and original analysis in one expandable audit record', async () => {
    render(<QuestionAudit dashboard={dashboard} />)

    const [stem] = await screen.findAllByText('原题文字辅助稿')
    fireEvent.click(stem.closest('summary')!)
    expect(screen.getByText('2025·福建卷')).toBeInTheDocument()
    expect(screen.getByText('文字辅助稿与答案')).toBeInTheDocument()
    expect(screen.getByText('复杂公式、结构式与装置图以原题图为准。')).toBeInTheDocument()
    expect(screen.getByText('正确答案')).toBeInTheDocument()
    expect(screen.getByText(/不能单题修改/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '批准' })).toBeDisabled()
    expect(screen.getByRole('button', { name: '待复核' })).toBeDisabled()
    expect(screen.getByRole('button', { name: '停用' })).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: '加载当时的原题图与解析图' }))

    await waitFor(() => expect(apiMocks.loadQuestionAsset).toHaveBeenCalledTimes(2))
    expect(apiMocks.loadQuestionAsset.mock.calls.map((call) => call[3])).toEqual(expect.arrayContaining(['question', 'analysis']))
    expect(await screen.findByAltText('原题题面')).toBeInTheDocument()
    expect(await screen.findByAltText('原题解析')).toBeInTheDocument()
  })
})
