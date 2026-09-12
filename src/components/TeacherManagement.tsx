import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { ArrowDown, ArrowUp, CheckCircle2, ChevronDown, ChevronRight, Eye, Plus, RefreshCw, Save, Trash2, Undo2, X } from 'lucide-react'
import type { GradeBand } from '../domain/types'
import { beijingToday, canSaveTeachingPreview, managementGrades, moveTeachingItem, nextPlanDate, teachingPlanProblems, topicLeaves, visibleTopicIds } from '../domain/teachingManagement'
import type { ManagedStudent, ManageStudentResult, TeachingCatalog, TeachingClass, TeachingPlanItem, TeachingPlanPreview, TeachingPlanRequest, TeachingTopic } from '../domain/teachingManagement'
import { teacherApi } from '../lib/api'
import { ChemText } from './ChemText'
import './TeacherManagement.css'

function messageOf(reason: unknown, fallback: string) { return reason instanceof Error ? reason.message : fallback }

export function TeacherManagement({ mode, initialDate, onPreview, onChanged }: { mode: 'students' | 'courses'; initialDate?: string; onPreview?: (studentId: string) => void; onChanged?: () => void }) {
  const [catalog, setCatalog] = useState<TeachingCatalog | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const request = useRef(0)
  const reload = useCallback(async () => {
    const id = ++request.current
    setLoading(true); setError('')
    try { const data = await teacherApi<TeachingCatalog>('teaching_catalog'); if (id === request.current) setCatalog({ ...data, classes: [...data.classes].sort((a, b) => managementGrades.indexOf(a.gradeBand) - managementGrades.indexOf(b.gradeBand) || a.name.localeCompare(b.name, 'zh-CN')), students: [...data.students].sort((a, b) => managementGrades.indexOf(a.gradeBand) - managementGrades.indexOf(b.gradeBand) || a.displayName.localeCompare(b.displayName, 'zh-CN')) }) }
    catch (reason) { if (id === request.current) setError(messageOf(reason, '学生与课程目录暂时无法读取。')) }
    finally { if (id === request.current) setLoading(false) }
  }, [])
  useEffect(() => { void reload(); return () => { request.current += 1 } }, [reload])
  const changed = async () => { await reload(); onChanged?.() }
  return <div className="teaching-management">
    {error && <div className="inline-alert" role="alert">{error}<button className="text-button" onClick={() => void reload()}>重新读取</button></div>}
    {!catalog ? loading && <div className="center-loading"><RefreshCw className="spin" />正在读取学生和课程…</div> : mode === 'students'
      ? <StudentManagement catalog={catalog} loading={loading} onReload={changed} onPreview={onPreview} />
      : <CourseManagement catalog={catalog} loading={loading} initialDate={initialDate} onReload={changed} />}
  </div>
}

function StudentManagement({ catalog, loading, onReload, onPreview }: { catalog: TeachingCatalog; loading: boolean; onReload: () => Promise<void>; onPreview?: (studentId: string) => void }) {
  const [grade, setGrade] = useState('')
  const [classId, setClassId] = useState('')
  const [status, setStatus] = useState<'active' | 'archived' | ''>('active')
  const [search, setSearch] = useState('')
  const [editing, setEditing] = useState<ManagedStudent | 'new' | null>(null)
  const [classesOpen, setClassesOpen] = useState(false)
  const [confirmId, setConfirmId] = useState('')
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [codes, setCodes] = useState<ManageStudentResult['accessCodes']>()
  const classes = catalog.classes.filter((item) => !grade || item.gradeBand === grade)
  const students = catalog.students.filter((student) => (!grade || student.gradeBand === grade) && (!classId || (classId === 'unassigned' ? !student.classId : student.classId === classId)) && (!status || student.status === status) && student.displayName.includes(search.trim()))
  async function changeStatus(student: ManagedStudent, operation: 'archive' | 'restore') {
    setBusy(student.id); setError(''); setMessage('')
    try { const result = await teacherApi<ManageStudentResult>('manage_student', { operation, studentId: student.id }); setMessage(result.message); setConfirmId(''); await onReload() }
    catch (reason) { setError(messageOf(reason, '学生名单没有更新成功，请重试。')) }
    finally { setBusy('') }
  }
  return <>
    <div className="teacher-page-head"><div><span className="eyebrow">初三 · 高一 · 高二 · 高三</span><h1>学生管理</h1></div><div className="tm-heading-actions"><button className="secondary-button" onClick={() => setClassesOpen((value) => !value)} aria-expanded={classesOpen}>管理班级</button><button className="primary-button" onClick={() => { setEditing('new'); setError(''); setCodes(undefined) }}><Plus size={17} />添加学生</button></div></div>
    <p className="tm-help">新学生可以按参照同学的教材和已学内容设置起点。成绩、答题记录、能力证据和错题由本人重新积累。</p>
    {message && <div className="success-message" role="status"><CheckCircle2 />{message}</div>}
    {error && <div className="inline-alert" role="alert">{error}</div>}
    {codes && <section className="tm-secrets" aria-label="新学生登录码"><h2>请保存这位学生的登录码</h2><dl><dt>学生登录码</dt><dd><code>{codes.studentCode}</code></dd><dt>家长登录码</dt><dd><code>{codes.guardianCode}</code></dd></dl><p>此处只展示本次创建返回的登录码，关闭后可在“权限与访问码”中管理。</p><button className="secondary-button" onClick={() => setCodes(undefined)}>已保存，收起登录码</button></section>}
    {classesOpen && <ClassManagement catalog={catalog} onReload={onReload} />}
    {editing && <StudentEditor key={editing === 'new' ? 'new' : editing.id} student={editing === 'new' ? undefined : editing} catalog={catalog} onClose={() => setEditing(null)} onSaved={async (result) => { setEditing(null); setMessage(result.message); setCodes(result.accessCodes); await onReload() }} />}
    <div className="tm-toolbar">
      <label className="tm-search">查找学生<input type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="输入姓名" /></label>
      <label>年段<select value={grade} onChange={(event) => { setGrade(event.target.value); setClassId('') }}><option value="">全部年段</option>{managementGrades.map((item) => <option key={item}>{item}</option>)}</select></label>
      <label>班级<select value={classId} onChange={(event) => setClassId(event.target.value)}><option value="">全部班级</option><option value="unassigned">未分班</option>{classes.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
      <label>名单范围<select value={status} onChange={(event) => setStatus(event.target.value as typeof status)}><option value="active">当前名单</option><option value="archived">已移出名单</option><option value="">全部档案</option></select></label>
    </div>
    <p className="tm-help">共 {students.length} 名{loading ? ' · 正在更新…' : ''}</p>
    <div className="tm-students">{students.map((student) => <article className="tm-student" key={student.id}>
      <div className="tm-student-head"><div><h2>{student.displayName}</h2><small>{student.gradeBand} · {student.className || '未分班'}</small></div><span className={`tm-status ${student.status}`}>{student.status === 'active' ? '在名单中' : '已移出'}</span></div>
      <p><b>教学起点：</b><ChemText>{student.progressSummary || '尚未设置'}</ChemText></p><p className="tm-help">{student.textbookVersion || '教材待设置'}</p>
      <div className="tm-actions"><button className="table-action" disabled={Boolean(busy) || loading} onClick={() => setEditing(student)}>编辑档案与起点</button>{student.status === 'active' && onPreview && <button className="table-action" onClick={() => onPreview(student.id)} aria-label={`模拟查看${student.displayName}的学生端`}><Eye size={16} />模拟查看</button>}{student.status === 'active' ? <button className="table-action tm-remove" disabled={Boolean(busy) || loading} onClick={() => setConfirmId(student.id)}>移出名单</button> : <button className="table-action" disabled={Boolean(busy) || loading} onClick={() => void changeStatus(student, 'restore')}><Undo2 size={16} />{busy === student.id ? '正在恢复…' : '恢复到名单'}</button>}</div>
      {confirmId === student.id && <section className="tm-confirm" role="alertdialog" aria-labelledby={`remove-${student.id}`}><h3 id={`remove-${student.id}`}>将{student.displayName}移出当前名单？</h3><p>学习历史会保留，之后可在“已移出名单”中恢复。</p><div className="tm-actions"><button className="secondary-button" disabled={Boolean(busy)} onClick={() => setConfirmId('')}>取消</button><button className="primary-button" disabled={Boolean(busy)} onClick={() => void changeStatus(student, 'archive')}>{busy === student.id ? '正在移出…' : '确认移出'}</button></div></section>}
    </article>)}</div>{!students.length && <div className="tm-empty">没有符合条件的学生，可调整筛选或添加新学生。</div>}
  </>
}

function StudentEditor({ student, catalog, onClose, onSaved }: { student?: ManagedStudent; catalog: TeachingCatalog; onClose: () => void; onSaved: (result: ManageStudentResult) => Promise<void> }) {
  const [name, setName] = useState(student?.displayName ?? '')
  const [grade, setGrade] = useState<GradeBand>(student?.gradeBand ?? '初三')
  const [classId, setClassId] = useState(student?.classId ?? '')
  const [referenceId, setReferenceId] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const reference = catalog.students.find((item) => item.id === referenceId)
  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!name.trim()) { setError('请填写学生姓名。'); return }
    setSaving(true); setError('')
    try { const result = await teacherApi<ManageStudentResult>('manage_student', { operation: student ? 'update' : 'create', ...(student ? { studentId: student.id } : {}), displayName: name.trim(), gradeBand: grade, classId: classId || null, referenceStudentId: referenceId || null }); await onSaved(result) }
    catch (reason) { setError(messageOf(reason, '学生档案没有保存成功，请重试。')) }
    finally { setSaving(false) }
  }
  return <section className="teacher-panel"><form className="tm-form" onSubmit={submit} aria-label={student ? '编辑学生档案' : '添加学生'}><div className="tm-form-head"><h2>{student ? `编辑${student.displayName}的档案` : '添加学生'}</h2><button type="button" className="tm-icon-button" aria-label="关闭学生编辑" disabled={saving} onClick={onClose}><X /></button></div>
    <div className="tm-form-grid"><label>学生姓名<input autoFocus value={name} maxLength={60} onChange={(event) => setName(event.target.value)} required /></label><label>学生年段<select value={grade} onChange={(event) => { setGrade(event.target.value as GradeBand); setClassId(''); setReferenceId('') }}>{managementGrades.map((item) => <option key={item}>{item}</option>)}</select></label><label>所属班级<select value={classId} onChange={(event) => setClassId(event.target.value)}><option value="">暂不分班</option>{catalog.classes.filter((item) => item.gradeBand === grade).map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label>参照学生的教学起点<select value={referenceId} onChange={(event) => setReferenceId(event.target.value)}><option value="">{student ? '保持当前起点' : '不使用参照学生'}</option>{catalog.students.filter((item) => item.id !== student?.id && item.gradeBand === grade && item.status === 'active').map((item) => <option key={item.id} value={item.id}>{item.displayName} · {item.className || '未分班'}</option>)}</select></label></div>
    {reference && <div className="tm-notice"><b>将按{reference.displayName}设置教学起点</b><p><ChemText>{`${reference.textbookVersion || '教材待设置'} · ${reference.progressSummary || '尚未登记已学内容'}`}</ChemText></p><span>仅复制教材和已学内容；成绩、能力证据、错题与答题历史不复制。</span></div>}
    {error && <div className="inline-alert" role="alert">{error}</div>}<div className="tm-actions"><button className="primary-button" disabled={saving}><Save size={17} />{saving ? '正在保存…' : student ? '保存档案' : '创建学生档案'}</button><button type="button" className="text-button" disabled={saving} onClick={onClose}>取消</button></div>
  </form></section>
}

function ClassManagement({ catalog, onReload }: { catalog: TeachingCatalog; onReload: () => Promise<void> }) {
  const [editing, setEditing] = useState<TeachingClass | null>(null)
  const [name, setName] = useState('')
  const [grade, setGrade] = useState<GradeBand>('初三')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  async function save(event: FormEvent) {
    event.preventDefault(); if (!name.trim()) { setError('请填写班级名称。'); return }
    setBusy(true); setError(''); setMessage('')
    try { const result = await teacherApi<{ classId: string; message: string }>('manage_class', { operation: editing ? 'update' : 'create', ...(editing ? { classId: editing.id } : {}), name: name.trim(), gradeBand: grade }); setMessage(result.message); setName(''); setEditing(null); await onReload() }
    catch (reason) { setError(messageOf(reason, '班级没有保存成功。')) }
    finally { setBusy(false) }
  }
  return <section className="teacher-panel"><h2>班级管理</h2><form className="tm-form" onSubmit={save}><div className="tm-form-grid"><label>班级名称<input value={name} maxLength={60} onChange={(event) => setName(event.target.value)} required placeholder="例如：高一周末班" /></label><label>班级年段<select value={grade} onChange={(event) => setGrade(event.target.value as GradeBand)}>{managementGrades.map((item) => <option key={item}>{item}</option>)}</select></label></div>{error && <div className="inline-alert" role="alert">{error}</div>}{message && <div className="success-message" role="status">{message}</div>}<div className="tm-actions"><button className="secondary-button" disabled={busy}>{busy ? '正在保存…' : editing ? '保存班级' : '创建班级'}</button>{editing && <button type="button" className="text-button" onClick={() => { setEditing(null); setName('') }}>取消编辑</button>}</div></form><div className="tm-class-list">{catalog.classes.map((item) => <article key={item.id}><div><b>{item.name}</b><small>{item.gradeBand} · {item.memberCount} 名学生</small></div><button className="table-action" disabled={busy} onClick={() => { setEditing(item); setName(item.name); setGrade(item.gradeBand); setError(''); setMessage('') }}>编辑班级</button></article>)}</div></section>
}

function TopicCheckbox({ checked, partial, disabled, label, onChange }: { checked: boolean; partial: boolean; disabled: boolean; label: string; onChange: () => void }) {
  const ref = useRef<HTMLInputElement>(null)
  useEffect(() => { if (ref.current) ref.current.indeterminate = partial }, [partial])
  return <input ref={ref} type="checkbox" checked={checked} aria-label={label} disabled={disabled} onChange={onChange} />
}

type TeachingMaterialsPage = { materials: Array<{ id: string; title: string; sourceLocation: string; topicTitles: string[]; status: 'ready' | 'needs_review'; candidateCount: number; duplicateCopies: number }>; total: number; page: number; pageSize: number }

function TeachingMaterials({ topics }: { topics: TeachingTopic[] }) {
  const [search, setSearch] = useState('')
  const [topicId, setTopicId] = useState('')
  const [query, setQuery] = useState({ search: '', topicId: '', page: 1 })
  const [data, setData] = useState<TeachingMaterialsPage | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [retry, setRetry] = useState(0)
  useEffect(() => {
    let active = true
    setLoading(true); setError(''); setData(null)
    void teacherApi<TeachingMaterialsPage>('list_teaching_materials', { ...(query.topicId ? { topicId: query.topicId } : {}), ...(query.search ? { search: query.search } : {}), page: query.page, pageSize: 25 })
      .then((result) => { if (active) setData(result) })
      .catch((reason) => { if (active) setError(messageOf(reason, '资源目录暂时无法读取。')) })
      .finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [query, retry])
  return <section className="teacher-panel"><h2>已收录资源</h2><p className="tm-help">浏览已收录的本地和U盘资料。待审核资源可以查阅，但不会因为出现在目录中就自动用于学生计划。</p><form className="tm-toolbar" onSubmit={(event) => { event.preventDefault(); setQuery({ search: search.trim(), topicId, page: 1 }) }}><label className="tm-search">搜索资源<input type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="材料名称" /></label><label>资源主题<select value={topicId} onChange={(event) => setTopicId(event.target.value)}><option value="">全部主题</option>{topics.map((topic) => <option key={topic.id} value={topic.id}>{topic.title}</option>)}</select></label><button className="secondary-button">查找资源</button></form>{loading && <div className="tm-busy"><RefreshCw className="spin" size={18} />正在查找资源…</div>}{error && <div className="inline-alert" role="alert">{error}<button className="text-button" onClick={() => setRetry((value) => value + 1)}>重试</button></div>}{data && <><p className="tm-help">共 {data.total} 份收录记录 · 第 {data.page} 页</p><div className="tm-material-list">{data.materials.map((material) => <article key={material.id}><div className="tm-student-head"><h3><ChemText>{material.title}</ChemText></h3><span className={`tm-status ${material.status === 'ready' ? 'active' : 'archived'}`}>{material.status === 'ready' ? '已审核' : '待审核'}</span></div><p><ChemText>{material.topicTitles.join(' · ') || '主题待整理'}</ChemText></p><p className="tm-help">收录候选 {material.candidateCount} 题 · 重复副本 {material.duplicateCopies} 份</p><details><summary>查看来源位置</summary><p className="tm-source-location">{material.sourceLocation || '来源位置待补充'}</p></details></article>)}</div>{!data.materials.length && <div className="tm-empty">没有找到符合条件的已收录资源。</div>}<div className="tm-material-pages"><button className="secondary-button" disabled={data.page <= 1} onClick={() => setQuery((current) => ({ ...current, page: current.page - 1 }))}>上一页</button><span>第 {data.page} / {Math.max(1, Math.ceil(data.total / data.pageSize))} 页</span><button className="secondary-button" disabled={data.page * data.pageSize >= data.total} onClick={() => setQuery((current) => ({ ...current, page: current.page + 1 }))}>下一页</button></div></>}</section>
}

function CourseManagement({ catalog, loading, initialDate, onReload }: { catalog: TeachingCatalog; loading: boolean; initialDate?: string; onReload: () => Promise<void> }) {
  const [targetType, setTargetType] = useState<'student' | 'class'>('class')
  const [targetId, setTargetId] = useState('')
  const [startDate, setStartDate] = useState(initialDate && initialDate > beijingToday() ? initialDate : beijingToday())
  const [items, setItems] = useState<TeachingPlanItem[]>([])
  const [keepExistingPlanIds, setKeepExistingPlanIds] = useState<string[]>([])
  const [search, setSearch] = useState('')
  const [grade, setGrade] = useState('')
  const [collapsed, setCollapsed] = useState<Set<string>>(() => new Set(catalog.topics.filter((topic) => topic.parentId && catalog.topics.some((child) => child.parentId === topic.id)).map((topic) => topic.id)))
  const [preview, setPreview] = useState<TeachingPlanPreview | null>(null)
  const [previewing, setPreviewing] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [validation, setValidation] = useState<string[]>([])
  const [materialsOpen, setMaterialsOpen] = useState(false)
  const draftVersion = useRef(0)
  const previewVersion = useRef(-1)
  const active = useRef(true)
  useEffect(() => { active.current = true; return () => { active.current = false; draftVersion.current += 1 } }, [])
  useEffect(() => { draftVersion.current += 1; setPreview(null) }, [catalog.catalogVersion])
  const topics = useMemo(() => [...catalog.topics].sort((a, b) => a.order - b.order || a.title.localeCompare(b.title, 'zh-CN')), [catalog.topics])
  const byId = new Map(topics.map((topic) => [topic.id, topic]))
  const visible = visibleTopicIds(topics, search, grade)
  const selected = new Set(items.map((item) => item.topicId))
  const targets = targetType === 'class' ? catalog.classes.map((item) => ({ id: item.id, title: `${item.name} · ${item.gradeBand} · ${item.memberCount}人`, planItems: item.planItems ?? [] })) : catalog.students.filter((item) => item.status === 'active').map((item) => ({ id: item.id, title: `${item.displayName} · ${item.gradeBand}${item.className ? ` · ${item.className}` : ''}`, planItems: item.planItems ?? [] }))
  const targetStudents = catalog.students.filter((student) => student.status === 'active' && (targetType === 'student' ? student.id === targetId : student.classId === targetId))
  const existingPlans = targetStudents.flatMap((student) => (student.currentPlans ?? []).map((plan) => ({ ...plan, studentName: student.displayName }))).sort((a, b) => a.date.localeCompare(b.date) || a.studentName.localeCompare(b.studentName, 'zh-CN'))
  const retainedIds = [...new Set([...keepExistingPlanIds, ...existingPlans.filter((plan) => plan.started).map((plan) => plan.id)])]
  const isEmptyPlan = items.length === 0 && retainedIds.length === 0
  const request: TeachingPlanRequest = { targetType, targetId, items, keepExistingPlanIds: retainedIds, replaceFuture: true }
  function invalidate() { draftVersion.current += 1; setPreview(null); setMessage(''); setError(''); setValidation([]) }
  function changeItems(next: TeachingPlanItem[]) { invalidate(); setItems(next) }
  function chooseTarget(id: string) {
    invalidate(); setTargetId(id)
    const students = catalog.students.filter((student) => student.status === 'active' && (targetType === 'student' ? student.id === id : student.classId === id))
    const plans = students.flatMap((student) => student.currentPlans ?? [])
    setKeepExistingPlanIds(plans.map((plan) => plan.id))
    // Current plan rows own the original question identities. Do not turn them
    // back into topic requests, which would silently draw different questions.
    setItems(students.some((student) => student.currentPlans !== undefined) ? [] : (targets.find((item) => item.id === id)?.planItems ?? []).map((item) => ({ ...item })))
  }
  function toggleExisting(id: string) {
    if (existingPlans.find((plan) => plan.id === id)?.started) return
    invalidate(); setKeepExistingPlanIds((current) => current.includes(id) ? current.filter((value) => value !== id) : [...current, id])
  }
  function toggleTopic(topic: TeachingTopic) {
    const leaves = topicLeaves(topics, topic.id)
    const ids = new Set(leaves.map((item) => item.id))
    if (leaves.every((item) => selected.has(item.id))) { changeItems(items.filter((item) => !ids.has(item.topicId))); return }
    const next = [...items]
    let date = next.length ? nextPlanDate(next.map((item) => item.date).sort().at(-1)!) : startDate
    for (const leaf of leaves) if (!selected.has(leaf.id)) { next.push({ topicId: leaf.id, date, questionCount: 3 }); date = nextPlanDate(date) }
    changeItems(next)
  }
  async function generatePreview() {
    const problems = teachingPlanProblems(request, existingPlans)
    setValidation(problems); setError(''); setMessage(''); setPreview(null)
    if (problems.length) return
    const version = draftVersion.current
    setPreviewing(true)
    try { const result = await teacherApi<TeachingPlanPreview>('preview_teaching_plan', request); if (active.current && version === draftVersion.current) { previewVersion.current = version; setPreview(result) } }
    catch (reason) { if (active.current && version === draftVersion.current) setError(messageOf(reason, '计划预览没有生成，请重试。')) }
    finally { if (active.current) setPreviewing(false) }
  }
  async function apply() {
    if (!canSaveTeachingPreview(preview) || previewVersion.current !== draftVersion.current || saving) return
    const token = preview!.previewToken!
    setSaving(true); setError(''); setMessage('')
    try { const result = await teacherApi<{ message: string; appliedPlans: number; affectedStudents: number }>('apply_teaching_plan', { previewToken: token }); if (active.current) { setPreview(null); setMessage(`${result.message}（${result.affectedStudents}名学生，新增${result.appliedPlans}个日计划，保留${retainedIds.length}个已有安排）`); setTargetId(''); setItems([]); setKeepExistingPlanIds([]); await onReload() } }
    catch (reason) { if (active.current) { setPreview(null); setError(messageOf(reason, '计划未保存，请重新预览后再试。')) } }
    finally { if (active.current) setSaving(false) }
  }
  function renderTopic(topic: TeachingTopic, ancestors: Set<string>) {
    if (!visible.has(topic.id) || ancestors.has(topic.id)) return null
    const children = topics.filter((item) => item.parentId === topic.id)
    const leaves = topicLeaves(topics, topic.id)
    const count = leaves.filter((item) => selected.has(item.id)).length
    const expanded = Boolean(search.trim()) || !collapsed.has(topic.id)
    const path = new Set([...ancestors, topic.id])
    return <li key={topic.id} className="tm-topic"><div className="tm-topic-line">{children.length ? <button type="button" className="tm-topic-toggle" aria-label={`${expanded ? '收起' : '展开'}${topic.title}`} aria-expanded={expanded} onClick={() => setCollapsed((current) => { const next = new Set(current); if (expanded) next.add(topic.id); else next.delete(topic.id); return next })}>{expanded ? <ChevronDown /> : <ChevronRight />}</button> : <span className="tm-topic-spacer" />}<label><TopicCheckbox checked={leaves.length > 0 && count === leaves.length} partial={count > 0 && count < leaves.length} disabled={saving || !leaves.length} label={`选择${topic.title}${children.length ? '全部细点' : ''}`} onChange={() => toggleTopic(topic)} /><span className="tm-topic-content"><b><ChemText>{topic.title}</ChemText></b><small>可用 {topic.readyQuestionCount} 题{topic.pendingQuestionCount > 0 && <span className="tm-pending"> · 待核对候选 {topic.pendingQuestionCount} 项</span>}{children.length ? ` · ${leaves.length} 个细点` : ''}</small></span></label></div>{children.length > 0 && expanded && <ul className="tm-topic-children">{children.map((child) => renderTopic(child, path))}</ul>}</li>
  }
  return <>
    <div className="teacher-page-head"><div><span className="eyebrow">选择内容 → 查看计划 → 保存安排</span><h1>课程安排</h1></div></div>
    {message && <div className="success-message" role="status"><CheckCircle2 />{message}</div>}
    <section className="teacher-panel"><div className="tm-target"><label>安排对象<select value={targetType} disabled={saving} onChange={(event) => { invalidate(); setTargetType(event.target.value as typeof targetType); setTargetId(''); setItems([]); setKeepExistingPlanIds([]) }}><option value="class">整个班级</option><option value="student">单个学生</option></select></label><label>{targetType === 'class' ? '选择班级' : '选择学生'}<select value={targetId} disabled={saving} onChange={(event) => chooseTarget(event.target.value)}><option value="">请选择</option>{targets.map((item) => <option key={item.id} value={item.id}>{item.title}</option>)}</select></label><label>起始日期（北京时间）<input type="date" value={startDate} disabled={saving} onChange={(event) => { const value = event.target.value; setStartDate(value); if (items.length) { let date = value; changeItems(items.map((item) => { const next = { ...item, date }; date = nextPlanDate(date); return next })) } else invalidate() }} /></label></div><p className="tm-help">勾选内容后可调整顺序、日期和题量；同一天的内容会合并为一个日计划，每天最多8道基础题。</p><p className="tm-help">已有安排默认保留原题。取消某项保留后，保存时只移除该项未开始的安排；新增内容从下方目录勾选。已开始的任务和历史记录保留。</p></section>
    {targetId && <section className="teacher-panel tm-existing-plans" aria-label="已有课程安排"><div className="panel-head"><h2>已有安排</h2><span>{existingPlans.length}个日计划</span></div><p className="tm-help">勾选“保留”会保留原来的题目、顺序和进度。取消勾选后，预览并保存才会移除；已开始的安排固定保留。</p>{existingPlans.length > 0 ? <><div className="tm-actions"><button className="text-button" disabled={saving} onClick={() => { invalidate(); setKeepExistingPlanIds(existingPlans.map((plan) => plan.id)) }}>保留全部已有安排</button><button className="text-button tm-remove" disabled={saving || existingPlans.every((plan) => plan.started)} onClick={() => { invalidate(); setKeepExistingPlanIds(existingPlans.filter((plan) => plan.started).map((plan) => plan.id)) }}>取消保留全部未开始安排</button></div><div className="tm-existing-list">{existingPlans.map((plan) => <label className={`tm-existing-plan ${retainedIds.includes(plan.id) ? '' : 'tm-existing-remove'}`} key={plan.id}><input type="checkbox" checked={retainedIds.includes(plan.id)} disabled={saving || plan.started} aria-label={`保留${plan.studentName} ${plan.date} ${plan.title}`} onChange={() => toggleExisting(plan.id)} /><span><b>{plan.date} · {plan.studentName}</b><span><ChemText>{plan.title}</ChemText> · {plan.questionCount}道基础题</span>{(plan.inCurrentProgram === false || plan.isScheduled === false) && <small>原有未开放安排</small>}</span><em>{plan.started ? '已开始 · 固定保留' : retainedIds.includes(plan.id) ? '保留原题' : '保存后移除'}</em></label>)}</div></> : <div className="tm-empty">该对象当前没有已有安排，可从目录中添加。</div>}</section>}
    <div className="tm-notice">高三本次先安排福州材料中的10道原选择题，由易到难推进；填空小题暂不安排。</div>
    <div className="tm-plan-grid"><section className="teacher-panel"><h2>课程目录</h2><div className="tm-catalog-tools"><label>搜索内容<input type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="章节或知识点" /></label><label>目录年段<select value={grade} onChange={(event) => setGrade(event.target.value)}><option value="">全部</option>{managementGrades.map((item) => <option key={item}>{item}</option>)}</select></label></div><p className="tm-help">勾选大主题会加入其全部细点。可跨年段选择复习内容，是否适合下发由计划预览核对。</p><ul className="tm-topic-tree" aria-label="课程主题与细点">{topics.filter((topic) => !topic.parentId || !byId.has(topic.parentId)).map((topic) => renderTopic(topic, new Set()))}</ul>{!visible.size && <div className="tm-empty">没有找到相关内容，请换个关键词。</div>}</section>
      <section className="teacher-panel"><div className="panel-head"><h2>已选内容</h2><button className="text-button" disabled={!items.length || saving} onClick={() => changeItems([])}>清空选择</button></div><p className="tm-help">上移、下移调整课程顺序，日期留在所在位置；也可直接修改每行日期。</p>{!items.length ? <div className="tm-empty">当前没有新增内容。已有安排按上方的保留选择处理；可从目录继续添加内容。</div> : <ol className="tm-selected-list">{items.map((item, index) => <li className="tm-selected-row" key={`${item.topicId}-${index}`}><div className="tm-selected-top"><b className="tm-selected-title">{index + 1}. <ChemText>{byId.get(item.topicId)?.title || '目录内容已变化，请重新选择'}</ChemText></b><div className="tm-order-buttons"><button className="tm-icon-button" aria-label={`上移${byId.get(item.topicId)?.title}`} disabled={index === 0 || saving} onClick={() => changeItems(moveTeachingItem(items, index, -1))}><ArrowUp /></button><button className="tm-icon-button" aria-label={`下移${byId.get(item.topicId)?.title}`} disabled={index === items.length - 1 || saving} onClick={() => changeItems(moveTeachingItem(items, index, 1))}><ArrowDown /></button><button className="tm-icon-button tm-remove" aria-label={`移除${byId.get(item.topicId)?.title}`} disabled={saving} onClick={() => changeItems(items.filter((_, position) => position !== index))}><Trash2 /></button></div></div><div className="tm-row-fields"><label>{byId.get(item.topicId)?.title} · 日期<input type="date" value={item.date} disabled={saving} onChange={(event) => changeItems(items.map((row, position) => position === index ? { ...row, date: event.target.value } : row))} /></label><label>题量<input type="number" value={item.questionCount} min={1} max={8} step={1} disabled={saving} aria-label={`${byId.get(item.topicId)?.title}题量`} onChange={(event) => changeItems(items.map((row, position) => position === index ? { ...row, questionCount: Number(event.target.value) } : row))} /></label></div></li>)}</ol>}<div className="tm-selected-summary"><p>{items.length} 项内容 · 共 {items.reduce((sum, item) => sum + item.questionCount, 0)} 题</p><button className="primary-button" disabled={previewing || saving || loading || !targetId} onClick={() => void generatePreview()}>{previewing ? <RefreshCw size={17} className="spin" /> : <Eye size={17} />}{previewing ? '正在核对计划…' : '预览具体计划'}</button></div></section></div>
    {validation.length > 0 && <div className="tm-errors" role="alert"><ul>{validation.map((problem) => <li key={problem}>{problem}</li>)}</ul></div>}{error && <div className="inline-alert" role="alert">{error}</div>}
    <details className="tm-materials" open={materialsOpen} onToggle={(event) => setMaterialsOpen(event.currentTarget.open)}><summary>浏览已收录资源目录</summary>{materialsOpen && <TeachingMaterials topics={topics} />}</details>
    {preview && <section className="teacher-panel tm-preview" aria-label="具体计划预览"><div className="panel-head"><h2>计划预览</h2><span>核对后直接保存</span></div><div className="tm-preview-summary"><span><b>{preview.summary.studentCount}</b>名学生</span><span><b>{preview.summary.planCount}</b>个新增日计划</span><span><b>{preview.summary.questionCount}</b>道新增基础题</span></div><p className="tm-help">保留 {preview.preservedPlanCount ?? retainedIds.length} 个已有安排 · 移除 {existingPlans.filter((plan) => !plan.started && !retainedIds.includes(plan.id)).length} 个未开始安排。保留的原题、顺序和个人进度不变。</p>{preview.warnings.length > 0 && <div className="tm-errors"><ul>{preview.warnings.map((warning, index) => <li key={index}><ChemText>{warning}</ChemText></li>)}</ul></div>}{preview.rows.map((row, index) => <article className={`tm-preview-row ${row.status}`} key={`${row.studentId}-${row.date}-${index}`}><time>{row.date}</time><div><h3>{row.studentName} · <ChemText>{row.title}</ChemText></h3><p>{row.questionCount}道题</p>{row.reason && <p><ChemText>{row.reason}</ChemText></p>}{row.questionIds.length > 0 && <details><summary>查看具体题目编号（{row.questionIds.length}题）</summary><ol>{row.questionIds.map((id, position) => <li key={`${id}-${position}`}>{id}</li>)}</ol></details>}</div><b className={row.status === 'ready' ? 'tm-preview-ready' : 'tm-preview-blocked'}>{row.status === 'ready' ? '可以安排' : '待处理'}</b></article>)}<div className="tm-preview-save"><p>{canSaveTeachingPreview(preview) ? (!isEmptyPlan ? '核对保留、移除和新增的安排后保存；保留的旧题不会重新抽取。' : '这是空计划：保存后清空所选对象今天起尚未开始的复习安排，已开始任务和历史保留。') : '本次计划还有待处理项，原安排保持不变。请调整内容或题量后重新预览。'}</p><button className="primary-button" disabled={saving || !canSaveTeachingPreview(preview)} onClick={() => void apply()}><Save size={17} />{saving ? '正在保存安排…' : !isEmptyPlan ? '保存这份计划' : '清空未开始的安排'}</button></div></section>}
  </>
}
