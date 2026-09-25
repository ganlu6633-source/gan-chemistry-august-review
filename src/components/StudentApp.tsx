import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Bell, BookOpen, Check, ChevronRight, CircleHelp, Clock3, KeyRound, Layers3, ListFilter, Map as MapIcon, RotateCcw, Settings, ShieldCheck, Sparkles, Trophy } from 'lucide-react'
import type { FuturePlanPreviewPayload, JuniorAdaptivePayload, KnowledgeCard, KnowledgeTreeNode, KnowledgeVisualSummary, KnowledgeVisualTreeNode, LearningAttempt, LearningPlanDay, LearningRecordData, OptionPracticeProgress, Question, QuestionFeedback, SessionIdentity, StudentDashboardData, StructuredKnowledgeContent } from '../domain/types'
import { selectFocusPlan } from '../domain/focusPlan'
import { splitAnswerExplanation } from '../domain/answerExplanation'
import { buildRecoveryTargets, type KnowledgeConfidence } from '../domain/learningRecovery'
import { isStructuredKnowledgeContent } from '../domain/knowledgeContent'
import { SKILLS } from '../data/catalog'
import { LECTURE_SECTIONS, lectureUrl } from '../data/lectureCatalog'
import { accessApi, loadFuturePlanPreview, loadLearningRecord, loadQuestionAsset, loadQuestionFeedback, openJuniorAdaptiveSession, previewQuestionFeedback, submitAttempt, teacherApi, type LoadedQuestionAsset, type QuestionAssetAccessContext } from '../lib/api'
import { AbilityMap } from './AbilityMap'
import { ChemText } from './ChemText'
import { EquilibriumConstantFormulaVisual } from './EquilibriumConstantFormulaVisual'
import { LearningRecordPanel } from './LearningRecordPanel'
import { JuniorAdaptiveSession } from './JuniorAdaptiveSession'
import { KnowledgeConfidencePicker, KnowledgeRepairPanel } from './KnowledgeRepairPanel'
import { QuestionSourceMedia } from './QuestionSourceMedia'
import { SourceInformedChemVisual } from './SourceInformedChemVisuals'
import { supportsSourceInformedChemVisual } from './sourceInformedChemVisualSupport'
import { StudentVideoSection } from './VideoLearning'
import { StudyLibrary, type StudyTopic } from './StudyLibrary'
import { HIGH1_SEMESTER_REMAINING_DAYS } from '../data/high1SemesterRoadmap'

type StudentView = 'choose' | 'today' | 'stage' | 'directory' | 'type' | 'reminders' | 'map' | 'growth' | 'settings'
type IssuedQuestion = Omit<Question, 'correctOption' | 'explanation' | 'scaffold'> & Partial<Pick<Question, 'correctOption' | 'explanation' | 'scaffold'>>
export type PlanPayload = {
  plan: LearningPlanDay
  simulationTopic?: { skillId: string; conceptKey: string; releaseId: string }
  cards: KnowledgeCard[]
  questions: IssuedQuestion[]
  /** Existing server-locked answers returned only when resuming this round. */
  lockedFeedback?: QuestionFeedback[]
  optionPractice?: OptionPracticeProgress[]
  /** Original group size before the server inserts option-specific practice. */
  baseQuestionCount?: number
  attemptSequence: number
  roundNumber: number
  roundLimit: number
  questionCount: number
  isResolved: boolean
  isComplete: boolean
  roundsRemaining: number
}

const PLAN_OPEN_TIMEOUT_MS = 15_000
const PLAN_PREFETCH_TTL_MS = 30_000

type PlanOpenRequest = {
  plan: LearningPlanDay
  previewRound?: number
}

type PlanOpenState = {
  status: 'loading' | 'error'
  request: PlanOpenRequest
  elapsedSeconds: number
  error?: string
  retryable?: boolean
}

type PlanStartResult = { payload: PlanPayload | JuniorAdaptivePayload }
type PlanRequestEntry = {
  controller: AbortController
  expiresAt: number
  promise: Promise<PlanStartResult>
}

function planRequestKey(plan: LearningPlanDay, identityKey: string, previewRound?: number) {
  return [identityKey, plan.id, plan.attemptCount, plan.deliveryMode ?? '', previewRound ?? 'current'].join(':')
}

function planOpenProgress(elapsedSeconds: number) {
  return {
    title: '正在取题，马上开练',
    detail: elapsedSeconds < 5 ? '正在把这组知识卡和原题送过来。' : '取题比平时慢一些；如果等太久，可以点重试。',
  }
}

function PlanOpenNotice({ state, onRetry, retryLabel = '重新打开题组', showRetryButton = false }: { state: PlanOpenState; onRetry: () => void; retryLabel?: string; showRetryButton?: boolean }) {
  if (state.status === 'error') return <div className="plan-open-notice is-error" role="alert">
    <div><b>所选题组还没有打开</b><span>{state.error}</span><small>{state.retryable === false ? '这是教师只读预览的安全边界；不会向学生作答接口发送请求，也不会产生学习记录。' : '当前页面和已有学习记录都保留；重试只会重新读取题组，不会重复提交答案。'}</small></div>
    {showRetryButton && state.retryable !== false && <button type="button" className="secondary-button compact" onClick={onRetry}><RotateCcw />{retryLabel}</button>}
  </div>

  const progress = planOpenProgress(state.elapsedSeconds)
  return <div className="plan-open-notice is-loading" role="status" aria-live="polite">
    <Clock3 aria-hidden="true" />
    <div><b>{progress.title}</b><span>{progress.detail}</span><small>{state.elapsedSeconds > 0 ? `已经等了 ${state.elapsedSeconds} 秒，题组还在路上。` : '正在连接题库…'}</small></div>
  </div>
}

const isSingleDailyReviewPlan = (plan: LearningPlanDay | undefined) => Boolean(plan && plan.mode === 'REVIEW' && plan.roundLimit === 1 && plan.deliveryMode !== 'junior_adaptive')

const planRhythmLabel = (plan: LearningPlanDay) => {
  if (plan.deliveryMode === 'junior_adaptive') return '今日 12 道原题起步 · 基础未稳最多 15 道 · 每题作答后动态选下一题'
  if (isSingleDailyReviewPlan(plan)) return `今日 ${plan.questionCount} 道原题 · 1 个题组 · 错题次日换原题`
  return `每轮 ${plan.questionCount} 题 · 共 ${plan.roundLimit} 轮 · 当天把问题接稳`
}

const compactPlanRhythmLabel = (plan: LearningPlanDay) => {
  if (plan.deliveryMode === 'junior_adaptive') return `今日自适应原题 · ${plan.estimatedMinutes}分钟`
  if (isSingleDailyReviewPlan(plan)) return `今日${plan.questionCount}道原题 · 1个题组 · ${plan.estimatedMinutes}分钟`
  return `每轮${plan.questionCount}题 · ${plan.roundLimit}轮 · ${plan.estimatedMinutes}分钟`
}

const nextRoundLabel = (plan: LearningPlanDay) => {
  if (plan.deliveryMode === 'junior_adaptive') return plan.isComplete ? '今天已完成' : plan.juniorSessionStatus === 'active' ? '继续今日学习' : '开始今日学习'
  if (isSingleDailyReviewPlan(plan)) return plan.isResolved ? '今日题组已接稳' : plan.isComplete || plan.attemptCount >= 1 ? '今日题组已完成' : '开始今日题组'
  if (plan.isResolved) return '今日问题已接稳'
  if (plan.isComplete || plan.attemptCount >= plan.roundLimit) return `今日 ${plan.roundLimit} 轮已完成`
  return plan.attemptCount === 0 ? '开始第一轮' : `继续第 ${plan.attemptCount + 1} 轮`
}

const statusLabel = (plan: LearningPlanDay, enrollment: string) => {
  if (plan.deliveryMode === 'junior_adaptive' && plan.isComplete) return '今日自适应学习已完成'
  if (plan.date < enrollment) return '加入前｜可补学'
  if (plan.attemptCount > 0) {
    if (isSingleDailyReviewPlan(plan)) return plan.isResolved ? '今日题组已接稳' : plan.isComplete || plan.attemptCount >= 1 ? '今日题组已完成' : '今日题组进行中'
    if (plan.isResolved) return `第 ${plan.attemptCount} 轮已接稳`
    if (plan.isComplete || plan.attemptCount >= plan.roundLimit) return `今日 ${plan.roundLimit} 轮已完成`
    if (plan.latestCompletedAt && plan.date > plan.latestCompletedAt.slice(0, 10)) return '已提前完成'
    if (plan.firstScore !== null && plan.latestScore !== null && plan.latestScore > plan.firstScore) return `复习后提升 ${plan.firstScore}→${plan.latestScore}`
    return `已完成 ${plan.attemptCount}/${plan.roundLimit} 轮`
  }
  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
  // A past plan is not evidence that the student has learned it. The plan
  // itself may be waiting for its very first attempt, so make the catch-up
  // action explicit. Only attemptCount tells us whether this is review.
  if (plan.date < today) return plan.attemptCount > 0 ? '可再次复习' : '补学第一轮'
  if (plan.date > today) return '可提前预习'
  return '今天'
}

export function StudentApp({ session, initialDashboard, onDashboard, previewMode = false }: { session: SessionIdentity; initialDashboard: StudentDashboardData; onDashboard: (data: StudentDashboardData) => void; previewMode?: boolean }) {
  const [view, setView] = useState<StudentView>('choose')
  const [dashboard, setDashboard] = useState(initialDashboard)
  const [activePlan, setActivePlan] = useState<PlanPayload | null>(null)
  const [activeJuniorPlan, setActiveJuniorPlan] = useState<JuniorAdaptivePayload | null>(null)
  const [activeFuturePreview, setActiveFuturePreview] = useState<FuturePlanPreviewPayload | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [planOpenState, setPlanOpenState] = useState<PlanOpenState | null>(null)
  const [studyTopics, setStudyTopics] = useState<StudyTopic[]>([])
  const [studyCatalogLoading, setStudyCatalogLoading] = useState(false)
  const [studyCatalogError, setStudyCatalogError] = useState('')
  const [studyCatalogRevision, setStudyCatalogRevision] = useState(0)
  const studyCatalogLoadedKey = useRef('')
  const studyCatalogRequest = useRef<{ key: string; promise: Promise<StudyTopic[]> } | null>(null)
  const planOpenRequestId = useRef(0)
  const planOpenAbort = useRef<AbortController | null>(null)
  const planRequestCache = useRef(new Map<string, PlanRequestEntry>())
  const planRequestDisposeTimer = useRef<number | null>(null)

  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
  const visiblePlans = useMemo(() => dashboard.plans.filter((plan) => plan.deliveryMode !== 'self_study').sort((a, b) => a.date.localeCompare(b.date)), [dashboard.plans])
  const plannedDates = new Set(visiblePlans.map((plan) => plan.date))
  const high1PendingDays = HIGH1_SEMESTER_REMAINING_DAYS.filter((day) => !plannedDates.has(day.date))
  const high1ReleasedDays = [...plannedDates].filter((date) => date >= '2026-09-12' && date <= '2026-12-11').length
  const todayPlan = selectFocusPlan(visiblePlans, today)
  const duePlans = visiblePlans.filter((plan) => plan.date <= today && !plan.isComplete)
  const completedPlans = visiblePlans.filter((plan) => plan.date <= today && plan.isComplete)
  const planRequestIdentityKey = [session.role, dashboard.profile.id, session.expiresAt].join(':')
  const todayPlanIsFuturePreview = Boolean(todayPlan && todayPlan.date > today)
  const todayPlanIsCatchUp = Boolean(todayPlan && todayPlan.date < today)
  const dueSkillCount = dashboard.skillStates.filter((state) => state.nextReviewAt && Date.parse(state.nextReviewAt) <= Date.now() && (state.verifiedLevel > 0 || state.consecutiveErrors > 0)).length
  const recommendedReviews = useMemo(() => {
    const distinct = new Map<string, StudyTopic>()
    for (const topic of studyTopics.filter((item) => item.reviewPriority > 0)
      .sort((a, b) => b.reviewPriority - a.reviewPriority || b.freshCount - a.freshCount)) {
      const key = `${topic.skillId}|${topic.conceptKey}`
      if (!distinct.has(key) || (!distinct.get(key)!.freshCount && topic.freshCount)) distinct.set(key, topic)
    }
    return [...distinct.values()].sort((a, b) => b.reviewPriority - a.reviewPriority)
  }, [studyTopics])
  const nextTeachingPlan = visiblePlans.find((plan) => plan.date >= today && !plan.isComplete)
  const recommendedNewTopic = useMemo(() => {
    const focus = nextTeachingPlan?.skillIds ?? []
    return [...studyTopics].filter((topic) => topic.freshCount > 0 && topic.answeredCount === 0)
      .sort((a, b) => Number(focus.includes(b.skillId)) - Number(focus.includes(a.skillId)) || a.sequence - b.sequence)[0]
  }, [nextTeachingPlan, studyTopics])

  useEffect(() => {
    if (!['stage', 'directory', 'type', 'reminders'].includes(view)
      && !(view === 'choose' && !dashboard.profile.isDemo)) return
    const catalogKey = `${dashboard.profile.id}:${studyCatalogRevision}`
    if (studyCatalogLoadedKey.current === catalogKey) return
    let active = true
    setStudyCatalogLoading(true)
    setStudyCatalogError('')
    if (studyCatalogRequest.current?.key !== catalogKey) {
      const promise = accessApi<{ catalog: { topics: StudyTopic[] } }>(session, 'self_study_catalog', previewMode || dashboard.profile.isDemo ? { studentId: dashboard.profile.id } : {})
        .then((result) => result.catalog.topics)
      studyCatalogRequest.current = { key: catalogKey, promise }
      void promise.catch(() => { if (studyCatalogRequest.current?.promise === promise) studyCatalogRequest.current = null })
    }
    studyCatalogRequest.current.promise
      .then((topics) => { if (active) { setStudyTopics(topics); studyCatalogLoadedKey.current = catalogKey } })
      .catch((reason) => { if (active) setStudyCatalogError(reason instanceof Error ? reason.message : '原题目录暂时无法读取。') })
      .finally(() => { if (active) setStudyCatalogLoading(false) })
    return () => { active = false }
  }, [session, dashboard.profile.id, dashboard.profile.isDemo, studyCatalogRevision, view, previewMode])

  const ensurePlanRequest = useCallback((plan: LearningPlanDay, previewRound?: number) => {
    const key = planRequestKey(plan, planRequestIdentityKey, previewRound)
    const cached = planRequestCache.current.get(key)
    if (cached && cached.expiresAt > Date.now()) return cached
    if (cached) {
      cached.controller.abort()
      planRequestCache.current.delete(key)
    }
    const controller = new AbortController()
    const promise = (plan.deliveryMode === 'junior_adaptive'
      ? previewMode
        ? accessApi<{ payload: JuniorAdaptivePayload }>(session, 'preview_junior_open_session', { studentId: dashboard.profile.id, planId: plan.id }, { signal: controller.signal })
        : openJuniorAdaptiveSession(session, plan.id, { signal: controller.signal })
      : previewMode
        ? accessApi<{ payload: PlanPayload }>(session, 'preview_start_plan', { studentId: dashboard.profile.id, planId: plan.id, ...(previewRound ? { previewRound } : {}) }, { signal: controller.signal })
        : accessApi<{ payload: PlanPayload }>(session, 'start_plan', { planId: plan.id, ...(dashboard.profile.isDemo ? { studentId: dashboard.profile.id, ...(previewRound ? { previewRound } : {}) } : {}) }, { signal: controller.signal })) as Promise<PlanStartResult>
    const entry = { controller, expiresAt: Date.now() + PLAN_PREFETCH_TTL_MS, promise }
    planRequestCache.current.set(key, entry)
    void promise.catch(() => {
      if (planRequestCache.current.get(key) === entry) planRequestCache.current.delete(key)
    })
    return entry
  }, [dashboard.profile.id, dashboard.profile.isDemo, planRequestIdentityKey, previewMode, session])

  useEffect(() => {
    if (
      !todayPlan
      || todayPlan.date > today
      || todayPlan.isComplete
      || todayPlan.mode !== 'REVIEW'
      || todayPlan.deliveryMode === 'junior_adaptive'
      || previewMode
      || !['高一', '高二', '高三'].includes(dashboard.profile.gradeBand)
    ) return
    const key = planRequestKey(todayPlan, planRequestIdentityKey)
    const entry = ensurePlanRequest(todayPlan)
    const expiryTimer = window.setTimeout(() => {
      if (planRequestCache.current.get(key) === entry) {
        entry.controller.abort()
        planRequestCache.current.delete(key)
      }
    }, PLAN_PREFETCH_TTL_MS)
    return () => window.clearTimeout(expiryTimer)
  }, [dashboard.profile.gradeBand, ensurePlanRequest, planRequestIdentityKey, previewMode, today, todayPlan])

  useEffect(() => {
    const requestCache = planRequestCache.current
    if (planRequestDisposeTimer.current !== null) {
      window.clearTimeout(planRequestDisposeTimer.current)
      planRequestDisposeTimer.current = null
    }
    return () => {
      planOpenRequestId.current += 1
      planOpenAbort.current?.abort()
      // React StrictMode replays effects once in development. Defer disposal by
      // one task so that replay can retain the same in-flight prefetch instead
      // of sending a duplicate protected start_plan request.
      planRequestDisposeTimer.current = window.setTimeout(() => {
        requestCache.forEach((entry) => entry.controller.abort())
        requestCache.clear()
        planRequestDisposeTimer.current = null
      }, 0)
    }
  }, [])

  async function openPlan(plan: LearningPlanDay, previewRound?: number): Promise<boolean> {
    if (busy) return false
    if (plan.date > today) {
      setBusy(true)
      setError('')
      try {
        const result = await loadFuturePlanPreview(session, plan.id, undefined, previewMode ? dashboard.profile.id : undefined)
        setActiveFuturePreview(result.preview)
        return true
      } catch (reason) {
        setError(reason instanceof Error ? reason.message : '预习内容暂时无法打开。')
        return false
      } finally {
        setBusy(false)
      }
    }
    const request = { plan, ...(previewRound ? { previewRound } : {}) }
    const requestId = ++planOpenRequestId.current
    const key = planRequestKey(plan, planRequestIdentityKey, previewRound)
    planRequestCache.current.forEach((entry, cachedKey) => {
      if (cachedKey === key) return
      entry.controller.abort()
      planRequestCache.current.delete(cachedKey)
    })
    const planRequest = ensurePlanRequest(plan, previewRound)
    const controller = planRequest.controller
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
      const result = await Promise.race([planRequest.promise, timeoutPromise])
      if (requestId !== planOpenRequestId.current) return false
      if (planRequestCache.current.get(key) === planRequest) planRequestCache.current.delete(key)
      setPlanOpenState(null)
      if (plan.deliveryMode === 'junior_adaptive') setActiveJuniorPlan((result as { payload: JuniorAdaptivePayload }).payload)
      else setActivePlan((result as { payload: PlanPayload }).payload)
      return true
    } catch (reason) {
      if (requestId !== planOpenRequestId.current) return false
      if (planRequestCache.current.get(key) === planRequest) planRequestCache.current.delete(key)
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

  async function openSelfStudy(skillId: string, conceptKey: string, releaseId: string) {
    if (busy || dashboard.profile.isDemo) return
    setBusy(true)
    setError('')
    try {
      if (previewMode) {
        const result = await accessApi<{ payload: PlanPayload }>(session, 'preview_self_study', {
          studentId: dashboard.profile.id, skillId, conceptKey, releaseId,
        })
        setActivePlan({ ...result.payload, simulationTopic: { skillId, conceptKey, releaseId } })
        return
      }
      const result = await accessApi<{ payload: PlanPayload }>(session, 'open_self_study', { skillId, conceptKey, releaseId })
      setActivePlan(result.payload)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '这组原题暂时无法打开，请换一个知识点。')
    } finally {
      setBusy(false)
    }
  }

  async function openRecoveryStudy(skillId: string, conceptKey: string) {
    if (dashboard.profile.isDemo) throw new Error('演示账号不保存专项练习。')
    const topics = studyTopics.length ? studyTopics : (await accessApi<{ catalog: { topics: StudyTopic[] } }>(session, 'self_study_catalog', previewMode ? { studentId: dashboard.profile.id } : {})).catalog.topics
    if (!studyTopics.length) setStudyTopics(topics)
    const topic = topics
      .filter((item) => item.skillId === skillId && item.conceptKey === conceptKey && item.freshCount > 0)
      .sort((a, b) => Number(a.releaseKind !== 'primary') - Number(b.releaseKind !== 'primary') || b.freshCount - a.freshCount)[0]
    if (!topic) throw new Error('这个小点暂时没有新的已审核原题。已保留刚才的作答记录，不会拿别的题凑数。')
    await openSelfStudy(topic.skillId, topic.conceptKey, topic.releaseId)
  }

  async function switchDemoGrade(gradeBand: string) {
    if (gradeBand === dashboard.profile.gradeBand || busy) return
    planRequestCache.current.forEach((entry) => entry.controller.abort())
    planRequestCache.current.clear()
    setBusy(true)
    setError('')
    try {
      const result = await accessApi<{ dashboard: StudentDashboardData }>(session, 'demo_dashboard', { gradeBand })
      setDashboard(result.dashboard)
      onDashboard(result.dashboard)
      setView('choose')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '演示年级暂时无法切换。')
    } finally {
      setBusy(false)
    }
  }

  const retryPlanOpen = () => {
    if (!planOpenState || planOpenState.status === 'loading' || planOpenState.retryable === false) return
    void openPlan(planOpenState.request.plan, planOpenState.request.previewRound)
  }

  if (activeJuniorPlan) {
    return <JuniorAdaptiveSession session={session} initialPayload={activeJuniorPlan} previewStudentId={previewMode ? dashboard.profile.id : undefined} onExit={() => setActiveJuniorPlan(null)} onComplete={(next) => { setDashboard(next); onDashboard(next); setActiveJuniorPlan(null); setView('growth') }} />
  }

  if (activeFuturePreview) {
    return <FuturePlanPreview preview={activeFuturePreview} onExit={() => setActiveFuturePreview(null)} />
  }

  if (activePlan) {
    return <LearningRound key={`${activePlan.plan.id}:${activePlan.roundNumber}:${activePlan.attemptSequence}`} session={session} payload={activePlan} practiceMode={previewMode || Boolean(dashboard.profile.isDemo)} practiceDashboard={dashboard} studyTopics={studyTopics} onOpenFocusedTopic={openRecoveryStudy} onBrowsePractice={(next) => { setDashboard(next); onDashboard(next); setActivePlan(null); setStudyCatalogRevision((value) => value + 1); setView('directory') }} planOpenState={planOpenState?.request.plan.id === activePlan.plan.id ? planOpenState : null} onRetryPlanOpen={retryPlanOpen} onExit={() => setActivePlan(null)} onContinue={(next, planId, nextRound) => continuePlan(next, planId, nextRound)} onComplete={(next) => { setDashboard(next); onDashboard(next); setActivePlan(null); setStudyCatalogRevision((value) => value + 1); setView(activePlan.plan.deliveryMode === 'self_study' ? 'directory' : 'growth') }} />
  }

  const todayPlanOpenState = todayPlan && planOpenState?.request.plan.id === todayPlan.id ? planOpenState : null

  return (
    <>{planOpenState?.status === 'loading' && <div className="plan-opening-overlay" aria-busy="true" aria-label="正在打开题组"><section className="plan-opening-panel"><Clock3 aria-hidden="true" /><span className="eyebrow">正在准备</span><h2>正在打开“<ChemText>{planOpenState.request.plan.title}</ChemText>”</h2><p>从题库取几道好题，马上见面。</p><PlanOpenNotice state={planOpenState} onRetry={retryPlanOpen} /></section></div>}<div className="role-layout student-theme">
      <aside className="side-nav" aria-label="学生导航">
        <button className={view === 'choose' ? 'active' : ''} onClick={() => setView('choose')}><BookOpen />学习大厅</button>
        <button className={view === 'today' ? 'active' : ''} onClick={() => setView('today')}><Sparkles />学习日历</button>
        <button className={view === 'stage' ? 'active' : ''} onClick={() => setView('stage')}><Layers3 />跟着进度走</button>
        <button className={view === 'directory' ? 'active' : ''} onClick={() => setView('directory')}><Layers3 />知识点任选</button>
        <button className={view === 'type' ? 'active' : ''} onClick={() => setView('type')}><ListFilter />题型训练场</button>
        <button className={view === 'reminders' ? 'active' : ''} onClick={() => setView('reminders')}><Bell />复习雷达</button>
        <button className={view === 'map' ? 'active' : ''} onClick={() => setView('map')}><MapIcon />能力地图</button>
        <button className={view === 'growth' ? 'active' : ''} onClick={() => setView('growth')}><Trophy />我的战绩</button>
        {!previewMode && !dashboard.profile.isDemo && <button className={view === 'settings' ? 'active' : ''} onClick={() => setView('settings')}><Settings />账户设置</button>}
      </aside>
      <div className="role-content">
        {view === 'choose' && <RecommendationOverview schoolClass={dashboard.profile.schoolClass} nextPlan={nextTeachingPlan} newTopic={recommendedNewTopic} reviews={recommendedReviews} dueSkillCount={dueSkillCount} loading={studyCatalogLoading} error={studyCatalogError} busy={busy || Boolean(dashboard.profile.isDemo)} onOpenTopic={openSelfStudy} onBrowse={(nextView) => setView(nextView)} />}
        {error && <div className="inline-alert" role="alert">{error}</div>}
        {view === 'choose' && <section className="study-choice" aria-labelledby="study-choice-title">
          <div className="page-title"><span className="eyebrow">{dashboard.profile.gradeBand} · 学习大厅</span><h1 id="study-choice-title">{dashboard.profile.displayName}，今天从哪儿开练？</h1><p>跟着计划走，或自己挑想学的；走哪条路，进步都算数。</p></div>
          <div className="study-choice-grid">
            <button type="button" onClick={() => setView('today')}><Clock3 /><b>学习日历</b><span>老师排好的题在这里；前几天漏做的，也能回来补上。</span><ChevronRight /></button>
            <button type="button" onClick={() => setView('stage')}><Layers3 /><b>跟着进度走</b><span>看看学到了哪一站，从这一站挑原题练。</span><ChevronRight /></button>
            <button type="button" onClick={() => setView('directory')}><BookOpen /><b>知识点任选</b><span>今天想攻哪一块？自己点名，做完就看解析。</span><ChevronRight /></button>
            <button type="button" onClick={() => setView('type')}><ListFilter /><b>题型训练场</b><span>想练哪类选择题，就从哪类开刷。</span><ChevronRight /></button>
            <button type="button" onClick={() => setView('reminders')}><Bell /><b>复习雷达</b><span>到时间该回看的、漏做的题组，这里帮你找出来。</span><ChevronRight /></button>
          </div>
          {dashboard.profile.isDemo && <div className="demo-grade-switch"><div><span className="eyebrow">演示查看</span><h2>切换年级查看原题目录</h2></div><div>{(dashboard.profile.availableDemoGrades ?? ['初三', '高一', '高二', '高三']).map((grade) => <button key={grade} className={dashboard.profile.gradeBand === grade ? 'active' : ''} onClick={() => void switchDemoGrade(grade)} disabled={busy}>{grade}</button>)}</div></div>}
        </section>}
        {view === 'today' && <>
          <section className="welcome-banner">
            <div><span className="eyebrow">{todayPlanIsFuturePreview ? '下一次学习' : todayPlanIsCatchUp ? '补上这一站' : todayPlan?.isComplete ? '今天已完成' : '今日安排'}</span><h1>{dashboard.profile.displayName}，{todayPlanIsFuturePreview ? '下一组题已经排好啦。' : todayPlanIsCatchUp ? '这组题等你回来接着练。' : todayPlan?.isComplete ? '今天的任务完成啦！' : todayPlan ? '今天的题组备好啦！' : '今天没有日期任务，想练什么自己挑。'}</h1><p>{todayPlanIsFuturePreview ? `正式题组将在北京时间 ${todayPlan?.date} 00:00 开放；现在可以先看知识卡。` : todayPlanIsCatchUp ? `这组原本安排在 ${todayPlan?.date}，还没做完。现在回来补上，正合适。` : todayPlan?.isComplete ? '想看看答题记录，或换个知识点继续练，都可以。' : !todayPlan ? '今天可以去“知识点任选”或“题型训练场”自由开练。' : dashboard.profile.needsInitialDiagnostic ? '先做几道题找找手感，再决定从哪里学起。' : '这是老师按课堂进度安排的原题；想练别的，也可以随时自己挑。'}</p></div>
            <div className="daily-orb"><b>{todayPlan?.questionCount ?? 0}</b><span>{!todayPlan ? '今日未安排' : todayPlanIsFuturePreview ? '下次题目' : todayPlan?.deliveryMode === 'junior_adaptive' ? '今日基础题' : isSingleDailyReviewPlan(todayPlan) ? '今日原题' : '每轮题目'}</span></div>
          </section>
          <button type="button" className="text-button study-change-way" onClick={() => setView('choose')}>切换学习方式<ChevronRight size={16} /></button>
          <p className="study-pace" role="status">截至今天，日期计划已完成 {completedPlans.length}/{visiblePlans.filter((plan) => plan.date <= today).length} 组{duePlans.length ? `；还有 ${duePlans.length} 组等你补做，去“复习雷达”就能找到。` : '；目前没有漏做的题组。'}</p>
          {dashboard.profile.isDemo && <section className="demo-grade-switch" aria-label="切换演示年级"><div><span className="eyebrow">演示查看</span><h2>每一天都可以打开完整学习链路</h2><p>演示题组只读取已审核、当前范围内、可用于复习的真实原题；作答只在当前页面模拟，不写入任何正式学生记录。</p></div><div>{(dashboard.profile.availableDemoGrades ?? ['高一', '高二', '高三']).map((grade) => <button key={grade} className={dashboard.profile.gradeBand === grade ? 'active' : ''} onClick={() => void switchDemoGrade(grade)} disabled={busy}>{grade}</button>)}</div></section>}
          {todayPlan ? <section className="focus-card">
            <div className="focus-icon"><BookOpen /></div>
            <div><span className="mode-pill">{todayPlan.deliveryMode === 'junior_adaptive' ? '初中自适应学习' : todayPlan.mode === 'EXAM_SPRINT' ? '考前拿分' : '长期复习'}</span><h2><ChemText>{todayPlan.title}</ChemText></h2><div className="focus-topics">{todayPlan.knowledgeSummaries.map((topic) => <span key={topic}><ChemText>{topic}</ChemText></span>)}</div><div className="meta-row"><span><Clock3 size={15} />约{todayPlan.estimatedMinutes}分钟</span><span>{todayPlanIsFuturePreview ? `安排日期 ${todayPlan.date} · ${todayPlan.questionCount} 道起` : planRhythmLabel(todayPlan)}</span></div></div>
            <div className="focus-action"><button className="primary-button compact" onClick={() => todayPlan.isComplete ? setView('growth') : void openPlan(todayPlan)} disabled={busy}>{todayPlanIsFuturePreview ? '进入预习' : todayPlanOpenState?.status === 'loading' ? `正在读取 · ${todayPlanOpenState.elapsedSeconds}秒` : todayPlanOpenState?.status === 'error' ? `重试${nextRoundLabel(todayPlan)}` : todayPlan.isComplete ? '查看今日成果' : nextRoundLabel(todayPlan)}<ChevronRight size={18} /></button>{todayPlanOpenState?.status === 'error' && <PlanOpenNotice state={todayPlanOpenState} onRetry={retryPlanOpen} />}</div>
          </section> : <EmptyState text="甘老师还没有为今天安排正式任务。" />}
          {todayPlan && <section className="date-lecture-links"><h2>这一天对应的讲义</h2><div>{LECTURE_SECTIONS.filter((section) => section.grade === dashboard.profile.gradeBand && section.skillIds.some((skillId) => todayPlan.skillIds.includes(skillId))).slice(0, 6).map((section) => <a key={section.id} href={lectureUrl(section)} target="_blank" rel="noopener noreferrer"><BookOpen size={15} />{section.title} · 第 {section.page} 页<ChevronRight size={15} /></a>)}</div></section>}
          {planOpenState?.status === 'error' && !todayPlanOpenState && <PlanOpenNotice state={planOpenState} onRetry={retryPlanOpen} showRetryButton />}
          <StudentVideoSection session={session} videos={dashboard.videoRecommendations ?? []} readOnly={previewMode || Boolean(dashboard.profile.isDemo)} />
          {dashboard.profile.gradeBand === '高一' && <section className="semester-progress" aria-label="高一学期进度">
            <b>这学期怎么走</b><span>9 月 12 日—12 月 11 日，共 91 天。这名学生已安排 {high1ReleasedDays} 天原题；之后按教材继续学硫、元素周期律和物质结构，最后做全册回看。</span>
            {high1PendingDays.length > 0 && <span>还有 {high1PendingDays.length} 天原题正在逐题核对；现在可先在下方查看每天的知识点。</span>}
          </section>}
          {dashboard.profile.gradeBand === '高一' && high1PendingDays.length > 0 && <details className="semester-roadmap">
            <summary>查看尚待核题的 {high1PendingDays.length} 天每日知识点</summary>
            <p>这些日期的学习顺序已经排好。题干、选项和解析核对完成后才会开放对应的选择题；前面已安排的日期仍可补做。</p>
            <ol>{high1PendingDays.map((day) => <li key={day.date}><time dateTime={day.date}>{day.date.slice(5)}</time><span>{day.unit} · {day.topic}</span><small>待核题</small></li>)}</ol>
          </details>}
          <PlanCalendar plans={visiblePlans} enrollment={dashboard.profile.enrollmentStartDate} onOpen={openPlan} busy={busy} embedded />
          <section className="section-block"><div className="section-head"><div><span className="eyebrow">最近获得</span><h2>已经亮起来的部分</h2></div><button className="text-button" onClick={() => setView('growth')}>查看全部</button></div>
            <div className="achievement-grid">{dashboard.achievements.slice(0, 3).map((item) => <article className="achievement-card" key={item.id}><div className="achievement-icon"><Trophy /></div><div><b><ChemText>{item.title}</ChemText></b><p><ChemText>{item.description}</ChemText></p></div></article>)}</div>
          </section>
        </>}
        {view === 'stage' && <StudyLibrary key="stage" axis="stage" dashboard={dashboard} topics={studyTopics} loading={studyCatalogLoading} error={studyCatalogError} onStart={openSelfStudy} busy={busy} />}
        {view === 'directory' && <StudyLibrary key="knowledge" axis="knowledge" dashboard={dashboard} topics={studyTopics} loading={studyCatalogLoading} error={studyCatalogError} onStart={openSelfStudy} busy={busy} />}
        {view === 'type' && <StudyLibrary key="type" axis="type" dashboard={dashboard} topics={studyTopics} loading={studyCatalogLoading} error={studyCatalogError} onStart={openSelfStudy} busy={busy} />}
        {view === 'reminders' && <StudyReminders dashboard={dashboard} reviews={recommendedReviews} catalogLoading={studyCatalogLoading} catalogError={studyCatalogError} onOpenPlan={openPlan} onOpenTopic={openSelfStudy} busy={busy || Boolean(dashboard.profile.isDemo)} />}
        {view === 'map' && <AbilityMap dashboard={dashboard} onOpenPlan={openPlan} busy={busy} />}
        {view === 'growth' && <GrowthPage dashboard={dashboard} session={session} previewMode={previewMode} />}
        {view === 'settings' && <AccountSettings session={session} />}
      </div>
    </div></>
  )
}

function KnowledgeCardArticle({ card, position, total, eyebrow = '从零讲清楚' }: { card: KnowledgeCard; position: number; total: number; eyebrow?: string }) {
  return <article className="knowledge-card" data-testid="learning-skill-card">
    <span className="eyebrow">{eyebrow} · {position}/{total}</span>
    <h1><ChemText>{card.title}</ChemText></h1>
    {!isStructuredKnowledgeContent(card.structuredContent) || !card.structuredContent.visualSummary ? <div className="core-rule"><ChemText>{card.core}</ChemText></div> : null}
    {isStructuredKnowledgeContent(card.structuredContent)
      ? <StructuredKnowledgeMap content={card.structuredContent} skillId={card.skillId} />
      : <details open><summary>展开理解</summary><p><ChemText>{card.detail}</ChemText></p><ol>{card.steps.map((step) => <li key={step}><ChemText>{step}</ChemText></li>)}</ol><div className="mistake-note"><b>容易踩坑</b><ul>{card.commonMistakes.map((mistake) => <li key={mistake}><ChemText>{mistake}</ChemText></li>)}</ul></div><p><b>完整例子：</b><ChemText>{card.microExample}</ChemText></p></details>}
  </article>
}

export function FuturePlanPreview({ preview, onExit }: { preview: FuturePlanPreviewPayload; onExit: () => void }) {
  const [cardIndex, setCardIndex] = useState(0)
  const card = preview.cards[cardIndex]
  const lastCard = cardIndex >= preview.cards.length - 1
  const displayDate = `${Number(preview.formalOpenDate.slice(5, 7))}月${Number(preview.formalOpenDate.slice(8, 10))}日`

  return <section className="learning-stage future-plan-preview" data-testid="future-plan-preview">
    <button className="text-button" onClick={onExit}>← 返回学习计划</button>
    <div className="future-preview-banner" role="status">
      <ShieldCheck aria-hidden="true" />
      <div><span className="eyebrow">提前预习 · 只读知识页</span><h2><ChemText>{preview.plan.title}</ChemText></h2><p>这里可以提前理解知识卡；不展示正式题目、答案或提示，不创建学习会话，也不计入掌握度和正式学习记录。正式学习会在 {displayDate} 开启。</p></div>
    </div>
    <div className="review-outline"><b>本次预习什么</b>{preview.plan.knowledgeSummaries.map((topic) => <span key={topic}><ChemText>{topic}</ChemText></span>)}</div>
    <div className="stage-progress" aria-label={`预习进度 ${cardIndex + 1}/${Math.max(preview.cards.length, 1)}`}><i style={{ width: `${(cardIndex + 1) / Math.max(preview.cards.length, 1) * 100}%` }} /></div>
    {card ? <KnowledgeCardArticle card={card} position={cardIndex + 1} total={preview.cards.length} eyebrow="提前看懂" /> : <EmptyState text="这一天的知识卡尚未完成审核，暂时不能预习。" />}
    <div className="stage-actions">
      {cardIndex > 0 && <button className="secondary-button" onClick={() => setCardIndex((index) => Math.max(0, index - 1))}>上一张</button>}
      <button className="primary-button" onClick={() => { if (lastCard || !card) onExit(); else setCardIndex((index) => index + 1) }}>{lastCard || !card ? '完成预习，返回计划' : '下一张知识卡'}<ChevronRight size={18} /></button>
    </div>
    <p className="future-preview-boundary"><BookOpen size={16} />预习和正式学习是两条独立路径：预习只帮助理解，安排日期到达后仍从正式题组开始，并单独记录作答证据。</p>
  </section>
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

function RecommendationOverview({ schoolClass, nextPlan, newTopic, reviews, dueSkillCount, loading, error, busy, onOpenTopic, onBrowse }: {
  schoolClass?: string | null
  nextPlan?: LearningPlanDay
  newTopic?: StudyTopic
  reviews: StudyTopic[]
  dueSkillCount: number
  loading: boolean
  error: string
  busy: boolean
  onOpenTopic: (skillId: string, conceptKey: string, releaseId: string) => Promise<void>
  onBrowse: (view: StudentView) => void
}) {
  const firstReadyReview = reviews.find((topic) => topic.freshCount > 0)
  return <section className="study-recommendations" aria-label="新学与复习建议">
    <article><span className="eyebrow"><BookOpen size={15} /> 学点新的 · {schoolClass || '按你的进度来'}</span><h2>{newTopic ? <ChemText>{newTopic.title}</ChemText> : '新知识，随你挑'}</h2><p>{nextPlan ? `老师接下来安排了「${nextPlan.title}」。${newTopic ? '可以从这组原题热热身，也能自己挑。' : '想从哪里开始，你自己定。'}` : '每个班进度不同，今天想学哪一块？你说了算。'}</p><div className="study-recommendation-actions">{newTopic && <button className="primary-button compact" disabled={busy} onClick={() => void onOpenTopic(newTopic.skillId, newTopic.conceptKey, newTopic.releaseId)}>先来这一组<ChevronRight size={16} /></button>}<button className="secondary-button compact" onClick={() => onBrowse('directory')}>我自己挑</button></div></article>
    <article><span className="eyebrow"><RotateCcw size={15} /> 复习雷达 · 跟着你的作答走</span><h2>{reviews.length ? `${reviews.length} 个知识点来敲门啦` : dueSkillCount ? `${dueSkillCount} 个模块该回头看看` : loading ? '正在寻找该复习的知识点…' : '今天的雷达很安静'}</h2><p>{firstReadyReview?.reviewReason || (reviews.length ? '这块暂时缺同考点的新原题，先记着，不拿别的题来凑。' : '做错或拿不准的先照顾；做稳的，晚点再见。想练别的也随时可以。')}</p><div className="study-recommendation-actions">{firstReadyReview && <button className="primary-button compact" disabled={busy} onClick={() => void onOpenTopic(firstReadyReview.skillId, firstReadyReview.conceptKey, firstReadyReview.releaseId)}>去练原题<ChevronRight size={16} /></button>}<button className="secondary-button compact" onClick={() => onBrowse('reminders')}>打开复习雷达</button></div></article>
    {error && <p className="inline-alert" role="alert">{error}</p>}
  </section>
}

function StudyReminders({ dashboard, reviews, catalogLoading, catalogError, onOpenPlan, onOpenTopic, busy }: { dashboard: StudentDashboardData; reviews: StudyTopic[]; catalogLoading: boolean; catalogError: string; onOpenPlan: (plan: LearningPlanDay) => void; onOpenTopic: (skillId: string, conceptKey: string, releaseId: string) => Promise<void>; busy: boolean }) {
  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
  const overduePlans = dashboard.plans.filter((plan) => plan.deliveryMode !== 'self_study' && plan.date < today && !plan.isComplete).sort((a, b) => a.date.localeCompare(b.date))
  const readyReview = reviews.find((topic) => topic.freshCount > 0)
  return <section className="study-reminders" aria-labelledby="study-reminders-title">
    <div className="page-title"><span className="eyebrow"><Bell size={14} />看看哪些知识点该回头练</span><h1 id="study-reminders-title">复习雷达</h1><p>答错的、拿不准的、到了复查时间的，都会来这里报到。先练哪块，你说了算。</p></div>
    {catalogError && <p className="inline-alert" role="alert">{catalogError}</p>}
    {readyReview && <div className="reminder-suggestion"><div><span className="eyebrow">今天先照顾它</span><h2><ChemText>{readyReview.title}</ChemText></h2><p>{readyReview.reviewReason}</p></div><button className="primary-button compact" type="button" onClick={() => void onOpenTopic(readyReview.skillId, readyReview.conceptKey, readyReview.releaseId)} disabled={busy}>开练同考点原题<ChevronRight size={16} /></button></div>}
    <div className="reminder-columns">
      <section><h2>日历里漏做的 <small>{overduePlans.length}</small></h2>{overduePlans.length ? <div className="reminder-list">{overduePlans.map((plan) => <article key={plan.id}><div><small>{plan.date} · {plan.attemptCount > 0 ? '接着做' : '还没开始'}</small><h3><ChemText>{plan.title}</ChemText></h3><p>{plan.knowledgeSummaries.slice(0, 2).join(' · ')}</p></div><button className="secondary-button compact" type="button" onClick={() => onOpenPlan(plan)} disabled={busy}>补上这一组</button></article>)}</div> : <EmptyState text="没有漏做的题组，日历很清爽。" />}</section>
      <section><h2>该回看的知识点 <small>{reviews.length}</small></h2>{catalogLoading ? <p>正在找你该回看的知识点…</p> : reviews.length ? <div className="reminder-list">{reviews.map((topic) => <article key={`${topic.skillId}:${topic.conceptKey}`}><div><small>提醒日期 {topic.reviewDueAt ? new Date(topic.reviewDueAt).toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' }) : ''} · 练过 {topic.answeredCount} 道</small><h3><ChemText>{topic.title}</ChemText></h3><p>{topic.reviewReason}</p></div>{topic.freshCount > 0 ? <button className="secondary-button compact" type="button" onClick={() => void onOpenTopic(topic.skillId, topic.conceptKey, topic.releaseId)} disabled={busy}>再练这块</button> : <small>暂无同考点新题</small>}</article>)}</div> : <EmptyState text="今天没有到点的知识点。想多练，也可以去“知识点任选”。" />}</section>
    </div>
  </section>
}

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
  return <section className={embedded ? 'home-plan section-block' : undefined} aria-labelledby="learning-plan-title"><div className="page-title"><span className="eyebrow">{displayDate(first)}—{displayDate(last)}</span>{embedded ? <h2 id="learning-plan-title">我的学习日历</h2> : <h1 id="learning-plan-title">我的学习日历</h1>}<p>老师安排的题组都在这里。前面漏做的可以补上；后面的可以先看知识卡，正式题目要到安排的日期才能做。</p></div>
    <div className="week-stack">{weeks.map((week, index) => { const currentWeek = week.some((plan) => plan.date === today); const nextWeek = week.some((plan) => plan.date === nextDate); return <div className={`week-card ${currentWeek ? 'is-current-week' : nextWeek ? 'is-next-week' : ''}`} key={week[0]?.date ?? index}><div className="week-label">{displayDate(week[0]?.date)}{week.length > 1 && `—${displayDate(week.at(-1)?.date)}`}{currentWeek ? ' · 今天已点亮' : nextWeek ? ' · 下一次安排' : ''}</div><div className="week-grid">{week.map((plan) => { const isToday = plan.date === today; const isNext = plan.date === nextDate; const isFuture = plan.date > today; return <button key={plan.id} ref={isToday || isNext ? focusButton : undefined} className={`plan-day ${isToday ? 'is-today' : isNext ? 'is-next' : ''} ${isFuture ? 'is-future-preview' : ''}`} aria-current={isToday ? 'date' : undefined} aria-label={isFuture ? `${plan.title}，可提前预习` : undefined} title={isFuture ? '提前预习只展示知识卡，不展示题目，也不计入学习记录' : undefined} onClick={() => onOpen(plan)} disabled={busy}><span className="plan-date">{plan.date.slice(5)} · {weekdayLabel(plan.date)}</span>{isToday ? <span className="plan-today-badge" aria-hidden="true">今天</span> : isNext ? <span className="plan-next-badge">下一次</span> : null}<b><ChemText>{plan.title}</ChemText></b><ul>{plan.knowledgeSummaries.map((topic) => <li key={topic}><ChemText>{topic}</ChemText></li>)}</ul><small>{isFuture ? '知识卡预习 · 不含正式题目' : compactPlanRhythmLabel(plan)}</small><em>{statusLabel(plan, enrollment)}</em></button> })}</div></div> })}</div>
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
  return <LearningRecordPanel record={record} gradeBand={dashboard.profile.gradeBand} audience="student" />
}

export function LearningRound({ session, payload, practiceMode = false, practiceDashboard, studyTopics = [], onOpenFocusedTopic, onBrowsePractice, planOpenState = null, onRetryPlanOpen, onExit, onContinue, onComplete }: { session: SessionIdentity; payload: PlanPayload; practiceMode?: boolean; practiceDashboard?: StudentDashboardData; studyTopics?: StudyTopic[]; onOpenFocusedTopic?: (skillId: string, conceptKey: string) => Promise<void>; onBrowsePractice?: (data: StudentDashboardData) => void; planOpenState?: PlanOpenState | null; onRetryPlanOpen?: () => void; onExit: () => void; onContinue: (data: StudentDashboardData, planId: string, nextRound: number) => Promise<void>; onComplete: (data: StudentDashboardData) => void }) {
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
  const [phase, setPhase] = useState<'cards' | 'quiz' | 'result' | 'repair'>(payload.plan.deliveryMode === 'self_study' ? 'quiz' : roundNumber === 1 && initialAnswers.length === 0 ? 'cards' : 'quiz')
  const [cardIndex, setCardIndex] = useState(0)
  const [questions, setQuestions] = useState(payload.questions)
  const [questionIndex, setQuestionIndex] = useState(initialQuestionIndex)
  const [selected, setSelected] = useState<number | null>(resumedFeedback?.selectedOption ?? null)
  const [answers, setAnswers] = useState<LearningAttempt['answers']>(initialAnswers)
  const [startedAt] = useState(new Date().toISOString())
  const [questionStartedAt, setQuestionStartedAt] = useState(Date.now())
  const [feedback, setFeedback] = useState(Boolean(resumedFeedback))
  const [serverFeedback, setServerFeedback] = useState<Record<string, QuestionFeedback>>(initialServerFeedback)
  const [optionPractice, setOptionPractice] = useState(payload.optionPractice ?? [])
  const [cardRatings, setCardRatings] = useState<Record<string, KnowledgeConfidence>>({})
  const [repairTargetKey, setRepairTargetKey] = useState<string | null>(null)
  const [repairError, setRepairError] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [nextDashboard, setNextDashboard] = useState<StudentDashboardData | null>(null)
  const [primaryMediaReady, setPrimaryMediaReady] = useState<Record<string, boolean>>({})
  const primaryActionRef = useRef<HTMLButtonElement>(null)
  const sourceAssetRequests = useRef(new Map<string, Promise<{ asset: LoadedQuestionAsset }>>())
  const card = payload.cards[cardIndex]
  const question = questions[questionIndex]
  const selfStudy = payload.plan.deliveryMode === 'self_study'
  const singleDailyReviewPackage = payload.plan.mode === 'REVIEW' && roundLimit === 1 && !selfStudy
  const conceptTitles = Object.fromEntries(studyTopics.map((topic) => [topic.conceptKey, topic.title]))
  const recoveryTargets = buildRecoveryTargets({ questions, answers, branches: optionPractice, cards: payload.cards, cardRatings, conceptTitles })
  const activeRepairTarget = recoveryTargets.find((target) => target.key === repairTargetKey)

  async function startFocusedPractice(skillId: string, conceptKey: string) {
    if (!onOpenFocusedTopic || busy) return
    setBusy(true)
    setRepairError('')
    try {
      await onOpenFocusedTopic(skillId, conceptKey)
    } catch (reason) {
      setRepairError(reason instanceof Error ? reason.message : '专项原题暂时无法打开。')
    } finally {
      setBusy(false)
    }
  }

  const cachedQuestionAssetLoader = useCallback((
    activeSession: SessionIdentity,
    questionId: string,
    assetId: string,
    assetPhase: 'question' | 'analysis',
    context?: QuestionAssetAccessContext,
  ) => {
    const key = [
      questionId,
      assetId,
      assetPhase,
      context?.planId ?? '',
      context?.attemptSequence ?? '',
      context?.revisionToken ?? '',
      context?.previewRound ?? '',
      context?.studentId ?? '',
    ].join('|')
    const cached = sourceAssetRequests.current.get(key)
    if (cached) return cached
    const request = loadQuestionAsset(activeSession, questionId, assetId, assetPhase, context)
      .catch((reason) => {
        if (sourceAssetRequests.current.get(key) === request) sourceAssetRequests.current.delete(key)
        throw reason
      })
    sourceAssetRequests.current.set(key, request)
    return request
  }, [])

  useEffect(() => {
    let active = true
    async function prefetchIssuedQuestionImages() {
      // Keep the current and next original warm without filling the network
      // with images for the whole round while an answer is being submitted.
      for (const issuedQuestion of questions.slice(questionIndex, questionIndex + 2)) {
        if (!active) return
        const isLicensedReview = payload.plan.mode === 'REVIEW'
          && ['高一', '高二', '高三'].includes(issuedQuestion.gradeBand)
          && issuedQuestion.sourceKind === 'licensed_local'
        if (!isLicensedReview && !issuedQuestion.secureFeedbackRequired) continue
        const context: QuestionAssetAccessContext = {
          ...(practiceMode && practiceDashboard ? { studentId: practiceDashboard.profile.id, previewRound: roundNumber } : {}),
          planId: payload.plan.id,
          attemptSequence: payload.attemptSequence,
          revisionToken: issuedQuestion.revisionToken ?? null,
        }
        for (const ref of issuedQuestion.assetRefs?.filter((item) => item.kind !== 'analysis_image') ?? []) {
          if (!active) return
          try {
            const result = await cachedQuestionAssetLoader(session, issuedQuestion.id, ref.assetId, 'question', context)
            if (typeof Image !== 'undefined') {
              const image = new Image()
              image.src = result.asset.dataUrl
              try { await image.decode() } catch { /* The visible image still has its normal retry/error path. */ }
            }
          } catch {
            // Prefetch is best-effort; the visible media component reports errors and permits retry.
          }
        }
      }
    }
    void prefetchIssuedQuestionImages()
    return () => {
      active = false
    }
  }, [cachedQuestionAssetLoader, payload.attemptSequence, payload.plan.id, payload.plan.mode, questionIndex, questions, practiceDashboard, practiceMode, roundNumber, session])

  useEffect(() => () => sourceAssetRequests.current.clear(), [])

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

  const roundTrack = <div className="round-track" aria-label={selfStudy ? '自主原题关卡' : singleDailyReviewPackage ? '今日复习题组' : `今天共${roundLimit}轮，当前第${roundNumber}轮`}>{Array.from({ length: roundLimit }, (_, index) => <span key={index} className={index + 1 < roundNumber ? 'done' : index + 1 === roundNumber ? 'current' : ''}><i>{index + 1}</i><b>{selfStudy ? '原题关卡' : singleDailyReviewPackage ? '今日题组' : index + 1 === roundNumber ? '本轮' : index + 1 < roundNumber ? '完成' : '待检验'}</b></span>)}</div>

  if (phase === 'repair' && activeRepairTarget) {
    const reviewCard = payload.cards.find((item) => item.skillId === activeRepairTarget.skillId)
    const reviewExplanation = activeRepairTarget.anchorQuestionId ? serverFeedback[activeRepairTarget.anchorQuestionId]?.explanation : undefined
    const topicByConcept = new Map<string, StudyTopic>()
    studyTopics.filter((topic) => topic.skillId === activeRepairTarget.skillId)
      .sort((a, b) => Number(b.freshCount > 0) - Number(a.freshCount > 0) || Number(a.releaseKind !== 'primary') - Number(b.releaseKind !== 'primary') || b.freshCount - a.freshCount)
      .forEach((topic) => { if (!topicByConcept.has(topic.conceptKey)) topicByConcept.set(topic.conceptKey, topic) })
    const practiceTopics = [...topicByConcept.values()].sort((a, b) => Number(b.conceptKey === activeRepairTarget.conceptKey) - Number(a.conceptKey === activeRepairTarget.conceptKey) || b.freshCount - a.freshCount || a.sequence - b.sequence)
    return <><KnowledgeRepairPanel key={activeRepairTarget.key} target={activeRepairTarget} card={reviewCard} explanation={reviewExplanation}
      practiceTopics={practiceTopics}
      onBack={() => { setRepairError(''); setPhase('result') }}
      onPractice={onOpenFocusedTopic && !practiceMode ? (conceptKey) => startFocusedPractice(activeRepairTarget.skillId, conceptKey) : undefined}
      onRating={(point, rating) => setCardRatings((current) => ({ ...current, [`${activeRepairTarget.key}:${point}`]: rating }))}
      practiceBusy={busy} />{repairError && <p className="inline-alert repair-error" role="alert">{repairError}</p>}</>
  }

  if (phase === 'cards') return <section className="learning-stage"><button className="text-button" onClick={onExit}>← 返回计划</button>{roundTrack}<div className="review-outline"><b>今天复习什么</b>{payload.plan.knowledgeSummaries.map((topic) => <span key={topic}><ChemText>{topic}</ChemText></span>)}</div><div className="stage-progress"><i style={{ width: `${(cardIndex + 1) / Math.max(payload.cards.length, 1) * 100}%` }} /></div>{card ? <><KnowledgeCardArticle card={card} position={cardIndex + 1} total={payload.cards.length} /><KnowledgeConfidencePicker value={cardRatings[card.id]} onChange={(rating) => setCardRatings((current) => ({ ...current, [card.id]: rating }))} /></> : <EmptyState text="本轮知识卡正在审核，暂不向学生展示。" />}
    <div className="stage-actions"><button className="secondary-button" onClick={onExit}>稍后再学</button><button ref={primaryActionRef} className="primary-button" aria-keyshortcuts="Enter" onClick={() => { if (cardIndex < payload.cards.length - 1) setCardIndex(cardIndex + 1); else setPhase('quiz') }}>{cardIndex < payload.cards.length - 1 ? '下一张' : '开始练习'}<ChevronRight size={18} /></button></div></section>

  if (phase === 'quiz' && question) {
    const isLicensedReview = payload.plan.mode === 'REVIEW' && ['高一', '高二', '高三'].includes(question.gradeBand) && question.sourceKind === 'licensed_local'
    const requiresServerFeedback = question.secureFeedbackRequired === true || isLicensedReview
    const hasLocalFeedbackContract = Number.isInteger(question.correctOption) && typeof question.explanation === 'string'
    const currentServerFeedback = serverFeedback[question.id]
    const resolvedCorrectOption = currentServerFeedback?.correctOption ?? question.correctOption
    const resolvedExplanation = currentServerFeedback?.explanation ?? question.explanation ?? ''
    const resolvedScaffold = currentServerFeedback?.scaffold ?? question.scaffold
    const isCorrect = requiresServerFeedback ? currentServerFeedback?.correct === true : selected === question.correctOption
    const isImagePrimary = requiresServerFeedback && question.renderMode === 'image_primary'
    const sourceMediaReady = !isImagePrimary || primaryMediaReady[question.id] === true
    const sourceAssetContext: QuestionAssetAccessContext = {
      ...(practiceMode && practiceDashboard ? { studentId: practiceDashboard.profile.id, previewRound: roundNumber } : {}),
      planId: payload.plan.id,
      attemptSequence: payload.attemptSequence,
      revisionToken: question.revisionToken ?? null,
    }
    async function submit() {
      if (selected === null || !sourceMediaReady || busy || feedback) return
      const durationSec = Math.max(1, Math.round((Date.now() - questionStartedAt) / 1000))
      if (requiresServerFeedback) {
        setBusy(true)
        try {
          setError('')
          const input = {
            ...(session.role === 'teacher' ? { previewAnswers: answers.map((answer) => ({ questionId: answer.questionId, selectedOption: answer.selectedOption ?? -1, revisionToken: answer.revisionToken })) } : {}),
            ...(session.role === 'teacher' && payload.simulationTopic ? { previewSelfStudy: payload.simulationTopic } : {}),
            ...(practiceMode && practiceDashboard ? { studentId: practiceDashboard.profile.id, previewRound: roundNumber } : {}),
            planId: payload.plan.id,
            questionId: question.id,
            selectedOption: selected,
            uncertain: false,
            durationSec,
            revisionToken: question.revisionToken ?? null,
          }
          const result = session.role === 'teacher'
            ? await previewQuestionFeedback(input)
            : await loadQuestionFeedback(session, input)
          if (result.feedback.questionId !== question.id || result.feedback.selectedOption !== selected) {
            throw new Error('服务器反馈与当前题目不一致，请重新打开本轮练习。')
          }
          if (result.questions) {
            const issuedIds = new Set(result.questions.map((item) => item.id))
            const currentIndex = result.questions.findIndex((item) => item.id === question.id)
            if (currentIndex < 0 || issuedIds.size !== result.questions.length || questions.some((item) => !issuedIds.has(item.id))) {
              throw new Error('服务器返回的题组不完整，请重新打开本轮练习以恢复已保存的选择。')
            }
            // The server alone selects, inserts and extends practice. Keep the
            // just-answered question visible until the student chooses Next.
            setQuestions(result.questions)
            setQuestionIndex(currentIndex)
          }
          if (result.optionPractice) setOptionPractice(result.optionPractice)
          setServerFeedback((items) => ({ ...items, [question.id]: result.feedback }))
          setAnswers((items) => [...items.filter((item) => item.questionId !== question.id), { questionId: question.id, motherId: question.motherId, skillId: question.skillId, level: question.level, correct: result.feedback.correct, uncertain: result.feedback.uncertain, durationSec: result.feedback.durationSec, selectedOption: result.feedback.selectedOption, revisionToken: question.revisionToken }])
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
      setAnswers((items) => [...items.filter((item) => item.questionId !== question.id), { questionId: question.id, motherId: question.motherId, skillId: question.skillId, level: question.level, correct: selected === question.correctOption, uncertain: false, durationSec, selectedOption: selected, revisionToken: question.revisionToken }])
      setFeedback(true)
    }
    async function next() {
      if (busy) return
      const nextQuestionIndex = questions.findIndex((item) => !answers.some((answer) => answer.questionId === item.id))
      if (nextQuestionIndex >= 0) {
        const nextQuestion = questions[nextQuestionIndex]
        const resumed = serverFeedback[nextQuestion.id]
        setQuestionIndex(nextQuestionIndex)
        setSelected(resumed?.selectedOption ?? null)
        setFeedback(Boolean(resumed))
        setQuestionStartedAt(Date.now())
        return
      }
      setBusy(true)
      // Preserve the server-issued order even when some answers came from a
      // resumed session rather than this browser visit.
      const finalAnswers = questions.flatMap((item) => answers.filter((answer) => answer.questionId === item.id))
      const attempt: LearningAttempt = { id: crypto.randomUUID(), studentId: practiceDashboard?.profile.id ?? '', planDayId: payload.plan.id, attemptKind: payload.attemptSequence === 0 ? 'scheduled' : 'review', sequence: payload.attemptSequence, mode: payload.plan.mode, startedAt, completedAt: new Date().toISOString(), answers: finalAnswers, firstScore: finalAnswers.filter((answer) => answer.correct).length }
      try {
        setError('')
        if (practiceMode && practiceDashboard) {
          const simulatedPlan = practiceDashboard.plans.find((plan) => plan.id === payload.plan.id)
          const updatedPlan = simulatedPlan ? {
            ...simulatedPlan, attemptCount: Math.max(simulatedPlan.attemptCount, roundNumber),
            firstScore: simulatedPlan.firstScore ?? attempt.firstScore, latestScore: attempt.firstScore,
            latestCompletedAt: attempt.completedAt,
            isComplete: roundNumber >= roundLimit,
            roundsRemaining: Math.max(0, roundLimit - roundNumber),
          } : null
          setNextDashboard(updatedPlan ? { ...practiceDashboard, plans: practiceDashboard.plans.map((plan) => plan.id === updatedPlan.id ? updatedPlan : plan) } : practiceDashboard)
          setPhase('result')
        } else {
          const result = await submitAttempt(session, attempt)
          if (requiresServerFeedback) {
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
    const questionSkillTitle = payload.cards.find((card) => card.skillId === question.skillId)?.title
      ?? SKILLS.find((skill) => skill.id === question.skillId)?.title ?? '针对性练习'
    const explanationParagraphs = splitAnswerExplanation(resolvedExplanation)
    return <section className="learning-stage">{roundTrack}{roundNumber > 1 && <div className="round-guidance"><Sparkles /><div><b>第 {roundNumber} 轮继续同一知识点</b><p>继续练习同一知识点，结合多道题的实际作答结果安排后续复习。</p></div></div>}{error && <div className="inline-alert" role="alert">{error}</div>}<div className="quiz-head"><span>{selfStudy ? '原题闯关' : singleDailyReviewPackage ? '今日题组' : `第 ${roundNumber} 轮`} · {questionIndex + 1}/{questions.length}</span><span>{questionSkillTitle ? <ChemText>{questionSkillTitle}</ChemText> : question.skillId}</span></div><div className="stage-progress"><i style={{ width: `${(questionIndex + 1) / questions.length * 100}%` }} /></div><article className="question-card"><span className="difficulty-pill">L{question.level} 练习</span>{question.optionPractice && <p className="option-practice-context"><ChemText>{question.optionPractice.knowledgePoint}</ChemText> · 该选项对应考点 · 第{question.optionPractice.position}/{question.optionPractice.total}题</p>}{requiresServerFeedback ? <QuestionSourceMedia question={question} enabled session={session} accessContext={sourceAssetContext} assetLoader={cachedQuestionAssetLoader} nativeContent={nativeStem} showSource={false} onZoomClose={() => primaryActionRef.current?.focus()} onPrimaryReadyChange={(ready) => setPrimaryMediaReady((current) => current[question.id] === ready ? current : { ...current, [question.id]: ready })} /> : nativeStem}<div className={`option-list ${isImagePrimary ? 'source-letter-options' : ''}`}>{question.options.map((option, index) => { const letter = String.fromCharCode(65 + index); const optionLabel = isImagePrimary ? `${letter} 选项，内容见原题图` : `${letter}. ${option}`; return <button aria-label={optionLabel} disabled={feedback || busy} className={`${selected === index ? 'selected' : ''} ${feedback && index === resolvedCorrectOption ? 'correct' : ''} ${feedback && selected === index && index !== resolvedCorrectOption ? 'wrong' : ''}`} key={`${index}-${option}`} onClick={() => setSelected(index)}><span>{letter}</span>{!isImagePrimary && <ChemText>{option}</ChemText>}</button> })}</div>{isImagePrimary && !sourceMediaReady && <p className="source-submit-blocked" role="status">原题主图加载完整后才能提交，避免因缺图误答。</p>}{feedback && <div className={`answer-feedback ${isCorrect ? 'good' : 'needs-work'}`}><b>{isCorrect ? '回答正确' : `回答错误，正确选项是 ${String.fromCharCode(65 + (resolvedCorrectOption ?? 0))}`}</b><div className="answer-explanation">{explanationParagraphs.map((item, index) => <p className={item.option ? undefined : 'is-unlabeled'} key={`${item.option ?? 'paragraph'}-${index}`}>{item.option && <b className="answer-option-label">{item.option}</b>}<span className="answer-explanation-text"><ChemText>{item.text}</ChemText></span></p>)}</div>{!isCorrect && resolvedScaffold && <p><CircleHelp size={16} />提示：<ChemText>{resolvedScaffold}</ChemText></p>}</div>}</article><div className="stage-actions">{!feedback ? <button ref={primaryActionRef} className="primary-button" aria-keyshortcuts="Enter" disabled={busy || selected === null || !sourceMediaReady} onClick={() => void submit()}>{busy ? '正在提交答案…' : '提交答案'}</button> : <button ref={primaryActionRef} className="primary-button" aria-keyshortcuts="Enter" disabled={busy} onClick={next}>{questions.some((item) => !answers.some((answer) => answer.questionId === item.id)) ? '下一题' : selfStudy ? '完成本关' : singleDailyReviewPackage ? '完成今日题组' : `完成第 ${roundNumber} 轮`}<ChevronRight size={18} /></button>}</div></section>
  }

  const correct = answers.filter((answer) => answer.correct).length
  const nextPlan = nextDashboard?.plans.find((plan) => plan.id === payload.plan.id)
  const hasNextRound = roundNumber < roundLimit && (nextPlan ? !nextPlan.isResolved : true)
  const nextRoundOpenState = planOpenState?.request.plan.id === payload.plan.id ? planOpenState : null
  const nextRoundLoading = nextRoundOpenState?.status === 'loading'
  return <section className="learning-stage result-stage">
    {roundTrack}
    <div className="result-badge"><Check /></div>
    <span className="eyebrow">{singleDailyReviewPackage ? '今日题组完成' : `今天第 ${roundNumber} 轮完成`}</span>
    <h1>{correct === answers.length ? '本组全部回答正确。' : `本组答对 ${correct}/${answers.length} 题。`}</h1>
    <p>{selfStudy ? '本关' : singleDailyReviewPackage ? '今日' : '本轮'}完成 {answers.length} 题，答对 {correct} 题。{recoveryTargets.length ? '需要补的知识点已经列在下面，现在就能复习；有已审核的同知识点原题，还可以接着练。'
      : hasNextRound ? '下一轮继续用原题检验，看看是不是真的稳了。' : '后续会按复习时间提醒你回看。'}</p>
    <div className="result-stats"><div><b>{answers.length}</b><span>完成练习</span></div><div><b>{new Set(answers.map((answer) => answer.skillId)).size}</b><span>复习模块</span></div><div><b>{answers.length - correct}</b><span>答错题数</span></div></div>
    {recoveryTargets.length > 0 && <section className="result-recovery" aria-labelledby="result-recovery-title">
      <div className="result-recovery-head"><span className="eyebrow"><RotateCcw size={16} />趁热补一补</span><h2 id="result-recovery-title">从哪里跌倒，就从哪里把题做明白</h2><p>先看错题对应的知识点。选项已有审核过的专项题时，会显示准确小点；没有绑定的题，先由你选卡住的环节，不乱猜。</p></div>
      <div className="result-recovery-list">{recoveryTargets.map((target) => <article key={target.key}>
        <div><b><ChemText>{target.title}</ChemText></b><p>{target.branch
          ? target.branch.status === 'reserve_gap' ? '这条选项暂缺足量、已审核的同类型原题；先复习知识点，不拿别的题凑数。'
            : target.branch.status === 'consolidated' ? `已做 ${target.branch.answered} 道专项原题，这一轮接稳了；之后还会复查。`
              : `已做 ${target.branch.answered}/${target.branch.questionIds.length} 道对应选项原题，仍需继续巩固。`
          : target.fromSelfRating ? '你标记了还不熟，先拆开知识卡，再用原题检验。'
            : `这块有 ${target.wrongCount} 道没做对；先查明具体卡在哪一步。`}</p></div>
        <div className="result-recovery-actions"><button type="button" className="primary-button compact" onClick={() => { setRepairTargetKey(target.key); setRepairError(''); setPhase('repair') }}>复习这块<ChevronRight size={16} /></button>
          {target.conceptKey && onOpenFocusedTopic && target.branch?.status !== 'reserve_gap'
            && <button type="button" className="secondary-button compact" disabled={busy} onClick={() => void startFocusedPractice(target.skillId, target.conceptKey!)}>练同知识点原题</button>}</div>
      </article>)}</div>
      {repairError && <p className="inline-alert" role="alert">{repairError}</p>}
    </section>}
    {nextRoundOpenState && onRetryPlanOpen && <PlanOpenNotice state={nextRoundOpenState} onRetry={onRetryPlanOpen} retryLabel={`重试进入第 ${roundNumber + 1} 轮`} />}
    <div className="result-actions">
      {onBrowsePractice && <button type="button" className="secondary-button" disabled={!nextDashboard || busy || nextRoundLoading} onClick={() => nextDashboard && onBrowsePractice(nextDashboard)}>自己挑下一组原题<ChevronRight size={18} /></button>}
      {hasNextRound && <button ref={primaryActionRef} className="primary-button" aria-keyshortcuts="Enter" disabled={!nextDashboard || busy || nextRoundLoading}
        onClick={async () => { if (!nextDashboard) return; setBusy(true); try { await onContinue(nextDashboard, payload.plan.id, roundNumber + 1) } finally { setBusy(false) } }}>
        {nextRoundLoading ? `正在读取 · ${nextRoundOpenState.elapsedSeconds}秒` : nextRoundOpenState?.status === 'error' ? `重试进入第 ${roundNumber + 1} 轮` : `进入第 ${roundNumber + 1} 轮 · 继续原题`}<ChevronRight size={18} />
      </button>}
      <button ref={hasNextRound ? undefined : primaryActionRef} className={hasNextRound ? 'secondary-button' : 'primary-button'} aria-keyshortcuts={hasNextRound ? undefined : 'Enter'} disabled={!nextDashboard || nextRoundLoading}
        onClick={() => nextDashboard && onComplete(nextDashboard)}>{selfStudy ? '返回知识点' : hasNextRound ? '先回首页' : '查看今日成果'}<Trophy size={18} /></button>
    </div>
  </section>
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
