import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Check, ChevronRight, CircleHelp, Clock3, RotateCcw, Trophy } from 'lucide-react'
import type { JuniorAdaptivePayload, JuniorQuestionFeedback, JuniorStepSubmissionResult, SessionIdentity, StudentDashboardData } from '../domain/types'
import { splitAnswerExplanation } from '../domain/answerExplanation'
import { buildKnowledgeCardDrilldown } from '../domain/knowledgeDrilldown'
import { juniorReviewPoint } from '../domain/juniorReviewPoint'
import { displayQuestionStem } from '../domain/questionDisplay'
import { accessApi, submitJuniorAdaptiveStep, type JuniorStepAnswerInput, type LoadedQuestionAsset, type loadQuestionAsset } from '../lib/api'
import { ChemText } from './ChemText'
import { InteractiveKnowledgeTree } from './InteractiveKnowledgeTree'
import { QuestionSourceMedia } from './QuestionSourceMedia'

const loadJuniorQuestionAsset: typeof loadQuestionAsset = (session, stepId, assetId, phase, context) =>
  accessApi<{ asset: LoadedQuestionAsset }>(session, 'junior_question_asset', { questionId: stepId, assetId, phase, ...(context ?? {}) })

export function JuniorAdaptiveSession({
  session,
  initialPayload,
  previewStudentId,
  onExit,
  onComplete,
}: {
  session: SessionIdentity
  initialPayload: JuniorAdaptivePayload
  previewStudentId?: string
  onExit: (completed?: JuniorAdaptivePayload) => void
  onComplete: (dashboard: StudentDashboardData) => void
}) {
  const [payload, setPayload] = useState(initialPayload)
  const [pendingPayload, setPendingPayload] = useState<JuniorAdaptivePayload | null>(null)
  const [completedDashboard, setCompletedDashboard] = useState<StudentDashboardData | null>(null)
  const [selected, setSelected] = useState<number | null>(null)
  const [feedback, setFeedback] = useState<JuniorQuestionFeedback | null>(null)
  const [startedAt, setStartedAt] = useState(Date.now())
  const [busy, setBusy] = useState(false)
  const [preparing, setPreparing] = useState(false)
  const [advanceRequested, setAdvanceRequested] = useState(false)
  const [error, setError] = useState('')
  const [reviewedBranches, setReviewedBranches] = useState<string[]>([])
  const answeredFeedback = useRef(new Map<string, JuniorQuestionFeedback>())
  const primaryAction = useRef<HTMLButtonElement>(null)
  const previewAnswers = useRef<Array<{ stepId: string; selectedOption: number; revisionToken?: string | null; uncertain: boolean; durationSec: number }>>([])
  const lockedSubmission = useRef<JuniorStepAnswerInput | null>(null)
  const submittingNow = useRef(false)
  const preparingNow = useRef(false)
  const advanceWhenReady = useRef(false)
  const requestVersion = useRef(0)
  const continuationAbort = useRef<AbortController | null>(null)
  const mounted = useRef(true)

  useEffect(() => {
    mounted.current = true
    return () => {
      mounted.current = false
      requestVersion.current += 1
      continuationAbort.current?.abort()
    }
  }, [])

  const question = payload.currentQuestion
  const mediaRefs = useMemo(() => [...(question?.assetRefs ?? []), ...(question?.auxiliaryAssetRefs ?? [])], [question?.assetRefs, question?.auxiliaryAssetRefs])
  const loadJuniorMedia: typeof loadQuestionAsset = useCallback((identity, stepId, assetId, phase, context) => {
    const isAuxiliary = (question?.auxiliaryAssetRefs ?? []).some((ref) => ref.assetId === assetId)
    return isAuxiliary ? accessApi<{ asset: LoadedQuestionAsset }>(identity, 'junior_auxiliary_asset', { questionId: stepId, assetId, phase, ...(context ?? {}) })
      : loadJuniorQuestionAsset(identity, stepId, assetId, phase, context)
  }, [question?.auxiliaryAssetRefs])
  const [primaryImage, setPrimaryImage] = useState({ stepId: initialPayload.currentStepId, ready: false })
  const primaryReady = question?.renderMode !== 'image_primary' || (primaryImage.stepId === payload.currentStepId && primaryImage.ready)
  const onPrimaryReadyChange = useCallback((ready: boolean) => setPrimaryImage({ stepId: payload.currentStepId, ready }), [payload.currentStepId])
  const assetAccessContext = useMemo(() => ({ planId: payload.plan.id, attemptSequence: 0,
    revisionToken: question?.revisionToken, ...(previewStudentId ? { studentId: previewStudentId } : {}) }),
  [payload.plan.id, question?.revisionToken, previewStudentId])
  const currentCard = useMemo(() => payload.cards.find((card) => card.skillId === question?.skillId) ?? null, [payload.cards, question?.skillId])
  const currentKnowledgeTree = useMemo(() => currentCard ? buildKnowledgeCardDrilldown(currentCard) : null, [currentCard])
  const answeredDisplay = Math.min(payload.session.answeredCount + (feedback ? 1 : 0), payload.session.hardQuestionCap)
  const initialTarget = payload.session.initialQuestionTarget
  const recoveryRound = question?.optionPractice?.recoveryRound ?? 0
  const threeRoundPolicy = payload.session.recoveryRoundLimit === 3
  const reviewKey = `${recoveryRound}:${question?.optionPractice?.anchorStepId ?? ''}:${question?.optionPractice?.optionIndex ?? ''}`
  const needsRoundReview = threeRoundPolicy && recoveryRound > 0 && !reviewedBranches.includes(reviewKey)
  const targetText = answeredDisplay <= initialTarget ? `${answeredDisplay}/${initialTarget}` : `${answeredDisplay}/${payload.session.hardQuestionCap}`
  const unfinishedPractice = (pendingPayload ?? payload).optionPractice?.filter((branch) => branch.status !== 'consolidated') ?? []
  const pendingPractice = unfinishedPractice.filter((branch) => branch.status !== 'practicing')

  function leave() {
    requestVersion.current += 1
    continuationAbort.current?.abort()
    const confirmed = pendingPayload ?? payload
    if (confirmed.completed && confirmed.session.status === 'completed') onExit(confirmed)
    else onExit()
  }

  function acceptContinuation(result: JuniorStepSubmissionResult) {
    setPendingPayload(result.payload)
    const simulatedDashboard = previewStudentId && result.dashboard && result.payload?.completed
      ? { ...result.dashboard, plans: result.dashboard.plans.map((plan) => plan.id === payload.plan.id
        ? { ...plan, isComplete: true, attemptCount: 1, latestScore: result.payload!.session.correctCount,
          firstScore: result.payload!.session.correctCount, roundsRemaining: 0 }
        : plan) } : result.dashboard
    setCompletedDashboard(simulatedDashboard ?? null)
    if (!result.payload) setError(result.continuation?.message ?? '本题解析仍可查看，下一题暂时无法打开。请重试或返回学习计划。')
    else if (result.payload.pendingMessage) setError(result.payload.pendingMessage)
  }

  async function prepareNext() {
    const submitted = lockedSubmission.current
    if (!submitted || preparingNow.current || !mounted.current) return
    preparingNow.current = true
    const version = ++requestVersion.current
    const controller = new AbortController()
    continuationAbort.current = controller
    setPreparing(true)
    setError('')
    try {
      const result = previewStudentId
        ? await accessApi<JuniorStepSubmissionResult>(session, 'preview_junior_submit_step', {
          studentId: previewStudentId, planId: submitted.planId, answers: previewAnswers.current, feedbackOnly: false,
        }, { signal: controller.signal })
        : await submitJuniorAdaptiveStep(session, submitted, { feedbackOnly: false, signal: controller.signal })
      if (!mounted.current || version !== requestVersion.current) return
      acceptContinuation(result)
      if (advanceWhenReady.current && result.payload) showNext(result.payload)
    } catch {
      if (!mounted.current || version !== requestVersion.current) return
      setError(previewStudentId ? '本题解析仍可查看。下一题暂时无法打开，请重试或返回学习计划。'
        : '答案已保存，解析仍可查看。下一题暂时无法打开，请重试或返回学习计划。')
    } finally {
      if (version === requestVersion.current) {
        preparingNow.current = false
        continuationAbort.current = null
        advanceWhenReady.current = false
        if (mounted.current) { setPreparing(false); setAdvanceRequested(false) }
      }
    }
  }

  async function submit() {
    if (!question || !payload.currentStepId || selected === null || submittingNow.current || feedback || !primaryReady) return
    submittingNow.current = true
    const version = ++requestVersion.current
    setBusy(true)
    setError('')
    try {
      const submitted = lockedSubmission.current ?? {
        planId: payload.plan.id,
        stepId: payload.currentStepId,
        selectedOption: selected,
        uncertain: false,
        durationSec: Math.min(3600, Math.max(0, Math.round((Date.now() - startedAt) / 1000))),
        revisionToken: question.revisionToken,
      }
      lockedSubmission.current = submitted
      const nextPreviewAnswers = previewAnswers.current.some((answer) => answer.stepId === submitted.stepId)
        ? previewAnswers.current : [...previewAnswers.current, submitted]
      const result: JuniorStepSubmissionResult = previewStudentId
        ? await accessApi<JuniorStepSubmissionResult>(session, 'preview_junior_submit_step', {
          studentId: previewStudentId, planId: payload.plan.id, answers: nextPreviewAnswers, feedbackOnly: true,
        })
        : await submitJuniorAdaptiveStep(session, submitted, { feedbackOnly: true })
      if (!mounted.current || version !== requestVersion.current) return
      if (previewStudentId) previewAnswers.current = nextPreviewAnswers
      lockedSubmission.current = { ...submitted, selectedOption: result.feedback.selectedOption,
        uncertain: result.feedback.uncertain, durationSec: result.feedback.durationSec,
        revisionToken: result.feedback.revisionToken ?? submitted.revisionToken }
      answeredFeedback.current.set(submitted.stepId, result.feedback)
      setFeedback(result.feedback)
      setSelected(result.feedback.selectedOption)
      if (result.continuation?.status === 'pending' && !result.payload) void prepareNext()
      else acceptContinuation(result)
    } catch (reason) {
      if (mounted.current && version === requestVersion.current) setError(reason instanceof Error ? reason.message : '这道题暂时无法提交，请稍后重试。')
    } finally {
      submittingNow.current = false
      if (mounted.current) setBusy(false)
    }
  }

  function showNext(nextPayload: JuniorAdaptivePayload) {
    requestVersion.current += 1
    preparingNow.current = false
    advanceWhenReady.current = false
    continuationAbort.current = null
    lockedSubmission.current = null
    setPreparing(false)
    setAdvanceRequested(false)
    if (nextPayload.completed) {
      setPayload(nextPayload)
      setPendingPayload(null)
      setFeedback(null)
      return
    }
    if (!nextPayload.currentQuestion) { leave(); return }
    setPayload(nextPayload)
    setPendingPayload(null)
    setSelected(null)
    setFeedback(null)
    setError('')
    setStartedAt(Date.now())
    window.setTimeout(() => primaryAction.current?.focus(), 0)
  }

  function next() {
    if (pendingPayload) { showNext(pendingPayload); return }
    if (preparingNow.current) {
      if (!advanceWhenReady.current) { advanceWhenReady.current = true; setAdvanceRequested(true) }
      return
    }
    void prepareNext()
  }

  useEffect(() => {
    function continueWithEnter(event: KeyboardEvent) {
      if (event.key !== 'Enter' || event.repeat || event.isComposing || event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return
      const target = event.target
      if (target instanceof HTMLElement && (
        target.isContentEditable
        || target.closest('button, a[href], input, textarea, select, summary, [role="button"], [role="link"], [contenteditable="true"]')
      )) return
      if (document.querySelector('dialog[data-question-media-dialog][open]')) return
      if (target instanceof HTMLElement && target.closest('[data-question-source-media], [data-question-media-dialog], [data-question-media-control]')) return
      const action = primaryAction.current
      if (!action || action.disabled || action.getAttribute('aria-disabled') === 'true') return
      if (target instanceof Node && action.contains(target)) return
      event.preventDefault()
      action.click()
    }
    window.addEventListener('keydown', continueWithEnter)
    return () => window.removeEventListener('keydown', continueWithEnter)
  }, [])

  if (payload.completed || (!question && payload.session.status === 'completed')) {
    return <section className="learning-stage result-stage">
      <div className="result-badge"><Check /></div>
      <span className="eyebrow">初三化学</span>
      <h1>今天的练习已完成</h1>
      <p>答对 {payload.session.correctCount} 道，共完成 {payload.session.answeredCount} 道。</p>
      {threeRoundPolicy && <p>首轮 8 题，错点最多补练 3 轮；每天合计最多 30 题。还没练稳的考点会留在后续复习中。</p>}
      {unfinishedPractice.length > 0 && <p>还有 {unfinishedPractice.length} 个错项考点待继续练习，进度已经保留。</p>}
      <div className="result-stats"><div><b>{payload.session.answeredCount}</b><span>完成题数</span></div><div><b>{payload.session.correctCount}</b><span>答对题数</span></div></div>
      <div className="result-actions"><button ref={primaryAction} className="primary-button" aria-keyshortcuts="Enter" onClick={() => completedDashboard ? onComplete(completedDashboard) : leave()}>查看今日成果<Trophy size={18} /></button></div>
    </section>
  }

  if (!question) return <section className="learning-stage"><div className="inline-alert" role="alert">{payload.pendingMessage ?? '当前题目暂时无法打开，请返回学习计划或联系甘老师。'}</div><button className="secondary-button" onClick={leave}>返回学习计划</button></section>

  if (needsRoundReview) {
    const pointName = question.optionPractice!.knowledgePoint
    const point = juniorReviewPoint(payload.cards, pointName)
    const reviewCard = payload.cards.find((card) => card.id === point?.cardId) ?? currentCard
    const reviewTree = reviewCard ? buildKnowledgeCardDrilldown(reviewCard) : null
    const anchorFeedback = answeredFeedback.current.get(question.optionPractice!.anchorStepId)
    const anchorOption = String.fromCharCode(65 + question.optionPractice!.optionIndex)
    const exactOptionExplanation = anchorFeedback ? splitAnswerExplanation(anchorFeedback.explanation)
      .filter((paragraph) => paragraph.option === anchorOption).map((paragraph) => paragraph.text) : []
    return <section className="learning-stage junior-adaptive-stage">
      <div className="round-guidance"><CircleHelp /><div><b>第 {recoveryRound} 轮补练前，先把错点理一理</b><p>一次只补一个小点。先看这一条判断方法，再用同类型原题试一次。</p></div></div>
      <article className="knowledge-card junior-knowledge-card" data-testid="junior-micro-review">
        <h2><ChemText>{point?.title ?? pointName}</ChemText></h2>
        {point ? <>
          <p><ChemText>{point.rule}</ChemText></p>
          {point.examples.map((example) => <p key={example}><b>看个小例子：</b><ChemText>{example}</ChemText></p>)}
          {point.caution && <p><b>容易踩的坑：</b><ChemText>{point.caution}</ChemText></p>}
        </> : exactOptionExplanation.length ? exactOptionExplanation.map((paragraph) => <p key={paragraph}><ChemText>{paragraph}</ChemText></p>)
          : <p>先想一想这个选项的判断依据。还拿不准时，点开下方知识树，找到同名的小节点再看。</p>}
      </article>
      {reviewCard && reviewTree && <details>
        <summary>还想看相关知识？展开完整知识树</summary>
        <InteractiveKnowledgeTree root={reviewTree} title={reviewCard.title} intro="点击需要的小节点，逐个看规则和例子。" />
      </details>}
      <div className="stage-actions"><button className="secondary-button" onClick={leave}>稍后继续 / 返回计划</button><button ref={primaryAction} className="primary-button" aria-keyshortcuts="Enter" onClick={() => { setReviewedBranches((branches) => [...branches, reviewKey]); setStartedAt(Date.now()) }}>开始第 {recoveryRound} 轮补练<ChevronRight size={18} /></button></div>
    </section>
  }

  const explanation = feedback ? splitAnswerExplanation(feedback.explanation) : []
  const answeredCorrectly = feedback?.correct === true
  const willExtend = pendingPayload && !pendingPayload.completed && pendingPayload.session.issuedCount > initialTarget
  return <section className="learning-stage junior-adaptive-stage">
    <div className="round-guidance"><Clock3 /><div><b>{threeRoundPolicy ? recoveryRound ? `第 ${recoveryRound} 轮错点补练` : '首轮 8 道原题' : '今日练习 12—15 题'}</b><p>{threeRoundPolicy ? '先做 8 题，错点先复习再补练；最多补练 3 轮，每天合计不超过 30 题。' : '看题，在纸上计算或思考，选择 A—D，提交后查看解析。'}</p></div></div>
    {pendingPractice.length > 0 && <p>有 {pendingPractice.length} 个错项考点的后续补练待准备或待续，进度已经保留。</p>}
    {error && <div className="inline-alert" role="alert">{error}</div>}
    <div className="quiz-head"><span>今日进度 {targetText}{willExtend ? ' · 正在做针对性补稳' : ''}</span><span>{currentCard ? <ChemText>{currentCard.title}</ChemText> : <ChemText>针对性练习</ChemText>}</span></div>
    <div className="stage-progress"><i style={{ width: `${Math.min(100, answeredDisplay / (recoveryRound ? payload.session.hardQuestionCap : initialTarget) * 100)}%` }} /></div>
    <aside className="knowledge-card junior-knowledge-card">
      <span className="eyebrow">当前知识点</span><h2><ChemText>{currentCard?.title ?? '针对性练习'}</ChemText></h2>
      {currentCard && currentKnowledgeTree && <details key={currentCard.id}>
        <summary>拆开看知识点</summary>
        <InteractiveKnowledgeTree root={currentKnowledgeTree} title={currentCard.title} intro="点开大知识点，再逐层找到小细分；点到最小一层，可以看判断依据和已有例子。" />
      </details>}
    </aside>
    <article className="question-card">
      <span className="difficulty-pill">L{question.level} 练习</span>
      {question.learningPurpose === 'spaced_review' && <p className="junior-review-purpose"><RotateCcw size={15} aria-hidden="true" />到期复习{question.lastAnsweredDate ? ` · 上次练习 ${question.lastAnsweredDate}` : ''}</p>}
      {question.optionPractice && <p>{question.optionPractice.knowledgePoint} · 第 {question.optionPractice.position}/{question.optionPractice.total} 题</p>}
      <QuestionSourceMedia question={{ id: question.mediaId ?? payload.currentStepId ?? '', stem: question.stem,
        options: question.options, renderMode: question.renderMode, assetRefs: mediaRefs }}
        enabled={question.renderMode === 'image_primary' || mediaRefs.length > 0} session={session} showSource={false}
        assetLoader={loadJuniorMedia} accessContext={assetAccessContext} onPrimaryReadyChange={onPrimaryReadyChange}
        onZoomClose={() => primaryAction.current?.focus()}
        nativeContent={<h1 style={question.stem.includes('\n') ? { whiteSpace: 'pre-line', fontSize: 'clamp(18px, 2.5vw, 23px)', lineHeight: 1.65 } : undefined}><ChemText>{displayQuestionStem(question.stem, question.options)}</ChemText></h1>} />
      <div className="option-list">{question.options.map((option, index) => {
        const letter = String.fromCharCode(65 + index)
        return <button key={`${letter}-${option}`} aria-label={`${letter}. ${option}`} disabled={feedback !== null || busy || lockedSubmission.current !== null} className={`${selected === index ? 'selected' : ''} ${feedback && index === feedback.correctOption ? 'correct' : ''} ${feedback && selected === index && index !== feedback.correctOption ? 'wrong' : ''}`} onClick={() => setSelected(index)}><span>{letter}</span><div className="junior-option-copy" style={{ flex: 1, minWidth: 0, overflowWrap: 'anywhere' }}><ChemText>{option}</ChemText></div></button>
      })}</div>
      {feedback && <div className={`answer-feedback ${answeredCorrectly ? 'good' : 'needs-work'}`}><b>{answeredCorrectly ? '回答正确' : `回答错误，正确选项是 ${String.fromCharCode(65 + feedback.correctOption)}`}</b><div className="answer-explanation">{explanation.map((item, index) => <p className={item.option ? undefined : 'is-unlabeled'} key={`${item.option ?? 'paragraph'}-${index}`}>{item.option ? <b className="answer-option-label">{item.option}</b> : null}<span className="answer-explanation-text"><ChemText>{item.text}</ChemText></span></p>)}</div>{!answeredCorrectly && feedback.scaffold ? <p><CircleHelp size={16} />提示：<ChemText>{feedback.scaffold}</ChemText></p> : null}</div>}
    </article>
    <div className="stage-actions"><button className="secondary-button" disabled={busy} onClick={leave}>稍后继续 / 返回计划</button>{feedback ? <button ref={primaryAction} className="primary-button" aria-keyshortcuts="Enter" disabled={busy || advanceRequested} onClick={next}>{advanceRequested ? '正在打开下一题…' : preparing ? '下一题（准备中…）' : !pendingPayload ? '重试获取下一题' : pendingPayload.completed ? '完成今天学习' : !pendingPayload.currentQuestion ? '返回学习计划' : '下一题'}<ChevronRight size={18} /></button> : <button ref={primaryAction} className="primary-button" aria-keyshortcuts="Enter" disabled={busy || selected === null || !primaryReady} onClick={() => void submit()}>{busy ? '正在提交答案…' : '提交答案'}</button>}</div>
  </section>
}
