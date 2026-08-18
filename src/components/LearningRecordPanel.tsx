import { useMemo, useState } from 'react'
import { BookOpenCheck, CheckCircle2, ChevronDown, CircleDashed, CircleDot, Clock3, RotateCcw } from 'lucide-react'
import { ABILITY_MAP_BLUEPRINTS } from '../data/abilityMap'
import type { GradeBand, LearningRecordData, LearningRecordQuestionEvidence, LearningRecordSkill } from '../domain/types'
import { ChemText } from './ChemText'
import { QuestionSourceMedia } from './QuestionSourceMedia'

type RecordAudience = 'student' | 'guardian' | 'teacher'
type RecordFilter = 'all' | 'full' | 'partial' | 'unlit' | 'due' | 'future'

interface LearningRecordPanelProps {
  record: LearningRecordData
  gradeBand: GradeBand
  audience?: RecordAudience
}

const FILTERS: Array<{ id: RecordFilter; label: string }> = [
  { id: 'all', label: '全部能力' },
  { id: 'full', label: '完全点亮' },
  { id: 'partial', label: '点亮一部分' },
  { id: 'unlit', label: '待建立证据' },
  { id: 'due', label: '需要回看' },
  { id: 'future', label: '后续学习' },
]

function matchesFilter(skill: LearningRecordSkill, filter: RecordFilter) {
  if (filter === 'all') return true
  if (filter === 'future') return skill.exposure === 'future'
  if (skill.exposure !== 'learned') return false
  if (filter === 'due') return skill.retentionStatus === 'due'
  return skill.evidenceStatus === filter
}

function skillStatus(skill: LearningRecordSkill) {
  if (skill.exposure === 'future') return { label: '后续学习', className: 'future', copy: '将在后续课堂或复习中进入。' }
  if (skill.retentionStatus === 'due') return { label: '需要回看', className: 'due', copy: '已有基础，到了再次唤醒的时间。' }
  if (skill.evidenceStatus === 'full') return { label: '完全点亮', className: 'full', copy: '真实作答已达到本技能当前最高证据等级。' }
  if (skill.evidenceStatus === 'partial') return { label: '点亮一部分', className: 'partial', copy: '已经形成真实作答证据，继续练习会更稳。' }
  return { label: '待建立证据', className: 'unlit', copy: '已进入学习范围，完成对应练习后开始点亮。' }
}

function formatDateTime(value: string | null) {
  if (!value) return '暂无记录'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value.slice(0, 10)
  return date.toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai', month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}

function AnswerText({ question, optionIndex }: { question: LearningRecordQuestionEvidence; optionIndex: number }) {
  if (!Number.isInteger(optionIndex) || optionIndex < 0) return <>历史答案暂不可显示</>
  const option = question.options[optionIndex]
  const letter = optionIndex >= 0 && optionIndex < 26 ? String.fromCharCode(65 + optionIndex) : `${optionIndex + 1}`
  return option ? <><span>{letter}. </span><ChemText>{option}</ChemText></> : <>第 {optionIndex + 1} 项</>
}

export function LearningRecordPanel({ record, gradeBand, audience = 'student' }: LearningRecordPanelProps) {
  const [filter, setFilter] = useState<RecordFilter>('all')
  const blueprint = ABILITY_MAP_BLUEPRINTS[gradeBand]
  const summary = useMemo(() => {
    const learnedSkills = record.skills.filter((skill) => skill.exposure === 'learned')
    return {
      learned: learnedSkills.length,
      full: learnedSkills.filter((skill) => skill.evidenceStatus === 'full').length,
      partial: learnedSkills.filter((skill) => skill.evidenceStatus === 'partial').length,
      unlit: learnedSkills.filter((skill) => skill.evidenceStatus === 'unlit').length,
      due: learnedSkills.filter((skill) => skill.retentionStatus === 'due').length,
      future: record.skills.filter((skill) => skill.exposure === 'future').length,
    }
  }, [record.skills])
  const counts: Record<RecordFilter, number> = {
    all: record.skills.length,
    full: summary.full,
    partial: summary.partial,
    unlit: summary.unlit,
    due: summary.due,
    future: summary.future,
  }
  const stageIds = new Set(blueprint.stages.flatMap((stage) => stage.skillIds))
  const groups = [
    ...blueprint.stages.map((stage, index) => ({
      id: stage.id,
      number: index + 1,
      title: stage.title,
      summary: stage.summary,
      skills: stage.skillIds.flatMap((skillId) => record.skills.filter((skill) => skill.skillId === skillId)),
    })),
    {
      id: 'record-additional',
      number: blueprint.stages.length + 1,
      title: '补充能力',
      summary: '课程中新加入的能力会在这里保留完整证据。',
      skills: record.skills.filter((skill) => !stageIds.has(skill.skillId)),
    },
  ].map((group) => ({ ...group, skills: group.skills.filter((skill) => matchesFilter(skill, filter)) }))
    .filter((group) => group.skills.length > 0)

  return <section className={`learning-record learning-record-${audience}`} aria-labelledby="learning-record-title">
    <div className="learning-record-heading">
      <div className="page-title">
        <span className="eyebrow">{audience === 'guardian' ? '完整学习档案' : audience === 'teacher' ? '只读学习证据' : '我的化学档案'}</span>
        {audience === 'guardian'
          ? <h2 id="learning-record-title">学过什么、点亮多少、下一步在哪里</h2>
          : <h1 id="learning-record-title">把学过的每一步，接成一条清楚的路。</h1>}
        <p>{audience === 'guardian'
          ? `目前有 ${summary.learned} 项能力进入课堂或复习范围；每一项都可以展开查看知识目录和真实作答。`
          : `已经进入学习范围 ${summary.learned} 项。点开任一能力，就能复盘知识目录、真实题目和解析。`}</p>
      </div>
      <div className="record-scope-note"><BookOpenCheck /><div><b>{summary.learned}/{record.skills.length}</b><span>已进入学习范围</span></div></div>
    </div>

    <div className="record-summary learning-record-summary" data-testid="learning-record-summary" aria-label="学习证据摘要">
      <button className="full" onClick={() => setFilter('full')} aria-pressed={filter === 'full'}><CheckCircle2 /><b>{summary.full}</b><span>完全点亮</span><small>达到当前最高证据等级</small></button>
      <button className="partial" onClick={() => setFilter('partial')} aria-pressed={filter === 'partial'}><CircleDot /><b>{summary.partial}</b><span>点亮一部分</span><small>已有证据，继续巩固</small></button>
      <button className="unlit" onClick={() => setFilter('unlit')} aria-pressed={filter === 'unlit'}><CircleDashed /><b>{summary.unlit}</b><span>待建立证据</span><small>已学范围内等待作答</small></button>
      <button className="due" onClick={() => setFilter('due')} aria-pressed={filter === 'due'}><RotateCcw /><b>{summary.due}</b><span>需要回看</span><small>到了再次唤醒的节点</small></button>
      <button className="future" onClick={() => setFilter('future')} aria-pressed={filter === 'future'}><Clock3 /><b>{summary.future}</b><span>后续学习</span><small>单独呈现，不计入待点亮</small></button>
    </div>

    <div className="record-filter" aria-label="筛选学习档案">
      {FILTERS.map((item) => <button key={item.id} onClick={() => setFilter(item.id)} aria-pressed={filter === item.id}>{item.label}<span>{counts[item.id]}</span></button>)}
    </div>

    <p className="record-measure-note"><CircleDot />{record.evidenceScope}</p>
    {record.historyWindow.hasMore && <p className="record-history-note"><Clock3 />当前显示最近记录：已读取 {record.historyWindow.loadedAttempts}/{record.historyWindow.totalAttempts} 轮学习、{record.historyWindow.loadedAnswers}/{record.historyWindow.totalAnswersInLoadedAttempts} 道作答；更早记录仍保留在学习档案中。</p>}

    {groups.length ? <div className="record-stage-list">{groups.map((group) => <section className="record-stage" key={group.id}>
      <header><span>{group.number}</span><div><h2><ChemText>{group.title}</ChemText></h2><p><ChemText>{group.summary}</ChemText></p></div><b>{group.skills.length}项</b></header>
      <div className="record-skill-list">{group.skills.map((skill) => <LearningRecordSkillCard key={skill.skillId} skill={skill} audience={audience} gradeBand={gradeBand} />)}</div>
    </section>)}</div> : <div className="record-empty"><CircleDashed /><b>这个筛选下暂时没有记录</b><p>切换上方分类，可以继续查看完整学习路线。</p></div>}
  </section>
}

function LearningRecordSkillCard({ skill, audience, gradeBand }: { skill: LearningRecordSkill; audience: RecordAudience; gradeBand: GradeBand }) {
  const status = skillStatus(skill)
  const progress = Math.max(0, Math.min(100, skill.maxLevel ? skill.verifiedLevel / skill.maxLevel * 100 : 0))
  const total = skill.answeredQuestionCount
  const accuracy = total ? Math.round(skill.correctQuestionCount / total * 100) : null
  return <details className={`record-skill learning-skill-card status-${status.className}`} data-testid="learning-skill-card">
    <summary>
      <span className="record-status-icon" aria-hidden="true">{status.className === 'full' ? '✓' : status.className === 'partial' ? '◐' : status.className === 'due' ? '↻' : status.className === 'future' ? '→' : '○'}</span>
      <div className="record-skill-summary"><div><h3><ChemText>{skill.title}</ChemText></h3><span className={`record-status status-${status.className}`}>{status.label}</span></div><p>{status.copy}</p><div className="record-level"><i><span style={{ width: `${progress}%` }} /></i><b>L{skill.verifiedLevel}/{skill.maxLevel}</b></div></div>
      <div className="record-skill-numbers"><span><b>{total}</b>道真实作答</span><span><b>{skill.uniqueMotherCount}</b>类母题</span>{accuracy !== null && <span><b>{accuracy}%</b>当前正确率</span>}</div>
      <ChevronDown className="record-chevron" />
    </summary>
    <div className="record-skill-detail">
      {skill.learnedTopics.length > 0 && <div className="record-topics"><b>已进入课堂/复习范围</b><div>{skill.learnedTopics.map((topic) => <span key={topic}><ChemText>{topic}</ChemText></span>)}</div></div>}
      <section className="record-knowledge" data-evidence-scope={skill.knowledgeEvidenceScope}><div className="record-subhead"><div><span>完整回忆</span><h4>本模块具体包含</h4></div><small>模块目录帮助找回主线，逐点证据随对应题目累积</small></div>
        {skill.knowledgeSections.length ? <div className="record-knowledge-grid">{skill.knowledgeSections.map((section) => <article key={section.id}><header><b><ChemText>{section.title}</ChemText></b>{section.summary && <p><ChemText>{section.summary}</ChemText></p>}</header><ul>{section.points.map((point) => <li key={point.id}><span><ChemText>{point.title}</ChemText></span>{point.rule && <p><ChemText>{point.rule}</ChemText></p>}</li>)}</ul></article>)}</div>
          : <div className="record-empty compact"><BookOpenCheck /><b>知识目录正在逐项校对</b><p>当前先依据已经保存的真实作答查看学习证据。</p></div>}
      </section>

      <section className="record-evidence"><div className="record-subhead"><div><span>真实证据</span><h4>做过什么题、怎样作答、怎样订正</h4></div><small>{skill.recentQuestionsTruncated ? `当前显示最近 ${skill.recentQuestions.length} 道（已读取 ${total} 道）` : total ? `已读取 ${total} 道作答` : '完成对应练习后自动保存'}</small></div>
        {skill.recentQuestionsTruncated && <p className="record-history-note compact"><Clock3 />当前显示最近记录，更早的真实作答仍保留在学习档案中。</p>}
        {skill.recentQuestions.length ? <div className="record-question-list">{skill.recentQuestions.map((question, index) => <QuestionEvidence key={`${question.questionId}-${question.answeredAt}-${index}`} question={question} index={index} gradeBand={gradeBand} />)}</div>
          : <div className="record-empty compact"><CircleDashed /><b>真实作答证据即将在这里累积</b><p>完成一次对应练习后，题目、选择、订正和解析会一起保存到这里。</p></div>}
      </section>

      <footer className="record-next-step"><div><Clock3 /><span>{skill.lastReviewedAt ? `最近复习：${formatDateTime(skill.lastReviewedAt)}` : '第一份复习证据正在等待建立'}</span></div>{skill.nextPlan ? <div><BookOpenCheck /><span>下一次安排：{skill.nextPlan.date.slice(5)} · <ChemText>{skill.nextPlan.title}</ChemText></span></div> : <div><CheckCircle2 /><span>{skill.exposure === 'future' ? '后续教学计划会在进入学习范围时点亮' : '系统会结合记忆节点安排下一次复习'}</span></div>}{skill.teacherIntervention && audience !== 'student' && <div><RotateCcw /><span>甘老师会结合后续作答继续关注这一项</span></div>}</footer>
    </div>
  </details>
}

function QuestionEvidence({ question, index, gradeBand }: { question: LearningRecordQuestionEvidence; index: number; gradeBand: GradeBand }) {
  const showsLicensedReviewSource = ['高一', '高二', '高三'].includes(gradeBand) && question.sourceKind === 'licensed_local' && question.mode === 'REVIEW'
  const nativeStem = <p className="record-question-stem"><ChemText>{question.stem}</ChemText></p>
  return <details className={`record-question learning-question-evidence ${question.correct ? 'is-correct' : 'needs-review'}`} data-testid="learning-question-evidence">
    <summary><span>{question.correct ? '✓' : '↻'}</span><div><b>真实作答 {index + 1} · {question.correct ? '本题答对' : '本题需要回看'}</b><p><ChemText>{question.stem}</ChemText></p></div><time>{formatDateTime(question.answeredAt)}</time><ChevronDown /></summary>
    <div className="record-question-body">
      <QuestionHistoryStatus question={question} />
      {showsLicensedReviewSource ? <QuestionSourceMedia question={{ id: question.questionId, stem: question.stem, options: question.options, sourceInfo: question.sourceInfo, assetRefs: (question.assetRefs ?? []).filter((asset) => asset.kind !== 'analysis_image'), renderMode: question.renderMode }} enabled deferLoad readOnly showSource={false} nativeContent={nativeStem} /> : <>{question.imageUrl && <img src={question.imageUrl} alt="这道题的题图" />}{nativeStem}</>}
      {question.options.length > 0 && <ol className="record-option-list">{question.options.map((option, optionIndex) => <li key={`${optionIndex}-${option}`} className={`${optionIndex === question.selectedOption ? 'selected' : ''} ${optionIndex === question.correctOption ? 'correct' : ''}`}><span>{String.fromCharCode(65 + optionIndex)}</span><p><ChemText>{option}</ChemText></p>{optionIndex === question.selectedOption && <small>学生选择</small>}{optionIndex === question.correctOption && <small>正确答案</small>}</li>)}</ol>}
      <div className="record-answer-row"><div><span>学生选择</span><b><AnswerText question={question} optionIndex={question.selectedOption} /></b></div><div><span>正确答案</span><b><AnswerText question={question} optionIndex={question.correctOption} /></b></div><div><span>作答状态</span><b>{question.correct ? '答对，继续保持' : '回看思路，再做同类题'}</b></div></div>
      <div className="record-explanation"><b>解析与订正</b><p><ChemText>{question.explanation || '这道题的解析正在校对，校对完成后会在这里补齐。'}</ChemText></p></div>
      <p className="record-answer-meta">难度 L{question.level} · 用时 {question.durationSec} 秒{question.uncertain ? ' · 本题作答时标记了“不确定”' : ''}</p>
    </div>
  </details>
}

function QuestionHistoryStatus({ question }: { question: LearningRecordQuestionEvidence }) {
  if (question.currentQuestionStatus === 'retired') return <p className="record-question-history status-retired"><Clock3 />这道历史题已退出当前使用版本；{question.snapshotAvailable ? '下方内容来自当时保存的题目快照。' : '作答结果仍按原记录保留。'}</p>
  if (question.currentQuestionStatus === 'out_of_scope') return <p className="record-question-history status-out"><Clock3 />这道历史题已超出当前复习范围；历史作答仍如实保留。</p>
  if (question.currentQuestionStatus === 'unavailable') return <p className="record-question-history status-unavailable"><Clock3 />这道历史题当前不可用；历史作答仍如实保留。</p>
  if (!question.snapshotAvailable) return <p className="record-question-history"><Clock3 />本次作答早于题目快照记录；题目正文采用当前审核版本。</p>
  return null
}
