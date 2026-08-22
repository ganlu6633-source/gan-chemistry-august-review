import { useMemo, useRef, useState } from 'react'
import { Check, ChevronRight, CircleHelp, Clock3, Trophy } from 'lucide-react'
import type { JuniorAdaptivePayload, QuestionFeedback, SessionIdentity, StudentDashboardData } from '../domain/types'
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
  const [uncertain, setUncertain] = useState(false)
  const [feedback, setFeedback] = useState<QuestionFeedback | null>(null)
  const [startedAt, setStartedAt] = useState(Date.now())
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const primaryAction = useRef<HTMLButtonElement>(null)

  const question = payload.currentQuestion
  const currentCard = useMemo(() => payload.cards.find((card) => card.skillId === question?.skillId) ?? null, [payload.cards, question?.skillId])
  const answeredDisplay = Math.min(payload.session.answeredCount + (feedback ? 1 : 0), payload.session.hardQuestionCap)
  const targetText = answeredDisplay <= 12 ? `${answeredDisplay}/12` : `${answeredDisplay}/15`

  async function submit() {
    if (!question || !payload.currentStepId || selected === null) return
    setBusy(true)
    setError('')
    try {
      const result = await submitJuniorAdaptiveStep(session, {
        planId: payload.plan.id,
        stepId: payload.currentStepId,
        selectedOption: selected,
        uncertain,
        durationSec: Math.max(0, Math.round((Date.now() - startedAt) / 1000)),
        revisionToken: question.revisionToken,
      })
      setFeedback(result.feedback)
      setPendingPayload(result.payload)
      setCompletedDashboard(result.dashboard ?? null)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '这道题暂时无法提交，请稍后重试。')
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
    setPayload(pendingPayload)
    setPendingPayload(null)
    setSelected(null)
    setUncertain(false)
    setFeedback(null)
    setStartedAt(Date.now())
    window.setTimeout(() => primaryAction.current?.focus(), 0)
  }

  if (payload.completed || (!question && payload.session.status === 'completed')) {
    return <section className="learning-stage result-stage">
      <div className="result-badge"><Check /></div>
      <span className="eyebrow">今日初中化学已完成</span>
      <h1>今天的 12—15 道原题已形成学习证据。</h1>
      <p>系统只在基础尚未稳定时增加题目；下一天若有错题，会换用同类型但不同的原题回收，不会复现今天做过的原题。</p>
      <div className="result-stats"><div><b>{payload.session.answeredCount}</b><span>完成原题</span></div><div><b>{payload.session.correctCount}</b><span>答对题目</span></div><div><b>{payload.cards.length}</b><span>对应知识点</span></div></div>
      <div className="result-actions"><button ref={primaryAction} className="primary-button" onClick={() => completedDashboard ? onComplete(completedDashboard) : onExit()}>查看今日成果<Trophy size={18} /></button></div>
    </section>
  }

  if (!question) return <section className="learning-stage"><div className="inline-alert" role="alert">当前没有可安全下发的原题。系统没有用自编题补位；请联系甘老师核验题源容量。</div><button className="secondary-button" onClick={onExit}>返回学习计划</button></section>

  const explanation = feedback ? splitAnswerExplanation(feedback.explanation) : []
  const answeredCorrectly = feedback?.correct === true
  const willExtend = pendingPayload && !pendingPayload.completed && pendingPayload.session.issuedCount > 12
  return <section className="learning-stage junior-adaptive-stage">
    <div className="round-guidance"><Clock3 /><div><b>今日基础目标 12 道原题</b><p>三个知识点逐一推进；基础证据不足时最多追加到 15 道。每一道都由服务器在上一题作答后选出。</p></div></div>
    {error && <div className="inline-alert" role="alert">{error}</div>}
    <div className="quiz-head"><span>今日进度 {targetText}{willExtend ? ' · 正在做针对性补稳' : ''}</span><span>{currentCard ? <ChemText>{currentCard.title}</ChemText> : <ChemText>{question.skillId}</ChemText>}</span></div>
    <div className="stage-progress"><i style={{ width: `${Math.min(100, answeredDisplay / 12 * 100)}%` }} /></div>
    <aside className="knowledge-card junior-knowledge-card">
      <span className="eyebrow">当前知识点</span><h2><ChemText>{currentCard?.title ?? question.skillId}</ChemText></h2>
      {currentCard && <><p><ChemText>{currentCard.core}</ChemText></p><ol>{currentCard.steps.slice(0, 3).map((step) => <li key={step}><ChemText>{step}</ChemText></li>)}</ol></>}
    </aside>
    <article className="question-card">
      <span className="difficulty-pill">L{question.level} 原题</span>
      <h1><ChemText>{question.stem}</ChemText></h1>
      <div className="option-list">{question.options.map((option, index) => {
        const letter = String.fromCharCode(65 + index)
        return <button key={`${letter}-${option}`} aria-label={`${letter}. ${option}`} disabled={feedback !== null || busy} className={`${selected === index ? 'selected' : ''} ${feedback && index === feedback.correctOption ? 'correct' : ''} ${feedback && selected === index && index !== feedback.correctOption ? 'wrong' : ''}`} onClick={() => setSelected(index)}><span>{letter}</span><ChemText>{option}</ChemText></button>
      })}</div>
      <label className="uncertain-toggle"><input type="checkbox" checked={uncertain} disabled={feedback !== null || busy} onChange={(event) => setUncertain(event.target.checked)} />我选了，但还不太确定</label>
      {feedback && <div className={`answer-feedback ${answeredCorrectly ? 'good' : 'needs-work'}`}><b>{answeredCorrectly ? (feedback.uncertain ? '答案正确，再确认一次会更稳' : '判断正确，系统正在选择下一道原题') : '这一步需要用另一道同知识点原题继续确认'}</b><div className="answer-explanation">{explanation.map((item, index) => <p className={item.option ? undefined : 'is-unlabeled'} key={`${item.option ?? 'paragraph'}-${index}`}>{item.option ? <b className="answer-option-label">{item.option}</b> : null}<ChemText>{item.text}</ChemText></p>)}</div>{!answeredCorrectly && feedback.scaffold ? <p><CircleHelp size={16} />提示：<ChemText>{feedback.scaffold}</ChemText></p> : null}</div>}
    </article>
    <div className="stage-actions">{feedback ? <button ref={primaryAction} className="primary-button" disabled={busy || !pendingPayload} onClick={next}>{pendingPayload?.completed ? '完成今天学习' : '下一题'}<ChevronRight size={18} /></button> : <button ref={primaryAction} className="primary-button" disabled={busy || selected === null} onClick={() => void submit()}>{busy ? '正在锁定第一次选择…' : '提交答案'}</button>}</div>
  </section>
}
