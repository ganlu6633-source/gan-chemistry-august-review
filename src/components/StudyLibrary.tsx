import { useMemo, useState } from 'react'
import { BookOpen, ChevronRight, ExternalLink, Search, Trophy } from 'lucide-react'
import { LECTURE_SECTIONS, lectureUrl } from '../data/lectureCatalog'
import { buildKnowledgeCardDrilldown, knowledgeSectionTree } from '../domain/knowledgeDrilldown'
import { isStructuredKnowledgeContent } from '../domain/knowledgeContent'
import type { KnowledgeCard, StudentDashboardData } from '../domain/types'
import { InteractiveKnowledgeTree } from './InteractiveKnowledgeTree'
import './StudyLibrary.css'

export type LibraryAxis = 'stage' | 'knowledge' | 'type'
export type StudyTopic = { skillId: string; skillTitle: string; conceptKey: string; title: string; sequence: number; originalCount: number; freshCount: number; releaseId: string; releaseKind: 'primary' | 'teaching_material'; answeredCount: number; recentCorrect: number; reviewDueAt: string | null; reviewPriority: number; reviewReason: string | null }
const COPY = {
  stage: ['跟着进度走', '每个班进度不同。找到你学到的这一站，挑组原题开练。'],
  knowledge: ['知识点任选', '想攻哪块就点哪块；纸上算一算，再选 A、B、C、D。'],
  type: ['题型训练场', '想练哪类题，自己挑。这里都是真实原题，照常四选一。'],
} as const

function KnowledgeTreeDisclosure({ label, skillId, onLoad }: { label: string; skillId: string; onLoad: (skillId: string) => Promise<KnowledgeCard | null> }) {
  const [open, setOpen] = useState(false)
  const [card, setCard] = useState<KnowledgeCard | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  async function toggle() {
    if (open) { setOpen(false); return }
    setOpen(true)
    if (card) return
    setLoading(true)
    setError('')
    try {
      const loaded = await onLoad(skillId)
      if (loaded) setCard(loaded)
      else setError('这一块还没有可学习的已审核知识卡。')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '知识树暂时没打开，请再试一次。')
    } finally { setLoading(false) }
  }

  const content = card?.structuredContent
  return <div className="library-knowledge-disclosure">
    <button type="button" className="library-knowledge-toggle" aria-expanded={open} onClick={() => void toggle()}>
      <span><ChevronRight size={18} aria-hidden="true" /><b>{label}</b></span><small>{open ? '收起知识树' : '点开大知识点，逐层看小点和例子'}</small>
    </button>
    {open && <div className="library-knowledge-content">
      {loading && <p role="status">正在打开知识树…</p>}
      {error && <p className="inline-alert" role="alert">{error}</p>}
      {card && <InteractiveKnowledgeTree root={buildKnowledgeCardDrilldown(card)} title={`${label} · 知识树`} />}
      {card && isStructuredKnowledgeContent(content) && content.rootTree && content.sections.length > 0 && <details className="knowledge-extra-tree"><summary>继续拆解：判断方法与易错小点</summary>
        <InteractiveKnowledgeTree root={knowledgeSectionTree(content, card.title, card)} title={`${label} · 小点与易错`} />
      </details>}
    </div>}
  </div>
}

export function StudyLibrary({ axis, dashboard, topics, loading, error, onStart, onLoadKnowledge, busy }: {
  axis: LibraryAxis
  dashboard: StudentDashboardData
  topics: StudyTopic[]
  loading: boolean
  error: string
  onStart: (skillId: string, conceptKey: string, releaseId: string) => Promise<void>
  onLoadKnowledge?: (skillId: string) => Promise<KnowledgeCard | null>
  busy: boolean
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
      const groupKey = axis === 'knowledge' ? `${topic.skillId}\u0000${label}` : label
      groups.set(groupKey, [...groups.get(groupKey) || [], topic])
    })
  if (axis === 'knowledge') {
    const groupedSkills = new Set([...groups.keys()].map((key) => key.split('\u0000')[0]))
    for (const skill of dashboard.skillDefinitions.filter((item) => item.gradeBand === grade && item.title.includes(search.trim()))) {
      const groupKey = `${skill.id}\u0000${skill.title}`
      if (!groupedSkills.has(skill.id)) groups.set(groupKey, [])
    }
  }
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
    {[...groups].map(([groupKey, items]) => {
      const label = axis === 'knowledge' ? groupKey.split('\u0000')[1] : groupKey
      return <section className="library-group" key={groupKey}>
      {axis === 'knowledge' && onLoadKnowledge
        ? <KnowledgeTreeDisclosure label={label} skillId={groupKey.split('\u0000')[0]} onLoad={onLoadKnowledge} />
        : <div className="library-group-head"><h2>{label}</h2><span>{items.length} 个知识点</span></div>}
      {items.length === 0 && <p className="library-no-questions">这块目前没有已审核的四选一原题；知识树仍可点开学习。</p>}
      <div className="library-grid">{items.map((topic) => {
      const lecture = lectureBySkill.get(topic.skillId)
      const ready = topic.freshCount >= 1
      const status = perfect.has(topic.conceptKey) ? '满分通关' : completed.has(topic.conceptKey) || topic.answeredCount > 0 ? '已练过' : '待挑战'
      return <article className="library-card self-study-card" key={`${topic.conceptKey}:${topic.releaseId}`}>
        <span className="library-card-book"><BookOpen size={15} />{topic.skillTitle} · {topic.releaseKind === 'teaching_material' ? '讲义原题' : '题库原题'} · {status}</span><b>{topic.title}</b>
        <span>{topic.originalCount} 道核对过的原题 · 还有 {topic.freshCount} 道没做{topic.reviewPriority > 0 ? ' · 该回来练练' : ''}</span>
        <div className="self-study-card-actions"><button type="button" className="primary-button compact" disabled={!ready || busy || dashboard.profile.isDemo} onClick={() => void onStart(topic.skillId, topic.conceptKey, topic.releaseId)}>{ready ? dashboard.profile.isDemo ? '演示账号只读' : completed.has(topic.conceptKey) ? '再练一组' : '开始练题' : '这块暂时没新题'}<ChevronRight size={16} /></button>
        {lecture && <a href={lectureUrl(lecture)} target="_blank" rel="noopener noreferrer" aria-label={`查看${topic.title}相关讲义`}>先看讲义<ExternalLink size={14} /></a>}</div>
      </article>
    })}</div></section>})}
    {!loading && !error && <p className="lecture-source-note">这里的题目、答案和解析都来自已审核的本地题库。想先看讲义也可以；做过的原题不会换个名字再当新题出现。</p>}
  </section>
}
