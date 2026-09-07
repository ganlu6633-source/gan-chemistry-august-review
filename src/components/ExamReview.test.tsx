import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { ExamReviewPayload, SessionIdentity, StudentDashboardData } from '../domain/types'
import { accessApi, teacherApi } from '../lib/api'
import { clearAccessSession, writeAccessSession } from '../lib/session'
import { ExamReview } from './ExamReview'
import { StudentApp } from './StudentApp'

vi.mock('../lib/api', async (importOriginal) => ({ ...await importOriginal<typeof import('../lib/api')>(), accessApi: vi.fn(), teacherApi: vi.fn() }))
const student: SessionIdentity = { role: 'student', token: 'test-student', displayName: '测试学生', expiresAt: '2099-01-01' }
function material(): ExamReviewPayload {
  return {
    material: {
      id: 'exam-test', title: '福州化学试卷', pageCount: 8, overview: '逐项说明理由，再用同类题检验。',
      units: [{
        id: 'Q01A', label: '第 1 题 A', questionNo: 1, page: 1, prompt: '判断 Ga 与 Al 是否同主族，并说明理由。',
        knowledgePoints: ['价电子排布与主族'], answer: '正确', explanation: '二者都是 ns²np¹。',
        commonMistakes: ['不要混淆周期和主族。'], practiceTargets: ['从电子排布判断主族'],
        status: 'ready', bankMatches: [{ questionId: 'bank-private-a', strength: 'same_type', reason: '均由电子排布判断主族。' }, { questionId: 'bank-private-b', strength: 'same_type', reason: '相同判断任务。' }],
      }], dailyOutline: [{ date: '2026-09-12', title: '分类与结构', questionNos: [1], unitIds: ['Q01A'] }],
    },
    recalls: [], evidence: [],
  }
}
function openUnit() {
  fireEvent.click(screen.getByText('第 1 题 A'))
}
function mockStudent(payload: ExamReviewPayload) {
  vi.mocked(accessApi).mockImplementation(async (_session, action) => {
    if (action === 'exam_material') return structuredClone(payload)
    if (action === 'exam_recall') return { ok: true, gradingStatus: 'ungraded_self_check' }
    if (action === 'exam_material_page') return { page: { mimeType: 'image/png', payloadBase64: 'dGVzdA==', width: 1300, height: 1900 } }
    throw new Error('unexpected action')
  })
}
describe('private exam review evidence and writing boundaries', () => {
  beforeEach(() => vi.resetAllMocks())
  afterEach(() => { cleanup(); clearAccessSession(); vi.unstubAllGlobals() })

  it('requires a written response and records only a self-check, revealing references after successful save', async () => {
    mockStudent(material())
    render(<ExamReview session={student} studentId="student-id" onExit={vi.fn()} />)
    await screen.findByText('第 1 题 A')
    openUnit()
    expect(screen.queryByText('二者都是 ns²np¹。')).not.toBeInTheDocument()
    const save = screen.getByRole('button', { name: '我能说明依据 · 保存自检' })
    expect(save).toBeDisabled()
    fireEvent.change(screen.getByLabelText('先写你的判断与依据'), { target: { value: '两者的价层电子排布都是 ns²np¹。' } })
    fireEvent.click(save)
    await screen.findByText('已保存自检。尚未评分，请展开参考解析核对自己的过程。')
    expect(vi.mocked(accessApi)).toHaveBeenCalledWith(student, 'exam_recall', { unitId: 'Q01A', response: '两者的价层电子排布都是 ns²np¹。', selfRating: 'understood' })
    expect(screen.getByText('展开参考答案与逐步解析')).toBeInTheDocument()
    expect(screen.queryByText('同类题已复核', { exact: true })).not.toBeInTheDocument()
    const progress = screen.getByLabelText('复盘进度')
    expect(within(progress).getByText('1/1')).toBeInTheDocument()
    expect(within(progress).getByText('0项')).toBeInTheDocument()
    expect(within(progress).queryByText('0/1')).not.toBeInTheDocument()
    expect(document.body.textContent).not.toContain('bank-private')
  })

  it('teacher previews use only the read API and never expose self-check write controls', async () => {
    vi.mocked(teacherApi).mockResolvedValue(material())
    render(<ExamReview session={{ ...student, role: 'teacher' }} studentId="target-student" onExit={vi.fn()} />)
    await screen.findByText('第 1 题 A')
    openUnit()
    expect(vi.mocked(teacherApi)).toHaveBeenCalledWith('exam_material', { studentId: 'target-student' }, expect.objectContaining({ signal: expect.any(AbortSignal) }))
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /保存自检/ })).not.toBeInTheDocument()
    expect(screen.getByText('展开参考答案与逐步解析')).toBeInTheDocument()
    expect(accessApi).not.toHaveBeenCalled()
  })

  it('keeps teacher-review and lack-of-exact-type warnings even after a student reports understanding', async () => {
    const data = material()
    data.material.units[0].status = 'needs_review'
    data.material.units[0].reviewNote = '原卷图示需要确认。'
    data.material.units[0].bankMatches = [{ questionId: 'partial-private', strength: 'partial', reason: '只覆盖电子排布。' }]
    data.recalls = [{ unitId: 'Q01A', response: '我按价电子排布完成判断。', selfRating: 'understood', responseCount: 1, updatedAt: '2026-09-12T00:00:00Z' }]
    data.evidence = [{ questionId: 'partial-private', correct: true, uncertain: false, completedAt: '2026-09-12T00:00:00Z' }]
    mockStudent(data)
    render(<ExamReview session={student} studentId="student-id" onExit={vi.fn()} />)
    await screen.findByText('第 1 题 A')
    fireEvent.change(screen.getByLabelText('筛选复盘状态'), { target: { value: 'review' } })
    openUnit()
    expect(screen.getByText('原卷图示需要确认。')).toBeInTheDocument()
    expect(screen.getByText(/目前没有同类型题。原卷书写需教师核验/)).toBeInTheDocument()
    expect(screen.queryByText('同类题已复核', { exact: true })).not.toBeInTheDocument()
    expect(screen.getByText('待核验参考：请以甘老师复核后的说明为准。')).toBeInTheDocument()
  })

  it('requires independent same-type questions on different Beijing dates and resets evidence after later uncertainty', async () => {
    const data = material()
    data.evidence = [
      { questionId: 'bank-private-a', correct: true, uncertain: false, completedAt: '2026-09-12T15:30:00Z' },
      { questionId: 'bank-private-b', correct: true, uncertain: false, completedAt: '2026-09-12T16:30:00Z' },
    ]
    mockStudent(data)
    const first = render(<ExamReview session={student} studentId="student-id" onExit={vi.fn()} />)
    await screen.findByText('第 1 题 A')
    openUnit()
    expect(screen.getByText('同类题已复核', { exact: true })).toBeInTheDocument()
    expect(screen.getByText(/仍不代表原卷书写或主观题已经掌握/)).toBeInTheDocument()
    first.unmount()
    data.evidence.push({ questionId: 'bank-private-a', correct: true, uncertain: true, completedAt: '2026-09-13T00:00:00Z' })
    mockStudent(data)
    render(<ExamReview session={student} studentId="student-id" onExit={vi.fn()} />)
    await screen.findByText('第 1 题 A')
    openUnit()
    expect(screen.queryByText('同类题已复核', { exact: true })).not.toBeInTheDocument()
    expect(screen.getByText(/近期出现过答错或不确定/)).toBeInTheDocument()
  })

  it('does not treat repetition of one question or two questions on the same Beijing day as cross-day verification', async () => {
    const data = material()
    data.evidence = [
      { questionId: 'bank-private-a', correct: true, uncertain: false, completedAt: '2026-09-11T16:30:00Z' },
      { questionId: 'bank-private-a', correct: true, uncertain: false, completedAt: '2026-09-12T01:00:00Z' },
      { questionId: 'bank-private-b', correct: true, uncertain: false, completedAt: '2026-09-12T03:00:00Z' },
    ]
    mockStudent(data)
    render(<ExamReview session={student} studentId="student-id" onExit={vi.fn()} />)
    await screen.findByText('第 1 题 A')
    openUnit()
    expect(screen.queryByText('同类题已复核', { exact: true })).not.toBeInTheDocument()
    expect(screen.getByText(/2 道不同题答对且确定 · 1 个北京时间日期/)).toBeInTheDocument()
  })

  it('loads no source page until requested, caches it in this panel and labels handwriting', async () => {
    mockStudent(material())
    render(<ExamReview session={student} studentId="student-id" onExit={vi.fn()} />)
    await screen.findByText('第 1 题 A')
    expect(vi.mocked(accessApi).mock.calls.filter((call) => call[1] === 'exam_material_page')).toHaveLength(0)
    fireEvent.click(screen.getByRole('button', { name: '第 1 页' }))
    expect(await screen.findByRole('img', { name: /含手写批注，仅用于复盘/ })).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: '收起原卷' }))
    fireEvent.click(screen.getByRole('button', { name: '第 1 页' }))
    await waitFor(() => expect(screen.getByRole('img', { name: /含手写批注/ })).toBeVisible())
    expect(vi.mocked(accessApi).mock.calls.filter((call) => call[1] === 'exam_material_page')).toHaveLength(1)
  })

  it('preserves written work through filtering and a failed save without unlocking an answer or marking it checked', async () => {
    mockStudent(material())
    render(<ExamReview session={student} studentId="student-id" onExit={vi.fn()} />)
    await screen.findByText('第 1 题 A')
    openUnit()
    fireEvent.change(screen.getByLabelText('先写你的判断与依据'), { target: { value: '我需要核对两者的价电子排布。' } })
    fireEvent.change(screen.getByLabelText('选择题号'), { target: { value: '2' } })
    fireEvent.change(screen.getByLabelText('选择题号'), { target: { value: '1' } })
    openUnit()
    expect(screen.getByLabelText('先写你的判断与依据')).toHaveValue('我需要核对两者的价电子排布。')
    vi.mocked(accessApi).mockRejectedValueOnce(new Error('连接暂时中断'))
    fireEvent.click(screen.getByRole('button', { name: '我还需要帮助 · 保存自检' }))
    await screen.findByRole('alert')
    expect(screen.queryByText('展开参考答案与逐步解析')).not.toBeInTheDocument()
    expect(screen.queryByText('已自检', { selector: 'em' })).not.toBeInTheDocument()
    expect(screen.getByLabelText('先写你的判断与依据')).toHaveValue('我需要核对两者的价电子排布。')
  })

  it('does not count the same question repeated across two dates as two independent questions', async () => {
    const data = material()
    data.evidence = [
      { questionId: 'bank-private-a', correct: true, uncertain: false, completedAt: '2026-09-12T00:00:00Z' },
      { questionId: 'bank-private-a', correct: true, uncertain: false, completedAt: '2026-09-13T00:00:00Z' },
    ]
    mockStudent(data)
    render(<ExamReview session={student} studentId="student-id" onExit={vi.fn()} />)
    await screen.findByText('第 1 题 A')
    openUnit()
    expect(screen.queryByText('同类题已复核', { exact: true })).not.toBeInTheDocument()
    expect(screen.getByText(/1 道不同题答对且确定 · 2 个北京时间日期/)).toBeInTheDocument()
  })

  it('counts Unicode code points for the eight-character minimum and safely caps input at 3000 characters', async () => {
    mockStudent(material())
    render(<ExamReview session={student} studentId="student-id" onExit={vi.fn()} />)
    await screen.findByText('第 1 题 A')
    openUnit()
    const input = screen.getByLabelText('先写你的判断与依据')
    const save = screen.getByRole('button', { name: '我能说明依据 · 保存自检' })
    fireEvent.change(input, { target: { value: '𝐶'.repeat(7) } })
    expect(save).toBeDisabled()
    expect(screen.getByText(/7\/3000/)).toBeInTheDocument()
    fireEvent.change(input, { target: { value: '𝐶'.repeat(8) } })
    expect(save).toBeEnabled()
    expect(screen.getByText(/8\/3000/)).toBeInTheDocument()
    const longResponse = '𝐶'.repeat(3000)
    fireEvent.change(input, { target: { value: longResponse + '𝐶多余' } })
    expect(input).toHaveValue(longResponse)
    expect(screen.getByText(/3000\/3000/)).toBeInTheDocument()
    fireEvent.click(save)
    await screen.findByText('已保存自检。尚未评分，请展开参考解析核对自己的过程。')
    expect(vi.mocked(accessApi)).toHaveBeenCalledWith(student, 'exam_recall', { unitId: 'Q01A', response: longResponse, selfRating: 'understood' })
  })

  it('opens from the real teacher preview dashboard and uses the authenticated teacher proxy for material and pages', async () => {
    const realApi = await vi.importActual<typeof import('../lib/api')>('../lib/api')
    vi.mocked(teacherApi).mockImplementation(realApi.teacherApi)
    const teacher: SessionIdentity = { ...student, role: 'teacher', token: 'teacher-test-only' }
    writeAccessSession(teacher)
    const fetchMock = vi.fn(async (_url: RequestInfo | URL, options?: RequestInit) => {
      const body = JSON.parse(String(options?.body)) as { action: string; data: unknown }
      if (body.action === 'exam_material') return new Response(JSON.stringify(material()), { status: 200 })
      if (body.action === 'exam_material_page') return new Response(JSON.stringify({ page: { mimeType: 'image/png', payloadBase64: 'dGVzdA==', width: 1300, height: 1900 } }), { status: 200 })
      throw new Error('Unexpected proxy action')
    })
    vi.stubGlobal('fetch', fetchMock)
    const dashboard: StudentDashboardData = { profile: { id: 'preview-target', displayName: '预览学生', gradeBand: '高三', enrollmentStartDate: '2026-09-12', needsInitialDiagnostic: false }, plans: [], skillStates: [], skillDefinitions: [], todayQuestionCount: 0, achievements: [], examReview: { id: 'exam-test', title: '福州化学试卷', unitCount: 95 } }
    render(<StudentApp session={teacher} initialDashboard={dashboard} onDashboard={vi.fn()} previewMode onExitPreview={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: '进入逐项复盘' }))
    await screen.findByText('第 1 题 A')
    expect(screen.getByText(/只读预览：可查看学生自检/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '第 1 页' }))
    await screen.findByRole('img', { name: /含手写批注/ })
    expect(fetchMock).toHaveBeenCalledTimes(2)
    const requests = fetchMock.mock.calls.map(([url, options]) => ({ url: String(url), body: JSON.parse(String(options?.body)), headers: options?.headers }))
    expect(requests.every((request) => request.url.endsWith('/chemistry-teacher'))).toBe(true)
    expect(requests.map((request) => request.body)).toEqual([{ action: 'exam_material', data: { studentId: 'preview-target' } }, { action: 'exam_material_page', data: { page: 1, studentId: 'preview-target' } }])
    expect(requests.every((request) => (request.headers as Record<string, string>)['x-app-session'] === teacher.token)).toBe(true)
    expect(accessApi).not.toHaveBeenCalled()
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /保存自检/ })).not.toBeInTheDocument()
  })
})
