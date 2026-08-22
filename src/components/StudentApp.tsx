import { Fragment, useEffect, useMemo, useRef, useState } from 'react'
import { BookOpen, Check, ChevronRight, CircleHelp, Clock3, KeyRound, Map as MapIcon, RotateCcw, Settings, ShieldCheck, Sparkles, Trophy } from 'lucide-react'
import type { KnowledgeCard, KnowledgeTreeNode, KnowledgeVisualSummary, KnowledgeVisualTreeNode, LearningAttempt, LearningPlanDay, LearningRecordData, Question, QuestionFeedback, SessionIdentity, StudentDashboardData, StructuredKnowledgeContent } from '../domain/types'
import { splitAnswerExplanation } from '../domain/answerExplanation'
import { isStructuredKnowledgeContent } from '../domain/knowledgeContent'
import { SKILLS } from '../data/catalog'
import { accessApi, loadLearningRecord, loadQuestionFeedback, previewQuestionFeedback, submitAttempt, teacherApi } from '../lib/api'
import { AbilityMap } from './AbilityMap'
import { ChemText } from './ChemText'
import { EquilibriumConstantFormulaVisual } from './EquilibriumConstantFormulaVisual'
import { LearningRecordPanel } from './LearningRecordPanel'
import { QuestionSourceMedia } from './QuestionSourceMedia'
import { SourceInformedChemVisual } from './SourceInformedChemVisuals'
import { supportsSourceInformedChemVisual } from './sourceInformedChemVisualSupport'
import { StudentVideoSection } from './VideoLearning'

type StudentView = 'today' | 'map' | 'growth' | 'settings'
type IssuedQuestion = Omit<Question, 'correctOption' | 'explanation' | 'scaffold'> & Partial<Pick<Question, 'correctOption' | 'explanation' | 'scaffold'>>
export type PlanPayload = {
  plan: LearningPlanDay
  cards: KnowledgeCard[]
  questions: IssuedQuestion[]
  /** Existing server-locked answers returned only when resuming this round. */
  lockedFeedback?: QuestionFeedback[]
  attemptSequence: number
  roundNumber: number
  roundLimit: number
  questionCount: number
  isResolved: boolean
  isComplete: boolean
  roundsRemaining: number
}

const PLAN_OPEN_TIMEOUT_MS = 15_000

type PlanOpenRequest = {
  plan: LearningPlanDay
  previewRound?: number
}

type PlanOpenState = {
  status: 'loading' | 'error'
  request: PlanOpenRequest
  elapsedSeconds: number
  error?: string
}

function planOpenProgress(elapsedSeconds: number) {
  if (elapsedSeconds < 2) return {
    title: '第1步/3 · 正在连接复习服务',
    detail: '先确认你的身份和这一天的学习计划，通常需要3—7秒。',
  }
  if (elapsedSeconds < 5) return {
    title: '第2步/3 · 正在核对知识卡与本轮原题',
    detail: '系统正在等题库返回完整的知识卡和题目清单。',
  }
  return {
    title: '第3步/3 · 正在安全装入本轮',
    detail: '当前网络较慢；进入题目后，原题图片会逐张加载。',
  }
}

function PlanOpenNotice({ state, onRetry, retryLabel = '重新打开本轮', showRetryButton = false }: { state: PlanOpenState; onRetry: () => void; retryLabel?: string; showRetryButton?: boolean }) {
  if (state.status === 'error') return <div className="plan-open-notice is-error" role="alert">
    <div><b>本轮还没有打开</b><span>{state.error}</span><small>当前页面和已有学习记录都保留；重试只会重新读取本轮，不会重复提交答案。</small></div>
    {showRetryButton && <button type="button" className="secondary-button compact" onClick={onRetry}><RotateCcw />{retryLabel}</button>}
  </div>

  const progress = planOpenProgress(state.elapsedSeconds)
  return <div className="plan-open-notice is-loading" role="status" aria-live="polite">
    <Clock3 aria-hidden="true" />
    <div><b>{progress.title}</b><span>{progress.detail}</span><small>{state.elapsedSeconds > 0 ? `已等待 ${state.elapsedSeconds} 秒，请不要重复点击。` : '请求已经发出，请稍候。'}</small></div>
  </div>
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
  const [planOpenState, setPlanOpenState] = useState<PlanOpenState | null>(null)
  const planOpenRequestId = useRef(0)
  const planOpenAbort = useRef<AbortController | null>(null)

  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
  const todayPlan = dashboard.plans.find((plan) => plan.date === today) ?? dashboard.plans.find((plan) => plan.date >= today) ?? dashboard.plans[0]
  const visiblePlans = useMemo(() => [...dashboard.plans].sort((a, b) => a.date.localeCompare(b.date)), [dashboard.plans])

  useEffect(() => () => {
    planOpenRequestId.current += 1
    planOpenAbort.current?.abort()
  }, [])

  async function openPlan(plan: LearningPlanDay, previewRound?: number): Promise<boolean> {
    if (busy) return false
    const request = { plan, ...(previewRound ? { previewRound } : {}) }
    const requestId = ++planOpenRequestId.current
    const controller = new AbortController()
    planOpenAbort.current = controller
    const startedAt = Date.now()
    setBusy(true)
    setError('')
    setPlanOpenState({ status: 'loading', request, elapsedSeconds: 0 })
    const progressTimer = window.setInterval(() => {
      if (requestId !== planOpenRequestId.current) return
      const elapsedSeconds = Math.max(1, Math.floor((Date.now() - startedAt) / 1000))
      setPlanOpenState((current) => current?.status === 'loading' && current.request.plan.id === plan.id ? { ...current, elapsedSeconds } : current)
    }, 1_000)
    let rejectForTimeout: ((reason: Error) => void) | undefined
    let timedOut = false
    const timeoutError = new Error('plan-open-timeout')
    const timeoutPromise = new Promise<never>((_resolve, reject) => { rejectForTimeout = reject })
    const timeoutTimer = window.setTimeout(() => {
      timedOut = true
      rejectForTimeout?.(timeoutError)
      controller.abort()
    }, PLAN_OPEN_TIMEOUT_MS)
    try {
      const planRequest = previewMode
        ? teacherApi<{ payload: PlanPayload }>('preview_start_plan', { studentId: dashboard.profile.id, planId: plan.id, ...(previewRound ? { previewRound } : {}) }, { signal: controller.signal })
        : accessApi<{ payload: PlanPayload }>(session, 'start_plan', { planId: plan.id, ...(dashboard.profile.isDemo ? { studentId: dashboard.profile.id, ...(previewRound ? { previewRound } : {}) } : {}) }, { signal: controller.signal })
      const result = await Promise.race([planRequest, timeoutPromise])
      if (requestId !== planOpenRequestId.current) return false
      setPlanOpenState(null)
      setActivePlan(result.payload)
      return true
    } catch (reason) {
      if (requestId !== planOpenRequestId.current) return false
      const message = timedOut || reason === timeoutError
        ? '连接复习服务已超过15秒，系统已安全停止等待。请检查网络后再试。'
        : reason instanceof Error && reason.message ? reason.message : '学习内容暂时无法打开。'
      setPlanOpenState({ status: 'error', request, elapsedSeconds: Math.max(0, Math.floor((Date.now() - startedAt) / 1000)), error: message })
      return false
    } finally {
      window.clearInterval(progressTimer)
      window.clearTimeout(timeoutTimer)
      if (requestId === planOpenRequestId.current) {
        planOpenAbort.current = null
        setBusy(false)
      }
    }
  }

  async function continuePlan(nextDashboard: StudentDashboardData, planId: string, nextRound: number) {
    setDashboard(nextDashboard)
    onDashboard(nextDashboard)
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

  const retryPlanOpen = () => {
    if (!planOpenState || planOpenState.status === 'loading') return
    void openPlan(planOpenState.request.plan, planOpenState.request.previewRound)
  }

  if (activePlan) {
    return <LearningRound key={`${activePlan.plan.id}:${activePlan.roundNumber}:${activePlan.attemptSequence}`} session={session} payload={activePlan} practiceMode={previewMode || Boolean(dashboard.profile.isDemo)} practiceDashboard={dashboard} planOpenState={planOpenState?.request.plan.id === activePlan.plan.id ? planOpenState : null} onRetryPlanOpen={retryPlanOpen} onExit={() => setActivePlan(null)} onContinue={(next, planId, nextRound) => continuePlan(next, planId, nextRound)} onComplete={(next) => { setDashboard(next); onDashboard(next); setActivePlan(null); setView(previewMode || dashboard.profile.isDemo ? 'today' : 'growth') }} />
  }

  const todayPlanOpenState = todayPlan && planOpenState?.request.plan.id === todayPlan.id ? planOpenState : null

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
          {dashboard.profile.isDemo && <section className="demo-grade-switch" aria-label="切换演示年级"><div><span className="eyebrow">演示查看</span><h2>这里只检查知识卡与学习路线</h2><p>公开演示不再提供无材料来源的模拟题；正式原题请由甘老师从教师后台选择真实学生并只读预览。</p></div><div>{(dashboard.profile.availableDemoGrades ?? ['高一', '高二', '高三']).map((grade) => <button key={grade} className={dashboard.profile.gradeBand === grade ? 'active' : ''} onClick={() => void switchDemoGrade(grade)} disabled={busy}>{grade}</button>)}</div></section>}
          {todayPlan ? <section className="focus-card">
            <div className="focus-icon"><BookOpen /></div>
            <div><span className="mode-pill">{todayPlan.mode === 'EXAM_SPRINT' ? '考前拿分' : '长期复习'}</span><h2><ChemText>{todayPlan.title}</ChemText></h2><div className="focus-topics">{todayPlan.knowledgeSummaries.map((topic) => <span key={topic}><ChemText>{topic}</ChemText></span>)}</div><div className="meta-row"><span><Clock3 size={15} />约{todayPlan.estimatedMinutes}分钟</span><span>每轮 {todayPlan.questionCount} 题 · 共 {todayPlan.roundLimit} 轮 · 当天把问题接稳</span></div></div>
            <div className="focus-action"><button className="primary-button compact" onClick={() => todayPlan.isComplete ? setView('growth') : void openPlan(todayPlan)} disabled={busy}>{todayPlanOpenState?.status === 'loading' ? `正在读取 · ${todayPlanOpenState.elapsedSeconds}秒` : todayPlanOpenState?.status === 'error' ? `重试${nextRoundLabel(todayPlan)}` : todayPlan.isComplete ? '查看今日成果' : nextRoundLabel(todayPlan)}<ChevronRight size={18} /></button>{todayPlanOpenState && <PlanOpenNotice state={todayPlanOpenState} onRetry={retryPlanOpen} />}</div>
          </section> : <EmptyState text="甘老师还没有为今天安排正式任务。" />}
          {planOpenState && !todayPlanOpenState && <PlanOpenNotice state={planOpenState} onRetry={retryPlanOpen} showRetryButton />}
          <StudentVideoSection session={session} videos={dashboard.videoRecommendations ?? []} readOnly={previewMode || Boolean(dashboard.profile.isDemo)} />
          <PlanCalendar plans={visiblePlans} enrollment={dashboard.profile.enrollmentStartDate} onOpen={(plan) => plan.isComplete && !previewMode && !dashboard.profile.isDemo ? setView('growth') : openPlan(plan)} busy={busy} embedded />
          <section className="section-block"><div className="section-head"><div><span className="eyebrow">最近获得</span><h2>已经亮起来的部分</h2></div><button className="text-button" onClick={() => setView('growth')}>查看全部</button></div>
            <div className="achievement-grid">{dashboard.achievements.slice(0, 3).map((item) => <article className="achievement-card" key={item.id}><div className="achievement-icon"><Trophy /></div><div><b><ChemText>{item.title}</ChemText></b><p><ChemText>{item.description}</ChemText></p></div></article>)}</div>
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
    <div className="week-stack">{weeks.map((week, index) => { const currentWeek = week.some((plan) => plan.date === today); const nextWeek = week.some((plan) => plan.date === nextDate); return <div className={`week-card ${currentWeek ? 'is-current-week' : nextWeek ? 'is-next-week' : ''}`} key={week[0]?.date ?? index}><div className="week-label">{currentWeek ? '本周 · 今天已点亮' : nextWeek ? '下一次安排' : index === 0 ? '复习起始周' : `复习第 ${index + 1} 周`}</div><div className="week-grid">{week.map((plan) => { const isToday = plan.date === today; const isNext = plan.date === nextDate; return <button key={plan.id} ref={isToday || isNext ? focusButton : undefined} className={`plan-day ${isToday ? 'is-today' : isNext ? 'is-next' : ''}`} aria-current={isToday ? 'date' : undefined} onClick={() => onOpen(plan)} disabled={busy}><span className="plan-date">{plan.date.slice(5)} · {weekdayLabel(plan.date)}</span>{isToday ? <span className="plan-today-badge" aria-hidden="true">今天</span> : isNext ? <span className="plan-next-badge">下一次</span> : null}<b><ChemText>{plan.title}</ChemText></b><ul>{plan.knowledgeSummaries.map((topic) => <li key={topic}><ChemText>{topic}</ChemText></li>)}</ul><small>每轮{plan.questionCount}题 · {plan.roundLimit}轮 · {plan.estimatedMinutes}分钟</small><em>{statusLabel(plan, enrollment)}</em></button> })}</div></div> })}</div>
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

export function LearningRound({ session, payload, practiceMode = false, practiceDashboard, planOpenState = null, onRetryPlanOpen, onExit, onContinue, onComplete }: { session: SessionIdentity; payload: PlanPayload; practiceMode?: boolean; practiceDashboard?: StudentDashboardData; planOpenState?: PlanOpenState | null; onRetryPlanOpen?: () => void; onExit: () => void; onContinue: (data: StudentDashboardData, planId: string, nextRound: number) => Promise<void>; onComplete: (data: StudentDashboardData) => void }) {
  const roundNumber = payload.roundNumber || payload.attemptSequence + 1
  const roundLimit = payload.roundLimit || payload.plan.roundLimit || 5
  const initialServerFeedback = Object.fromEntries((payload.lockedFeedback ?? []).map((item) => [item.questionId, item]))
  const initialAnswers: LearningAttempt['answers'] = payload.questions.flatMap((question) => {
    const item = initialServerFeedback[question.id]
    return item ? [{ questionId: question.id, motherId: question.motherId, skillId: question.skillId, level: question.level, correct: item.correct, uncertain: item.uncertain, durationSec: item.durationSec, selectedOption: item.selectedOption, revisionToken: question.revisionToken }] : []
  })
  const firstUnansweredQuestion = payload.questions.findIndex((question) => !initialServerFeedback[question.id])
  const initialQuestionIndex = firstUnansweredQuestion >= 0 ? firstUnansweredQuestion : Math.max(0, payload.questions.length - 1)
  const resumedFeedback = payload.questions[initialQuestionIndex] ? initialServerFeedback[payload.questions[initialQuestionIndex].id] : undefined
  const [phase, setPhase] = useState<'cards' | 'quiz' | 'result'>(roundNumber === 1 ? 'cards' : 'quiz')
  const [cardIndex, setCardIndex] = useState(0)
  const [questionIndex, setQuestionIndex] = useState(initialQuestionIndex)
  const [selected, setSelected] = useState<number | null>(resumedFeedback?.selectedOption ?? null)
  const [uncertain, setUncertain] = useState(resumedFeedback?.uncertain ?? false)
  const [answers, setAnswers] = useState<LearningAttempt['answers']>(initialAnswers)
  const [startedAt] = useState(new Date().toISOString())
  const [questionStartedAt, setQuestionStartedAt] = useState(Date.now())
  const [feedback, setFeedback] = useState(Boolean(resumedFeedback))
  const [serverFeedback, setServerFeedback] = useState<Record<string, QuestionFeedback>>(initialServerFeedback)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [nextDashboard, setNextDashboard] = useState<StudentDashboardData | null>(null)
  const [primaryMediaReady, setPrimaryMediaReady] = useState<Record<string, boolean>>({})
  const primaryActionRef = useRef<HTMLButtonElement>(null)
  const card = payload.cards[cardIndex]
  const question = payload.questions[questionIndex]

  useEffect(() => {
    function continueWithEnter(event: KeyboardEvent) {
      if (event.key !== 'Enter' || event.repeat || event.isComposing || event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return
      const target = event.target
      if (target instanceof HTMLElement && (target.matches('input, textarea, select') || target.isContentEditable)) return
      if (document.querySelector('dialog[data-question-media-dialog][open]')) return
      if (target instanceof HTMLElement && target.closest('[data-question-source-media], [data-question-media-dialog], [data-question-media-control]')) return
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

  if (phase === 'cards') return <section className="learning-stage"><button className="text-button" onClick={onExit}>← 返回计划</button>{roundTrack}<div className="review-outline"><b>今天复习什么</b>{payload.plan.knowledgeSummaries.map((topic) => <span key={topic}><ChemText>{topic}</ChemText></span>)}</div><div className="stage-progress"><i style={{ width: `${(cardIndex + 1) / Math.max(payload.cards.length, 1) * 100}%` }} /></div>{card ? <article className="knowledge-card"><span className="eyebrow">从零讲清楚 · {cardIndex + 1}/{payload.cards.length}</span><h1><ChemText>{card.title}</ChemText></h1>{!isStructuredKnowledgeContent(card.structuredContent) || !card.structuredContent.visualSummary ? <div className="core-rule"><ChemText>{card.core}</ChemText></div> : null}{isStructuredKnowledgeContent(card.structuredContent) ? <StructuredKnowledgeMap content={card.structuredContent} skillId={card.skillId} /> : <details open><summary>展开理解</summary><p><ChemText>{card.detail}</ChemText></p><ol>{card.steps.map((step) => <li key={step}><ChemText>{step}</ChemText></li>)}</ol><div className="mistake-note"><b>容易踩坑</b><ul>{card.commonMistakes.map((mistake) => <li key={mistake}><ChemText>{mistake}</ChemText></li>)}</ul></div><p><b>完整例子：</b><ChemText>{card.microExample}</ChemText></p></details>}</article> : <EmptyState text="本轮知识卡正在审核，暂不向学生展示。" />}
    <div className="stage-actions"><button className="secondary-button" onClick={onExit}>稍后再学</button><button ref={primaryActionRef} className="primary-button" aria-keyshortcuts="Enter" onClick={() => { if (cardIndex < payload.cards.length - 1) setCardIndex(cardIndex + 1); else setPhase('quiz') }}>{cardIndex < payload.cards.length - 1 ? '下一张' : '我理解了，开始练习'}<ChevronRight size={18} /></button></div></section>

  if (phase === 'quiz' && question) {
    const isLicensedReview = payload.plan.mode === 'REVIEW' && ['高一', '高二', '高三'].includes(question.gradeBand) && question.sourceKind === 'licensed_local'
    const hasLocalFeedbackContract = Number.isInteger(question.correctOption) && typeof question.explanation === 'string'
    const currentServerFeedback = serverFeedback[question.id]
    const resolvedCorrectOption = currentServerFeedback?.correctOption ?? question.correctOption
    const resolvedExplanation = currentServerFeedback?.explanation ?? question.explanation ?? ''
    const resolvedScaffold = currentServerFeedback?.scaffold ?? question.scaffold
    const isCorrect = isLicensedReview ? currentServerFeedback?.correct === true : selected === question.correctOption
    const isImagePrimary = isLicensedReview && question.renderMode === 'image_primary'
    const sourceMediaReady = !isImagePrimary || primaryMediaReady[question.id] === true
    const sourceAssetContext = {
      ...(practiceMode && practiceDashboard ? { studentId: practiceDashboard.profile.id, previewRound: roundNumber } : {}),
      planId: payload.plan.id,
      attemptSequence: payload.attemptSequence,
      revisionToken: question.revisionToken ?? null,
    }
    async function submit() {
      if (selected === null || !sourceMediaReady) return
      const durationSec = Math.max(1, Math.round((Date.now() - questionStartedAt) / 1000))
      if (isLicensedReview) {
        setBusy(true)
        try {
          setError('')
          const input = {
            ...(practiceMode && practiceDashboard ? { studentId: practiceDashboard.profile.id, previewRound: roundNumber } : {}),
            planId: payload.plan.id,
            questionId: question.id,
            selectedOption: selected,
            uncertain,
            durationSec,
            revisionToken: question.revisionToken ?? null,
          }
          const result = session.role === 'teacher'
            ? await previewQuestionFeedback(input)
            : await loadQuestionFeedback(session, input)
          if (result.feedback.questionId !== question.id || result.feedback.selectedOption !== selected) {
            throw new Error('服务器反馈与当前题目不一致，请重新打开本轮练习。')
          }
          setServerFeedback((items) => ({ ...items, [question.id]: result.feedback }))
          setAnswers((items) => [...items, { questionId: question.id, motherId: question.motherId, skillId: question.skillId, level: question.level, correct: result.feedback.correct, uncertain: result.feedback.uncertain, durationSec: result.feedback.durationSec, selectedOption: result.feedback.selectedOption, revisionToken: question.revisionToken }])
          setFeedback(true)
        } catch (reason) {
          setError(reason instanceof Error ? reason.message : '这道题暂时无法提交，请稍后重试。')
        } finally {
          setBusy(false)
        }
        return
      }
      if (!hasLocalFeedbackContract) {
        setError('这道题的反馈信息不完整，已停止提交，请联系甘老师。')
        return
      }
      setAnswers((items) => [...items, { questionId: question.id, motherId: question.motherId, skillId: question.skillId, level: question.level, correct: selected === question.correctOption, uncertain, durationSec, selectedOption: selected, revisionToken: question.revisionToken }])
      setFeedback(true)
    }
    async function next() {
      if (questionIndex < payload.questions.length - 1) {
        const nextQuestionIndex = questionIndex + 1
        const nextQuestion = payload.questions[nextQuestionIndex]
        const resumed = serverFeedback[nextQuestion.id]
        setQuestionIndex(nextQuestionIndex)
        setSelected(resumed?.selectedOption ?? null)
        setUncertain(resumed?.uncertain ?? false)
        setFeedback(Boolean(resumed))
        setQuestionStartedAt(Date.now())
        return
      }
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
          if (isLicensedReview) {
            const finalFeedback = result.feedback ?? []
            if (finalFeedback.length !== finalAnswers.length) throw new Error('本轮答案已保存，但反馈不完整，请返回学习档案查看。')
            const finalFeedbackByQuestionId = new Map(finalFeedback.map((item) => [item.questionId, item]))
            setAnswers(finalAnswers.map((answer) => {
              const item = finalFeedbackByQuestionId.get(answer.questionId)
              if (!item) return answer
              return { ...answer, selectedOption: item.selectedOption, correct: item.correct, uncertain: item.uncertain, durationSec: item.durationSec }
            }))
            setServerFeedback(Object.fromEntries(finalFeedback.map((item) => [item.questionId, item])))
          }
          setNextDashboard(result.dashboard)
          setPhase('result')
        }
      } catch (reason) {
        setError(reason instanceof Error ? reason.message : '这一轮暂时没有保存成功，请稍后再试。')
      } finally { setBusy(false) }
    }
    const nativeStem = <h1><ChemText>{question.stem}</ChemText></h1>
    const questionSkillTitle = SKILLS.find((skill) => skill.id === question.skillId)?.title
    const explanationParagraphs = splitAnswerExplanation(resolvedExplanation)
    return <section className="learning-stage">{roundTrack}{roundNumber > 1 && <div className="round-guidance"><Sparkles /><div><b>第 {roundNumber} 轮继续同一知识点</b><p>答对且确定，下一轮提高难度；答错或不确定，也会换一道同知识点原题重新确认。此前复习中已经做过的原题不会再次出现。</p></div></div>}{error && <div className="inline-alert" role="alert">{error}</div>}<div className="quiz-head"><span>第 {roundNumber} 轮 · {questionIndex + 1}/{payload.questions.length}</span><span>{questionSkillTitle ? <ChemText>{questionSkillTitle}</ChemText> : question.skillId}</span></div><div className="stage-progress"><i style={{ width: `${(questionIndex + 1) / payload.questions.length * 100}%` }} /></div><article className="question-card"><span className="difficulty-pill">L{question.level} 原题</span>{isLicensedReview ? <QuestionSourceMedia question={question} enabled session={session} accessContext={sourceAssetContext} nativeContent={nativeStem} showSource={false} onZoomClose={() => primaryActionRef.current?.focus()} onPrimaryReadyChange={(ready) => setPrimaryMediaReady((current) => current[question.id] === ready ? current : { ...current, [question.id]: ready })} /> : nativeStem}<div className={`option-list ${isImagePrimary ? 'source-letter-options' : ''}`}>{question.options.map((option, index) => { const letter = String.fromCharCode(65 + index); return <button aria-label={`${letter}. ${option}`} disabled={feedback || busy} className={`${selected === index ? 'selected' : ''} ${feedback && index === resolvedCorrectOption ? 'correct' : ''} ${feedback && selected === index && index !== resolvedCorrectOption ? 'wrong' : ''}`} key={`${index}-${option}`} onClick={() => setSelected(index)}><span>{letter}</span>{!isImagePrimary && <ChemText>{option}</ChemText>}</button> })}</div>{isImagePrimary && !sourceMediaReady && <p className="source-submit-blocked" role="status">原题主图加载完整后才能提交，避免因缺图误答。</p>}<label className="uncertain-toggle"><input type="checkbox" checked={uncertain} onChange={(event) => setUncertain(event.target.checked)} disabled={feedback || busy} />我选了，但还不太确定</label>{feedback && <div className={`answer-feedback ${isCorrect ? 'good' : 'needs-work'}`}><b>{isCorrect ? uncertain ? '答案正确，再确认一次就更稳' : '判断正确，下一轮提高难度' : '先把关键一步稳住'}</b><div className="answer-explanation">{explanationParagraphs.map((item, index) => <p className={item.option ? undefined : 'is-unlabeled'} key={`${item.option ?? 'paragraph'}-${index}`}>{item.option && <b className="answer-option-label">{item.option}</b>}<ChemText>{item.text}</ChemText></p>)}</div>{!isCorrect && resolvedScaffold && <p><CircleHelp size={16} />提示：<ChemText>{resolvedScaffold}</ChemText></p>}</div>}</article><div className="stage-actions">{!feedback ? <button ref={primaryActionRef} className="primary-button" aria-keyshortcuts="Enter" disabled={busy || selected === null || !sourceMediaReady} onClick={() => void submit()}>{busy ? '正在锁定第一次选择…' : '提交答案'}</button> : <button ref={primaryActionRef} className="primary-button" aria-keyshortcuts="Enter" disabled={busy} onClick={next}>{questionIndex < payload.questions.length - 1 ? '下一题' : `完成第 ${roundNumber} 轮`}<ChevronRight size={18} /></button>}</div></section>
  }

  const correct = answers.filter((answer) => answer.correct).length
  const unresolved = answers.filter((answer) => !answer.correct || answer.uncertain).length
  const nextPlan = nextDashboard?.plans.find((plan) => plan.id === payload.plan.id)
  const hasNextRound = roundNumber < roundLimit && (practiceMode || (nextPlan ? !nextPlan.isResolved : true))
  const nextRoundOpenState = planOpenState?.request.plan.id === payload.plan.id ? planOpenState : null
  const nextRoundLoading = nextRoundOpenState?.status === 'loading'
  return <section className="learning-stage result-stage">{roundTrack}<div className="result-badge"><Check /></div><span className="eyebrow">{practiceMode ? `演示第 ${roundNumber} 轮完成` : `今天第 ${roundNumber} 轮完成`}</span><h1>{unresolved === 0 ? '这一轮全部答对，下一轮可以提高难度。' : `还有 ${unresolved} 个知识点需要换一道原题确认。`}</h1><p>本轮答对 {correct}/{answers.length}，其中 {answers.filter((answer) => answer.uncertain).length} 题标记为不确定。{practiceMode ? '本次结果只在当前页面展示，不会写入任何真实学生档案。' : hasNextRound ? unresolved === 0 ? '下一轮每个知识点都会换成更高难度的原题。' : '下一轮会换同知识点的另一道原题；答对且确定的知识点提高难度。' : '今天的记录已交给系统整理，甘老师可在后台查看并安排后续讲解。'}</p><div className="result-stats"><div><b>{answers.length}</b><span>完成原题</span></div><div><b>{new Set(answers.map((answer) => answer.skillId)).size}</b><span>复习模块</span></div><div><b>{unresolved}</b><span>仍需确认</span></div></div>{nextRoundOpenState && onRetryPlanOpen && <PlanOpenNotice state={nextRoundOpenState} onRetry={onRetryPlanOpen} retryLabel={`重试进入第 ${roundNumber + 1} 轮`} />}<div className="result-actions">{hasNextRound && <button ref={primaryActionRef} className="primary-button" aria-keyshortcuts="Enter" disabled={!nextDashboard || busy || nextRoundLoading} onClick={async () => { if (!nextDashboard) return; setBusy(true); try { await onContinue(nextDashboard, payload.plan.id, roundNumber + 1) } finally { setBusy(false) } }}>{nextRoundLoading ? `正在读取 · ${nextRoundOpenState.elapsedSeconds}秒` : nextRoundOpenState?.status === 'error' ? `重试进入第 ${roundNumber + 1} 轮` : `进入第 ${roundNumber + 1} 轮`}<ChevronRight size={18} /></button>}<button ref={hasNextRound ? undefined : primaryActionRef} className={hasNextRound ? 'secondary-button' : 'primary-button'} aria-keyshortcuts={hasNextRound ? undefined : 'Enter'} disabled={!nextDashboard || nextRoundLoading} onClick={() => nextDashboard && onComplete(nextDashboard)}>{practiceMode ? '返回演示计划' : hasNextRound ? '先回首页' : '查看今日成果'}<Trophy size={18} /></button></div></section>
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

function HydrogenCombustionEnergyVisual() {
  return <figure className="hydrogen-energy-visual" aria-label="H₂燃烧生成液态水的放热反应能量图">
    <figcaption><span>例子配图</span><b>H₂燃烧：两种高度差不能混</b></figcaption>
    <div className="hydrogen-energy-equation"><ChemText>2H₂(g) + O₂(g) → 2H₂O(l)</ChemText><strong>放热｜ΔH＜0</strong></div>
    <svg className="hydrogen-energy-svg-desktop" viewBox="0 0 640 370" role="img" aria-labelledby="hydrogen-energy-title hydrogen-energy-desc">
      <title id="hydrogen-energy-title">氢气燃烧生成液态水的放热反应能量图</title>
      <desc id="hydrogen-energy-desc">反应物能量高于生成物；反应物能量线到曲线峰顶的高度差表示正反应活化能，反应物与生成物的高度差表示焓变，体系向环境放出能量。</desc>
      <defs>
        <marker id="hydrogen-energy-arrow" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto"><path d="M0,0 L0,6 L7,3 z" /></marker>
      </defs>
      <path className="hydrogen-example-axis" d="M68 310V42M68 310H608" />
      <text className="hydrogen-axis-label" x="20" y="30">体系的焓 H</text>
      <text className="hydrogen-axis-label" x="20" y="47">（相对值）</text>
      <text className="hydrogen-axis-label" x="536" y="343">反应过程</text>
      <path className="hydrogen-example-guide" d="M88 150H550M88 252H550" />
      <path className="hydrogen-example-curve" d="M88 150 C172 150 197 70 310 70 C419 70 438 252 550 252" />
      <path className="hydrogen-example-platform" d="M88 150H177M458 252H550" />
      <text className="hydrogen-example-label" x="88" y="134">反应物</text>
      <text className="hydrogen-example-formula" x="88" y="176">2H₂(g) + O₂(g)</text>
      <text className="hydrogen-example-label" x="458" y="278">生成物</text>
      <text className="hydrogen-example-formula" x="458" y="300">2H₂O(l)</text>
      <circle className="hydrogen-example-peak" cx="310" cy="70" r="5" />
      <text className="hydrogen-peak-label" x="252" y="52">能量最高位置</text>
      <path className="hydrogen-ea-arrow" markerEnd="url(#hydrogen-energy-arrow)" d="M174 145V78" />
      <text className="hydrogen-ea-label" x="184" y="105">正反应活化能 Eₐ</text>
      <path className="hydrogen-dh-arrow" markerEnd="url(#hydrogen-energy-arrow)" d="M431 158V244" />
      <text className="hydrogen-dh-label" x="346" y="204">ΔH＜0</text>
    </svg>
    <svg className="hydrogen-energy-svg-mobile" viewBox="0 0 280 390" role="img" aria-labelledby="hydrogen-energy-mobile-title hydrogen-energy-mobile-desc">
      <title id="hydrogen-energy-mobile-title">手机竖版氢气燃烧放热反应能量图</title>
      <desc id="hydrogen-energy-mobile-desc">反应物平台较高，生成物平台较低；反应物平台到峰顶是正反应活化能，始末平台高度差是负焓变。</desc>
      <defs>
        <marker id="hydrogen-energy-mobile-arrow" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto"><path d="M0,0 L0,6 L7,3 z" /></marker>
      </defs>
      <path className="hydrogen-example-axis" d="M38 342V38M38 342H263" />
      <text className="hydrogen-axis-label" x="8" y="20">体系的焓 H（相对值）</text>
      <text className="hydrogen-axis-label" x="194" y="370">反应过程</text>
      <path className="hydrogen-example-guide" d="M50 126H252M50 258H252" />
      <path className="hydrogen-example-curve" d="M50 126 C96 126 105 58 145 58 C194 58 201 258 252 258" />
      <path className="hydrogen-example-platform" d="M50 126H96M210 258H252" />
      <text className="hydrogen-example-label" x="50" y="108">反应物</text>
      <text className="hydrogen-example-formula" x="50" y="151">2H₂(g)+O₂(g)</text>
      <text className="hydrogen-example-label" x="184" y="284">生成物</text>
      <text className="hydrogen-example-formula" x="174" y="309">2H₂O(l)</text>
      <circle className="hydrogen-example-peak" cx="145" cy="58" r="5" />
      <text className="hydrogen-peak-label" x="113" y="43">最高位置</text>
      <path className="hydrogen-ea-arrow" markerEnd="url(#hydrogen-energy-mobile-arrow)" d="M97 120V67" />
      <text className="hydrogen-ea-label" x="105" y="92">正反应 Eₐ</text>
      <path className="hydrogen-dh-arrow" markerEnd="url(#hydrogen-energy-mobile-arrow)" d="M198 134V250" />
      <text className="hydrogen-dh-label" x="150" y="197">ΔH＜0</text>
    </svg>
    <div className="hydrogen-energy-key">
      <section><b>① 看活化能</b><span>反应物能量线 → 峰顶的高度差</span></section>
      <section><b>② 看 ΔH</b><span>H（生成物）− H（反应物）＜0</span></section>
      <section><b>③ 看热量方向</b><span>体系 → 环境：放出热量</span></section>
    </div>
    <p className="hydrogen-energy-boundary"><b>别混：</b>曲线峰顶只表示反应过程中能量最高的位置；峰顶本身不是活化能，峰顶高度也不是 ΔH。这是能量变化示意图，不表示氢气燃烧只有一个反应步骤。</p>
  </figure>
}

function PermanganateIronBalanceVisual() {
  return <figure className="redox-balance-visual" aria-label="酸性高锰酸根与亚铁离子配平五步图">
    <figcaption><span>配平图</span><b>酸性 MnO₄⁻ + Fe²⁺：沿箭头走五步</b></figcaption>
    <ol className="redox-balance-steps">
      <li className="redox-step redox-step-change">
        <header><span>01</span><b>标变价</b></header>
        <div className="redox-change-lanes">
          <section className="redox-mn-lane"><small>Mn</small><b>+7</b><i aria-hidden="true">↓</i><b>+2</b><strong>得 5e⁻</strong><em><ChemText>MnO₄⁻ 被还原｜发生还原反应｜氧化剂 → Mn²⁺ 还原产物</ChemText></em></section>
          <section className="redox-fe-lane"><small>Fe</small><b>+2</b><i aria-hidden="true">↑</i><b>+3</b><strong>失 1e⁻</strong><em><ChemText>Fe²⁺ 被氧化｜发生氧化反应｜还原剂 → Fe³⁺ 氧化产物</ChemText></em></section>
        </div>
      </li>
      <li className="redox-step redox-step-electron">
        <header><span>02</span><b>电子数相等</b></header>
        <div className="redox-electron-balance">
          <section><small>1 个 Mn</small><b>得 5e⁻</b></section><i aria-hidden="true">＝</i><section><small>5 个 Fe</small><b>共失 5e⁻</b></section>
        </div>
        <div className="redox-ratio"><ChemText>MnO₄⁻ ∶ Fe²⁺ ＝ 1 ∶ 5</ChemText></div>
      </li>
      <li className="redox-step redox-step-half">
        <header><span>03</span><b>酸性介质补 H、O</b></header>
        <div className="redox-acid-additions"><span><b>先补 O</b>右侧 + 4H₂O</span><i aria-hidden="true">→</i><span><b>再补 H</b>左侧 + 8H⁺</span></div>
        <div className="redox-half-reactions">
          <section><small>Mn 得电子</small><strong><ChemText>MnO₄⁻ + 8H⁺ + 5e⁻ → Mn²⁺ + 4H₂O</ChemText></strong></section>
          <section><small>Fe 失电子｜整体 ×5</small><strong><ChemText>5Fe²⁺ → 5Fe³⁺ + 5e⁻</ChemText></strong></section>
        </div>
        <div className="redox-electron-cancel"><span>5e⁻</span><b>相加后对消</b><span>5e⁻</span></div>
      </li>
      <li className="redox-step redox-step-result">
        <header><span>04</span><b>写出总方程式</b></header>
        <strong className="redox-final-equation"><ChemText>MnO₄⁻ + 5Fe²⁺ + 8H⁺ → Mn²⁺ + 5Fe³⁺ + 4H₂O</ChemText></strong>
      </li>
      <li className="redox-step redox-step-check">
        <header><span>05</span><b>三项校验</b></header>
        <div className="redox-check-grid">
          <section><b>✓ 原子</b><span>Mn 1＝1｜Fe 5＝5</span><span>H 8＝8｜O 4＝4</span></section>
          <section><b>✓ 电荷</b><span>左：−1+10+8＝+17</span><span>右：2+15＝+17</span></section>
          <section><b>✓ 电子</b><span>Mn 得 5e⁻＝5Fe 共失 5e⁻</span></section>
        </div>
        <p className="redox-medium-boundary"><b>条件：</b>题目明确为酸性，且 Mn 的还原产物是 Mn²⁺。</p>
      </li>
    </ol>
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
    {skillId === 'H2_K' || skillId === 'H3_EQUILIBRIUM' ? <EquilibriumConstantFormulaVisual /> : null}
    <details className="full-explanation"><summary><span><b>从零学会</b><small>展开完整讲解、例子、易错边界与自查</small></span><i aria-hidden="true">⌄</i></summary><div className="classification-map">
      {content.rootTree ? <section className="knowledge-tree-panel" aria-labelledby="knowledge-tree-title"><div className="map-section-title"><span>01</span><div><h2 id="knowledge-tree-title">知识总树</h2><p>先沿纵向主干走完，再补横向标签。</p></div></div><ul className="knowledge-tree"><KnowledgeBranch node={content.rootTree} /></ul></section> : null}
      {content.sections.map((section, index) => <section className="classification-section" key={section.title}><div className="map-section-title"><span>{String(index + offset).padStart(2, '0')}</span><div><h2><ChemText>{section.title}</ChemText></h2>{section.summary && <p><ChemText>{section.summary}</ChemText></p>}</div></div><div className="classification-items">{section.items.map((item) => <details className="classification-item" key={item.label}><summary className="classification-item-summary"><span><ChemText>{item.label}</ChemText></span><i aria-hidden="true">⌄</i></summary><div className="classification-item-body point-with-demo"><div className="point-copy"><p><ChemText>{item.rule}</ChemText></p>{item.caution && <div className="branch-caution">注意：<ChemText>{item.caution}</ChemText></div>}</div><NodeLearningAid node={item} /></div></details>)}</div></section>)}
      {content.workedExamples?.length ? <section className="classification-section worked-examples"><div className="map-section-title"><span>{String(content.sections.length + offset).padStart(2, '0')}</span><div><h2>完整例题：把逻辑一步一步走通</h2><p>先看为什么，再看怎么算或怎样判断。</p></div></div><div className="worked-example-grid">{content.workedExamples.map((example) => {
        const showHydrogenEnergyVisual = skillId === 'H2_THERMO' && example.substance === 'H₂燃烧的能量账'
        const showRedoxBalanceVisual = (skillId === 'H1_REDOX' && example.substance === '酸性MnO₄⁻氧化Fe²⁺') || (skillId === 'H3_ION_REDOX' && example.substance === '酸性MnO₄⁻配Fe²⁺')
        const showWorkedVisual = showHydrogenEnergyVisual || showRedoxBalanceVisual
        return <article className={showWorkedVisual ? 'worked-example-with-visual' : undefined} key={example.substance}><h3><ChemText>{example.substance}</ChemText></h3>{showRedoxBalanceVisual ? null : <p><ChemText>{example.path}</ChemText></p>}{showHydrogenEnergyVisual ? <HydrogenCombustionEnergyVisual /> : null}{showRedoxBalanceVisual ? <PermanganateIronBalanceVisual /> : null}<div className="example-chips">{example.labels.map((label) => <span key={label}><ChemText>{label}</ChemText></span>)}</div></article>
      })}</div></section> : null}
      {content.checkpoints?.length ? <section className="classification-section recall-check"><div className="map-section-title"><span>✓</span><div><h2>合上页面前，我应该能做到</h2><p>说不出来就回到对应小节，不需要硬撑着进入练习。</p></div></div><ul>{content.checkpoints.map((checkpoint) => <li key={checkpoint}><ChemText>{checkpoint}</ChemText></li>)}</ul></section> : null}
      {content.scopeNote ? <p className="scope-note"><b>范围说明：</b><ChemText>{content.scopeNote}</ChemText></p> : null}
    </div></details>
  </div>
}

function EmptyState({ text }: { text: string }) { return <div className="empty-state"><RotateCcw /><p>{text}</p></div> }
