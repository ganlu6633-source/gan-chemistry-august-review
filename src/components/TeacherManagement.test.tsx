import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { teacherApi } from '../lib/api'
import type { TeachingCatalog, TeachingPlanPreview } from '../domain/teachingManagement'
import { TeacherManagement } from './TeacherManagement'

vi.mock('../lib/api', () => ({ teacherApi: vi.fn() }))
const api = vi.mocked(teacherApi)
const catalog: TeachingCatalog = {
  catalogVersion: 'version-1',
  classes: [{ id: 'c1', name: '高一周末班', gradeBand: '高一', memberCount: 1 }],
  students: [
    { id: 's1', displayName: '林天佑', gradeBand: '高一', classId: 'c1', className: '高一周末班', status: 'active', progressSummary: '物质分类第一课', topicIds: ['pure'], textbookVersion: '高一教材' },
    { id: 's2', displayName: '初三同学', gradeBand: '初三', classId: null, className: '', status: 'active', progressSummary: '化学导言', topicIds: [], textbookVersion: '科粤版' },
  ],
  topics: [
    { id: 'root', parentId: null, title: '物质分类', gradeBands: ['高一'], order: 0, readyQuestionCount: 12, pendingQuestionCount: 2 },
    { id: 'pure', parentId: 'root', title: '纯净物与混合物', gradeBands: ['高一'], order: 0, readyQuestionCount: 6, pendingQuestionCount: 0 },
    { id: 'oxide', parentId: 'root', title: '氧化物', gradeBands: ['高一'], order: 1, readyQuestionCount: 6, pendingQuestionCount: 2 },
  ],
}
const preview: TeachingPlanPreview = { previewToken: 'preview-123', canApply: true, rows: [{ studentId: 's1', studentName: '林天佑', date: '2026-09-12', title: '纯净物与混合物', questionCount: 3, questionIds: ['q1', 'q2', 'q3'], status: 'ready' }], warnings: [], summary: { studentCount: 1, planCount: 1, questionCount: 3 } }

async function courseReady() {
  render(<TeacherManagement mode="courses" initialDate="2026-09-12" />)
  await screen.findByRole('heading', { name: '课程安排' })
  fireEvent.change(screen.getByLabelText('选择班级'), { target: { value: 'c1' } })
  fireEvent.click(screen.getByRole('checkbox', { name: '选择纯净物与混合物' }))
}

beforeEach(() => {
  api.mockReset()
  api.mockImplementation(async (action) => {
    if (action === 'teaching_catalog') return structuredClone(catalog)
    if (action === 'preview_teaching_plan') return structuredClone(preview)
    if (action === 'apply_teaching_plan') return { message: '计划已保存', appliedPlans: 1, affectedStudents: 1 }
    throw new Error(`Unexpected action: ${action}`)
  })
})
afterEach(cleanup)

describe('teacher management workflow', () => {
  it('creates a student from a same-grade reference using progress identity only', async () => {
    const original = api.getMockImplementation()!
    api.mockImplementation(async (action, data) => action === 'manage_student' ? { studentId: 'new', message: '学生已创建', accessCodes: { studentCode: 'new-student-code', guardianCode: 'new-guardian-code' } } : original(action, data))
    render(<TeacherManagement mode="students" />)
    fireEvent.click(await screen.findByRole('button', { name: '添加学生' }))
    const form = screen.getByRole('form', { name: '添加学生' })
    fireEvent.change(within(form).getByLabelText('学生姓名'), { target: { value: '肖存鑫' } })
    fireEvent.change(within(form).getByLabelText('学生年段'), { target: { value: '高一' } })
    const reference = within(form).getByLabelText('参照学生的教学起点')
    expect(within(reference).queryByRole('option', { name: /初三同学/ })).not.toBeInTheDocument()
    fireEvent.change(reference, { target: { value: 's1' } })
    fireEvent.change(within(form).getByLabelText('所属班级'), { target: { value: 'c1' } })
    expect(within(form).getByText(/成绩、能力证据、错题与答题历史不复制/)).toBeInTheDocument()
    fireEvent.click(within(form).getByRole('button', { name: '创建学生档案' }))
    await screen.findByText('new-student-code')
    expect(api).toHaveBeenCalledWith('manage_student', { operation: 'create', displayName: '肖存鑫', gradeBand: '高一', classId: 'c1', referenceStudentId: 's1' })
    const payload = api.mock.calls.find(([action]) => action === 'manage_student')![1] as Record<string, unknown>
    expect(Object.keys(payload).sort()).toEqual(['operation', 'displayName', 'gradeBand', 'classId', 'referenceStudentId'].sort())
  })

  it('requires one business confirmation to archive and restores without another confirmation', async () => {
    const current = structuredClone(catalog)
    api.mockImplementation(async (action, data) => {
      if (action === 'teaching_catalog') return structuredClone(current)
      if (action === 'manage_student') { current.students[0].status = (data as { operation: string }).operation === 'archive' ? 'archived' : 'active'; return { studentId: 's1', message: '名单已更新' } }
      throw new Error('Unexpected call')
    })
    render(<TeacherManagement mode="students" />)
    await screen.findByRole('heading', { name: '林天佑' })
    const card = screen.getByRole('heading', { name: '林天佑' }).closest('article')!
    fireEvent.click(within(card).getByRole('button', { name: '移出名单' }))
    expect(api.mock.calls.filter(([action]) => action === 'manage_student')).toHaveLength(0)
    fireEvent.click(within(screen.getByRole('alertdialog')).getByRole('button', { name: '确认移出' }))
    await waitFor(() => expect(screen.queryByRole('heading', { name: '林天佑' })).not.toBeInTheDocument())
    fireEvent.change(screen.getByLabelText('名单范围'), { target: { value: 'archived' } })
    fireEvent.click(await screen.findByRole('button', { name: '恢复到名单' }))
    await waitFor(() => expect(api).toHaveBeenCalledWith('manage_student', { operation: 'restore', studentId: 's1' }))
    expect(api.mock.calls.filter(([action]) => action === 'manage_student')).toHaveLength(2)
  })

  it('saves only the exact reviewed token and never sends an unpreviewed question list', async () => {
    await courseReady()
    expect(api.mock.calls.some(([action]) => action === 'apply_teaching_plan')).toBe(false)
    fireEvent.click(screen.getByRole('button', { name: '预览具体计划' }))
    fireEvent.click(await screen.findByRole('button', { name: '保存这份计划' }))
    await screen.findByText(/计划已保存/)
    expect(api).toHaveBeenCalledWith('apply_teaching_plan', { previewToken: 'preview-123' })
  })

  it('invalidates the preview when the teacher changes dates or quantity', async () => {
    await courseReady()
    fireEvent.click(screen.getByRole('button', { name: '预览具体计划' }))
    await screen.findByRole('button', { name: '保存这份计划' })
    fireEvent.change(screen.getByLabelText('纯净物与混合物题量'), { target: { value: '1' } })
    expect(screen.queryByRole('button', { name: '保存这份计划' })).not.toBeInTheDocument()
    expect(api.mock.calls.some(([action]) => action === 'apply_teaching_plan')).toBe(false)
  })

  it('discards a late preview response after the target has changed', async () => {
    let resolvePreview!: (value: TeachingPlanPreview) => void
    api.mockImplementation(async (action) => action === 'teaching_catalog' ? structuredClone(catalog) : new Promise<TeachingPlanPreview>((resolve) => { resolvePreview = resolve }))
    await courseReady()
    fireEvent.click(screen.getByRole('button', { name: '预览具体计划' }))
    fireEvent.change(screen.getByLabelText('安排对象'), { target: { value: 'student' } })
    await act(async () => resolvePreview(preview))
    expect(screen.queryByRole('button', { name: '保存这份计划' })).not.toBeInTheDocument()
    expect(screen.getByLabelText('选择学生')).toHaveValue('')
  })

  it('blocks partial plans and explains the exact missing resource', async () => {
    api.mockImplementation(async (action) => action === 'teaching_catalog' ? structuredClone(catalog) : { ...preview, canApply: false, previewToken: null, rows: [{ ...preview.rows[0], status: 'blocked', reason: '该学生可用的独立原题不足3道' }], warnings: ['原计划保持不变'] })
    await courseReady()
    fireEvent.click(screen.getByRole('button', { name: '预览具体计划' }))
    expect(await screen.findByRole('button', { name: '保存这份计划' })).toBeDisabled()
    expect(screen.getByText('该学生可用的独立原题不足3道')).toBeInTheDocument()
    expect(api.mock.calls.some(([action]) => action === 'apply_teaching_plan')).toBe(false)
  })

  it('adds a parent through its leaves and does not duplicate selected topics', async () => {
    await courseReady()
    fireEvent.click(screen.getByRole('checkbox', { name: '选择物质分类全部细点' }))
    expect(screen.getAllByRole('spinbutton')).toHaveLength(2)
    fireEvent.click(screen.getByRole('button', { name: '上移氧化物' }))
    fireEvent.click(screen.getByRole('button', { name: '预览具体计划' }))
    await screen.findByRole('button', { name: '保存这份计划' })
    const request = api.mock.calls.find(([action]) => action === 'preview_teaching_plan')![1] as { items: Array<{ topicId: string; date: string }> }
    expect(request.items.map((item) => item.topicId)).toEqual(['oxide', 'pure'])
    expect(new Set(request.items.map((item) => item.topicId)).size).toBe(2)
  })

  it('loads a saved target plan and permits a reviewed empty plan to clear unstarted work', async () => {
    const saved = structuredClone(catalog)
    saved.classes[0].planItems = [{ topicId: 'oxide', date: '2026-09-15', questionCount: 2 }]
    api.mockImplementation(async (action) => {
      if (action === 'teaching_catalog') return saved
      if (action === 'preview_teaching_plan') return { ...preview, rows: [], summary: { studentCount: 1, planCount: 0, questionCount: 0 } }
      if (action === 'apply_teaching_plan') return { message: '未开始的安排已清空', appliedPlans: 0, affectedStudents: 1 }
      throw new Error('Unexpected call')
    })
    render(<TeacherManagement mode="courses" />)
    fireEvent.change(await screen.findByLabelText('选择班级'), { target: { value: 'c1' } })
    expect(screen.getByLabelText('氧化物题量')).toHaveValue(2)
    expect(screen.getByLabelText('氧化物 · 日期')).toHaveValue('2026-09-15')
    fireEvent.click(screen.getByRole('button', { name: '清空选择' }))
    fireEvent.click(screen.getByRole('button', { name: '预览具体计划' }))
    fireEvent.click(await screen.findByRole('button', { name: '清空未开始的安排' }))
    await screen.findByText(/未开始的安排已清空/)
    expect(api).toHaveBeenCalledWith('preview_teaching_plan', { targetType: 'class', targetId: 'c1', items: [], keepExistingPlanIds: [], replaceFuture: true })
    expect(api).toHaveBeenCalledWith('apply_teaching_plan', { previewToken: 'preview-123' })
  })

  it('browses pending source records without adding them to the teaching plan', async () => {
    const original = api.getMockImplementation()!
    api.mockImplementation(async (action, data) => action === 'list_teaching_materials' ? { materials: [{ id: 'm1', title: '物质分类练习原卷', sourceLocation: 'U盘/高一/第一单元.pdf', topicTitles: ['物质分类'], status: 'needs_review', candidateCount: 12, duplicateCopies: 2 }], total: 26, page: (data as { page: number }).page, pageSize: 25 } : original(action, data))
    await courseReady()
    const summary = screen.getByText('浏览已收录资源目录')
    const details = summary.closest('details')!
    await act(async () => { details.open = true; fireEvent(details, new Event('toggle')) })
    await screen.findByText('物质分类练习原卷')
    expect(screen.getByText('待审核')).toBeInTheDocument()
    expect(screen.getAllByRole('spinbutton')).toHaveLength(1)
    fireEvent.click(screen.getByRole('button', { name: '下一页' }))
    await waitFor(() => expect(api).toHaveBeenCalledWith('list_teaching_materials', { page: 2, pageSize: 25 }))
    expect(api.mock.calls.some(([action]) => action === 'apply_teaching_plan')).toBe(false)
  })

  it('retains exact existing plans by default instead of rerolling their saved topic selections', async () => {
    const current = structuredClone(catalog)
    current.students[0].currentPlans = [
      { id: 'old-original', date: '2026-09-12', title: '原卷第1题', questionCount: 1, started: false, inCurrentProgram: true },
      { id: 'old-hidden', date: '2026-09-20', title: '旧版后续安排', questionCount: 12, started: false, inCurrentProgram: false },
    ]
    current.classes[0].planItems = [{ topicId: 'pure', date: '2026-09-12', questionCount: 1 }]
    const original = api.getMockImplementation()!
    api.mockImplementation(async (action, data) => action === 'teaching_catalog' ? current : original(action, data))
    render(<TeacherManagement mode="courses" />)
    fireEvent.change(await screen.findByLabelText('选择班级'), { target: { value: 'c1' } })
    expect(screen.getByRole('checkbox', { name: '保留林天佑 2026-09-12 原卷第1题' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: '保留林天佑 2026-09-20 旧版后续安排' })).toBeChecked()
    expect(screen.getByText('原有未开放安排')).toBeInTheDocument()
    expect(screen.queryAllByRole('spinbutton')).toHaveLength(0)
    fireEvent.click(screen.getByRole('button', { name: '预览具体计划' }))
    expect(await screen.findByRole('button', { name: '保存这份计划' })).toBeEnabled()
    expect(screen.queryByRole('button', { name: '清空未开始的安排' })).not.toBeInTheDocument()
    expect(api).toHaveBeenCalledWith('preview_teaching_plan', { targetType: 'class', targetId: 'c1', items: [], keepExistingPlanIds: ['old-original', 'old-hidden'], replaceFuture: true })
  })

  it('removes only explicitly unchecked plans and keeps started plans locked in the draft', async () => {
    const current = structuredClone(catalog)
    current.students[0].currentPlans = [
      { id: 'started', date: '2026-09-12', title: '进行中原卷', questionCount: 2, started: true },
      { id: 'future', date: '2026-09-13', title: '后续原卷', questionCount: 2, started: false },
    ]
    const original = api.getMockImplementation()!
    api.mockImplementation(async (action, data) => action === 'teaching_catalog' ? current : original(action, data))
    render(<TeacherManagement mode="courses" />)
    fireEvent.change(await screen.findByLabelText('选择班级'), { target: { value: 'c1' } })
    const started = screen.getByRole('checkbox', { name: '保留林天佑 2026-09-12 进行中原卷' })
    expect(started).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: '取消保留全部未开始安排' }))
    expect(started).toBeChecked()
    expect(screen.getByRole('checkbox', { name: '保留林天佑 2026-09-13 后续原卷' })).not.toBeChecked()
    fireEvent.click(screen.getByRole('button', { name: '预览具体计划' }))
    await screen.findByRole('button', { name: '保存这份计划' })
    expect(api).toHaveBeenCalledWith('preview_teaching_plan', expect.objectContaining({ keepExistingPlanIds: ['started'], items: [] }))
    fireEvent.click(screen.getByRole('checkbox', { name: '保留林天佑 2026-09-13 后续原卷' }))
    expect(screen.queryByRole('button', { name: '保存这份计划' })).not.toBeInTheDocument()
  })

  it('requires removing the retained day or changing the date before adding new topics on that date', async () => {
    const current = structuredClone(catalog)
    current.students[0].currentPlans = [{ id: 'existing', date: '2026-09-12', title: '原来的题组', questionCount: 4, started: false }]
    const original = api.getMockImplementation()!
    api.mockImplementation(async (action, data) => action === 'teaching_catalog' ? current : original(action, data))
    await courseReady()
    fireEvent.click(screen.getByRole('button', { name: '预览具体计划' }))
    expect(screen.getByRole('alert')).toHaveTextContent('已有保留的安排')
    expect(api.mock.calls.some(([action]) => action === 'preview_teaching_plan')).toBe(false)
    fireEvent.click(screen.getByRole('checkbox', { name: '保留林天佑 2026-09-12 原来的题组' }))
    fireEvent.click(screen.getByRole('button', { name: '预览具体计划' }))
    await screen.findByRole('button', { name: '保存这份计划' })
    expect(api).toHaveBeenCalledWith('preview_teaching_plan', expect.objectContaining({ keepExistingPlanIds: [], items: [{ topicId: 'pure', date: '2026-09-12', questionCount: 3 }] }))
  })

  it('collects every classmate original plan identity and resets them when changing target', async () => {
    const current = structuredClone(catalog)
    current.students[0].currentPlans = [{ id: 'one', date: '2026-09-12', title: '甲原题', questionCount: 7, started: false }]
    current.students.push({ ...current.students[0], id: 's3', displayName: '同班同学', currentPlans: [{ id: 'two', date: '2026-09-12', title: '乙原题', questionCount: 6, started: false }] })
    const original = api.getMockImplementation()!
    api.mockImplementation(async (action, data) => action === 'teaching_catalog' ? current : original(action, data))
    render(<TeacherManagement mode="courses" />)
    fireEvent.change(await screen.findByLabelText('选择班级'), { target: { value: 'c1' } })
    fireEvent.click(screen.getByRole('button', { name: '预览具体计划' }))
    await screen.findByRole('button', { name: '保存这份计划' })
    expect(api).toHaveBeenCalledWith('preview_teaching_plan', expect.objectContaining({ keepExistingPlanIds: ['one', 'two'] }))
    fireEvent.change(screen.getByLabelText('安排对象'), { target: { value: 'student' } })
    fireEvent.change(screen.getByLabelText('选择学生'), { target: { value: 's1' } })
    expect(screen.queryByRole('checkbox', { name: /保留同班同学/ })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '预览具体计划' }))
    await screen.findByRole('button', { name: '保存这份计划' })
    expect(api).toHaveBeenLastCalledWith('preview_teaching_plan', expect.objectContaining({ targetType: 'student', keepExistingPlanIds: ['one'] }))
  })
})
