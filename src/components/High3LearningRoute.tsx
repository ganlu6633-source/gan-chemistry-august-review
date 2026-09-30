import { useState } from 'react'
import { ChevronRight, Route, Search } from 'lucide-react'
import { high3LearningStops } from '../domain/high3StudyNavigation'
import { calendarPlanProgress, isKnowledgeOnlyFuturePlan } from '../domain/learningCalendar'
import type { LearningPlanDay, StudentDashboardData } from '../domain/types'
import { ChemText } from './ChemText'
import './StudyLibrary.css'

function actionLabel(plan: LearningPlanDay, today: string) {
  const progress = calendarPlanProgress(plan)
  if (progress === 'completed') return '回顾与复习'
  if (progress === 'in_progress') return '接着练'
  if (progress === 'blocked') return '查看保留进度'
  return isKnowledgeOnlyFuturePlan(plan, today) ? '先预习这一组' : '开始这一组'
}

export function High3LearningRoute({ dashboard, today, onOpenPlan, busy }: {
  dashboard: StudentDashboardData
  today: string
  onOpenPlan: (plan: LearningPlanDay) => Promise<boolean>
  busy: boolean
}) {
  const [search, setSearch] = useState('')
  const [openStop, setOpenStop] = useState<string | null>(null)
  const [closedSearchStops, setClosedSearchStops] = useState<string[]>([])
  const stops = high3LearningStops(dashboard.plans, dashboard.skillDefinitions)
  const lessons = stops.flatMap((stop) => stop.plans)
  const resume = lessons.find((plan) => calendarPlanProgress(plan) === 'in_progress')
  const next = resume ?? lessons.find((plan) => calendarPlanProgress(plan) === 'not_started')
  const completedCount = lessons.filter((plan) => calendarPlanProgress(plan) === 'completed').length
  const keyword = search.trim()

  return <section className="study-library high3-learning-route">
    <div className="page-title"><span className="eyebrow">高三 · 我的学习路线</span><h1>跟着进度走</h1><p>按老师给你的进度，一站一站练；也可以跳到想学的站点。没做过的随时补，做过的随时回顾。</p></div>
    <div className="route-progress"><Route size={21} aria-hidden="true" /><span>已完成 <b>{completedCount}</b> 组<span className="route-progress-note"> · 以实际练习记录为准</span></span></div>
    {next && <div className="route-resume"><div><small>{resume ? '上次练到这里' : '还没开始的题组'}</small><b><ChemText>{next.title}</ChemText></b></div><button type="button" className="primary-button compact" disabled={busy} onClick={() => void onOpenPlan(next)}>{actionLabel(next, today)}<ChevronRight size={16} /></button></div>}
    <label className="library-search"><Search size={18} aria-hidden="true" /><span className="sr-only">搜索学习站点或题组</span><input type="search" placeholder="搜索学习站点或题组" value={search} onChange={(event) => { setSearch(event.target.value); setClosedSearchStops([]) }} /></label>
    {stops.length === 0 && <p className="empty-state">你的学习路线还没排好。可以先去“知识点任选”或“题型训练场”自由练习。</p>}
    {stops.length > 0 && !stops.some((stop) => `${stop.title} ${stop.plans.map((plan) => `${plan.title} ${plan.knowledgeSummaries.join(' ')}`).join(' ')}`.includes(keyword)) && <p className="empty-state">没找到这一站，换个词试试。</p>}
    <div className="route-stops">{stops.map((stop, index) => {
      const plans = keyword ? stop.plans.filter((plan) => `${stop.title} ${plan.title} ${plan.knowledgeSummaries.join(' ')}`.includes(keyword)) : stop.plans
      if (!plans.length) return null
      const done = stop.plans.filter((plan) => calendarPlanProgress(plan) === 'completed').length
      const expanded = keyword ? !closedSearchStops.includes(stop.id) : openStop === stop.id
      return <section className="route-stop" key={stop.id}>
        <button type="button" className="route-stop-toggle" aria-expanded={expanded} aria-controls={`route-stop-${stop.id}`} onClick={() => {
          if (keyword) setClosedSearchStops((closed) => expanded ? [...closed, stop.id] : closed.filter((id) => id !== stop.id))
          else setOpenStop(expanded ? null : stop.id)
        }}>
          <span className="route-stop-number">{index + 1}</span><span className="route-stop-title"><b>{stop.title}</b><small>{stop.plans.length} 组练习 · 已完成 {done} 组</small></span><ChevronRight size={20} aria-hidden="true" />
        </button>
        {expanded && <ol className="route-lessons" id={`route-stop-${stop.id}`}>{plans.map((plan) => {
          const progress = calendarPlanProgress(plan)
          const status = progress === 'completed' ? '已完成' : progress === 'in_progress' ? '进行中' : progress === 'blocked' ? '进度已保留' : '还没学过'
          return <li key={plan.id} className={`route-lesson route-lesson-${progress}`}>
            <div><span className="route-lesson-status">{status}</span><h3><ChemText>{plan.title}</ChemText></h3><p><ChemText>{plan.knowledgeSummaries.join(' · ')}</ChemText></p></div>
            <button className="secondary-button compact" type="button" disabled={busy} onClick={() => void onOpenPlan(plan)}>{actionLabel(plan, today)}</button>
          </li>
        })}</ol>}
      </section>
    })}</div>
  </section>
}
