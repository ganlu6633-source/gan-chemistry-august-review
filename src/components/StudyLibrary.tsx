import { useMemo, useState } from 'react'
import { BookOpen, ChevronRight, ExternalLink, Search, X } from 'lucide-react'
import { LECTURE_BOOKS, LECTURE_SECTIONS, lectureUrl, type LectureSection } from '../data/lectureCatalog'
import type { LearningPlanDay, StudentDashboardData } from '../domain/types'

export type LibraryAxis = 'stage' | 'knowledge' | 'type'

const AXIS_COPY = {
  stage: { title: '按学习阶段或进度节点', intro: '从讲义的专题与复习阶段选择。每个节点都能直接打开讲义。' },
  knowledge: { title: '按知识点', intro: '从讲义目录选择具体知识点，已经学过的可以回看，未学过的也能先学。' },
  type: { title: '按题型', intro: '从讲义中的题型板块进入。高三选择题与综合题材料分开列出。' },
} as const

function relevantPlan(section: LectureSection, plans: LearningPlanDay[], today: string) {
  return plans.filter((plan) => plan.date <= today && section.skillIds.some((skill) => plan.skillIds.includes(skill)))
    .sort((a, b) => Number(a.isComplete) - Number(b.isComplete) || b.date.localeCompare(a.date))[0]
}

export function StudyLibrary({ axis, dashboard, onOpenPlan, busy }: {
  axis: LibraryAxis
  dashboard: StudentDashboardData
  onOpenPlan: (plan: LearningPlanDay) => void
  busy: boolean
}) {
  const [search, setSearch] = useState('')
  const [active, setActive] = useState<LectureSection | null>(null)
  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
  const sections = useMemo(() => LECTURE_SECTIONS.filter((section) => section.grade === dashboard.profile.gradeBand), [dashboard.profile.gradeBand])
  const filtered = sections.filter((section) => `${section.title} ${section.stage} ${section.type} ${LECTURE_BOOKS[section.book].title}`.includes(search.trim()))
  const groups = new Map<string, LectureSection[]>()
  filtered.forEach((section) => {
    const label = axis === 'stage' ? section.stage : axis === 'type' ? section.type : LECTURE_BOOKS[section.book].title
    groups.set(label, [...(groups.get(label) ?? []), section])
  })

  if (active) {
    const plan = relevantPlan(active, dashboard.plans, today)
    return <section className="lecture-reader" aria-label={`${active.title}讲义`}>
      <div className="lecture-reader-head">
        <button type="button" className="text-button" onClick={() => setActive(null)}><X size={16} />返回{AXIS_COPY[axis].title}</button>
        <div><span className="eyebrow">{LECTURE_BOOKS[active.book].title} · 第 {active.page}—{active.endPage} 页</span><h1>{active.title}</h1></div>
        <div className="lecture-reader-actions"><a className="secondary-button compact" href={lectureUrl(active)} target="_blank" rel="noopener noreferrer">单独打开讲义<ExternalLink size={15} /></a>{plan && <button type="button" className="primary-button compact" onClick={() => onOpenPlan(plan)} disabled={busy}>做相关已安排原题<ChevronRight size={16} /></button>}</div>
      </div>
      <p className="lecture-source-note">下方是讲义原页。做题时可在纸上演算；题组只会使用网站中已审核的选择题。{!plan && '这节尚无可直接打开的已安排题组，可以先阅读讲义。'}</p>
      <iframe title={`${active.title}讲义原页`} src={lectureUrl(active)} loading="lazy" />
    </section>
  }

  return <section className="study-library">
    <div className="page-title"><span className="eyebrow">{dashboard.profile.gradeBand} · 讲义原页</span><h1>{AXIS_COPY[axis].title}</h1><p>{AXIS_COPY[axis].intro}</p></div>
    <label className="library-search"><Search size={18} aria-hidden="true" /><span className="sr-only">搜索知识点或题型</span><input type="search" placeholder="搜索知识点、题型或专题" value={search} onChange={(event) => setSearch(event.target.value)} /></label>
    {groups.size === 0 ? <p className="empty-state">没有找到对应的讲义章节。</p> : [...groups].map(([label, items]) => <section className="library-group" key={label}><div className="library-group-head"><h2>{label}</h2><span>{items.length} 节</span></div><div className="library-grid">{items.map((section) => {
      const plan = relevantPlan(section, dashboard.plans, today)
      return <button type="button" className="library-card" key={section.id} onClick={() => setActive(section)}><span className="library-card-book"><BookOpen size={15} />{LECTURE_BOOKS[section.book].title}</span><b>{section.title}</b><span>{section.type} · 第 {section.page}—{section.endPage} 页</span><em>{plan ? '讲义 + 相关已安排原题' : '打开讲义'}</em><ChevronRight className="library-card-arrow" size={18} /></button>
    })}</div></section>)}
  </section>
}
