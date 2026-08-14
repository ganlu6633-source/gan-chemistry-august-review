import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react'
import { Navigate } from 'react-router-dom'
import { AlertCircle, BookOpen, CheckCircle2, ClipboardPen, Eye, Film, GraduationCap, KeyRound, LayoutDashboard, LogIn, MessageSquareText, MonitorPlay, RefreshCw, Save, Settings2, Shield, Users } from 'lucide-react'
import type { GradeBand, StudentDashboardData, TeacherDashboardData, TeacherObservation } from '../domain/types'
import { loadTeacherDashboard, saveTeacherObservation, teacherApi } from '../lib/api'
import { clearAccessSession, readAccessSession } from '../lib/session'
import { TeacherVideoManager } from './VideoLearning'

type TeacherView = 'overview' | 'observation' | 'students' | 'preview' | 'videos' | 'plans' | 'questions' | 'settings'

export function TeacherGate({ onPreviewStudent }: { onPreviewStudent?: (studentId: string) => void }) {
  const session = readAccessSession()
  if (session?.role !== 'teacher') return <Navigate to="/" replace />
  return <TeacherWorkspace onPreviewStudent={onPreviewStudent} />
}

function TeacherWorkspace({ onPreviewStudent }: { onPreviewStudent?: (studentId: string) => void }) {
  const [view, setView] = useState<TeacherView>('overview')
  const [previewStudentId, setPreviewStudentId] = useState('')
  const [dashboard, setDashboard] = useState<TeacherDashboardData | null>(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)

  const refresh = useCallback(async (silent = false) => {
    if (!silent) setLoading(true)
    setError('')
    try { const result = await loadTeacherDashboard(); setDashboard(result.dashboard) } catch (reason) { setError(reason instanceof Error ? reason.message : '教师数据读取失败。') } finally { if (!silent) setLoading(false) }
  }, [])
  useEffect(() => {
    void refresh()
    const silentRefresh = () => { void refresh(true) }
    const onVisibility = () => { if (document.visibilityState === 'visible') silentRefresh() }
    const timer = window.setInterval(silentRefresh, 10000)
    window.addEventListener('focus', silentRefresh)
    document.addEventListener('visibilitychange', onVisibility)
    return () => {
      window.clearInterval(timer)
      window.removeEventListener('focus', silentRefresh)
      document.removeEventListener('visibilitychange', onVisibility)
    }
  }, [refresh])

  return <div className="teacher-workspace"><aside className="teacher-sidebar"><div className="teacher-brand"><Shield /><div><b>甘老师工作台</b><span>证据驱动教学</span></div></div><nav>
    <button className={view === 'overview' ? 'active' : ''} onClick={() => setView('overview')}><LayoutDashboard />今日总览</button>
    <button className={view === 'observation' ? 'active' : ''} onClick={() => setView('observation')}><ClipboardPen />课堂记录</button>
    <button className={view === 'students' ? 'active' : ''} onClick={() => setView('students')}><Users />学生档案</button>
    <button className={view === 'preview' ? 'active' : ''} onClick={() => setView('preview')}><MonitorPlay />模拟学生端</button>
    <button className={view === 'videos' ? 'active' : ''} onClick={() => setView('videos')}><Film />视频讲解</button>
    <button className={view === 'plans' ? 'active' : ''} onClick={() => setView('plans')}><BookOpen />计划编辑器</button>
    <button className={view === 'questions' ? 'active' : ''} onClick={() => setView('questions')}><MessageSquareText />题库审核</button>
    <button className={view === 'settings' ? 'active' : ''} onClick={() => setView('settings')}><Settings2 />权限与访问码</button>
  </nav><button className="logout-button" onClick={() => { clearAccessSession(); window.location.assign(`${window.location.origin}${import.meta.env.BASE_URL}`) }}><LogIn />退出登录</button></aside>
  <main className="teacher-main">{error && <div className="inline-alert">{error}</div>}{loading || !dashboard ? <div className="center-loading"><RefreshCw className="spin" />读取统一数据层…</div> : <>
    {view === 'overview' && <TeacherOverview dashboard={dashboard} onRefresh={() => { void refresh() }} />}
    {view === 'observation' && <ObservationForm dashboard={dashboard} />}
    {view === 'students' && <StudentTable dashboard={dashboard} onPreview={(studentId) => { setPreviewStudentId(studentId); setView('preview') }} />}
    {view === 'preview' && <StudentPreview dashboard={dashboard} initialStudentId={previewStudentId} onOpenFull={onPreviewStudent} />}
    {view === 'videos' && <TeacherVideoManager dashboard={dashboard} />}
    {view === 'plans' && <PlanEditor dashboard={dashboard} />}
    {view === 'questions' && <QuestionAudit dashboard={dashboard} />}
    {view === 'settings' && <AccessSettings dashboard={dashboard} />}
  </>}</main></div>
}

function TeacherOverview({ dashboard, onRefresh }: { dashboard: TeacherDashboardData; onRefresh: () => void }) {
  return <><div className="teacher-page-head"><div><span className="eyebrow">小测完成后自动更新（约10秒）</span><h1>今天最值得看的事</h1></div><button className="secondary-button" onClick={onRefresh}><RefreshCw size={17} />刷新证据</button></div>
    <div className="teacher-metrics"><article><Users /><b>{dashboard.students.length}</b><span>统一学生档案</span></article><article><CheckCircle2 /><b>{dashboard.dailySummary.classQuizCount}</b><span>即时小测轮次</span></article><article><RefreshCw /><b>{dashboard.dailySummary.reviewCount}</b><span>长期复习完成</span></article><article><AlertCircle /><b>{dashboard.dailySummary.interventionCount}</b><span>建议教师介入</span></article></div>
    <section className="teacher-panel"><div className="panel-head"><h2>今日即时小测</h2><span>{dashboard.dailySummary.quizCompletedStudentCount}/{dashboard.dailySummary.quizRosterCount} 名学生已完成 · 共 {dashboard.dailySummary.classQuizCount} 轮</span></div><div className="audit-list">{dashboard.recentQuizSessions.map((session) => <article key={session.id}><div><b>{session.studentName} · 第{session.round}轮</b><p>{session.trainingTheme} · {new Date(session.completedAt).toLocaleTimeString('zh-CN', { timeZone: 'Asia/Shanghai', hour: '2-digit', minute: '2-digit' })}{session.wrongTags.length ? ` · 需巩固：${session.wrongTags.join('、')}` : ' · 本轮无错题'}{session.slowTags.length ? ` · 偏慢：${session.slowTags.join('、')}` : ''}</p></div><div className="quiz-session-score"><b>{session.correctCount}/{session.totalCount}</b><span>{formatDuration(session.totalSec)}</span></div></article>)}{!dashboard.recentQuizSessions.length && <div className="empty-state"><RefreshCw /><p>今天还没有学生完成即时小测。</p></div>}</div></section>
    <section className="teacher-panel"><div className="panel-head"><h2>优先提醒</h2><span>只显示3—5件最值得看的事</span></div><div className="alert-list">{dashboard.alerts.slice(0,5).map((alert) => { const student = dashboard.students.find((item) => item.id === alert.studentId); return <article key={alert.id} className={alert.severity}><AlertCircle /><div><b>{student?.displayName ?? '学生'} · {alert.title}</b><p>{alert.reason}</p></div></article> })}{!dashboard.alerts.length && <div className="empty-state"><CheckCircle2 /><p>当前没有需要立即处理的提醒。</p></div>}</div></section>
  </>
}

function formatDuration(totalSec: number) {
  const minutes = Math.floor(totalSec / 60)
  const seconds = Math.round(totalSec % 60)
  return minutes ? `${minutes}分${seconds}秒` : `${seconds}秒`
}

function ObservationForm({ dashboard }: { dashboard: TeacherDashboardData }) {
  const [studentId, setStudentId] = useState(dashboard.students[0]?.id ?? '')
  const [taught, setTaught] = useState('')
  const [evidence, setEvidence] = useState('')
  const [internal, setInternal] = useState('')
  const [studentMessage, setStudentMessage] = useState('')
  const [guardianMessage, setGuardianMessage] = useState('')
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  async function submit(event: FormEvent) {
    event.preventDefault(); setSaving(true); setSaved(false)
    const observation: Omit<TeacherObservation, 'id'> = { studentId, courseDate: new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' }), taughtContent: taught, observedEvidence: evidence, internalNote: internal, studentMessage, guardianMessage, visibility: 'internal' }
    try { await saveTeacherObservation(observation); setSaved(true); setTaught(''); setEvidence(''); setInternal(''); setStudentMessage(''); setGuardianMessage('') } finally { setSaving(false) }
  }
  return <><div className="teacher-page-head"><div><span className="eyebrow">只输入一次，系统自动分发</span><h1>快速课堂记录</h1></div></div><form className="observation-form" onSubmit={submit}><label>学生<select value={studentId} onChange={(event) => setStudentId(event.target.value)}>{dashboard.students.map((student) => <option key={student.id} value={student.id}>{student.displayName} · {student.gradeBand}</option>)}</select></label><label>今天讲了什么<textarea value={taught} onChange={(event) => setTaught(event.target.value)} required placeholder="知识点、题型、课堂进度" /></label><label>我观察到了什么<textarea value={evidence} onChange={(event) => setEvidence(event.target.value)} required placeholder="只记录可观察事实，如：两次把比较对象看反" /></label><label className="internal-field">教师内部备注（永不直接展示给家长）<textarea value={internal} onChange={(event) => setInternal(event.target.value)} placeholder="教学策略、需要后续核验的判断" /></label><div className="two-fields"><label>给学生的话<textarea value={studentMessage} onChange={(event) => setStudentMessage(event.target.value)} placeholder="强调已经获得的能力" /></label><label>给家长的话<textarea value={guardianMessage} onChange={(event) => setGuardianMessage(event.target.value)} placeholder="简短、事实化、喜忧都报" /></label></div>{saved && <div className="success-message"><CheckCircle2 />已写入学生档案，并按可见性分发。</div>}<button className="primary-button" disabled={saving}><Save size={18} />{saving ? '正在保存…' : '保存并自动分发'}</button></form></>
}

type StudentDirectoryGrade = '全部' | GradeBand

const teacherGradeOrder: StudentDirectoryGrade[] = ['全部', '高一', '高二', '高三', '初三']

export function StudentTable({ dashboard, onPreview }: { dashboard: TeacherDashboardData; onPreview: (studentId: string) => void }) {
  const [grade, setGrade] = useState<StudentDirectoryGrade>('全部')
  const grades = teacherGradeOrder.filter((item) => item === '全部' || dashboard.students.some((student) => student.gradeBand === item))
  const students = useMemo(() => dashboard.students.filter((student) => grade === '全部' || student.gradeBand === grade), [dashboard.students, grade])

  return <>
    <div className="teacher-page-head"><div><span className="eyebrow">按年级查看完整档案与家庭联系信息</span><h1>学生与家长档案</h1></div><span className="directory-total">共 {dashboard.students.length} 名学生</span></div>
    <div className="grade-filter" role="group" aria-label="按年级筛选学生">
      {grades.map((item) => {
        const count = item === '全部' ? dashboard.students.length : dashboard.students.filter((student) => student.gradeBand === item).length
        return <button key={item} className={grade === item ? 'active' : ''} aria-pressed={grade === item} onClick={() => setGrade(item)}>{item}<span>{count}</span></button>
      })}
    </div>
    <div className="data-table student-directory"><div className="data-row head"><span>学生</span><span>年级</span><span>复习计划</span><span>家长信息</span><span>学习档案</span><span>操作</span></div>{students.map((student) => <div className="data-row" key={student.id}>
      <span><b>{student.displayName}</b><small>档案号 {student.id.slice(0, 8)}</small></span>
      <span><b className="grade-badge">{student.gradeBand}</b></span>
      <span className={student.planDays >= 28 ? 'status active' : 'status pending'}>{student.planDays}天</span>
      <span className="guardian-cell">{student.guardianNames.length ? <><small>已登记 {student.guardianNames.length} 位</small><b>{student.guardianNames.join('、')}</b></> : <em className="pending-name">待登记家长姓名</em>}</span>
      <span>{student.needsInitialDiagnostic ? '需要初始诊断' : '已有学习证据'}</span>
      <span><button className="table-action" onClick={() => onPreview(student.id)} aria-label={`模拟查看${student.displayName}的学生端`}><Eye size={16} />模拟查看</button></span>
    </div>)}{!students.length && <div className="directory-empty">这个年级暂时没有学生档案。</div>}</div>
  </>
}

function StudentPreview({ dashboard, initialStudentId, onOpenFull }: { dashboard: TeacherDashboardData; initialStudentId: string; onOpenFull?: (studentId: string) => void }) {
  const fallbackId = dashboard.students[0]?.id ?? ''
  const availableStudentIds = useMemo(() => dashboard.students.map((student) => student.id).join('|'), [dashboard.students])
  const [studentId, setStudentId] = useState(initialStudentId || fallbackId)
  const [preview, setPreview] = useState<StudentDashboardData | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const selected = dashboard.students.find((student) => student.id === studentId)

  useEffect(() => {
    if (!studentId || !availableStudentIds.split('|').includes(studentId)) {
      if (fallbackId) setStudentId(fallbackId)
      return
    }
    let active = true
    setLoading(true)
    setError('')
    setPreview((current) => current?.profile.id === studentId ? current : null)
    void teacherApi<{ dashboard: StudentDashboardData }>('student_preview_dashboard', { studentId })
      .then((result) => { if (active) setPreview(result.dashboard) })
      .catch((reason) => { if (active) setError(reason instanceof Error ? reason.message : '学生端预览暂时无法打开。') })
      .finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [availableStudentIds, fallbackId, studentId])

  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
  const todayPlan = preview?.plans.find((plan) => plan.date === today) ?? preview?.plans.find((plan) => plan.date >= today) ?? preview?.plans[0]
  const litSkills = preview?.skillStates.filter((state) => state.verifiedLevel > 0).length ?? 0
  const upcoming = preview ? [...preview.plans].sort((a, b) => a.date.localeCompare(b.date)).slice(0, 7) : []

  return <>
    <div className="teacher-page-head"><div><span className="eyebrow">按真人计划检查页面，预览过程完全只读</span><h1>模拟学生端</h1></div></div>
    <section className="preview-safety"><Shield /><div><b>安全预览，不写入真人记录</b><p>这里不会提交答案、改变能力等级或增加完成次数；进入完整界面后也保持只读。</p></div></section>
    <section className="teacher-panel preview-picker">
      <label>选择年级与学生<select value={studentId} onChange={(event) => setStudentId(event.target.value)}>{(['高一', '高二', '高三', '初三'] as GradeBand[]).map((grade) => {
        const group = dashboard.students.filter((student) => student.gradeBand === grade)
        return group.length ? <optgroup key={grade} label={grade}>{group.map((student) => <option value={student.id} key={student.id}>{student.displayName}{student.guardianNames.length ? ` · 家长：${student.guardianNames.join('、')}` : ''}</option>)}</optgroup> : null
      })}</select></label>
      <button className="primary-button" disabled={!studentId || loading || !onOpenFull} onClick={() => studentId && onOpenFull?.(studentId)}><MonitorPlay size={18} />打开完整模拟学生界面</button>
    </section>
    {error && <div className="inline-alert" role="alert">{error}</div>}
    {loading && <div className="center-loading"><RefreshCw className="spin" />正在准备{selected?.displayName ?? '学生'}的只读视图…</div>}
    {!loading && preview && <div className="student-preview-frame">
      <div className="preview-identity"><div><span className="eyebrow">学生看到的首页概览</span><h2>{preview.profile.displayName} · {preview.profile.gradeBand}</h2><p>家长：{selected?.guardianNames.length ? selected.guardianNames.join('、') : '暂未登记'}</p></div><GraduationCap /></div>
      <div className="preview-metrics"><article><b>{preview.plans.length}</b><span>计划天数</span></article><article><b>{preview.todayQuestionCount}</b><span>本轮题目</span></article><article><b>{litSkills}</b><span>已点亮能力</span></article><article><b>{preview.achievements.length}</b><span>成长记录</span></article></div>
      {todayPlan ? <section className="preview-today"><BookOpen /><div><span>{todayPlan.date === today ? '今天已点亮' : '当前安排'}</span><h3>{todayPlan.title}</h3><p>{todayPlan.knowledgeSummaries.join(' · ')}</p></div><b>约{todayPlan.estimatedMinutes}分钟</b></section> : <div className="directory-empty">这个学生还没有复习计划。</div>}
      <section className="preview-week"><div className="panel-head"><h3>学习计划前7天</h3><span>用于核对标题、知识点与节奏</span></div><div>{upcoming.map((plan) => <article key={plan.id}><time>{plan.date.slice(5)}</time><div><b>{plan.title}</b><p>{plan.knowledgeSummaries.join('、')}</p></div></article>)}</div></section>
    </div>}
  </>
}

type CourseNodeRow = { id: string; grade_band: string; textbook_version: string; chapter: string; title: string; teacher_approved: boolean }
function PlanEditor({ dashboard }: { dashboard: TeacherDashboardData }) {
  const [nodes, setNodes] = useState<CourseNodeRow[]>([])
  const [busy, setBusy] = useState('')
  useEffect(() => { void teacherApi<{ nodes: CourseNodeRow[] }>('list_course_nodes').then((r) => setNodes(r.nodes)) }, [])
  async function toggle(node: CourseNodeRow) { setBusy(node.id); await teacherApi('approve_course_node', { id: node.id, approved: !node.teacher_approved }); setNodes((all) => all.map((item) => item.id === node.id ? { ...item, teacher_approved: !item.teacher_approved } : item)); setBusy('') }
  return <><div className="teacher-page-head"><div><span className="eyebrow">课程脑与考试脑的正式输入</span><h1>学习计划编辑器</h1></div></div><section className="teacher-panel"><p>课程节点只有经教师确认后才会参与选题。</p><div className="editor-summary"><div><b>{dashboard.pendingCourseNodes}</b><span>课程节点待审核</span></div><div><b>3</b><span>调度模式</span></div><div><b>8 / 10</b><span>默认 / 硬上限</span></div></div><div className="audit-list">{nodes.map((node) => <article key={node.id}><div><b>{node.title}</b><p>{node.grade_band} · {node.textbook_version} · {node.chapter}</p></div><button className="secondary-button" disabled={busy === node.id} onClick={() => void toggle(node)}>{node.teacher_approved ? '撤回批准' : '批准使用'}</button></article>)}</div></section></>
}

type QuestionAuditRow = { id: string; mother_id: string; skill_id: string; level: number; stem: string; review_status: string; scope_status: string }
function QuestionAudit({ dashboard }: { dashboard: TeacherDashboardData }) {
  const [questions, setQuestions] = useState<QuestionAuditRow[]>([])
  const [busy, setBusy] = useState('')
  useEffect(() => { void teacherApi<{ questions: QuestionAuditRow[] }>('list_questions').then((r) => setQuestions(r.questions)) }, [])
  async function review(id: string, reviewStatus: string) { setBusy(id); await teacherApi('review_question', { id, reviewStatus }); setQuestions((all) => all.map((q) => q.id === id ? { ...q, review_status: reviewStatus } : q)); setBusy('') }
  return <><div className="teacher-page-head"><div><span className="eyebrow">draft绝不进入学生端</span><h1>题库审核</h1></div></div><section className="teacher-panel"><div className="audit-hero"><MessageSquareText /><div><b>{dashboard.pendingQuestions} 道题等待人工复核</b><p>检查化学正确性、唯一答案、题面完整、福建范围、图片与公式后才能批准。</p></div></div><div className="audit-list">{questions.map((q) => <article key={q.id}><div><b>{q.stem}</b><p>{q.skill_id} · L{q.level} · {q.scope_status} · {q.review_status}</p></div><div className="audit-actions"><button disabled={busy === q.id} onClick={() => void review(q.id, 'approved')}>批准</button><button disabled={busy === q.id} onClick={() => void review(q.id, 'needs_review')}>待复核</button><button disabled={busy === q.id} onClick={() => void review(q.id, 'retired')}>停用</button></div></article>)}</div></section></>
}

function AccessSettings({ dashboard }: { dashboard: TeacherDashboardData }) {
  const [generated, setGenerated] = useState<{ studentCode: string; guardianCode: string } | null>(null)
  const [studentId, setStudentId] = useState(dashboard.students[0]?.id ?? '')
  async function generate() { const result = await teacherApi<{ studentCode: string; guardianCode: string }>('reset_access_codes', { studentId }); setGenerated(result) }
  return <><div className="teacher-page-head"><div><span className="eyebrow">学生码与家长码完全分开</span><h1>权限与访问码</h1></div></div><section className="teacher-panel"><label>学生<select value={studentId} onChange={(event) => { setStudentId(event.target.value); setGenerated(null) }}>{dashboard.students.map((student) => <option value={student.id} key={student.id}>{student.displayName}</option>)}</select></label><div className="security-rules"><p><KeyRound />重置时生成8位初始码；学生登录后可自行改成6—12位数字。</p><p><Shield />重置后旧码立即失效；明文只在本次页面显示一次。</p></div><button className="primary-button" onClick={generate}>生成或重置两种访问码</button>{generated && <div className="one-time-secret"><b>请立即安全交给对应用户，关闭后无法再次查看</b><div><span>学生码</span><code>{generated.studentCode}</code></div><div><span>家长码</span><code>{generated.guardianCode}</code></div></div>}</section></>
}
