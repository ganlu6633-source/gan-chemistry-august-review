import { Fragment, useState } from 'react'
import { BookOpen, CalendarDays, Check, ChevronRight, CircleHelp, Clock3, Map as MapIcon, RotateCcw, Sparkles, Trophy } from 'lucide-react'
import type { KnowledgeCard, KnowledgeTreeNode, KnowledgeVisualSummary, KnowledgeVisualTreeNode, LearningAttempt, LearningPlanDay, Question, SessionIdentity, StudentDashboardData, StructuredKnowledgeContent } from '../domain/types'
import { SKILLS } from '../data/catalog'
import { accessApi, submitAttempt } from '../lib/api'

type StudentView = 'today' | 'plan' | 'map' | 'growth'
type PlanPayload = { plan: LearningPlanDay; cards: KnowledgeCard[]; questions: Question[]; attemptSequence: number }

const statusLabel = (plan: LearningPlanDay, enrollment: string) => {
  if (plan.date < enrollment) return '加入前｜可补学'
  if (plan.attemptCount > 0) {
    if (plan.latestCompletedAt && plan.date > plan.latestCompletedAt.slice(0, 10)) return '已提前完成'
    if (plan.firstScore !== null && plan.latestScore !== null && plan.latestScore > plan.firstScore) return `复习后提升 ${plan.firstScore}→${plan.latestScore}`
    return plan.attemptCount > 1 ? `已复习 ${plan.attemptCount} 次` : '已完成'
  }
  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
  if (plan.date < today) return '可再次复习'
  if (plan.date > today) return '可提前复习'
  return '今天'
}

export function StudentApp({ session, initialDashboard, onDashboard }: { session: SessionIdentity; initialDashboard: StudentDashboardData; onDashboard: (data: StudentDashboardData) => void }) {
  const [view, setView] = useState<StudentView>('today')
  const [dashboard, setDashboard] = useState(initialDashboard)
  const [activePlan, setActivePlan] = useState<PlanPayload | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
  const todayPlan = dashboard.plans.find((plan) => plan.date === today) ?? dashboard.plans.find((plan) => plan.date >= today) ?? dashboard.plans[0]
  const cyclePlans = dashboard.plans
    .filter((plan) => plan.mode === 'REVIEW')
    .sort((a, b) => a.date.localeCompare(b.date))

  async function openPlan(plan: LearningPlanDay) {
    setBusy(true)
    setError('')
    try {
      const result = await accessApi<{ payload: PlanPayload }>(session, 'start_plan', { planId: plan.id })
      setActivePlan(result.payload)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '学习内容暂时无法打开。')
    } finally {
      setBusy(false)
    }
  }

  if (activePlan) {
    return <LearningRound session={session} payload={activePlan} onExit={() => setActivePlan(null)} onComplete={(next) => { setDashboard(next); onDashboard(next); setActivePlan(null); setView('growth') }} />
  }

  return (
    <div className="role-layout student-theme">
      <aside className="side-nav" aria-label="学生导航">
        <button className={view === 'today' ? 'active' : ''} onClick={() => setView('today')}><Sparkles />今天</button>
        <button className={view === 'plan' ? 'active' : ''} onClick={() => setView('plan')}><CalendarDays />学习计划</button>
        <button className={view === 'map' ? 'active' : ''} onClick={() => setView('map')}><MapIcon />能力星图</button>
        <button className={view === 'growth' ? 'active' : ''} onClick={() => setView('growth')}><Trophy />我的战绩</button>
      </aside>
      <div className="role-content">
        {error && <div className="inline-alert" role="alert">{error}</div>}
        {view === 'today' && <>
          <section className="welcome-banner">
            <div><span className="eyebrow">今天也只走一小步</span><h1>{dashboard.profile.displayName}，今天先把最值得的几件事稳住。</h1><p>{dashboard.profile.needsInitialDiagnostic ? '我们会先做一组轻量诊断，不会根据缺失数据猜你的水平。' : '系统已经结合课堂进度、记忆节点和最近表现排好了第一轮。'}</p></div>
            <div className="daily-orb"><b>{Math.min(dashboard.todayQuestionCount || 6, 8)}</b><span>第一轮题目</span></div>
          </section>
          {todayPlan ? <section className="focus-card">
            <div className="focus-icon"><BookOpen /></div>
            <div><span className="mode-pill">{todayPlan.mode === 'EXAM_SPRINT' ? '考前拿分' : '长期复习'}</span><h2>{todayPlan.title}</h2><div className="focus-topics">{todayPlan.knowledgeSummaries.map((topic) => <span key={topic}>{topic}</span>)}</div><div className="meta-row"><span><Clock3 size={15} />约{todayPlan.estimatedMinutes}分钟</span><span>不会提前显示后续总题量</span></div></div>
            <button className="primary-button compact" onClick={() => openPlan(todayPlan)} disabled={busy}>{busy ? '正在准备…' : '开始第一轮'}<ChevronRight size={18} /></button>
          </section> : <EmptyState text="甘老师还没有为今天安排正式任务。" />}
          <section className="section-block"><div className="section-head"><div><span className="eyebrow">最近获得</span><h2>已经亮起来的部分</h2></div><button className="text-button" onClick={() => setView('growth')}>查看全部</button></div>
            <div className="achievement-grid">{dashboard.achievements.slice(0, 3).map((item) => <article className="achievement-card" key={item.id}><div className="achievement-icon"><Trophy /></div><div><b>{item.title}</b><p>{item.description}</p></div></article>)}</div>
          </section>
        </>}
        {view === 'plan' && <PlanCalendar plans={cyclePlans} enrollment={dashboard.profile.enrollmentStartDate} onOpen={openPlan} busy={busy} />}
        {view === 'map' && <SkillGalaxy dashboard={dashboard} />}
        {view === 'growth' && <GrowthPage dashboard={dashboard} />}
      </div>
    </div>
  )
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

function PlanCalendar({ plans, enrollment, onOpen, busy }: { plans: LearningPlanDay[]; enrollment: string; onOpen: (plan: LearningPlanDay) => void; busy: boolean }) {
  const weeks = splitCalendarWeeks(plans)
  const first = plans[0]?.date
  const last = plans.at(-1)?.date
  const displayDate = (date?: string) => date ? `${Number(date.slice(5, 7))}月${Number(date.slice(8, 10))}日` : ''
  return <section><div className="page-title"><span className="eyebrow">{displayDate(first)}—{displayDate(last)}</span><h1>我的长期复习计划</h1><p>{displayDate(first)}是复习第1天；此后按自然周排列，过去可以重做，未来可以提前预习。</p></div>
    <div className="week-stack">{weeks.map((week, index) => <div className="week-card" key={week[0]?.date ?? index}><div className="week-label">{index === 0 ? '复习起始周' : `复习第 ${index + 1} 周`}</div><div className="week-grid">{week.map((plan) => <button key={plan.id} className="plan-day" onClick={() => onOpen(plan)} disabled={busy}><span className="plan-date">{plan.date.slice(5)} · {weekdayLabel(plan.date)}</span><b>{plan.title}</b><ul>{plan.knowledgeSummaries.map((topic) => <li key={topic}>{topic}</li>)}</ul><small>{plan.knowledgeSummaries.length}个知识点 · {plan.estimatedMinutes}分钟</small><em>{statusLabel(plan, enrollment)}</em></button>)}</div></div>)}</div>
  </section>
}

function SkillGalaxy({ dashboard }: { dashboard: StudentDashboardData }) {
  const states = new Map(dashboard.skillStates.map((state) => [state.skillId, state]))
  const visible = dashboard.skillDefinitions.filter((skill) => dashboard.profile.gradeBand === skill.gradeBand || dashboard.skillStates.some((state) => state.skillId === skill.id))
  const modules = visible.reduce<Record<string, typeof visible>>((grouped, skill) => {
    ;(grouped[skill.moduleId] ??= []).push(skill)
    return grouped
  }, {})
  return <section><div className="page-title"><span className="eyebrow">只和昨天的自己比较</span><h1>我的化学能力星图</h1><p>每一道光都来自真实检验。暗色不是失败，只表示还没有学到或还没有形成证据。</p></div>
    <div className="galaxy">{Object.entries(modules).map(([moduleId, skills]) => <div className="galaxy-zone" key={moduleId}><h2>{moduleName(moduleId)}</h2><div className="skill-grid">{(skills ?? []).map((skill) => { const state = states.get(skill.id); const level = state?.verifiedLevel ?? 0; return <article className={`skill-star ${level ? 'lit' : ''}`} key={skill.id}><div className="rings" style={{ '--progress': `${Math.max(8, level / skill.maxLevel * 100)}%` } as React.CSSProperties}><Sparkles /></div><b>{skill.title}</b><span>L{level} / L{skill.maxLevel}</span><div className="level-dots">{Array.from({ length: skill.maxLevel }, (_, i) => <i className={i < level ? 'on' : ''} key={i} />)}</div>{state?.stability === 'forgotten' && <em>正在重新找回</em>}{state?.stability === 'recovered' && <em>已重燃</em>}</article> })}</div></div>)}</div>
  </section>
}

function GrowthPage({ dashboard }: { dashboard: StudentDashboardData }) {
  const lit = dashboard.skillStates.filter((state) => state.verifiedLevel > 0).length
  const stable = dashboard.skillStates.filter((state) => state.stability === 'stable').length
  const recovered = dashboard.skillStates.filter((state) => state.stability === 'recovered').length
  return <section><div className="page-title"><span className="eyebrow">我的化学档案</span><h1>每一次理解，都留下来了。</h1><p>这里记录你已经获得的能力，不做同学之间的排行榜。</p></div>
    <div className="stat-grid"><div><b>{dashboard.skillStates.length}</b><span>已经走过的技能</span></div><div><b>{lit}</b><span>已经点亮</span></div><div><b>{stable}</b><span>完整通过</span></div><div><b>{recovered}</b><span>重新找回</span></div></div>
    <div className="section-block"><h2>最近新获得</h2><div className="achievement-list">{dashboard.achievements.map((item) => <article key={item.id}><Trophy /><div><b>{item.title}</b><p>{item.description}</p><small>{item.earnedAt.slice(0,10)}</small></div></article>)}</div></div>
  </section>
}

function LearningRound({ session, payload, onExit, onComplete }: { session: SessionIdentity; payload: PlanPayload; onExit: () => void; onComplete: (data: StudentDashboardData) => void }) {
  const [phase, setPhase] = useState<'cards' | 'quiz' | 'result'>('cards')
  const [cardIndex, setCardIndex] = useState(0)
  const [questionIndex, setQuestionIndex] = useState(0)
  const [selected, setSelected] = useState<number | null>(null)
  const [uncertain, setUncertain] = useState(false)
  const [answers, setAnswers] = useState<LearningAttempt['answers']>([])
  const [startedAt] = useState(new Date().toISOString())
  const [questionStartedAt, setQuestionStartedAt] = useState(Date.now())
  const [feedback, setFeedback] = useState(false)
  const [busy, setBusy] = useState(false)
  const [nextDashboard, setNextDashboard] = useState<StudentDashboardData | null>(null)
  const card = payload.cards[cardIndex]
  const question = payload.questions[questionIndex]

  if (phase === 'cards') return <section className="learning-stage"><button className="text-button" onClick={onExit}>← 返回计划</button><div className="review-outline"><b>今天复习什么</b>{payload.plan.knowledgeSummaries.map((topic) => <span key={topic}>{topic}</span>)}</div><div className="stage-progress"><i style={{ width: `${(cardIndex + 1) / Math.max(payload.cards.length, 1) * 100}%` }} /></div>{card ? <article className="knowledge-card"><span className="eyebrow">从零讲清楚 · {cardIndex + 1}/{payload.cards.length}</span><h1>{card.title}</h1>{!card.structuredContent?.visualSummary ? <div className="core-rule">{card.core}</div> : null}{card.structuredContent ? <StructuredKnowledgeMap content={card.structuredContent} /> : <details open><summary>展开理解</summary><p>{card.detail}</p><ol>{card.steps.map((step) => <li key={step}>{step}</li>)}</ol><div className="mistake-note"><b>容易踩坑</b><ul>{card.commonMistakes.map((mistake) => <li key={mistake}>{mistake}</li>)}</ul></div><p><b>完整例子：</b>{card.microExample}</p></details>}</article> : <EmptyState text="本轮知识卡正在审核，暂不向学生展示。" />}
    <div className="stage-actions"><button className="secondary-button" onClick={onExit}>稍后再学</button><button className="primary-button" onClick={() => { if (cardIndex < payload.cards.length - 1) setCardIndex(cardIndex + 1); else setPhase('quiz') }}>{cardIndex < payload.cards.length - 1 ? '下一张' : '我理解了，开始练习'}<ChevronRight size={18} /></button></div></section>

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
      const attempt: LearningAttempt = { id: crypto.randomUUID(), studentId: '', planDayId: payload.plan.id, attemptKind: payload.attemptSequence === 0 ? 'scheduled' : 'review', sequence: payload.attemptSequence, mode: payload.plan.mode, startedAt, completedAt: new Date().toISOString(), answers: finalAnswers, firstScore: finalAnswers.filter((answer) => answer.correct).length }
      try { const result = await submitAttempt(session, attempt); setNextDashboard(result.dashboard); setPhase('result') } finally { setBusy(false) }
    }
    return <section className="learning-stage"><div className="quiz-head"><span>第一轮 · {questionIndex + 1}/{payload.questions.length}</span><span>{SKILLS.find((skill) => skill.id === question.skillId)?.title}</span></div><div className="stage-progress"><i style={{ width: `${(questionIndex + 1) / payload.questions.length * 100}%` }} /></div><article className="question-card"><span className="difficulty-pill">L{question.level}检验</span><h1>{question.stem}</h1><div className="option-list">{question.options.map((option, index) => <button disabled={feedback} className={`${selected === index ? 'selected' : ''} ${feedback && index === question.correctOption ? 'correct' : ''} ${feedback && selected === index && index !== question.correctOption ? 'wrong' : ''}`} key={option} onClick={() => setSelected(index)}><span>{String.fromCharCode(65 + index)}</span>{option}</button>)}</div><label className="uncertain-toggle"><input type="checkbox" checked={uncertain} onChange={(event) => setUncertain(event.target.checked)} disabled={feedback} />我选了，但还不太确定</label>{feedback && <div className={`answer-feedback ${isCorrect ? 'good' : 'needs-work'}`}><b>{isCorrect ? '判断正确' : '先把关键一步稳住'}</b><p>{question.explanation}</p>{!isCorrect && question.scaffold && <p><CircleHelp size={16} />提示：{question.scaffold}</p>}</div>}</article><div className="stage-actions">{!feedback ? <button className="primary-button" disabled={selected === null} onClick={submit}>提交答案</button> : <button className="primary-button" disabled={busy} onClick={next}>{questionIndex < payload.questions.length - 1 ? '下一题' : '完成第一轮'}<ChevronRight size={18} /></button>}</div></section>
  }

  const correct = answers.filter((answer) => answer.correct).length
  return <section className="learning-stage result-stage"><div className="result-badge"><Check /></div><span className="eyebrow">今天的第一轮完成啦</span><h1>你已经完成了一次真实检验。</h1><p>本轮 {correct}/{answers.length}。系统会用新的母题继续确认，不会让你机械重复原题。</p><div className="result-stats"><div><b>{answers.length}</b><span>完成题目</span></div><div><b>{new Set(answers.map((answer) => answer.skillId)).size}</b><span>检验技能</span></div><div><b>{answers.filter((answer) => answer.uncertain).length}</b><span>不确定标记</span></div></div><button className="primary-button" disabled={!nextDashboard} onClick={() => nextDashboard && onComplete(nextDashboard)}>查看我获得了什么<Trophy size={18} /></button></section>
}

function KnowledgeBranch({ node, depth = 0 }: { node: KnowledgeTreeNode; depth?: number }) {
  return <li className={`knowledge-branch depth-${Math.min(depth, 3)}`}>
    <div className="branch-card point-with-demo"><div className="point-copy"><b>{node.label}</b><p>{node.rule}</p>{node.caution && <div className="branch-caution">注意：{node.caution}</div>}</div><NodeLearningAid node={node} /></div>
    {node.children?.length ? <ul>{node.children.map((child) => <KnowledgeBranch key={`${node.label}-${child.label}`} node={child} depth={depth + 1} />)}</ul> : null}
  </li>
}

function compactVisualStep(value: string) {
  const compact = value.replace(/^以“[^”]+”为示范：/, '').replace(/。.*$/u, '').trim()
  return compact.length > 26 ? `${compact.slice(0, 25)}…` : compact
}

function NodeLearningAid({ node }: { node: KnowledgeTreeNode }) {
  const visualSteps = (node.visualSteps?.length ? node.visualSteps : [node.label, ...(node.examples?.slice(0, 2) ?? ['按定义判断'])]).map(compactVisualStep)
  return <aside className="point-learning-aid" aria-label={`${node.label}的示范与图像记忆`}>
    <div className="point-demo"><b>马上看例子</b>{node.examples?.map((example) => <p key={example}>{example}</p>)}</div>
    <figure className="memory-diagram"><figcaption>图像记忆</figcaption><div className="memory-flow">{visualSteps.map((step, index) => <Fragment key={`${node.label}-${step}-${index}`}><span>{step}</span>{index < visualSteps.length - 1 ? <i aria-hidden="true">→</i> : null}</Fragment>)}</div></figure>
  </aside>
}

function visualTreeFromKnowledge(node: KnowledgeTreeNode): KnowledgeVisualTreeNode {
  return { label: node.label, children: node.children?.map(visualTreeFromKnowledge) }
}

function QuickTreeBranch({ node }: { node: KnowledgeVisualTreeNode }) {
  return <li className="quick-tree-branch"><span className="quick-tree-node">{node.label}</span>{node.children?.length ? <ul className="quick-tree-children">{node.children.map((child) => <QuickTreeBranch key={`${node.label}-${child.label}`} node={child} />)}</ul> : null}</li>
}

function fallbackVisual(content: StructuredKnowledgeContent): KnowledgeVisualSummary {
  if (content.rootTree) return { kind: 'tree', title: '知识关系总图', tree: visualTreeFromKnowledge(content.rootTree) }
  return {
    kind: 'flow',
    title: '先看逻辑路线',
    steps: content.sections.slice(0, 6).map((section, index) => ({ label: section.title, caption: `${index + 1}` })),
  }
}

function QuickVisualSummary({ visual }: { visual: KnowledgeVisualSummary }) {
  const groups = visual.groups ?? []
  return <figure className={`quick-visual quick-visual-${visual.kind}`} aria-label={`30秒图解：${visual.title}`}>
    <figcaption><span>30秒图解</span><b>{visual.title}</b></figcaption>
    {visual.kind === 'tree' && visual.tree ? <div className="quick-tree-visual"><ul className="quick-tree"><QuickTreeBranch node={visual.tree} /></ul>{visual.axes?.length ? <div className="quick-tree-axes"><b>横向分类轴</b>{visual.axes.map((axis) => <div className="quick-axis" key={axis.label}><strong>{axis.label}</strong><div>{axis.items.map((item) => <span key={item}>{item}</span>)}</div></div>)}</div> : null}</div> : null}
    {(visual.kind === 'flow' || visual.kind === 'cycle') && visual.steps?.length ? <ol className="quick-flow">{visual.steps.map((step, index) => <Fragment key={`${step.label}-${index}`}><li><small>{step.caption ?? String(index + 1).padStart(2, '0')}</small><b>{step.label}</b></li>{index < visual.steps!.length - 1 ? <i aria-hidden="true">→</i> : null}</Fragment>)}{visual.kind === 'cycle' ? <i className="cycle-return" aria-label="回到起点">↺</i> : null}</ol> : null}
    {visual.kind === 'compare' ? <div className="quick-compare">{groups.map((group) => <section key={group.label}><b>{group.label}</b><div>{group.items.map((item) => <span key={item}>{item}</span>)}</div></section>)}</div> : null}
    {visual.kind === 'network' ? <div className="quick-network"><div className="network-hub">{visual.center ?? visual.title}</div><div className="network-branches">{groups.map((group) => <section key={group.label}><b>{group.label}</b>{group.items.map((item) => <span key={item}>{item}</span>)}</section>)}</div></div> : null}
    {visual.kind === 'balance' ? <div className="quick-balance">{groups.map((group, index) => <Fragment key={group.label}><section><b>{group.label}</b>{group.items.map((item) => <span key={item}>{item}</span>)}</section>{index < groups.length - 1 ? <i aria-hidden="true">{visual.center ?? '='}</i> : null}</Fragment>)}</div> : null}
  </figure>
}

function StructuredKnowledgeMap({ content }: { content: StructuredKnowledgeContent }) {
  const offset = content.rootTree ? 2 : 1
  return <div className="knowledge-explainer">
    <QuickVisualSummary visual={content.visualSummary ?? fallbackVisual(content)} />
    <details className="full-explanation"><summary><span><b>从零学会</b><small>展开完整讲解、例子、易错边界与自查</small></span><i aria-hidden="true">⌄</i></summary><div className="classification-map">
      {content.rootTree ? <section className="knowledge-tree-panel" aria-labelledby="knowledge-tree-title"><div className="map-section-title"><span>01</span><div><h2 id="knowledge-tree-title">知识总树</h2><p>先沿纵向主干走完，再补横向标签。</p></div></div><ul className="knowledge-tree"><KnowledgeBranch node={content.rootTree} /></ul></section> : null}
      {content.sections.map((section, index) => <section className="classification-section" key={section.title}><div className="map-section-title"><span>{String(index + offset).padStart(2, '0')}</span><div><h2>{section.title}</h2>{section.summary && <p>{section.summary}</p>}</div></div><div className="classification-items">{section.items.map((item) => <article className="classification-item point-with-demo" key={item.label}><div className="point-copy"><b>{item.label}</b><p>{item.rule}</p>{item.caution && <div className="branch-caution">注意：{item.caution}</div>}</div><NodeLearningAid node={item} /></article>)}</div></section>)}
      {content.workedExamples?.length ? <section className="classification-section worked-examples"><div className="map-section-title"><span>{String(content.sections.length + offset).padStart(2, '0')}</span><div><h2>完整例题：把逻辑一步一步走通</h2><p>先看为什么，再看怎么算或怎样判断。</p></div></div><div className="worked-example-grid">{content.workedExamples.map((example) => <article key={example.substance}><h3>{example.substance}</h3><p>{example.path}</p><div className="example-chips">{example.labels.map((label) => <span key={label}>{label}</span>)}</div></article>)}</div></section> : null}
      {content.checkpoints?.length ? <section className="classification-section recall-check"><div className="map-section-title"><span>✓</span><div><h2>合上页面前，我应该能做到</h2><p>说不出来就回到对应小节，不需要硬撑着进入练习。</p></div></div><ul>{content.checkpoints.map((checkpoint) => <li key={checkpoint}>{checkpoint}</li>)}</ul></section> : null}
      {content.scopeNote ? <p className="scope-note"><b>范围说明：</b>{content.scopeNote}</p> : null}
    </div></details>
  </div>
}

function EmptyState({ text }: { text: string }) { return <div className="empty-state"><RotateCcw /><p>{text}</p></div> }

function moduleName(id: string) {
  const names: Record<string, string> = { F01: '物质世界', F02: '元素规律', F03: '微粒世界', F04: '离子反应', F05: '反应世界', F06: '计量世界', 'H1-F01': '物质分类', 'H1-F01A': '电解质基础', 'H1-F02': '元素周期律', 'H1-F03': '氧化还原', 'H1-F04': '离子反应', 'H1-F05': '物质的量', 'H1-F05A': '物质的量基础', 'H1-F06': '钠和氯', E01: '钠的世界', E02: '氯的世界', H201: '速率与平衡', H202: '平衡计算', H203: '水溶液', H204: '电化学', H301: '离子基础', H302: '工艺流程', H303: '有机世界', H304: '结构世界', J01: '微粒启蒙', J02: '物质基础' }
  return names[id] ?? id
}
