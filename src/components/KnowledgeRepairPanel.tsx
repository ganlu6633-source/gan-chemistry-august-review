import { useState } from 'react'
import { BookOpen, ChevronRight, RotateCcw } from 'lucide-react'
import type { KnowledgeCard, KnowledgeTreeNode } from '../domain/types'
import type { KnowledgeConfidence, RecoveryTarget } from '../domain/learningRecovery'
import type { StudyTopic } from './StudyLibrary'
import { isStructuredKnowledgeContent } from '../domain/knowledgeContent'
import { ChemText } from './ChemText'

export function KnowledgeConfidencePicker({ value, onChange }: { value?: KnowledgeConfidence; onChange: (value: KnowledgeConfidence) => void }) {
  const choices: Array<{ value: KnowledgeConfidence; label: string; detail: string }> = [
    { value: 'unknown', label: '不知道', detail: '需要从头捋一遍' },
    { value: 'familiar', label: '眼熟', detail: '见过，但还做不稳' },
    { value: 'fluent', label: '熟练', detail: '能独立解释并做题' },
  ]
  return <div className="knowledge-confidence" role="group" aria-label="这块知识现在有多熟">
    <b>这块知识现在有多熟？</b><span>先凭感觉选，真正掌握还要看后面的原题。</span>
    <div>{choices.map((choice) => <button type="button" key={choice.value} className={value === choice.value ? 'selected' : ''}
      aria-pressed={value === choice.value} onClick={() => onChange(choice.value)}><strong>{choice.label}</strong><small>{choice.detail}</small></button>)}</div>
  </div>
}

type RepairSection = { id: string; title: string; items: KnowledgeTreeNode[] }

function sectionsFor(card: KnowledgeCard | undefined, target: RecoveryTarget, explanation?: string): RepairSection[] {
  if (card && isStructuredKnowledgeContent(card.structuredContent) && card.structuredContent.sections.length) {
    const sections = card.structuredContent.sections.map((section, index) => ({ ...section, id: `${card.id}:${index}` }))
    const route = card.structuredContent.overview?.find((item) => item.includes('电子') && item.includes('外电路'))
    if ((card.skillId === 'H3_ELECTRO' || card.skillId === 'H2_ELECTRO') && route) return [
      ...sections.slice(0, 1),
      { id: `${card.id}:electron-route`, title: '电子流向与离子迁移', items: [{ label: '电子走哪里、离子走哪里', rule: route }] },
      ...sections.slice(1),
    ]
    return sections
  }
  const rule = card?.core || explanation || '请结合刚才的原题解析，先说清判断依据，再做同知识点原题。'
  return [{ id: `${target.key}:core`, title: target.title, items: [{ label: target.title, rule,
    examples: card?.microExample ? [card.microExample] : undefined }] }]
}

export function KnowledgeRepairPanel({ target, card, explanation, practiceTopics = [], onBack, onPractice, onRating, practiceBusy }: {
  target: RecoveryTarget
  card?: KnowledgeCard
  explanation?: string
  practiceTopics?: StudyTopic[]
  onBack: () => void
  onPractice?: (conceptKey: string) => Promise<void>
  onRating?: (point: string, rating: KnowledgeConfidence) => void
  practiceBusy?: boolean
}) {
  const sections = sectionsFor(card, target, explanation)
  const suggested = target.branch?.knowledgePoint || target.title
  const suggestedIndex = sections.findIndex((section) => section.title.includes(suggested)
    || section.items.some((item) => item.label.includes(suggested) || suggested.includes(item.label)))
  const [sectionIndex, setSectionIndex] = useState<number | null>(suggestedIndex >= 0 ? suggestedIndex : sections.length === 1 ? 0 : null)
  const [pointIndex, setPointIndex] = useState(0)
  const [ratings, setRatings] = useState<Record<string, KnowledgeConfidence>>({})
  const section = sectionIndex === null ? undefined : sections[sectionIndex]
  const point: KnowledgeTreeNode | undefined = section?.items[pointIndex]
  const done = Boolean(section && pointIndex >= section.items.length)

  function rate(value: KnowledgeConfidence) {
    if (!section || !point) return
    const key = `${section.id}:${point.label}`
    setRatings((current) => ({ ...current, [key]: value }))
    onRating?.(`${section.title} · ${point.label}`, value)
    setPointIndex((index) => index + 1)
  }

  return <section className="learning-stage repair-stage">
    <button type="button" className="text-button" onClick={onBack}>← 返回本轮结果</button>
    <div className="repair-intro"><span className="eyebrow"><BookOpen size={16} />知识点补给站</span><h1><ChemText>{target.title}</ChemText></h1>
      <p>{target.branch ? '这条小点来自刚才选错的选项及甘老师审核过的对应关系。' : '一道错题只能说明这一块还要查一查；请你选出真正卡住的小点。'}</p></div>
    {sectionIndex === null ? <div className="repair-section-list"><h2>先找卡住的那一环</h2><p>选你最想弄明白的部分，一次只啃一小块。</p>
      <div>{sections.map((item, index) => <button type="button" key={item.id} onClick={() => { setSectionIndex(index); setPointIndex(0) }}><span><ChemText>{item.title}</ChemText></span><small>{item.items.length} 个小点</small><ChevronRight size={17} /></button>)}</div>
    </div> : done && section ? <div className="repair-finished"><h2>这块复习完，拿原题检验一下</h2><p>“不知道／眼熟／熟练”是你的自我判断；系统会以之后的选择题作答继续检验，不会因为点了“熟练”就直接判定掌握。</p>
      <div className="repair-rating-summary">{section.items.map((item) => <span key={item.label}><ChemText>{item.label}</ChemText><b>{ratings[`${section.id}:${item.label}`] === 'unknown' ? '不知道' : ratings[`${section.id}:${item.label}`] === 'familiar' ? '眼熟' : '熟练'}</b></span>)}</div>
      {onPractice && <div className="repair-practice-topics"><h3>选一个要突破的题库小点</h3><p>这里只列本模块已有审核原题的知识点。请选与你刚才卡住的环节对应的一项；没有合适的，就先回结果页。</p>
        <div>{practiceTopics.map((topic) => <button type="button" key={`${topic.releaseId}:${topic.conceptKey}`} disabled={practiceBusy || topic.freshCount < 1} onClick={() => void onPractice(topic.conceptKey)}>
          <span><ChemText>{topic.title}</ChemText>{topic.conceptKey === target.conceptKey && <small>刚才错题所属</small>}</span><b>{topic.freshCount > 0 ? `${topic.freshCount} 道未做原题` : '暂无未做原题'}</b><ChevronRight size={17} /></button>)}</div>
        {!practiceTopics.length && <p>这个模块暂时没有可继续做的已审核原题。</p>}</div>}
      <div className="repair-actions">
        <button type="button" className="secondary-button" onClick={() => { setSectionIndex(null); setPointIndex(0) }}>再挑一个小点</button><button type="button" className="secondary-button" onClick={onBack}>返回结果页</button></div>
    </div> : <><div className="repair-step-head"><span>{section?.title} · {pointIndex + 1}/{section?.items.length}</span><button type="button" className="text-button" onClick={() => { setSectionIndex(null); setPointIndex(0) }}>换一个小点</button></div>
      <article className="knowledge-card repair-point"><span className="eyebrow">把这一点讲清楚</span><h2><ChemText>{point?.label ?? ''}</ChemText></h2><p className="repair-rule"><ChemText>{point?.rule ?? ''}</ChemText></p>
        {point?.examples?.length ? <details><summary>看一个例子</summary><ul>{point.examples.slice(0, 2).map((example) => <li key={example}><ChemText>{example}</ChemText></li>)}</ul></details> : null}
        {point?.caution && <p className="mistake-note"><b>当心这个坑</b><ChemText>{point.caution}</ChemText></p>}</article>
      <KnowledgeConfidencePicker onChange={rate} />
      <p className="repair-bottom-note"><RotateCcw size={15} />选完会接着看下一个小点；做题的对错才是下一轮安排的依据。</p>
    </>}
  </section>
}
