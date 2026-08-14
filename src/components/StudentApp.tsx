import { Fragment, useEffect, useMemo, useRef, useState } from 'react'
import { BookOpen, Check, ChevronRight, CircleHelp, Clock3, KeyRound, Map as MapIcon, RotateCcw, Settings, ShieldCheck, Sparkles, Trophy } from 'lucide-react'
import type { KnowledgeCard, KnowledgeTreeNode, KnowledgeVisualSummary, KnowledgeVisualTreeNode, LearningAttempt, LearningPlanDay, LearningRecordData, Question, SessionIdentity, StudentDashboardData, StructuredKnowledgeContent } from '../domain/types'
import { SKILLS } from '../data/catalog'
import { accessApi, loadLearningRecord, submitAttempt, teacherApi } from '../lib/api'
import { AbilityMap } from './AbilityMap'
import { ChemText } from './ChemText'
import { LearningRecordPanel } from './LearningRecordPanel'
import { SourceInformedChemVisual } from './SourceInformedChemVisuals'
import { supportsSourceInformedChemVisual } from './sourceInformedChemVisualSupport'
import { StudentVideoSection } from './VideoLearning'

type StudentView = 'today' | 'map' | 'growth' | 'settings'
export type PlanPayload = {
  plan: LearningPlanDay
  cards: KnowledgeCard[]
  questions: Question[]
  attemptSequence: number
  roundNumber: number
  roundLimit: number
  questionCount: number
  isResolved: boolean
  isComplete: boolean
  roundsRemaining: number
}

const nextRoundLabel = (plan: LearningPlanDay) => {
  if (plan.isResolved) return '今日问题已接稳'
  if (plan.isComplete || plan.attemptCount >= plan.roundLimit) return `今日 ${plan.roundLimit} 轮已完成`
  return plan.attemptCount === 0 ? '开始第一轮' : `继续第 ${plan.attemptCount + 1} 轮`
}

const statusLabel = (plan: LearningPlanDay, enrollment: string) => {
  if (plan.date < enrollment) return '加入前｜可补学'
  if (plan.attemptCount > 0) {
    if (plan.isResolved) return `第 ${plan.attemptCount} 轮已接稳`
    if (plan.isComplete || plan.attemptCount >= plan.roundLimit) return `今日 ${plan.roundLimit} 轮已完成`
    if (plan.latestCompletedAt && plan.date > plan.latestCompletedAt.slice(0, 10)) return '已提前完成'
    if (plan.firstScore !== null && plan.latestScore !== null && plan.latestScore > plan.firstScore) return `复习后提升 ${plan.firstScore}→${plan.latestScore}`
    return `已完成 ${plan.attemptCount}/${plan.roundLimit} 轮`
  }
  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
  if (plan.date < today) return '可再次复习'
  if (plan.date > today) return '可提前复习'
  return '今天'
}

export function StudentApp({ session, initialDashboard, onDashboard, previewMode = false, onExitPreview }: { session: SessionIdentity; initialDashboard: StudentDashboardData; onDashboard: (data: StudentDashboardData) => void; previewMode?: boolean; onExitPreview?: () => void }) {
  const [view, setView] = useState<StudentView>('today')
  const [dashboard, setDashboard] = useState(initialDashboard)
  const [activePlan, setActivePlan] = useState<PlanPayload | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
  const todayPlan = dashboard.plans.find((plan) => plan.date === today) ?? dashboard.plans.find((plan) => plan.date >= today) ?? dashboard.plans[0]
  const visiblePlans = useMemo(() => [...dashboard.plans].sort((a, b) => a.date.localeCompare(b.date)), [dashboard.plans])

  async function openPlan(plan: LearningPlanDay, previewRound?: number) {
    setBusy(true)
    setError('')
    try {
      const result = previewMode
        ? await teacherApi<{ payload: PlanPayload }>('preview_start_plan', { studentId: dashboard.profile.id, planId: plan.id, ...(previewRound ? { previewRound } : {}) })
        : await accessApi<{ payload: PlanPayload }>(session, 'start_plan', { planId: plan.id, ...(dashboard.profile.isDemo ? { studentId: dashboard.profile.id, ...(previewRound ? { previewRound } : {}) } : {}) })
      setActivePlan(result.payload)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '学习内容暂时无法打开。')
    } finally {
      setBusy(false)
    }
  }

  async function continuePlan(nextDashboard: StudentDashboardData, planId: string, nextRound: number) {
    setDashboard(nextDashboard)
    onDashboard(nextDashboard)
    setActivePlan(null)
    const nextPlan = nextDashboard.plans.find((plan) => plan.id === planId)
    if (nextPlan) await openPlan(nextPlan, previewMode || nextDashboard.profile.isDemo ? nextRound : undefined)
  }

  async function switchDemoGrade(gradeBand: string) {
    if (gradeBand === dashboard.profile.gradeBand || busy) return
    setBusy(true)
    setError('')
    try {
      const result = await accessApi<{ dashboard: StudentDashboardData }>(session, 'demo_dashboard', { gradeBand })
      setDashboard(result.dashboard)
      onDashboard(result.dashboard)
      setView('today')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '演示年级暂时无法切换。')
    } finally {
      setBusy(false)
    }
  }

  if (activePlan) {
    return <LearningRound session={session} payload={activePlan} practiceMode={previewMode || Boolean(dashboard.profile.isDemo)} practiceDashboard={dashboard} onExit={() => setActivePlan(null)} onContinue={(next, planId, nextRound) => continuePlan(next, planId, nextRound)} onComplete={(next) => { setDashboard(next); onDashboard(next); setActivePlan(null); setView(previewMode || dashboard.profile.isDemo ? 'today' : 'growth') }} />
  }

  return (
    <>{previewMode && <section className="teacher-preview-strip" role="status"><ShieldCheck /><div><b>甘老师只读模拟 · {dashboard.profile.displayName} · {dashboard.profile.gradeBand}</b><span>可以查看知识点、题目和解析；所有作答都不会写入这名学生的档案。</span></div><button className="secondary-button" onClick={onExitPreview}>返回教师后台</button></section>}<div className="role-layout student-theme">
      <aside className={`side-nav ${previewMode || dashboard.profile.isDemo ? 'three-items' : ''}`} aria-label="学生导航">
        <button className={view === 'today' ? 'active' : ''} onClick={() => setView('today')}><Sparkles />今天</button>
        <button className={view === 'map' ? 'active' : ''} onClick={() => setView('map')}><MapIcon />能力地图</button>
        <button className={view === 'growth' ? 'active' : ''} onClick={() => setView('growth')}><Trophy />我的战绩</button>
        {!previewMode && !dashboard.profile.isDemo && <button className={view === 'settings' ? 'active' : ''} onClick={() => setView('settings')}><Settings />账户设置</button>}
      </aside>
      <div className="role-content">
        {error && <div className="inline-alert" role="alert">{error}</div>}
        {view === 'today' && <>
          <section className="welcome-banner">
            <div><span className="eyebrow">今天也只走一小步</span><h1>{dashboard.profile.displayName}，今天先把最值得的几件事稳住。</h1><p>{dashboard.profile.needsInitialDiagnostic ? '我们会先做一组轻量诊断，不会根据缺失数据猜你的水平。' : '系统已经结合课堂进度、记忆节点和最近表现排好了第一轮。'}</p></div>
            <div className="daily-orb"><b>{dashboard.todayQuestionCount || todayPlan?.questionCount || 5}</b><span>每轮题目</span></div>
          </section>
          {dashboard.profile.isDemo && <section className="demo-grade-switch" aria-label="切换演示年级"><div><span className="eyebrow">演示查看</span><h2>切换年级，检查不同学习路线</h2><p>演示练习不会写入任何真实学生档案。</p></div><div>{(dashboard.profile.availableDemoGrades ?? ['高一', '高二', '高三']).map((grade) => <button key={grade} className={dashboard.profile.gradeBand === grade ? 'active' : ''} onClick={() => void switchDemoGrade(grade)} disabled={busy}>{grade}</button>)}</div></section>}
          {todayPlan ? <section className="focus-card">
            <div className="focus-icon"><BookOpen /></div>
            <div><span className="mode-pill">{todayPlan.mode === 'EXAM_SPRINT' ? '考前拿分' : '长期复习'}</span><h2>{todayPlan.title}</h2><div className="focus-topics">{todayPlan.knowledgeSummaries.map((topic) => <span key={topic}>{topic}</span>)}</div><div className="meta-row"><span><Clock3 size={15} />约{todayPlan.estimatedMinutes}分钟</span><span>每轮 {todayPlan.questionCount} 题 · 共 {todayPlan.roundLimit} 轮 · 当天把问题接稳</span></div></div>
            <button className="primary-button compact" onClick={() => todayPlan.isComplete ? setView('growth') : openPlan(todayPlan)} disabled={busy}>{busy ? '正在准备…' : todayPlan.isComplete ? '查看今日成果' : nextRoundLabel(todayPlan)}<ChevronRight size={18} /></button>
          </section> : <EmptyState text="甘老师还没有为今天安排正式任务。" />}
          <StudentVideoSection session={session} videos={dashboard.videoRecommendations ?? []} readOnly={previewMode || Boolean(dashboard.profile.isDemo)} />
          <PlanCalendar plans={visiblePlans} enrollment={dashboard.profile.enrollmentStartDate} onOpen={(plan) => plan.isComplete && !previewMode && !dashboard.profile.isDemo ? setView('growth') : openPlan(plan)} busy={busy} embedded />
          <section className="section-block"><div className="section-head"><div><span className="eyebrow">最近获得</span><h2>已经亮起来的部分</h2></div><button className="text-button" onClick={() => setView('growth')}>查看全部</button></div>
            <div className="achievement-grid">{dashboard.achievements.slice(0, 3).map((item) => <article className="achievement-card" key={item.id}><div className="achievement-icon"><Trophy /></div><div><b>{item.title}</b><p>{item.description}</p></div></article>)}</div>
          </section>
        </>}
        {view === 'map' && <AbilityMap dashboard={dashboard} onOpenPlan={openPlan} busy={busy} />}
        {view === 'growth' && <GrowthPage dashboard={dashboard} session={session} previewMode={previewMode} />}
        {view === 'settings' && <AccountSettings session={session} />}
      </div>
    </div></>
  )
}

function AccountSettings({ session }: { session: SessionIdentity }) {
  const [currentCode, setCurrentCode] = useState('')
  const [newCode, setNewCode] = useState('')
  const [confirmCode, setConfirmCode] = useState('')
  const [recoveryCurrentCode, setRecoveryCurrentCode] = useState('')
  const [recoverySecret, setRecoverySecret] = useState('')
  const [confirmSecret, setConfirmSecret] = useState('')
  const [busy, setBusy] = useState<'code' | 'recovery' | ''>('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  async function changeCode(event: React.FormEvent) {
    event.preventDefault()
    setError(''); setMessage('')
    if (!/^\d{6,12}$/.test(currentCode) || !/^\d{6,12}$/.test(newCode)) return setError('当前登录码和新登录码都应为6—12位数字。')
    if (newCode !== confirmCode) return setError('两次输入的新登录码不一致。')
    if (newCode === currentCode) return setError('新登录码需要与当前登录码不同。')
    setBusy('code')
    try {
      const result = await accessApi<{ message?: string }>(session, 'change_own_code', { currentCode, newCode })
      setMessage(result.message || '登录码已修改。下次请使用新登录码进入。')
      setCurrentCode(''); setNewCode(''); setConfirmCode('')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '登录码修改失败。')
    } finally { setBusy('') }
  }

  async function saveRecoverySecret(event: React.FormEvent) {
    event.preventDefault()
    setError(''); setMessage('')
    const cleanSecret = recoverySecret.trim()
    if (!/^\d{6,12}$/.test(recoveryCurrentCode)) return setError('请输入当前6—12位数字登录码。')
    if (cleanSecret.length < 6 || cleanSecret.length > 40) return setError('私密找回短语需为6—40个字符。')
    if (/^\d+$/.test(cleanSecret)) return setError('私密找回短语请至少包含一个汉字或字母，不能只用数字。')
    if (cleanSecret !== confirmSecret.trim()) return setError('两次输入的私密找回短语不一致。')
    if (cleanSecret === recoveryCurrentCode) return setError('私密找回短语不能与登录码相同。')
    setBusy('recovery')
    try {
      const result = await accessApi<{ message?: string }>(session, 'set_recovery_secret', { currentCode: recoveryCurrentCode, recoverySecret: cleanSecret })
      setMessage(result.message || '私密找回短语已安全保存。')
      setRecoveryCurrentCode(''); setRecoverySecret(''); setConfirmSecret('')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '私密找回短语保存失败。')
    } finally { setBusy('') }
  }

  return <section className="account-settings"><div className="page-title"><span className="eyebrow">只有你自己知道</span><h1>账户与找回</h1><p>你可以把初始登录码改成更好记的6—12位数字，也可以设置一个私密找回短语。</p></div>{error && <div className="inline-alert" role="alert">{error}</div>}{message && <div className="success-message" role="status">{message}</div>}<div className="account-settings-grid"><form className="account-card" onSubmit={changeCode}><div className="account-card-title"><KeyRound /><div><h2>修改登录码</h2><p>修改后，旧登录码立即失效。</p></div></div><label>当前登录码<input type="password" inputMode="numeric" autoComplete="current-password" value={currentCode} onChange={(event) => setCurrentCode(event.target.value.replace(/\D/g, '').slice(0, 12))} placeholder="6—12位数字" /></label><label>新登录码<input type="password" inputMode="numeric" autoComplete="new-password" value={newCode} onChange={(event) => setNewCode(event.target.value.replace(/\D/g, '').slice(0, 12))} placeholder="6—12位数字" /></label><label>再次输入新登录码<input type="password" inputMode="numeric" autoComplete="new-password" value={confirmCode} onChange={(event) => setConfirmCode(event.target.value.replace(/\D/g, '').slice(0, 12))} placeholder="请再次输入" /></label><button className="primary-button" disabled={Boolean(busy)}>{busy === 'code' ? '正在修改…' : '保存新登录码'}</button></form><form className="account-card" onSubmit={saveRecoverySecret}><div className="account-card-title"><ShieldCheck /><div><h2>设置私密找回短语</h2><p>忘记登录码时，用姓名和这句话重新设置。</p></div></div><label>当前登录码<input type="password" inputMode="numeric" autoComplete="current-password" value={recoveryCurrentCode} onChange={(event) => setRecoveryCurrentCode(event.target.value.replace(/\D/g, '').slice(0, 12))} placeholder="用于确认是本人" /></label><label>私密找回短语<input type="password" autoComplete="off" value={recoverySecret} onChange={(event) => setRecoverySecret(event.target.value.slice(0, 40))} placeholder="6—40个字符" /></label><label>再次输入找回短语<input type="password" autoComplete="off" value={confirmSecret} onChange={(event) => setConfirmSecret(event.target.value.slice(0, 40))} placeholder="请再次输入" /></label><div className="privacy-tip"><ShieldCheck />不要使用身份证号、生日、手机号或常用密码。系统只保存加密摘要，无法查看你的原文。</div><button className="primary-button" disabled={Boolean(busy)}>{busy === 'recovery' ? '正在安全保存…' : '保存找回短语'}</button></form></div></section>
}

function splitCalendarWeeks(plans: LearningPlanDay[]) {
  const sorted = [...plans].sort((a, b) => a.date.localeCompare(b.date))
  const weeks: LearningPlanDay[][] = []
  let cursor = 0
  while (cursor < sorted.length) {
    const weekday = new Date(`${sorted[cursor].date}T12:00:00+08:00`).getUTCDay()
    const remainingInWeek = weekday === 0 ? 1 : 8 - weekday
    weeks.push(sorted.slice(cursor, cursor + remainingInWeek))
    cursor += remainingInWeek
  }
  return weeks
}

const weekdayLabel = (date: string) => `周${'日一二三四五六'[new Date(`${date}T12:00:00+08:00`).getUTCDay()]}`

function PlanCalendar({ plans, enrollment, onOpen, busy, embedded = false }: { plans: LearningPlanDay[]; enrollment: string; onOpen: (plan: LearningPlanDay) => void; busy: boolean; embedded?: boolean }) {
  const weeks = splitCalendarWeeks(plans)
  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
  const hasToday = plans.some((plan) => plan.date === today)
  const nextDate = hasToday ? undefined : plans.find((plan) => plan.date > today)?.date
  const focusButton = useRef<HTMLButtonElement | null>(null)
  const first = plans[0]?.date
  const last = plans.at(-1)?.date
  const displayDate = (date?: string) => date ? `${Number(date.slice(5, 7))}月${Number(date.slice(8, 10))}日` : ''
  useEffect(() => {
    const button = focusButton.current
    const grid = button?.parentElement
    if (!button || !grid) return
    const buttonRect = button.getBoundingClientRect()
    const gridRect = grid.getBoundingClientRect()
    grid.scrollLeft += buttonRect.left - gridRect.left - (grid.clientWidth - button.offsetWidth) / 2
  }, [today, first, last])
  return <section className={embedded ? 'home-plan section-block' : undefined} aria-labelledby="learning-plan-title"><div className="page-title"><span className="eyebrow">{displayDate(first)}—{displayDate(last)}</span>{embedded ? <h2 id="learning-plan-title">我的学习计划</h2> : <h1 id="learning-plan-title">我的学习计划</h1>}<p>计划就在首页；今天的任务会自动点亮。{displayDate(first)}是复习第1天，过去可以重做，未来可以提前预习。</p></div>
    <div className="week-stack">{weeks.map((week, index) => { const currentWeek = week.some((plan) => plan.date === today); const nextWeek = week.some((plan) => plan.date === nextDate); return <div className={`week-card ${currentWeek ? 'is-current-week' : nextWeek ? 'is-next-week' : ''}`} key={week[0]?.date ?? index}><div className="week-label">{currentWeek ? '本周 · 今天已点亮' : nextWeek ? '下一次安排' : index === 0 ? '复习起始周' : `复习第 ${index + 1} 周`}</div><div className="week-grid">{week.map((plan) => { const isToday = plan.date === today; const isNext = plan.date === nextDate; return <button key={plan.id} ref={isToday || isNext ? focusButton : undefined} className={`plan-day ${isToday ? 'is-today' : isNext ? 'is-next' : ''}`} aria-current={isToday ? 'date' : undefined} onClick={() => onOpen(plan)} disabled={busy}><span className="plan-date">{plan.date.slice(5)} · {weekdayLabel(plan.date)}</span>{isToday ? <span className="plan-today-badge" aria-hidden="true">今天</span> : isNext ? <span className="plan-next-badge">下一次</span> : null}<b>{plan.title}</b><ul>{plan.knowledgeSummaries.map((topic) => <li key={topic}>{topic}</li>)}</ul><small>每轮{plan.questionCount}题 · {plan.roundLimit}轮 · {plan.estimatedMinutes}分钟</small><em>{statusLabel(plan, enrollment)}</em></button> })}</div></div> })}</div>
  </section>
}

function GrowthPage({ dashboard, session, previewMode }: { dashboard: StudentDashboardData; session: SessionIdentity; previewMode: boolean }) {
  const [record, setRecord] = useState<LearningRecordData | null>(null)
  const [error, setError] = useState('')
  useEffect(() => {
    let active = true
    setRecord(null)
    setError('')
    const request = previewMode
      ? teacherApi<{ record: LearningRecordData }>('student_learning_record', { studentId: dashboard.profile.id })
      : loadLearningRecord(session, dashboard.profile.isDemo ? dashboard.profile.id : undefined)
    void request.then((result) => { if (active) setRecord(result.record) })
      .catch((reason) => { if (active) setError(reason instanceof Error ? reason.message : '学习档案暂时无法打开。') })
    return () => { active = false }
  }, [dashboard.profile.id, dashboard.profile.isDemo, previewMode, session])

  if (error) return <section><div className="page-title"><span className="eyebrow">我的化学档案</span><h1>学习证据正在整理</h1></div><div className="inline-alert" role="alert">{error}</div></section>
  if (!record) return <section><div className="page-title"><span className="eyebrow">我的化学档案</span><h1>正在接起每一步学习证据…</h1></div><div className="record-loading"><span /><span /><span /></div></section>
  return <LearningRecordPanel record={record} gradeBand={dashboard.profile.gradeBand} audience={previewMode ? 'teacher' : 'student'} />
}

export function LearningRound({ session, payload, practiceMode = false, practiceDashboard, onExit, onContinue, onComplete }: { session: SessionIdentity; payload: PlanPayload; practiceMode?: boolean; practiceDashboard?: StudentDashboardData; onExit: () => void; onContinue: (data: StudentDashboardData, planId: string, nextRound: number) => Promise<void>; onComplete: (data: StudentDashboardData) => void }) {
  const roundNumber = payload.roundNumber || payload.attemptSequence + 1
  const roundLimit = payload.roundLimit || payload.plan.roundLimit || 5
  const [phase, setPhase] = useState<'cards' | 'quiz' | 'result'>(roundNumber === 1 ? 'cards' : 'quiz')
  const [cardIndex, setCardIndex] = useState(0)
  const [questionIndex, setQuestionIndex] = useState(0)
  const [selected, setSelected] = useState<number | null>(null)
  const [uncertain, setUncertain] = useState(false)
  const [answers, setAnswers] = useState<LearningAttempt['answers']>([])
  const [startedAt] = useState(new Date().toISOString())
  const [questionStartedAt, setQuestionStartedAt] = useState(Date.now())
  const [feedback, setFeedback] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [nextDashboard, setNextDashboard] = useState<StudentDashboardData | null>(null)
  const primaryActionRef = useRef<HTMLButtonElement>(null)
  const card = payload.cards[cardIndex]
  const question = payload.questions[questionIndex]

  useEffect(() => {
    function continueWithEnter(event: KeyboardEvent) {
      if (event.key !== 'Enter' || event.repeat || event.isComposing || event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return
      const target = event.target
      if (target instanceof HTMLElement && (target.matches('input, textarea, select') || target.isContentEditable)) return
      const action = primaryActionRef.current
      if (!action || action.disabled || action.getAttribute('aria-disabled') === 'true') return
      if (target instanceof Node && action.contains(target)) return
      event.preventDefault()
      action.click()
    }
    window.addEventListener('keydown', continueWithEnter)
    return () => window.removeEventListener('keydown', continueWithEnter)
  }, [])

  const roundTrack = <div className="round-track" aria-label={`今天共${roundLimit}轮，当前第${roundNumber}轮`}>{Array.from({ length: roundLimit }, (_, index) => <span key={index} className={index + 1 < roundNumber ? 'done' : index + 1 === roundNumber ? 'current' : ''}><i>{index + 1}</i><b>{index + 1 === roundNumber ? '本轮' : index + 1 < roundNumber ? '完成' : '待检验'}</b></span>)}</div>

  if (phase === 'cards') return <section className="learning-stage"><button className="text-button" onClick={onExit}>← 返回计划</button>{roundTrack}<div className="review-outline"><b>今天复习什么</b>{payload.plan.knowledgeSummaries.map((topic) => <span key={topic}><ChemText>{topic}</ChemText></span>)}</div><div className="stage-progress"><i style={{ width: `${(cardIndex + 1) / Math.max(payload.cards.length, 1) * 100}%` }} /></div>{card ? <article className="knowledge-card"><span className="eyebrow">从零讲清楚 · {cardIndex + 1}/{payload.cards.length}</span><h1><ChemText>{card.title}</ChemText></h1>{!card.structuredContent?.visualSummary ? <div className="core-rule"><ChemText>{card.core}</ChemText></div> : null}{card.structuredContent ? <StructuredKnowledgeMap content={card.structuredContent} skillId={card.skillId} /> : <details open><summary>展开理解</summary><p><ChemText>{card.detail}</ChemText></p><ol>{card.steps.map((step) => <li key={step}><ChemText>{step}</ChemText></li>)}</ol><div className="mistake-note"><b>容易踩坑</b><ul>{card.commonMistakes.map((mistake) => <li key={mistake}><ChemText>{mistake}</ChemText></li>)}</ul></div><p><b>完整例子：</b><ChemText>{card.microExample}</ChemText></p></details>}</article> : <EmptyState text="本轮知识卡正在审核，暂不向学生展示。" />}
    <div className="stage-actions"><button className="secondary-button" onClick={onExit}>稍后再学</button><button ref={primaryActionRef} className="primary-button" aria-keyshortcuts="Enter" onClick={() => { if (cardIndex < payload.cards.length - 1) setCardIndex(cardIndex + 1); else setPhase('quiz') }}>{cardIndex < payload.cards.length - 1 ? '下一张' : '我理解了，开始练习'}<ChevronRight size={18} /></button></div></section>

  if (phase === 'quiz' && question) {
    const isCorrect = selected === question.correctOption
    function submit() {
      if (selected === null) return
      setAnswers((items) => [...items, { questionId: question.id, motherId: question.motherId, skillId: question.skillId, level: question.level, correct: isCorrect, uncertain, durationSec: Math.max(1, Math.round((Date.now() - questionStartedAt) / 1000)), selectedOption: selected }])
      setFeedback(true)
    }
    async function next() {
      if (questionIndex < payload.questions.length - 1) { setQuestionIndex(questionIndex + 1); setSelected(null); setUncertain(false); setFeedback(false); setQuestionStartedAt(Date.now()); return }
      setBusy(true)
      const finalAnswers = [...answers, ...(feedback ? [] : [])]
      const attempt: LearningAttempt = { id: crypto.randomUUID(), studentId: practiceDashboard?.profile.id ?? '', planDayId: payload.plan.id, attemptKind: payload.attemptSequence === 0 ? 'scheduled' : 'review', sequence: payload.attemptSequence, mode: payload.plan.mode, startedAt, completedAt: new Date().toISOString(), answers: finalAnswers, firstScore: finalAnswers.filter((answer) => answer.correct).length }
      try {
        setError('')
        if (practiceMode && practiceDashboard) {
          setNextDashboard(practiceDashboard)
          setPhase('result')
        } else {
          const result = await submitAttempt(session, attempt)
          setNextDashboard(result.dashboard)
          setPhase('result')
        }
      } catch (reason) {
        setError(reason instanceof Error ? reason.message : '这一轮暂时没有保存成功，请稍后再试。')
      } finally { setBusy(false) }
    }
    return <section className="learning-stage">{roundTrack}{roundNumber > 1 && <div className="round-guidance"><Sparkles /><div><b>第 {roundNumber} 轮换一种问法</b><p>继续检验同一知识逻辑，但题目与母题都和今天前面的轮次不同；第5轮也不会回到原题。</p></div></div>}{error && <div className="inline-alert" role="alert">{error}</div>}<div className="quiz-head"><span>第 {roundNumber} 轮 · {questionIndex + 1}/{payload.questions.length}</span><span>{SKILLS.find((skill) => skill.id === question.skillId)?.title}</span></div><div className="stage-progress"><i style={{ width: `${(questionIndex + 1) / payload.questions.length * 100}%` }} /></div><article className="question-card"><span className="difficulty-pill">L{question.level}检验</span><h1><ChemText>{question.stem}</ChemText></h1><div className="option-list">{question.options.map((option, index) => <button disabled={feedback} className={`${selected === index ? 'selected' : ''} ${feedback && index === question.correctOption ? 'correct' : ''} ${feedback && selected === index && index !== question.correctOption ? 'wrong' : ''}`} key={option} onClick={() => setSelected(index)}><span>{String.fromCharCode(65 + index)}</span><ChemText>{option}</ChemText></button>)}</div><label className="uncertain-toggle"><input type="checkbox" checked={uncertain} onChange={(event) => setUncertain(event.target.checked)} disabled={feedback} />我选了，但还不太确定</label>{feedback && <div className={`answer-feedback ${isCorrect ? 'good' : 'needs-work'}`}><b>{isCorrect ? uncertain ? '答案正确，再确认一次就更稳' : '判断正确' : '先把关键一步稳住'}</b><p><ChemText>{question.explanation}</ChemText></p>{!isCorrect && question.scaffold && <p><CircleHelp size={16} />提示：<ChemText>{question.scaffold}</ChemText></p>}</div>}</article><div className="stage-actions">{!feedback ? <button ref={primaryActionRef} className="primary-button" aria-keyshortcuts="Enter" disabled={selected === null} onClick={submit}>提交答案</button> : <button ref={primaryActionRef} className="primary-button" aria-keyshortcuts="Enter" disabled={busy} onClick={next}>{questionIndex < payload.questions.length - 1 ? '下一题' : `完成第 ${roundNumber} 轮`}<ChevronRight size={18} /></button>}</div></section>
  }

  const correct = answers.filter((answer) => answer.correct).length
  const unresolved = answers.filter((answer) => !answer.correct || answer.uncertain).length
  const hasNextRound = roundNumber < roundLimit && (practiceMode || unresolved > 0)
  return <section className="learning-stage result-stage">{roundTrack}<div className="result-badge"><Check /></div><span className="eyebrow">{practiceMode ? `演示第 ${roundNumber} 轮完成` : `今天第 ${roundNumber} 轮完成`}</span><h1>{unresolved === 0 ? '这一轮的逻辑已经接稳。' : `还有 ${unresolved} 个判断需要换一种方式确认。`}</h1><p>本轮答对 {correct}/{answers.length}，其中 {answers.filter((answer) => answer.uncertain).length} 题标记为不确定。{practiceMode ? '本次结果只在当前页面展示，不会写入任何真实学生档案。' : hasNextRound ? '下一轮会优先更换母题，继续解决今天暴露的问题。' : '五轮记录已交给系统整理，甘老师可在后台查看并安排后续讲解。'}</p><div className="result-stats"><div><b>{answers.length}</b><span>完成题目</span></div><div><b>{new Set(answers.map((answer) => answer.skillId)).size}</b><span>检验技能</span></div><div><b>{unresolved}</b><span>仍需确认</span></div></div><div className="result-actions">{hasNextRound && <button ref={primaryActionRef} className="primary-button" aria-keyshortcuts="Enter" disabled={!nextDashboard || busy} onClick={async () => { if (!nextDashboard) return; setBusy(true); try { await onContinue(nextDashboard, payload.plan.id, roundNumber + 1) } finally { setBusy(false) } }}>{busy ? '正在准备…' : `进入第 ${roundNumber + 1} 轮`}<ChevronRight size={18} /></button>}<button ref={hasNextRound ? undefined : primaryActionRef} className={hasNextRound ? 'secondary-button' : 'primary-button'} aria-keyshortcuts={hasNextRound ? undefined : 'Enter'} disabled={!nextDashboard} onClick={() => nextDashboard && onComplete(nextDashboard)}>{practiceMode ? '返回演示计划' : hasNextRound ? '先回首页' : '查看今日成果'}<Trophy size={18} /></button></div></section>
}

function KnowledgeBranch({ node, depth = 0 }: { node: KnowledgeTreeNode; depth?: number }) {
  return <li className={`knowledge-branch depth-${Math.min(depth, 3)}`}>
    <details className="knowledge-branch-details" open={depth === 0}>
      <summary className="branch-summary"><span><ChemText>{node.label}</ChemText></span><i aria-hidden="true">⌄</i></summary>
      <div className="branch-card point-with-demo"><div className="point-copy"><p><ChemText>{node.rule}</ChemText></p>{node.caution && <div className="branch-caution">注意：<ChemText>{node.caution}</ChemText></div>}</div><NodeLearningAid node={node} /></div>
      {node.children?.length ? <ul>{node.children.map((child) => <KnowledgeBranch key={`${node.label}-${child.label}`} node={child} depth={depth + 1} />)}</ul> : null}
    </details>
  </li>
}

function compactVisualStep(value: string) {
  return value.replace(/^以“[^”]+”为示范：/, '').trim()
}

function NodeLearningAid({ node }: { node: KnowledgeTreeNode }) {
  const visualSteps = (node.visualSteps?.length ? node.visualSteps : [node.label, ...(node.examples?.slice(0, 2) ?? ['按定义判断'])]).map(compactVisualStep)
  return <aside className="point-learning-aid" aria-label={`${node.label}的示范与图像记忆`}>
    <div className="point-demo"><b>马上看例子</b>{node.examples?.map((example) => <p key={example}><ChemText>{example}</ChemText></p>)}</div>
    <figure className="memory-diagram"><figcaption>图像记忆</figcaption><div className="memory-flow">{visualSteps.map((step, index) => <Fragment key={`${node.label}-${step}-${index}`}><span><ChemText>{step}</ChemText></span>{index < visualSteps.length - 1 ? <i aria-hidden="true">→</i> : null}</Fragment>)}</div></figure>
  </aside>
}

function visualTreeFromKnowledge(node: KnowledgeTreeNode): KnowledgeVisualTreeNode {
  return { label: node.label, children: node.children?.map(visualTreeFromKnowledge) }
}

function QuickTreeBranch({ node }: { node: KnowledgeVisualTreeNode }) {
  return <li className="quick-tree-branch"><span className="quick-tree-node"><ChemText>{node.label}</ChemText></span>{node.children?.length ? <ul className="quick-tree-children">{node.children.map((child) => <QuickTreeBranch key={`${node.label}-${child.label}`} node={child} />)}</ul> : null}</li>
}

function fallbackVisual(content: StructuredKnowledgeContent): KnowledgeVisualSummary {
  if (content.rootTree) return { kind: 'tree', title: '知识关系总图', tree: visualTreeFromKnowledge(content.rootTree) }
  return {
    kind: 'flow',
    title: '先看逻辑路线',
    steps: content.sections.slice(0, 6).map((section, index) => ({ label: section.title, caption: `${index + 1}` })),
  }
}

const periodThreeTrend = [
  { element: 'Na', valence: '+1', oxide: 'Na₂O', hydrate: 'NaOH', nature: '碱' },
  { element: 'Mg', valence: '+2', oxide: 'MgO', hydrate: 'Mg(OH)₂', nature: '碱' },
  { element: 'Al', valence: '+3', oxide: 'Al₂O₃', hydrate: 'Al(OH)₃', nature: '两性' },
  { element: 'Si', valence: '+4', oxide: 'SiO₂', hydrate: 'H₂SiO₃', nature: '酸' },
  { element: 'P', valence: '+5', oxide: 'P₄O₁₀（常简写P₂O₅）', hydrate: 'H₃PO₄', nature: '酸' },
  { element: 'S', valence: '+6', oxide: 'SO₃', hydrate: 'H₂SO₄', nature: '酸' },
  { element: 'Cl', valence: '+7', oxide: 'Cl₂O₇', hydrate: 'HClO₄', nature: '酸' },
]

function PeriodicTrendVisual() {
  return <figure className="quick-visual periodic-trend-visual" aria-label="30秒图解：第三周期元素最高价氧化物、对应水化物和气态氢化物完整趋势">
    <figcaption><span>30秒图解</span><b>元素周期律完整趋势图</b></figcaption>
    <div className="periodic-cause-strip"><b>同周期从左到右</b><span>电子层数不变</span><i>→</i><span>核电荷递增</span><i>→</i><span>原子半径总体减小</span><i>→</i><span>金属性减弱、非金属性增强</span></div>
    <div className="periodic-comparison" role="table" aria-label="第三周期最高价氧化物及对应水化物逐元素对照">
      <div className="periodic-row periodic-head" role="row"><b role="columnheader">元素</b><b role="columnheader">最高正价</b><b role="columnheader">最高价氧化物</b><b role="columnheader">对应水化物</b><b role="columnheader">酸碱类别</b></div>
      {periodThreeTrend.map((entry) => <div className="periodic-row" role="row" key={entry.element}>
        <strong role="cell"><ChemText>{entry.element}</ChemText></strong><span role="cell"><ChemText>{entry.valence}</ChemText></span><span role="cell"><ChemText>{entry.oxide}</ChemText></span><span role="cell"><ChemText>{entry.hydrate}</ChemText></span><span role="cell" className={`nature-${entry.nature}`}><ChemText>{entry.nature}</ChemText></span>
      </div>)}
    </div>
    <div className="periodic-direction" aria-label="第三周期对应水化物酸碱性趋势"><span>碱性逐渐减弱</span><i>→</i><b>Al(OH)₃ 两性分界</b><i>→</i><span>酸性逐渐增强</span></div>
    <div className="periodic-hydrides"><section><b>同周期气态氢化物热稳定性</b><p><ChemText>SiH₄ ＜ PH₃ ＜ H₂S ＜ HCl</ChemText></p><small>从左到右总体增强</small></section><section><b>同主族氢化物热稳定性</b><p><ChemText>HF ＞ HCl ＞ HBr ＞ HI</ChemText></p><small>从上到下总体减弱</small></section></div>
    <p className="periodic-boundary"><b>边界：</b>“对应水化物”表示组成与价态上的对应关系，不表示该氧化物一定能直接与水反应制得；例如SiO₂不能直接与水生成H₂SiO₃。热稳定性也不等于水溶液酸性或还原性。</p>
  </figure>
}

function EnergyProfile({ mode }: { mode: 'exo' | 'endo' }) {
  const exo = mode === 'exo'
  const reactantY = exo ? 88 : 152
  const productY = exo ? 152 : 88
  const arrowId = `${mode}-energy-arrow`
  return <section className={`energy-profile energy-profile-${mode}`}>
    <h3>{exo ? '放热反应：ΔH＜0' : '吸热反应：ΔH＞0'}</h3>
    <svg viewBox="0 0 380 230" role="img" aria-label={`${exo ? '放热' : '吸热'}反应能量随反应进程变化图`}>
      <defs><marker id={arrowId} markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto"><path d="M0,0 L0,6 L7,3 z" /></marker></defs>
      <path className="energy-axis" d="M42 190V24M42 190H354" />
      <text x="9" y="25" className="axis-label">能量</text><text x="292" y="215" className="axis-label">反应进程</text>
      <path className="energy-curve" d={`M54 ${reactantY} C105 ${reactantY},116 38,190 38 C260 38,276 ${productY},344 ${productY}`} />
      <path className="energy-platform" d={`M54 ${reactantY}H108M288 ${productY}H344`} />
      <text x="54" y={reactantY - 10}>反应物</text><text x="288" y={productY - 10}>生成物</text>
      <path className="energy-arrow" markerEnd={`url(#${arrowId})`} d={`M82 ${reactantY - 3}V47`} />
      <text x="88" y={(reactantY + 42) / 2}>正反应活化能 Eₐ</text>
      <path className="enthalpy-arrow" markerEnd={`url(#${arrowId})`} d={`M328 ${reactantY + (exo ? 6 : -6)}V${productY + (exo ? -6 : 6)}`} />
      <text x="274" y={(reactantY + productY) / 2}>{exo ? 'ΔH＜0' : 'ΔH＞0'}</text>
    </svg>
    <p>{exo ? '生成物总焓低于反应物总焓，体系向环境释放能量。' : '生成物总焓高于反应物总焓，体系从环境吸收能量。'}</p>
  </section>
}

function ThermochemistryVisual() {
  return <figure className="quick-visual thermo-energy-visual" aria-label="30秒图解：放热反应与吸热反应能量曲线">
    <figcaption><span>30秒图解</span><b>反应热必须看能量图</b></figcaption>
    <div className="energy-profile-grid"><EnergyProfile mode="exo" /><EnergyProfile mode="endo" /></div>
    <div className="enthalpy-definition"><b>始态—终态定义</b><span>ΔH = H（生成物）− H（反应物）</span></div>
    <div className="bond-energy-ledger"><section><b>反应物断键</b><span>吸收能量</span></section><i>→</i><section><b>原子或基团重排</b><span>跨越活化能</span></section><i>→</i><section><b>生成物成键</b><span>释放能量</span></section></div>
    <p className="bond-energy-equation">用平均键能估算时：<b>ΔH ≈ ΣE（反应物断键吸收）− ΣE（生成物成键释放）</b></p>
  </figure>
}

function QuickVisualSummary({ visual }: { visual: KnowledgeVisualSummary }) {
  if (visual.title === '元素周期律完整趋势图') return <PeriodicTrendVisual />
  if (visual.title === '反应热的能量账本') return <ThermochemistryVisual />
  const groups = visual.groups ?? []
  return <figure className={`quick-visual quick-visual-${visual.kind}`} aria-label={`30秒图解：${visual.title}`}>
    <figcaption><span>30秒图解</span><b><ChemText>{visual.title}</ChemText></b></figcaption>
    {visual.kind === 'tree' && visual.tree ? <div className="quick-tree-visual"><ul className="quick-tree"><QuickTreeBranch node={visual.tree} /></ul>{visual.axes?.length ? <div className="quick-tree-axes"><b>横向分类轴</b>{visual.axes.map((axis) => <div className="quick-axis" key={axis.label}><strong><ChemText>{axis.label}</ChemText></strong><div>{axis.items.map((item) => <span key={item}><ChemText>{item}</ChemText></span>)}</div></div>)}</div> : null}</div> : null}
    {(visual.kind === 'flow' || visual.kind === 'cycle') && visual.steps?.length ? <ol className="quick-flow">{visual.steps.map((step, index) => <Fragment key={`${step.label}-${index}`}><li><small><ChemText>{step.caption ?? String(index + 1).padStart(2, '0')}</ChemText></small><b><ChemText>{step.label}</ChemText></b></li>{index < visual.steps!.length - 1 ? <i aria-hidden="true">→</i> : null}</Fragment>)}{visual.kind === 'cycle' ? <i className="cycle-return" aria-label="回到起点">↺</i> : null}</ol> : null}
    {visual.kind === 'compare' ? <div className="quick-compare">{groups.map((group) => <section key={group.label}><b><ChemText>{group.label}</ChemText></b><div>{group.items.map((item) => <span key={item}><ChemText>{item}</ChemText></span>)}</div></section>)}</div> : null}
    {visual.kind === 'network' ? <div className="quick-network"><div className="network-hub"><ChemText>{visual.center ?? visual.title}</ChemText></div><div className="network-branches">{groups.map((group) => <section key={group.label}><b><ChemText>{group.label}</ChemText></b>{group.items.map((item) => <span key={item}><ChemText>{item}</ChemText></span>)}</section>)}</div></div> : null}
    {visual.kind === 'balance' ? <div className="quick-balance">{groups.map((group, index) => <Fragment key={group.label}><section><b><ChemText>{group.label}</ChemText></b>{group.items.map((item) => <span key={item}><ChemText>{item}</ChemText></span>)}</section>{index < groups.length - 1 ? <i aria-hidden="true"><ChemText>{visual.center ?? '='}</ChemText></i> : null}</Fragment>)}</div> : null}
  </figure>
}

export function StructuredKnowledgeMap({ content, skillId }: { content: StructuredKnowledgeContent; skillId?: string }) {
  const offset = content.rootTree ? 2 : 1
  return <div className="knowledge-explainer">
    {skillId && supportsSourceInformedChemVisual(skillId)
      ? <SourceInformedChemVisual skillId={skillId} />
      : <QuickVisualSummary visual={content.visualSummary ?? fallbackVisual(content)} />}
    <details className="full-explanation"><summary><span><b>从零学会</b><small>展开完整讲解、例子、易错边界与自查</small></span><i aria-hidden="true">⌄</i></summary><div className="classification-map">
      {content.rootTree ? <section className="knowledge-tree-panel" aria-labelledby="knowledge-tree-title"><div className="map-section-title"><span>01</span><div><h2 id="knowledge-tree-title">知识总树</h2><p>先沿纵向主干走完，再补横向标签。</p></div></div><ul className="knowledge-tree"><KnowledgeBranch node={content.rootTree} /></ul></section> : null}
      {content.sections.map((section, index) => <section className="classification-section" key={section.title}><div className="map-section-title"><span>{String(index + offset).padStart(2, '0')}</span><div><h2><ChemText>{section.title}</ChemText></h2>{section.summary && <p><ChemText>{section.summary}</ChemText></p>}</div></div><div className="classification-items">{section.items.map((item) => <details className="classification-item" key={item.label}><summary className="classification-item-summary"><span><ChemText>{item.label}</ChemText></span><i aria-hidden="true">⌄</i></summary><div className="classification-item-body point-with-demo"><div className="point-copy"><p><ChemText>{item.rule}</ChemText></p>{item.caution && <div className="branch-caution">注意：<ChemText>{item.caution}</ChemText></div>}</div><NodeLearningAid node={item} /></div></details>)}</div></section>)}
      {content.workedExamples?.length ? <section className="classification-section worked-examples"><div className="map-section-title"><span>{String(content.sections.length + offset).padStart(2, '0')}</span><div><h2>完整例题：把逻辑一步一步走通</h2><p>先看为什么，再看怎么算或怎样判断。</p></div></div><div className="worked-example-grid">{content.workedExamples.map((example) => <article key={example.substance}><h3><ChemText>{example.substance}</ChemText></h3><p><ChemText>{example.path}</ChemText></p><div className="example-chips">{example.labels.map((label) => <span key={label}><ChemText>{label}</ChemText></span>)}</div></article>)}</div></section> : null}
      {content.checkpoints?.length ? <section className="classification-section recall-check"><div className="map-section-title"><span>✓</span><div><h2>合上页面前，我应该能做到</h2><p>说不出来就回到对应小节，不需要硬撑着进入练习。</p></div></div><ul>{content.checkpoints.map((checkpoint) => <li key={checkpoint}><ChemText>{checkpoint}</ChemText></li>)}</ul></section> : null}
      {content.scopeNote ? <p className="scope-note"><b>范围说明：</b><ChemText>{content.scopeNote}</ChemText></p> : null}
    </div></details>
  </div>
}

function EmptyState({ text }: { text: string }) { return <div className="empty-state"><RotateCcw /><p>{text}</p></div> }
