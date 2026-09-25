import { useMemo, useState } from 'react'
import { BookOpen, ChevronRight, ExternalLink, Search, Trophy } from 'lucide-react'
import { LECTURE_SECTIONS, lectureUrl } from '../data/lectureCatalog'
import type { StudentDashboardData } from '../domain/types'

export type LibraryAxis = 'stage' | 'knowledge' | 'type'
export type StudyTopic = { skillId: string; skillTitle: string; conceptKey: string; title: string; sequence: number; originalCount: number; freshCount: number; releaseId: string; releaseKind: 'primary' | 'teaching_material'; answeredCount: number; recentCorrect: number; reviewDueAt: string | null; reviewPriority: number; reviewReason: string | null }
const COPY = {
  stage: ['跟着进度走', '每个班进度不同。找到你学到的这一站，挑组原题开练。'],
  knowledge: ['知识点任选', '想攻哪块就点哪块；纸上算一算，再选 A、B、C、D。'],
  type: ['题型训练场', '想练哪类题，自己挑。这里都是真实原题，照常四选一。'],
} as const

export function StudyLibrary({ axis, dashboard, topics, loading, error, onStart, busy, readOnly = false }: {
  axis: LibraryAxis
  dashboard: StudentDashboardData
  topics: StudyTopic[]
  loading: boolean
  error: string
  onStart: (skillId: string, conceptKey: string, releaseId: string) => Promise<void>
  busy: boolean
  readOnly?: boolean
}) {
  const [search, setSearch] = useState('')
  const grade = dashboard.profile.gradeBand

  const lectureBySkill = useMemo(() => {
    const map = new Map<string, typeof LECTURE_SECTIONS[number]>()
    LECTURE_SECTIONS.filter((section) => section.grade === grade).forEach((section) => section.skillIds.forEach((skill) => {
      if (!map.has(skill)) map.set(skill, section)
    }))
    return map
  }, [grade])
  const groups = new Map<string, StudyTopic[]>()
  topics.filter((topic) => `${topic.title} ${topic.skillTitle} ${lectureBySkill.get(topic.skillId)?.type || ''}`.includes(search.trim()))
    .sort((a, b) => a.skillTitle.localeCompare(b.skillTitle, 'zh-CN') || a.sequence - b.sequence)
    .forEach((topic) => {
      const lecture = lectureBySkill.get(topic.skillId)
      const label = axis === 'stage' ? lecture?.stage || (grade === '初三' ? '科粤版 · 当前单元' : '题库补充专题')
        : axis === 'type' ? `选择题 · ${lecture?.type || topic.skillTitle}` : topic.skillTitle
      groups.set(label, [...groups.get(label) || [], topic])
    })
  const challenges = dashboard.plans.filter((plan) => plan.deliveryMode === 'self_study' && plan.isComplete)
  const completed = new Set(challenges.flatMap((plan) => plan.targetConceptKeys ?? []))
  const perfect = new Set(challenges.filter((plan) => plan.latestScore === plan.questionCount).flatMap((plan) => plan.targetConceptKeys ?? []))

  return <section className="study-library">
    <div className="page-title"><span className="eyebrow">{grade} · 原题练习</span><h1>{COPY[axis][0]}</h1><p>{COPY[axis][1]}</p></div>
    <div className="self-study-progress"><Trophy size={20} /><span>已挑战 <b>{completed.size}/{new Set(topics.map((topic) => topic.conceptKey)).size}</b> 个知识点</span><span>满分通关 {perfect.size} 个 · 每次练 1—3 道同考点原题</span></div>
    <label className="library-search"><Search size={18} aria-hidden="true" /><span className="sr-only">搜索知识点或题型</span><input type="search" placeholder="搜索知识点或题型" value={search} onChange={(event) => setSearch(event.target.value)} /></label>
    {loading && <p className="empty-state">正在把题库搬过来…</p>}
    {error && <p className="inline-alert" role="alert">{error}</p>}
    {!loading && !error && groups.size === 0 && <p className="empty-state">没找到对应的已审核选择题，换个词试试。</p>}
    {[...groups].map(([label, items]) => <section className="library-group" key={label}><div className="library-group-head"><h2>{label}</h2><span>{items.length} 个知识点</span></div><div className="library-grid">{items.map((topic) => {
      const lecture = lectureBySkill.get(topic.skillId)
      const ready = topic.freshCount >= 1
      const status = perfect.has(topic.conceptKey) ? '满分通关' : completed.has(topic.conceptKey) || topic.answeredCount > 0 ? '已练过' : '待挑战'
      return <article className="library-card self-study-card" key={`${topic.conceptKey}:${topic.releaseId}`}>
        <span className="library-card-book"><BookOpen size={15} />{topic.skillTitle} · {topic.releaseKind === 'teaching_material' ? '讲义原题' : '题库原题'} · {status}</span><b>{topic.title}</b>
        <span>{topic.originalCount} 道核对过的原题 · 还有 {topic.freshCount} 道没做{topic.reviewPriority > 0 ? ' · 该回来练练' : ''}</span>
        <div className="self-study-card-actions"><button type="button" className="primary-button compact" disabled={!ready || busy || dashboard.profile.isDemo} onClick={() => void onStart(topic.skillId, topic.conceptKey, topic.releaseId)}>{readOnly ? '只读预览' : ready ? dashboard.profile.isDemo ? '演示账号只读' : completed.has(topic.conceptKey) ? '再练一组' : '开始练题' : '这块暂时没新题'}<ChevronRight size={16} /></button>
        {lecture && <a href={lectureUrl(lecture)} target="_blank" rel="noopener noreferrer" aria-label={`查看${topic.title}相关讲义`}>先看讲义<ExternalLink size={14} /></a>}</div>
      </article>
    })}</div></section>)}
    {!loading && !error && <p className="lecture-source-note">这里的题目、答案和解析都来自已审核的本地题库。想先看讲义也可以；做过的原题不会换个名字再当新题出现。</p>}
  </section>
}
