import { useEffect, useMemo, useState } from 'react'
import { BookOpen, ChevronRight, ExternalLink, Search, Trophy } from 'lucide-react'
import { LECTURE_SECTIONS, lectureUrl } from '../data/lectureCatalog'
import type { SessionIdentity, StudentDashboardData } from '../domain/types'
import { accessApi } from '../lib/api'

export type LibraryAxis = 'stage' | 'knowledge' | 'type'
type Topic = { skillId: string; skillTitle: string; conceptKey: string; title: string; sequence: number; originalCount: number; freshCount: number }
const COPY = {
  stage: ['按学习阶段', '从当前专题选一个知识点，直接做已核对的原题。'],
  knowledge: ['按知识点', '自己挑选想突破的知识点，纸上演算后选择 A、B、C、D。'],
  type: ['按题型', '从选择题专题进入；所有题组都用题库原题和四个选项。'],
} as const

export function StudyLibrary({ axis, dashboard, session, onStart, busy }: {
  axis: LibraryAxis
  dashboard: StudentDashboardData
  session: SessionIdentity
  onStart: (skillId: string, conceptKey: string) => Promise<void>
  busy: boolean
}) {
  const [search, setSearch] = useState('')
  const [topics, setTopics] = useState<Topic[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const grade = dashboard.profile.gradeBand
  useEffect(() => {
    let active = true
    setLoading(true)
    setError('')
    accessApi<{ catalog: { topics: Topic[] } }>(session, 'self_study_catalog', dashboard.profile.isDemo ? { studentId: dashboard.profile.id } : {})
      .then((result) => { if (active) setTopics(result.catalog.topics) })
      .catch((reason) => { if (active) setError(reason instanceof Error ? reason.message : '题库目录暂时无法加载。') })
      .finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [session, dashboard.profile.id, dashboard.profile.isDemo])

  const lectureBySkill = useMemo(() => {
    const map = new Map<string, typeof LECTURE_SECTIONS[number]>()
    LECTURE_SECTIONS.filter((section) => section.grade === grade).forEach((section) => section.skillIds.forEach((skill) => {
      if (!map.has(skill)) map.set(skill, section)
    }))
    return map
  }, [grade])
  const groups = new Map<string, Topic[]>()
  topics.filter((topic) => `${topic.title} ${topic.skillTitle} ${lectureBySkill.get(topic.skillId)?.type || ''}`.includes(search.trim()))
    .sort((a, b) => a.skillTitle.localeCompare(b.skillTitle, 'zh-CN') || a.sequence - b.sequence)
    .forEach((topic) => {
      const lecture = lectureBySkill.get(topic.skillId)
      const label = axis === 'stage' ? lecture?.stage || '题库补充专题'
        : axis === 'type' ? `选择题 · ${lecture?.type || topic.skillTitle}` : topic.skillTitle
      groups.set(label, [...groups.get(label) || [], topic])
    })
  const challenges = dashboard.plans.filter((plan) => plan.deliveryMode === 'self_study' && plan.isComplete)
  const completed = new Set(challenges.flatMap((plan) => plan.targetConceptKeys ?? []))
  const perfect = new Set(challenges.filter((plan) => plan.latestScore === plan.questionCount).flatMap((plan) => plan.targetConceptKeys ?? []))

  return <section className="study-library">
    <div className="page-title"><span className="eyebrow">{grade} · 原题闯关</span><h1>{COPY[axis][0]}</h1><p>{COPY[axis][1]}</p></div>
    <div className="self-study-progress"><Trophy size={20} /><span>已挑战 <b>{completed.size}/{topics.length}</b> 个知识点</span><span>满分通关 {perfect.size} 个 · 每关 3 道原题</span></div>
    <label className="library-search"><Search size={18} aria-hidden="true" /><span className="sr-only">搜索知识点或题型</span><input type="search" placeholder="搜索知识点或题型" value={search} onChange={(event) => setSearch(event.target.value)} /></label>
    {loading && <p className="empty-state">正在核对原题目录…</p>}
    {error && <p className="inline-alert" role="alert">{error}</p>}
    {!loading && !error && groups.size === 0 && <p className="empty-state">没有找到这个知识点的已审核选择题。</p>}
    {[...groups].map(([label, items]) => <section className="library-group" key={label}><div className="library-group-head"><h2>{label}</h2><span>{items.length} 个知识点</span></div><div className="library-grid">{items.map((topic) => {
      const lecture = lectureBySkill.get(topic.skillId)
      const ready = topic.freshCount >= 3
      const status = perfect.has(topic.conceptKey) ? '满分通关' : completed.has(topic.conceptKey) ? '已挑战' : '待挑战'
      return <article className="library-card self-study-card" key={topic.conceptKey}>
        <span className="library-card-book"><BookOpen size={15} />{topic.skillTitle} · {status}</span><b>{topic.title}</b>
        <span>{topic.originalCount} 道已核对原题 · 还可练 {topic.freshCount} 道</span>
        <div className="self-study-card-actions"><button type="button" className="primary-button compact" disabled={!ready || busy || dashboard.profile.isDemo} onClick={() => void onStart(topic.skillId, topic.conceptKey)}>{ready ? dashboard.profile.isDemo ? '演示账号只读' : completed.has(topic.conceptKey) ? '再练一关' : '开始闯关' : '新题不足 3 道'}<ChevronRight size={16} /></button>
        {lecture && <a href={lectureUrl(lecture)} target="_blank" rel="noopener noreferrer" aria-label={`查看${topic.title}相关讲义`}>相关讲义<ExternalLink size={14} /></a>}</div>
      </article>
    })}</div></section>)}
    {!loading && !error && <p className="lecture-source-note">题目、答案和解析来自已审核的本地原题库。相关讲义仅供需要时查阅；已做过的同一原题不会作为新题再次下发。</p>}
  </section>
}
