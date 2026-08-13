import { AlertTriangle, BookOpenCheck, Brain, CheckCircle2, Clock3, MessageCircle, RotateCcw, ShieldCheck, Sparkles } from 'lucide-react'
import type { GuardianDashboardData } from '../domain/types'

export function GuardianApp({ dashboard }: { dashboard: GuardianDashboardData }) {
  return <div className="guardian-dashboard">
    <section className="guardian-hero"><div><span className="eyebrow">30秒看懂孩子这一周</span><h1>{dashboard.student.displayName}的化学成长说明</h1><p>这里同时呈现进步与需要关注的地方，也会告诉您系统和甘老师已经做了什么。</p><p className="live-sync-note"><CheckCircle2 size={17} />本周已有 {dashboard.weeklyQuizCompleted} 轮即时小测同步到这里，完成后约10秒更新。</p></div><div className="completion-ring"><b>{dashboard.weeklyCompleted}/{dashboard.weeklyPlanned}</b><span>本周复习</span></div></section>
    <section className="guardian-metrics">
      <article className="positive"><Sparkles /><b>+{dashboard.stableSkillCount}</b><span>新增稳定技能</span></article>
      <article className="working"><BookOpenCheck /><b>{dashboard.growingSkillCount}</b><span>正在巩固</span></article>
      <article className="forget"><RotateCcw /><b>{dashboard.forgottenSkillCount}</b><span>发现遗忘并回收</span></article>
      <article className="teacher"><MessageCircle /><b>{dashboard.teacherAttentionCount}</b><span>老师持续关注</span></article>
    </section>
    <div className="guardian-columns">
      <section className="guardian-card"><div className="card-title positive-text"><CheckCircle2 /><div><span>本周明显进步</span><h2>已经获得什么</h2></div></div><ul className="plain-list">{dashboard.progress.length ? dashboard.progress.map((item) => <li key={item}>{item}</li>) : <li>本周还没有形成足够的稳定证据。</li>}</ul></section>
      <section className="guardian-card"><div className="card-title attention-text"><AlertTriangle /><div><span>仍需注意</span><h2>真实问题不回避</h2></div></div><ul className="plain-list">{dashboard.concerns.length ? dashboard.concerns.map((item) => <li key={item}>{item}</li>) : <li>目前没有需要额外介入的问题。</li>}</ul></section>
    </div>
    {dashboard.behaviorSignals.length > 0 && <section className="guardian-card"><div className="card-title"><Brain /><div><span>学习行为信号</span><h2>只报告重复出现的表现，不做心理诊断</h2></div></div><div className="behavior-grid">{dashboard.behaviorSignals.map((signal) => <article key={signal.kind}><b>{behaviorTitle(signal.kind)}</b><p>{signal.guardianCopy}</p><small>来自{signal.sessionCount}次训练、{signal.evidenceCount}条重复证据</small></article>)}</div></section>}
    <section className="guardian-card timeline-card"><div className="card-title"><Clock3 /><div><span>老师与系统一直在做什么</span><h2>成长时间线</h2></div></div><div className="timeline">{dashboard.timeline.map((event) => <article key={event.id}><div className={`timeline-dot ${event.type}`} /> <div><time>{new Date(event.at).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai', month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })}</time><b>{event.title}</b><p>{event.description}</p></div></article>)}</div></section>
    <section className="privacy-card"><ShieldCheck /><div><b>家长看到的是说明，不是后台标签</b><p>不会展示教师内部备注、内部难度参数或未经验证的判断。</p></div></section>
  </div>
}

function behaviorTitle(kind: GuardianDashboardData['behaviorSignals'][number]['kind']) {
  return { pace_fast: '作答节奏偏快', pace_slow: '部分题目停留偏长', unstable: '近期稳定性有波动', uncertain: '做对但经常不确定', guessing: '快速错误重复出现' }[kind]
}
