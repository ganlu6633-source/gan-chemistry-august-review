import { useEffect, useMemo, useRef, useState } from 'react'
import { Check, ChevronRight, CircleHelp, Clock3, Trophy } from 'lucide-react'
import type { JuniorAdaptivePayload, JuniorQuestionFeedback, SessionIdentity, StudentDashboardData } from '../domain/types'
import { splitAnswerExplanation } from '../domain/answerExplanation'
import { submitJuniorAdaptiveStep } from '../lib/api'
import { ChemText } from './ChemText'

export function JuniorAdaptiveSession({
  session,
  initialPayload,
  onExit,
  onComplete,
}: {
  session: SessionIdentity
  initialPayload: JuniorAdaptivePayload
  onExit: () => void
  onComplete: (dashboard: StudentDashboardData) => void
}) {
  const [payload, setPayload] = useState(initialPayload)
  const [pendingPayload, setPendingPayload] = useState<JuniorAdaptivePayload | null>(null)
  const [completedDashboard, setCompletedDashboard] = useState<StudentDashboardData | null>(null)
  const [selected, setSelected] = useState<number | null>(null)
  const [feedback, setFeedback] = useState<JuniorQuestionFeedback | null>(null)
  const [startedAt, setStartedAt] = useState(Date.now())
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const primaryAction = useRef<HTMLButtonElement>(null)

  const question = payload.currentQuestion
  const currentCard = useMemo(() => payload.cards.find((card) => card.skillId === question?.skillId) ?? null, [payload.cards, question?.skillId])
  const answeredDisplay = Math.min(payload.session.answeredCount + (feedback ? 1 : 0), payload.session.hardQuestionCap)
  const targetText = answeredDisplay <= 12 ? `${answeredDisplay}/12` : `${answeredDisplay}/15`
  const unfinishedPractice = (pendingPayload ?? payload).optionPractice?.filter((branch) => branch.status !== 'consolidated') ?? []
  const pendingPractice = unfinishedPractice.filter((branch) => branch.status !== 'practicing')

  async function submit(retryContinuation = false) {
    if (!question || !payload.currentStepId || selected === null || busy || (feedback && !retryContinuation)) return
    setBusy(true)
    setError('')
    try {
      const result = await submitJuniorAdaptiveStep(session, {
        planId: payload.plan.id,
        stepId: payload.currentStepId,
        selectedOption: feedback?.selectedOption ?? selected,
        uncertain: feedback?.uncertain ?? false,
        durationSec: feedback?.durationSec ?? Math.min(3600, Math.max(0, Math.round((Date.now() - startedAt) / 1000))),
        revisionToken: feedback?.revisionToken ?? question.revisionToken,
      })
      setFeedback(result.feedback)
      setSelected(result.feedback.selectedOption)
      setPendingPayload(result.payload)
      setCompletedDashboard(result.dashboard ?? null)
      if (!result.payload) setError(result.continuation?.message ?? '答案已保存，下一题暂时无法打开。你可以查看本题解析，再重试或返回学习计划。')
      else if (result.payload.pendingMessage) setError(result.payload.pendingMessage)
    } catch (reason) {
      setError(feedback ? '答案已保存，解析仍可查看。下一题暂时无法打开，请重试或返回学习计划。'
        : reason instanceof Error ? reason.message : '这道题暂时无法提交，请稍后重试。')
    } finally {
      setBusy(false)
    }
  }

  function next() {
    if (!pendingPayload) return
    if (pendingPayload.completed) {
      if (completedDashboard) onComplete(completedDashboard)
      else onExit()
      return
    }
    if (!pendingPayload.currentQuestion) { onExit(); return }
    setPayload(pendingPayload)
    setPendingPayload(null)
    setSelected(null)
    setFeedback(null)
    setError('')
    setStartedAt(Date.now())
    window.setTimeout(() => primaryAction.current?.focus(), 0)
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
      {unfinishedPractice.length > 0 && <p>还有 {unfinishedPractice.length} 个错项考点待继续练习，进度已经保留。</p>}
      <div className="result-stats"><div><b>{payload.session.answeredCount}</b><span>完成题数</span></div><div><b>{payload.session.correctCount}</b><span>答对题数</span></div></div>
      <div className="result-actions"><button ref={primaryAction} className="primary-button" aria-keyshortcuts="Enter" onClick={() => completedDashboard ? onComplete(completedDashboard) : onExit()}>查看今日成果<Trophy size={18} /></button></div>
    </section>
  }

  if (!question) return <section className="learning-stage"><div className="inline-alert" role="alert">{payload.pendingMessage ?? '当前题目暂时无法打开，请返回学习计划或联系甘老师。'}</div><button className="secondary-button" onClick={onExit}>返回学习计划</button></section>

  const explanation = feedback ? splitAnswerExplanation(feedback.explanation) : []
  const answeredCorrectly = feedback?.correct === true
  const willExtend = pendingPayload && !pendingPayload.completed && pendingPayload.session.issuedCount > 12
  return <section className="learning-stage junior-adaptive-stage">
    <div className="round-guidance"><Clock3 /><div><b>今日练习 12—15 题</b><p>看题，在纸上计算或思考，选择 A—D，提交后查看解析。</p></div></div>
    {pendingPractice.length > 0 && <p>有 {pendingPractice.length} 个错项考点的后续补练待准备或待续，进度已经保留。</p>}
    {error && <div className="inline-alert" role="alert">{error}</div>}
    <div className="quiz-head"><span>今日进度 {targetText}{willExtend ? ' · 正在做针对性补稳' : ''}</span><span>{currentCard ? <ChemText>{currentCard.title}</ChemText> : <ChemText>针对性练习</ChemText>}</span></div>
    <div className="stage-progress"><i style={{ width: `${Math.min(100, answeredDisplay / 12 * 100)}%` }} /></div>
    <aside className="knowledge-card junior-knowledge-card">
      <span className="eyebrow">当前知识点</span><h2><ChemText>{currentCard?.title ?? '针对性练习'}</ChemText></h2>
      {currentCard && <><p><ChemText>{currentCard.core}</ChemText></p><ol>{currentCard.steps.slice(0, 3).map((step) => <li key={step}><ChemText>{step}</ChemText></li>)}</ol></>}
    </aside>
    <article className="question-card">
      <span className="difficulty-pill">L{question.level} 练习</span>
      {question.optionPractice && <p>{question.optionPractice.knowledgePoint} · 第 {question.optionPractice.position}/{question.optionPractice.total} 题</p>}
      <h1><ChemText>{question.stem}</ChemText></h1>
      <div className="option-list">{question.options.map((option, index) => {
        const letter = String.fromCharCode(65 + index)
        return <button key={`${letter}-${option}`} aria-label={`${letter}. ${option}`} disabled={feedback !== null || busy} className={`${selected === index ? 'selected' : ''} ${feedback && index === feedback.correctOption ? 'correct' : ''} ${feedback && selected === index && index !== feedback.correctOption ? 'wrong' : ''}`} onClick={() => setSelected(index)}><span>{letter}</span><ChemText>{option}</ChemText></button>
      })}</div>
      {feedback && <div className={`answer-feedback ${answeredCorrectly ? 'good' : 'needs-work'}`}><b>{answeredCorrectly ? '回答正确' : `回答错误，正确选项是 ${String.fromCharCode(65 + feedback.correctOption)}`}</b><div className="answer-explanation">{explanation.map((item, index) => <p className={item.option ? undefined : 'is-unlabeled'} key={`${item.option ?? 'paragraph'}-${index}`}>{item.option ? <b className="answer-option-label">{item.option}</b> : null}<span className="answer-explanation-text"><ChemText>{item.text}</ChemText></span></p>)}</div>{!answeredCorrectly && feedback.scaffold ? <p><CircleHelp size={16} />提示：<ChemText>{feedback.scaffold}</ChemText></p> : null}</div>}
    </article>
    <div className="stage-actions"><button className="secondary-button" disabled={busy} onClick={onExit}>稍后继续 / 返回计划</button>{feedback ? <button ref={primaryAction} className="primary-button" aria-keyshortcuts="Enter" disabled={busy} onClick={() => pendingPayload ? next() : void submit(true)}>{busy ? '正在准备下一题…' : !pendingPayload ? '重试获取下一题' : pendingPayload.completed ? '完成今天学习' : !pendingPayload.currentQuestion ? '返回学习计划' : '下一题'}<ChevronRight size={18} /></button> : <button ref={primaryAction} className="primary-button" aria-keyshortcuts="Enter" disabled={busy || selected === null} onClick={() => void submit()}>{busy ? '正在提交答案…' : '提交答案'}</button>}</div>
  </section>
}
