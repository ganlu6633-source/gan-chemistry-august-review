import { useEffect, useState } from 'react'
import { ArrowRight, BookOpen, Check, Clock3, Sparkles } from 'lucide-react'
import type { SessionIdentity } from '../domain/types'
import { accessApi } from '../lib/api'
import { ChemText } from './ChemText'
import './GuestTrialApp.css'

interface GuestQuestion {
  id: string
  stem: string
  options: string[]
}

interface GuestPractice {
  gradeBand: string
  total: number
  answeredCount: number
  correctCount: number
  currentQuestion: GuestQuestion | null
  history: Array<{ questionId: string; selectedOption: number; correct: boolean }>
}

interface GuestFeedback {
  questionId: string
  selectedOption: number
  correct: boolean
  correctOption: number
  explanation: string
}

const OPTION_LABELS = ['A', 'B', 'C', 'D']

function trialDeadline(value?: string) {
  if (!value || !Number.isFinite(Date.parse(value))) return ''
  return new Intl.DateTimeFormat('zh-CN', {
    timeZone: 'Asia/Shanghai', year: 'numeric', month: 'long', day: 'numeric',
    hour: '2-digit', minute: '2-digit', hour12: false,
  }).format(new Date(value))
}

export function GuestTrialApp({ session, onLogout, onRegister }: {
  session: SessionIdentity
  onLogout: () => void
  onRegister: () => void
}) {
  const [practice, setPractice] = useState<GuestPractice | null>(null)
  const [selectedOption, setSelectedOption] = useState<number | null>(null)
  const [feedback, setFeedback] = useState<GuestFeedback | null>(null)
  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    if (session.trialExpiresAt && Date.parse(session.trialExpiresAt) <= Date.now()) {
      setLoading(false)
      return
    }
    const controller = new AbortController()
    setLoading(true)
    setError('')
    accessApi<{ practice: GuestPractice }>(session, 'guest_practice', undefined, { signal: controller.signal })
      .then((result) => setPractice(result.practice))
      .catch((reason) => {
        if (!controller.signal.aborted) setError(reason instanceof Error ? reason.message : '体验题暂时无法打开，请稍后重试。')
      })
      .finally(() => { if (!controller.signal.aborted) setLoading(false) })
    return () => controller.abort()
  }, [session])

  async function submitAnswer() {
    const question = practice?.currentQuestion
    if (!question || selectedOption === null || submitting) return
    setSubmitting(true)
    setError('')
    try {
      const result = await accessApi<{ feedback: GuestFeedback; practice: GuestPractice }>(session, 'guest_submit_practice', {
        questionId: question.id,
        selectedOption,
      })
      setFeedback(result.feedback)
      setPractice(result.practice)
      setSelectedOption(null)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '答案暂时没有提交成功，请重试。')
    } finally {
      setSubmitting(false)
    }
  }

  function continuePractice() {
    setFeedback(null)
    setError('')
  }

  const question = feedback ? null : practice?.currentQuestion
  const deadline = trialDeadline(session.trialExpiresAt)
  const isTrialExpired = session.trialExpiresAt ? Date.parse(session.trialExpiresAt) <= Date.now() : false
  const showExpired = isTrialExpired || /试用已到期|试用已结束|试用期已结束/.test(error)
  const progress = practice && practice.total > 0 ? Math.round(practice.answeredCount / practice.total * 100) : 0

  return <main className="guest-trial">
    <header className="guest-trial-intro">
      <div>
        <span className="eyebrow"><Sparkles size={17} aria-hidden="true" /> 七天访客体验</span>
        <h1>先来做几道题，看看学起来顺不顺手</h1>
        <p>选一个答案，马上看对错和解析。草稿尽管写在纸上，网站只需要你点 A、B、C、D。</p>
      </div>
      <span className="guest-trial-icon" aria-hidden="true"><BookOpen size={34} /></span>
    </header>

    <div className="guest-trial-meta">
      <span><b>{practice?.gradeBand || '访客'}</b> · 平台原创示例题</span>
      {deadline && <span><Clock3 size={16} aria-hidden="true" /> 试用至 {deadline}（北京时间）</span>}
    </div>
    <p className="guest-trial-scope">这里的示例题与正式学生题库分开，作答只保存在你的访客体验中。正式学习档案需要加甘老师微信、领取邀请码后开通。</p>

    {showExpired ? <section className="guest-trial-panel guest-trial-expired" role="alert">
      <h2>七天体验结束啦</h2>
      <p>想继续学习？添加甘老师微信，拿到邀请码后就可以申请正式账号。</p>
      <div className="guest-trial-actions"><button className="primary-button" onClick={onRegister}>去注册 <ArrowRight size={17} /></button><button className="secondary-button" onClick={onLogout}>返回首页</button></div>
    </section> : <>
      {practice && <div className="guest-trial-progress">
        <div><b>已做 {practice.answeredCount}/{practice.total} 题</b><span>答对 {practice.correctCount} 题</span></div>
        <div className="guest-trial-progress-track" role="progressbar" aria-label="访客练习进度" aria-valuenow={practice.answeredCount} aria-valuemin={0} aria-valuemax={practice.total}><span style={{ width: `${progress}%` }} /></div>
      </div>}

      {loading ? <div className="guest-trial-panel guest-trial-loading" role="status">正在准备体验题…</div> : null}
      {error && !showExpired && <div className="form-error guest-trial-error" role="alert">{error}<button type="button" className="text-button" onClick={onLogout}>返回首页</button></div>}

      {!loading && feedback && <section className={`guest-trial-panel guest-trial-feedback ${feedback.correct ? 'is-correct' : 'is-wrong'}`} aria-live="polite">
        <span className="eyebrow">刚刚这道题</span>
        <h2>{feedback.correct ? '答对啦，手感不错！' : `这题的答案是 ${OPTION_LABELS[feedback.correctOption] ?? '正确选项'}`}</h2>
        <p><ChemText>{feedback.explanation}</ChemText></p>
        <button type="button" className="primary-button" onClick={continuePractice}>{practice?.currentQuestion ? '继续下一题' : '查看练习结果'} <ArrowRight size={17} /></button>
      </section>}

      {!loading && question && <section className="guest-trial-panel guest-trial-question">
        <div className="guest-trial-question-head"><span className="eyebrow">第 {practice!.answeredCount + 1} 题 · 单项选择</span><span>先想一想，再作答</span></div>
        <h2><ChemText>{question.stem}</ChemText></h2>
        <div className="guest-trial-options" role="group" aria-label="选择一个答案">
          {question.options.map((option, index) => <button
            type="button" key={`${question.id}-${index}`} className={selectedOption === index ? 'is-selected' : ''}
            aria-pressed={selectedOption === index} disabled={submitting} onClick={() => setSelectedOption(index)}>
            <b>{OPTION_LABELS[index] ?? index + 1}</b><span><ChemText>{option}</ChemText></span>
          </button>)}
        </div>
        <button type="button" className="primary-button guest-trial-submit" disabled={selectedOption === null || submitting} onClick={submitAnswer}>{submitting ? '正在核对答案…' : '提交答案'} <ArrowRight size={17} /></button>
      </section>}

      {!loading && !feedback && practice && !practice.currentQuestion && <section className="guest-trial-panel guest-trial-complete">
        <span className="guest-trial-check"><Check size={30} aria-hidden="true" /></span>
        <h2>{practice.total > 0 ? '这组体验题做完啦！' : '体验题正在准备中'}</h2>
        <p>{practice.total > 0 ? `共做 ${practice.answeredCount} 题，答对 ${practice.correctCount} 题。加甘老师微信开通正式账号后，就可以按自己的进度继续学。` : '这个年级的体验题暂未开放，欢迎先申请正式账号。'}</p>
        <button type="button" className="primary-button" onClick={onRegister}>加老师微信，申请正式账号 <ArrowRight size={17} /></button>
      </section>}
    </>}

    {!showExpired && <aside className="guest-trial-register">
      <div><b>想学完整课程？</b><p>扫码添加甘老师企业微信，领取邀请码后再注册。点二维码可以查看完整名片。</p></div>
      <a className="wecom-qr-preview" href={`${import.meta.env.BASE_URL}wechat-add.jpg`} target="_blank" rel="noreferrer" aria-label="查看企业微信名片大图"><span role="img" aria-label="扫码添加甘老师企业微信，领取正式账号邀请码" style={{ backgroundImage: `url(${import.meta.env.BASE_URL}wechat-add.jpg)` }} /></a>
      <button type="button" className="secondary-button" onClick={onRegister}>我已加老师，去注册 <ArrowRight size={17} /></button>
    </aside>}
  </main>
}
