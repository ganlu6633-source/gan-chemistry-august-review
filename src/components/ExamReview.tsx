import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { BookOpen, ChevronDown, Image as ImageIcon, RotateCcw } from 'lucide-react'
import type { ExamMaterialPage, ExamRecall, ExamReviewPayload, ExamReviewUnit, SessionIdentity } from '../domain/types'
import { accessApi, teacherApi } from '../lib/api'
import { ChemText } from './ChemText'
import './ExamReview.css'

type Filter = 'all' | 'pending' | 'help' | 'review'
type Props = { session: SessionIdentity; studentId: string; previewMode?: boolean; onExit: () => void }
type EvidenceSummary = { questionCount: number; dateCount: number; verified: boolean; recentSetback: boolean }

const beijingDate = (time: string) => new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Shanghai' }).format(new Date(time))

function evidenceFor(unit: ExamReviewUnit, evidence: ExamReviewPayload['evidence']): EvidenceSummary {
  const strongIds = new Set(unit.bankMatches.filter((match) => match.strength === 'same_type').map((match) => match.questionId))
  const rows = evidence.filter((row) => strongIds.has(row.questionId) && Number.isFinite(Date.parse(row.completedAt)))
    .sort((a, b) => Date.parse(a.completedAt) - Date.parse(b.completedAt))
  // A later wrong or uncertain response resets this unit's corroborating streak.
  // Repeating one question never supplies two independent pieces of evidence.
  const lastSetback = Math.max(-Infinity, ...rows.filter((row) => !row.correct || row.uncertain).map((row) => Date.parse(row.completedAt)))
  const reliable = rows.filter((row) => row.correct && !row.uncertain && Date.parse(row.completedAt) > lastSetback)
  const questionCount = new Set(reliable.map((row) => row.questionId)).size
  const dateCount = new Set(reliable.map((row) => beijingDate(row.completedAt))).size
  return { questionCount, dateCount, verified: questionCount >= 2 && dateCount >= 2, recentSetback: Number.isFinite(lastSetback) }
}

function TextList({ items }: { items: string[] }) {
  return <ul>{items.map((item, index) => <li key={index}><ChemText>{item}</ChemText></li>)}</ul>
}

function RecallCard({ unit, recall, draft, onDraft, evidence, readOnly, saving, onSave, onOpenPage }: {
  unit: ExamReviewUnit
  recall?: ExamRecall
  draft?: string
  onDraft: (unitId: string, value: string) => void
  evidence: EvidenceSummary
  readOnly: boolean
  saving: boolean
  onSave: (unitId: string, response: string, rating: ExamRecall['selfRating']) => Promise<void>
  onOpenPage: (page: number) => void
}) {
  const response = draft ?? recall?.response ?? ''
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const strongCount = new Set(unit.bankMatches.filter((match) => match.strength === 'same_type').map((match) => match.questionId)).size
  const partialCount = new Set(unit.bankMatches.filter((match) => match.strength === 'partial').map((match) => match.questionId)).size
  const responseLength = [...response.trim()].length
  const responseId = `recall-${unit.id}`
  async function submit(rating: ExamRecall['selfRating']) {
    if (readOnly || saving) return
    setError('')
    setNotice('')
    if (responseLength < 8) { setError('请先写至少 8 个字，说明你的判断、依据或卡住的地方。'); return }
    try {
      await onSave(unit.id, response.trim(), rating)
      setNotice('已保存自检。尚未评分，请展开参考解析核对自己的过程。')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '自检未保存，请重试。')
    }
  }
  return <details className="exam-unit">
    <summary>
      <span><b><ChemText>{unit.label}</ChemText></b><small><ChemText>{unit.knowledgePoints.join(' · ')}</ChemText></small></span>
      <span className="exam-unit-tags">
        {unit.status === 'needs_review' && <em className="exam-tag is-caution">待核验</em>}
        {recall ? <em className={`exam-tag ${recall.selfRating === 'needs_help' ? 'is-caution' : ''}`}>{recall.selfRating === 'needs_help' ? '需帮助 · 已自检' : '已自检'}</em> : <em className="exam-tag">待自检</em>}
        <ChevronDown aria-hidden="true" size={18} />
      </span>
    </summary>
    <div className="exam-unit-body">
      <div className="exam-prompt"><ChemText>{unit.prompt}</ChemText></div>
      <button type="button" className="text-button" onClick={() => onOpenPage(unit.page)}><ImageIcon size={16} />查看原卷第 {unit.page} 页（带批注）</button>
      {unit.status === 'needs_review' && <div className="exam-review-note" role="note"><b>需要甘老师核验</b><p><ChemText>{unit.reviewNote || '本项存在需要核实的题面或参考结论，先记录你的思路，等待老师确认。'}</ChemText></p></div>}
      <div className="exam-knowledge"><h3>这一项要用到</h3><TextList items={unit.knowledgePoints} /></div>
      {readOnly ? <div className="exam-readonly-response"><b>学生已记录的思路</b><p><ChemText>{recall?.response || '尚无自检记录。'}</ChemText></p><small>只读预览，可查看解析，不写入学生档案。</small></div> : <div className="exam-response">
        <label htmlFor={responseId}>先写你的判断与依据</label>
        {/* Native maxlength counts UTF-16 units; onChange enforces 3000 Unicode code points without splitting surrogate pairs. */}
        <textarea id={responseId} value={response} onChange={(event) => onDraft(unit.id, [...event.target.value].slice(0, 3000).join(''))} maxLength={6000} rows={5} disabled={saving} aria-describedby={`${responseId}-hint`} placeholder="选择题写清每个判断的依据；计算题写公式与步骤；暂时不会也写出卡住的地方。" />
        <small id={`${responseId}-hint`}>至少 8 个字；可以直接输入化学式。{responseLength}/3000</small>
        <div className="exam-response-actions" aria-label="自评并保存">
          <button type="button" className="primary-button compact" disabled={saving || responseLength < 8} onClick={() => void submit('understood')}>{saving ? '正在保存…' : '我能说明依据 · 保存自检'}</button>
          <button type="button" className="secondary-button compact" disabled={saving || responseLength < 8} onClick={() => void submit('needs_help')}>我还需要帮助 · 保存自检</button>
        </div>
        {error && <p className="inline-alert" role="alert">{error}可保留文字后再次点击保存。</p>}
        {notice && <p className="exam-saved-notice" role="status">{notice}</p>}
      </div>}
      {readOnly || recall ? <details className="exam-reference">
        <summary>展开参考答案与逐步解析</summary>
        <div>{unit.status === 'needs_review' && <p className="exam-review-note">待核验参考：请以甘老师复核后的说明为准。</p>}<h3>参考答案</h3><p><ChemText>{unit.answer}</ChemText></p><h3>为什么这样判断</h3><p className="exam-multiline"><ChemText>{unit.explanation}</ChemText></p>{unit.commonMistakes.length > 0 && <><h3>容易在哪一步出错</h3><TextList items={unit.commonMistakes} /></>}</div>
      </details> : <p className="exam-unlock-note">先保存一次自己的思路，再展开参考解析。</p>}
      <div className="exam-evidence">
        <h3>同类题证据</h3>
        <p>完全同型 {strongCount} 道 · 部分匹配 {partialCount} 道</p>
        {strongCount === 0 && <p className="exam-review-note">目前没有完全同型题。原卷书写需教师核验；部分匹配题只练其中的知识点。</p>}
        <p><b>{evidence.verified ? '同类题已复核' : '同类题证据待积累'}</b> · {evidence.questionCount} 道不同题答对且确定 · {evidence.dateCount} 个北京时间日期</p>
        <small>{evidence.verified ? '这是正式同型题的作答证据，仍不代表原卷书写或主观题已经掌握。' : evidence.recentSetback ? '近期出现过答错或不确定，需在其后用不同题、不同日期重新确认。' : '需要至少 2 道不同的完全同型题，在不同北京时间日期答对且确定，并且之后没有答错或不确定。'}</small>
        {unit.bankMatches.length > 0 && <details className="exam-match-details"><summary>查看训练对应关系</summary><ul>{unit.bankMatches.map((match, index) => <li key={`${match.questionId}:${index}`}><b>{match.strength === 'same_type' ? '完全同型' : '部分匹配'}：</b><ChemText>{match.reason}</ChemText></li>)}</ul></details>}
        {unit.practiceTargets.length > 0 && <><h3>接下来重点练</h3><TextList items={unit.practiceTargets} /></>}
      </div>
    </div>
  </details>
}

export function ExamReview({ session, studentId, previewMode = false, onExit }: Props) {
  const [payload, setPayload] = useState<ExamReviewPayload | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [retry, setRetry] = useState(0)
  const [question, setQuestion] = useState('all')
  const [filter, setFilter] = useState<Filter>('all')
  const [drafts, setDrafts] = useState<Record<string, string>>({})
  const [savingUnits, setSavingUnits] = useState<Set<string>>(new Set())
  const savingRef = useRef(new Set<string>())
  const [selectedPage, setSelectedPage] = useState<number | null>(null)
  const [pageImage, setPageImage] = useState<ExamMaterialPage | null>(null)
  const [pageLoading, setPageLoading] = useState(false)
  const [pageError, setPageError] = useState('')
  const [pageRetry, setPageRetry] = useState(0)
  const pages = useRef(new Map<number, ExamMaterialPage>())
  const pagePanel = useRef<HTMLDivElement | null>(null)
  const titleRef = useRef<HTMLHeadingElement | null>(null)
  const readOnly = previewMode || session.role !== 'student'
  const materialId = payload?.material.id

  const read = useCallback(<T,>(action: string, data: Record<string, unknown>, signal?: AbortSignal) => session.role === 'teacher'
    ? teacherApi<T>(action, { ...data, studentId }, { signal })
    : accessApi<T>(session, action, data, { signal }), [session, studentId])

  useEffect(() => {
    const controller = new AbortController()
    setLoading(true)
    setError('')
    void read<ExamReviewPayload>('exam_material', {}, controller.signal).then((result) => {
      if (!controller.signal.aborted) setPayload(result)
    }).catch((reason: unknown) => {
      if (!controller.signal.aborted) setError(reason instanceof Error ? reason.message : '复盘材料暂时无法打开。')
    }).finally(() => { if (!controller.signal.aborted) setLoading(false) })
    return () => controller.abort()
  }, [read, retry])

  useEffect(() => {
    if (!loading && materialId) titleRef.current?.focus()
  }, [loading, materialId])

  useEffect(() => {
    if (selectedPage === null) return
    const controller = new AbortController()
    const cached = pages.current.get(selectedPage)
    setPageImage(cached ?? null)
    setPageError('')
    setPageLoading(!cached)
    if (!cached) void read<{ page: ExamMaterialPage }>('exam_material_page', { page: selectedPage }, controller.signal)
      .then(({ page }) => {
        if (!['image/png', 'image/jpeg', 'image/webp'].includes(page.mimeType) || !page.payloadBase64) throw new Error('原卷图片格式不受支持，请联系甘老师。')
        if (!controller.signal.aborted) { pages.current.set(selectedPage, page); setPageImage(page) }
      }).catch((reason: unknown) => {
        if (!controller.signal.aborted) setPageError(reason instanceof Error ? reason.message : '原卷图片未能载入。')
      }).finally(() => { if (!controller.signal.aborted) setPageLoading(false) })
    pagePanel.current?.scrollIntoView?.({ behavior: 'smooth', block: 'start' })
    pagePanel.current?.focus()
    return () => controller.abort()
  }, [selectedPage, pageRetry, read])

  const recallMap = useMemo(() => new Map((payload?.recalls ?? []).map((recall) => [recall.unitId, recall])), [payload?.recalls])
  const evidenceMap = useMemo(() => new Map((payload?.material.units ?? []).map((unit) => [unit.id, evidenceFor(unit, payload?.evidence ?? [])])), [payload?.material.units, payload?.evidence])
  const units = payload?.material.units ?? []
  const visible = units.filter((unit) => (question === 'all' || unit.questionNo === Number(question))
    && (filter === 'all' || filter === 'pending' && !recallMap.has(unit.id) || filter === 'help' && recallMap.get(unit.id)?.selfRating === 'needs_help' || filter === 'review' && unit.status === 'needs_review'))
  const checkedCount = units.filter((unit) => recallMap.has(unit.id)).length
  const evidenceCount = units.filter((unit) => evidenceMap.get(unit.id)?.verified).length

  async function saveRecall(unitId: string, response: string, selfRating: ExamRecall['selfRating']) {
    if (readOnly) throw new Error('只读预览不写入学生档案。')
    if (savingRef.current.has(unitId)) return
    savingRef.current.add(unitId)
    setSavingUnits(new Set(savingRef.current))
    try {
      const result = await accessApi<{ ok: true; gradingStatus: 'ungraded_self_check' }>(session, 'exam_recall', { unitId, response, selfRating })
      if (!result.ok || result.gradingStatus !== 'ungraded_self_check') throw new Error('自检保存结果未确认，请重试。')
      setPayload((current) => current && ({ ...current, recalls: [...current.recalls.filter((item) => item.unitId !== unitId), {
        unitId, response, selfRating, responseCount: (current.recalls.find((item) => item.unitId === unitId)?.responseCount ?? 0) + 1, updatedAt: new Date().toISOString(),
      }] }))
    } finally {
      savingRef.current.delete(unitId)
      setSavingUnits(new Set(savingRef.current))
    }
  }

  return <section className="exam-review-panel" aria-labelledby="exam-review-title">
    <button type="button" className="text-button exam-back" onClick={onExit}>← 返回今天</button>
    <header className="exam-header"><span className="eyebrow">逐项复盘 · 用依据说清楚</span><h1 id="exam-review-title" ref={titleRef} tabIndex={-1}>福州试卷逐项复盘</h1><p>先独立写思路，再对照解析，最后用正式同类题检验。原卷自检可提前进行，不计为正式作答，也不自动认定掌握。</p></header>
    {readOnly && <p className="exam-review-note" role="status">只读预览：可查看学生自检、参考解析和原卷，不会写入学生档案。</p>}
    {loading && <div className="exam-loading" role="status" aria-live="polite"><BookOpen aria-hidden="true" />正在读取复盘材料…</div>}
    {error && <div className="inline-alert" role="alert"><p>{error}</p><button type="button" className="secondary-button compact" onClick={() => setRetry((value) => value + 1)}><RotateCcw size={16} />重试读取材料</button></div>}
    {!loading && !error && payload && <>
      <p className="exam-material-title"><ChemText>{payload.material.title}</ChemText></p>
      <p className="exam-multiline"><ChemText>{payload.material.overview}</ChemText></p>
      <div className="exam-progress" aria-label="复盘进度">
        <div><b>{checkedCount}/{units.length}</b><span>已自检</span></div>
        <div><b>{evidenceCount}/{units.length}</b><span>同类题证据已复核</span></div>
        <div><b>{units.filter((unit) => unit.status === 'needs_review').length}</b><span>待教师核验</span></div>
      </div>
      {payload.material.dailyOutline.length > 0 && <details className="exam-week-outline"><summary>查看本周复盘与正式训练安排</summary><p>按日回看下面的原卷题号；同类题请进入首页当天正式题组。自检和正式作答分别记录。</p><ol>{payload.material.dailyOutline.map((day) => <li key={day.date}><time dateTime={day.date}>{day.date.slice(5)}</time><div><b><ChemText>{day.title}</ChemText></b><span>原卷第 {day.questionNos.join('、')} 题 · {day.unitIds.length} 个复盘项</span></div></li>)}</ol></details>}
      <div className="exam-source-controls"><b>带批注原卷，仅用于复盘</b><p>页上手写内容是批注，不是标准答案；以核验后的解析为准。点击需要的页再加载。</p><div>{Array.from({ length: payload.material.pageCount }, (_, index) => index + 1).map((page) => <button type="button" className="secondary-button compact" key={page} aria-pressed={selectedPage === page} onClick={() => setSelectedPage(page)}>第 {page} 页</button>)}</div></div>
      {selectedPage !== null && <div className="exam-page-panel" ref={pagePanel} tabIndex={-1} aria-label={`带批注原卷第 ${selectedPage} 页`}><div className="exam-page-head"><b>原卷第 {selectedPage} 页 · 带批注</b><button type="button" className="text-button" onClick={() => setSelectedPage(null)}>收起原卷</button></div>{pageLoading && <p role="status">正在加载这一页…</p>}{pageError && <div role="alert"><p>{pageError}</p><button type="button" className="secondary-button compact" onClick={() => setPageRetry((value) => value + 1)}>重试原卷图片</button></div>}{pageImage && <div className="exam-page-scroll"><img src={`data:${pageImage.mimeType};base64,${pageImage.payloadBase64}`} width={pageImage.width} height={pageImage.height} alt={`福州化学试卷第 ${selectedPage} 页，含手写批注，仅用于复盘`} /></div>}</div>}
      <div className="exam-filters"><label>选择题号<select value={question} onChange={(event) => setQuestion(event.target.value)}><option value="all">全部题号</option>{Array.from({ length: 14 }, (_, index) => index + 1).map((number) => <option key={number} value={number}>第 {number} 题</option>)}</select></label><label>筛选复盘状态<select value={filter} onChange={(event) => setFilter(event.target.value as Filter)}><option value="all">全部状态</option><option value="pending">待自检</option><option value="help">需帮助</option><option value="review">待核验</option></select></label><span aria-live="polite">显示 {visible.length} 个复盘项</span></div>
      <div className="exam-unit-list">{visible.map((unit) => <RecallCard key={unit.id} unit={unit} recall={recallMap.get(unit.id)} draft={drafts[unit.id]} onDraft={(id, value) => setDrafts((current) => ({ ...current, [id]: value }))} evidence={evidenceMap.get(unit.id)!} readOnly={readOnly} saving={savingUnits.has(unit.id)} onSave={saveRecall} onOpenPage={setSelectedPage} />)}</div>
      {visible.length === 0 && <p className="exam-empty" role="status">当前筛选没有复盘项，可切换题号或状态查看。</p>}
    </>}
  </section>
}
