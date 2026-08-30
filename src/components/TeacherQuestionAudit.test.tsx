import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { GradeBand, TeacherDashboardData } from '../domain/types'
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

let auditGrade: GradeBand = '高三'
let auditSourceKind: 'licensed_local' | 'user_provided_local' = 'licensed_local'
let auditUsableForReview = false

describe('Teacher source-question audit', () => {
  beforeEach(() => {
    auditGrade = '高三'
    auditSourceKind = 'licensed_local'
    auditUsableForReview = false
    writeAccessSession({ role: 'teacher', token: 'teacher-test-token', displayName: '甘老师', expiresAt: new Date(Date.now() + 60_000).toISOString() })
    apiMocks.teacherApi.mockReset()
    apiMocks.loadQuestionAsset.mockReset()
    apiMocks.teacherApi.mockImplementation(async (action: string) => {
      if (action !== 'list_questions') return { ok: true }
      return {
        page: 1, pageSize: 20, total: 1,
        questions: [{
          id: 'QH3O_SOURCE_1', mother_id: 'MH3O_SOURCE_1', skill_id: 'H3_AQ', concept_key: 'H3_AQ__C01', level: 3,
          grade_band: auditGrade, stem: '原题文字辅助稿', options: ['选项甲', '选项乙', '选项丙', '选项丁'], correct_option: 1,
          explanation: 'A：选项甲错误；B：选项乙正确；C：选项丙错误；D：选项丁错误。', scaffold: null, review_status: 'needs_review', scope_status: 'IN', source_kind: auditSourceKind,
          source_info: { title: '2025年高考化学真题分类汇编', exam: '2025·福建卷', year: 2025, questionNo: '第3题', locator: '专题10，第2页' },
          asset_refs: auditSourceKind === 'licensed_local' && ['高一', '高二', '高三'].includes(auditGrade) ? [
            { kind: 'question_image', path: 'opaque/source/question', alt: '原题题面', sha256: 'a'.repeat(64), width: 900, height: 500 },
            { kind: 'analysis_image', path: 'opaque/source/analysis', alt: '原题解析', sha256: 'b'.repeat(64), width: 900, height: 600 },
          ] : [],
          render_mode: auditSourceKind === 'licensed_local' && ['高一', '高二', '高三'].includes(auditGrade) ? 'image_primary' : 'native', content_fingerprint: 'c'.repeat(64), source_release_id: 'release-managed-id', usable_for_review: auditUsableForReview,
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
    expect(document.querySelectorAll('.question-audit-analysis .answer-explanation>p')).toHaveLength(4)
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

  it.each(['高一', '高二'] as const)('also gives the teacher both source images for %s originals', async (grade) => {
    auditGrade = grade
    render(<QuestionAudit dashboard={dashboard} />)

    const [stem] = await screen.findAllByText('原题文字辅助稿')
    fireEvent.click(stem.closest('summary')!)
    fireEvent.click(screen.getByRole('button', { name: '加载当时的原题图与解析图' }))

    await waitFor(() => expect(apiMocks.loadQuestionAsset).toHaveBeenCalledTimes(2))
    expect(apiMocks.loadQuestionAsset.mock.calls.map((call) => call[3])).toEqual(expect.arrayContaining(['question', 'analysis']))
    expect(await screen.findByAltText('原题题面')).toBeInTheDocument()
    expect(await screen.findByAltText('原题解析')).toBeInTheDocument()
  })

  it('marks a legacy junior licensed label as unverified historical evidence even if the raw row says usable', async () => {
    auditGrade = '初三'
    auditSourceKind = 'licensed_local'
    auditUsableForReview = true
    render(<QuestionAudit dashboard={dashboard} />)

    expect(await screen.findByText(/历史旧标签（授权未核验，不下发）/)).toBeInTheDocument()
    expect(screen.getByText('历史证据/当前不下发')).toBeInTheDocument()
    expect(screen.queryByText('复习中')).not.toBeInTheDocument()
    expect(screen.queryByText('已授权本地原题')).not.toBeInTheDocument()
  })

  it('describes junior user-provided native text without claiming source images or a redistribution license', async () => {
    auditGrade = '初三'
    auditSourceKind = 'user_provided_local'
    render(<QuestionAudit dashboard={dashboard} />)

    const [stem] = await screen.findAllByText('原题文字辅助稿')
    fireEvent.click(stem.closest('summary')!)
    expect(screen.getAllByText(/用户提供的本地资料/).length).toBeGreaterThanOrEqual(2)
    expect(screen.getByRole('heading', { name: '原生文字题面与答案' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: '文字解析（整套发布核验后下发）' })).toBeInTheDocument()
    expect(screen.getByText(/只有整套发布完成核验后才会下发/)).toBeInTheDocument()
    expect(screen.getByText(/不依赖原题图或本地路径/)).toBeInTheDocument()
    expect(screen.queryByText(/原解析图为最终依据/)).not.toBeInTheDocument()
    expect(screen.queryByText(/已授权本地原题/)).not.toBeInTheDocument()
  })
})
