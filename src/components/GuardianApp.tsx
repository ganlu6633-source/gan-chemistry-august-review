import { useEffect, useState } from 'react'
import { AlertTriangle, BookOpenCheck, Brain, CheckCircle2, Clock3, MessageCircle, RotateCcw, ShieldCheck, Sparkles } from 'lucide-react'
import type { GuardianDashboardData, LearningRecordData, SessionIdentity } from '../domain/types'
import { loadLearningRecord } from '../lib/api'
import { LearningRecordPanel } from './LearningRecordPanel'
import { GuardianVideoSection } from './VideoLearning'

export function GuardianApp({ dashboard, session }: { dashboard: GuardianDashboardData; session: SessionIdentity }) {
  const [record, setRecord] = useState<LearningRecordData | null>(null)
  const [recordError, setRecordError] = useState('')
  const summary = dashboard.skillSummary ?? {
    total: dashboard.stableSkillCount + dashboard.growingSkillCount + dashboard.forgottenSkillCount,
    learned: dashboard.stableSkillCount + dashboard.growingSkillCount + dashboard.forgottenSkillCount,
    full: dashboard.stableSkillCount,
    partial: dashboard.growingSkillCount,
    unlit: dashboard.forgottenSkillCount,
    due: 0,
    recovered: 0,
    answeredQuestions: 0,
  }
  useEffect(() => {
    let active = true
    setRecordError('')
    void loadLearningRecord(session).then((result) => { if (active) setRecord(result.record) })
      .catch((reason) => { if (active) setRecordError(reason instanceof Error ? reason.message : '完整学习档案暂时无法打开。') })
    return () => { active = false }
  }, [dashboard.weeklyCompleted, dashboard.weeklyQuizCompleted, session, summary.answeredQuestions])

  return <div className="guardian-dashboard">
    <section className="guardian-hero"><div><span className="eyebrow">30秒看懂孩子这一周</span><h1>{dashboard.student.displayName}的化学成长说明</h1><p>这里同时呈现进步与需要关注的地方，也会告诉您系统和甘老师已经做了什么。</p><p className="live-sync-note"><CheckCircle2 size={17} />本周已有 {dashboard.weeklyQuizCompleted} 轮即时小测同步到这里，完成后约10秒更新。</p></div><div className="completion-ring"><b>{dashboard.weeklyCompleted}/{dashboard.weeklyPlanned}</b><span>本周复习</span></div></section>
    <section className="guardian-care-design" aria-labelledby="guardian-care-title"><div className="guardian-care-copy"><span className="eyebrow">甘老师为孩子设计的复习闭环</span><h2 id="guardian-care-title">当天发现，当天接稳</h2><p>每一步都从孩子真正学过的范围出发；系统负责整理证据，最终由甘老师判断怎样讲、推什么内容。</p></div><ol><li><Sparkles /><div><b>第一轮 5 题</b><span>小步开始，先找出真正卡住的逻辑。</span></div></li><li><RotateCcw /><div><b>最多 5 轮举一反三</b><span>优先更换母题，不让孩子只记住原题答案。</span></div></li><li><BookOpenCheck /><div><b>仍不稳就补讲解</b><span>甘老师复核错因后安排讲解，观看情况也会如实反馈。</span></div></li></ol></section>
    <section className="guardian-metrics">
      <article className="positive"><Sparkles /><b>{summary.full}</b><span>完全点亮</span></article>
      <article className="working"><BookOpenCheck /><b>{summary.partial}</b><span>点亮一部分</span></article>
      <article className="forget"><RotateCcw /><b>{summary.unlit}</b><span>待建立证据</span></article>
      <article className="teacher"><MessageCircle /><b>{dashboard.teacherAttentionCount}</b><span>老师持续关注</span></article>
    </section>
    <GuardianVideoSection videos={dashboard.videoRecommendations ?? []} />
    <section className="guardian-record-wrap">
      {record ? <LearningRecordPanel record={record} gradeBand={dashboard.student.gradeBand} audience="guardian" />
        : recordError ? <div className="inline-alert" role="alert">{recordError}</div>
          : <div className="record-loading" aria-label="正在读取完整学习档案"><span /><span /><span /></div>}
    </section>
    <div className="guardian-columns">
      <section className="guardian-card"><div className="card-title positive-text"><CheckCircle2 /><div><span>本周明显进步</span><h2>已经获得什么</h2></div></div><ul className="plain-list">{dashboard.progress.length ? dashboard.progress.map((item) => <li key={item}>{item}</li>) : <li>本周还没有形成足够的稳定证据。</li>}</ul></section>
      <section className="guardian-card"><div className="card-title attention-text"><AlertTriangle /><div><span>下一步重点</span><h2>一起把基础接得更稳</h2></div></div><ul className="plain-list">{dashboard.concerns.length ? dashboard.concerns.map((item) => <li key={item}>{item}</li>) : <li>目前按既定节奏继续复习即可。</li>}</ul></section>
    </div>
    {dashboard.behaviorSignals.length > 0 && <section className="guardian-card"><div className="card-title"><Brain /><div><span>学习行为信号</span><h2>只报告重复出现的表现，不做心理诊断</h2></div></div><div className="behavior-grid">{dashboard.behaviorSignals.map((signal) => <article key={signal.kind}><b>{behaviorTitle(signal.kind)}</b><p>{signal.guardianCopy}</p><small>来自{signal.sessionCount}次训练、{signal.evidenceCount}条重复证据</small></article>)}</div></section>}
    <section className="guardian-card timeline-card"><div className="card-title"><Clock3 /><div><span>老师与系统一直在做什么</span><h2>成长时间线</h2></div></div><div className="timeline">{dashboard.timeline.map((event) => <article key={event.id}><div className={`timeline-dot ${event.type}`} /> <div><time>{new Date(event.at).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai', month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })}</time><b>{event.title}</b><p>{event.description}</p></div></article>)}</div></section>
    <section className="privacy-card"><ShieldCheck /><div><b>这里呈现清楚、可信的学习说明</b><p>内容来自已经确认的学习事实，并给出下一步安排。</p></div></section>
  </div>
}

function behaviorTitle(kind: GuardianDashboardData['behaviorSignals'][number]['kind']) {
  return { pace_fast: '作答节奏偏快', pace_slow: '部分题目停留偏长', unstable: '近期稳定性有波动', uncertain: '做对但经常不确定', guessing: '快速错误重复出现' }[kind]
}
