import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react'
import { CheckCircle2, Clock3, ExternalLink, Eye, Film, Link2, PlayCircle, PlusCircle, RefreshCw, Send, ShieldCheck, Undo2 } from 'lucide-react'
import type { CreateVideoRecommendationInput, RecordVideoEngagementInput, SessionIdentity, StudentDashboardData, TeacherDashboardData, VideoRecommendation, VideoRecommendationProgress, VideoRecommendationStatus } from '../domain/types'
import { formatVideoEngagementTime as formatEngagementTime, getVideoProgress as progressOf, safeExternalVideoUrl, videoProgressView } from '../domain/videoLearning'
import { createVideoRecommendation, listVideoRecommendations, publishVideoRecommendation, recordVideoEngagement, teacherApi, withdrawVideoRecommendation } from '../lib/api'
import { ChemText } from './ChemText'

type VideoRecorder = (input: RecordVideoEngagementInput) => Promise<{ recommendation?: VideoRecommendation; ok?: true }>

function VideoSkillLabel({ video }: { video: VideoRecommendation }) {
  return video.skillTitle ? <ChemText>{video.skillTitle}</ChemText> : video.skillId
}

export function StudentVideoSection({
  session,
  videos,
  readOnly = false,
  onRecord,
}: {
  session: SessionIdentity
  videos: VideoRecommendation[]
  readOnly?: boolean
  onRecord?: VideoRecorder
}) {
  const publishedVideos = useMemo(() => videos.filter((video) => video.status === 'published'), [videos])
  const [items, setItems] = useState(publishedVideos)
  const [minutesById, setMinutesById] = useState<Record<string, string>>({})
  const [busyId, setBusyId] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  useEffect(() => setItems(publishedVideos), [publishedVideos])

  const updateItem = useCallback((id: string, updater: (item: VideoRecommendation) => VideoRecommendation) => {
    setItems((current) => current.map((item) => item.id === id ? updater(item) : item))
  }, [])

  async function persist(video: VideoRecommendation, input: RecordVideoEngagementInput, optimisticProgress: Partial<VideoRecommendationProgress>) {
    if (readOnly) return
    setBusyId(video.id)
    setError('')
    setMessage('')
    updateItem(video.id, (item) => ({ ...item, progress: { ...progressOf(item), ...optimisticProgress } }))
    try {
      const result = onRecord ? await onRecord(input) : await recordVideoEngagement(session, input)
      if (result.recommendation) updateItem(video.id, () => result.recommendation as VideoRecommendation)
      setMessage(input.event === 'complete' ? '已记录“看完”，甘老师可以看到这条反馈。' : input.event === 'progress' ? '观看位置已保存，下次可以从这里接着看。' : '')
    } catch (reason) {
      updateItem(video.id, () => video)
      setError(reason instanceof Error ? reason.message : '观看记录暂时没有保存，请稍后再试。')
    } finally {
      setBusyId('')
    }
  }

  function noteOpen(video: VideoRecommendation) {
    if (readOnly) return
    const now = new Date().toISOString()
    void persist(video, { recommendationId: video.id, event: 'open', trackingMethod: 'link_open_only' }, {
      openedAt: progressOf(video).openedAt ?? now,
      lastEngagedAt: now,
      trackingMethod: 'link_open_only',
    })
  }

  function savePosition(video: VideoRecommendation) {
    const minutes = Number(minutesById[video.id])
    if (!Number.isFinite(minutes) || minutes <= 0 || minutes > 600) {
      setError('请填写已经看到的分钟数，例如“8”。')
      return
    }
    const seconds = Math.round(minutes * 60)
    const now = new Date().toISOString()
    void persist(video, {
      recommendationId: video.id,
      event: 'progress',
      progressSeconds: seconds,
      trackingMethod: 'self_reported',
    }, {
      openedAt: progressOf(video).openedAt ?? now,
      lastEngagedAt: now,
      progressSeconds: seconds,
      trackingMethod: 'self_reported',
    })
  }

  function markComplete(video: VideoRecommendation) {
    const now = new Date().toISOString()
    void persist(video, {
      recommendationId: video.id,
      event: 'complete',
      trackingMethod: 'self_reported',
    }, {
      openedAt: progressOf(video).openedAt ?? now,
      lastEngagedAt: now,
      completionPercent: 100,
      completedAt: now,
      trackingMethod: 'self_reported',
    })
  }

  if (!items.length) return null

  return <section className="video-learning section-block" aria-labelledby="student-video-title">
    <div className="section-head video-section-head"><div><span className="eyebrow">甘老师为这一步挑选</span><h2 id="student-video-title">讲解视频</h2><p>先看老师说明，再打开对应讲解；看到哪里可以自己留下位置。</p></div><Film /></div>
    {readOnly && <div className="video-readonly-note"><Eye />只读模拟中：可以检查链接与内容，操作不会写入学生记录。</div>}
    {error && <div className="inline-alert" role="alert">{error}</div>}
    {message && <div className="success-message" role="status"><CheckCircle2 />{message}</div>}
    <div className="video-card-list">{items.map((video) => {
      const view = videoProgressView(video)
      const safeUrl = safeExternalVideoUrl(video.url)
      const progress = progressOf(video)
      return <article className="video-card student-video-card" key={video.id}>
        <div className="video-card-top"><div className="video-provider"><PlayCircle /><span>{video.provider}</span></div><span className={`video-progress-badge ${view.tone}`}>{view.label}</span></div>
        <h3><ChemText>{video.title}</ChemText></h3>
        <p className="video-skill">对应知识点：<VideoSkillLabel video={video} /></p>
        <div className="teacher-video-reason"><ShieldCheck /><div><b>甘老师为什么安排这个</b><p><ChemText>{video.teacherReason}</ChemText></p></div></div>
        <div className="video-progress-row"><div className="video-progress-track" aria-label={`观看进度${view.percent}%`}><span style={{ width: `${view.percent}%` }} /></div><small>{view.detail}</small></div>
        <div className="video-actions">
          {safeUrl ? <a className="primary-button compact" href={safeUrl} target="_blank" rel="noreferrer" onClick={() => noteOpen(video)}>打开讲解<ExternalLink /></a> : <span className="video-link-invalid"><Link2 />链接待甘老师修正</span>}
          {!readOnly && <div className="video-self-report"><label htmlFor={`video-minute-${video.id}`}>我看到<input id={`video-minute-${video.id}`} type="number" min="1" max="600" step="0.5" inputMode="decimal" value={minutesById[video.id] ?? ''} onChange={(event) => setMinutesById((current) => ({ ...current, [video.id]: event.target.value }))} disabled={busyId === video.id} /><span>分钟</span></label><button className="secondary-button" onClick={() => savePosition(video)} disabled={busyId === video.id}>保存位置</button><button className="video-complete-button" onClick={() => markComplete(video)} disabled={busyId === video.id || Boolean(progress.completedAt)}><CheckCircle2 />{progress.completedAt ? '已经看完' : '我已看完'}</button></div>}
        </div>
      </article>
    })}</div>
  </section>
}

export function GuardianVideoSection({ videos }: { videos: VideoRecommendation[] }) {
  const publishedVideos = videos.filter((video) => video.status === 'published')
  return <section className="guardian-card guardian-video-section" aria-labelledby="guardian-video-title">
    <div className="card-title"><Film /><div><span>讲解安排与真实进度</span><h2 id="guardian-video-title">甘老师为孩子补上的讲解</h2></div></div>
    <div className="guardian-video-principle"><ShieldCheck /><p>讲解由甘老师依据课堂进度和复习规则安排；系统负责辅助推送与记录，甘老师可以复核。这里只按事实区分“尚未打开、已打开、学生反馈进度、已反馈看完”，不会把打开链接当成已经掌握。</p></div>
    {!publishedVideos.length ? <div className="video-empty"><Film /><div><b>目前没有正在推送的讲解</b><p>需要补充时，甘老师会结合课堂与复习证据安排。</p></div></div> : <div className="guardian-video-list">{publishedVideos.map((video) => {
      const view = videoProgressView(video)
      const progress = progressOf(video)
      return <article key={video.id} className={`guardian-video-item ${view.tone}`}><div className="guardian-video-status"><span className={`video-progress-badge ${view.tone}`}>{view.label}</span>{progress.lastEngagedAt && <time>{formatEngagementTime(progress.lastEngagedAt)}</time>}</div><h3><ChemText>{video.title}</ChemText></h3><p className="video-skill"><VideoSkillLabel video={video} /> · {video.provider}</p><p className="guardian-video-reason"><b>安排原因：</b><ChemText>{video.teacherReason}</ChemText></p><small>{view.detail}</small></article>
    })}</div>}
  </section>
}

const statusCopy: Record<VideoRecommendationStatus, string> = { draft: '待审核', published: '已发布', withdrawn: '已撤回' }

export function TeacherVideoManager({ dashboard }: { dashboard: TeacherDashboardData }) {
  const [recommendations, setRecommendations] = useState<VideoRecommendation[]>([])
  const [studentId, setStudentId] = useState(dashboard.students[0]?.id ?? '')
  const [status, setStatus] = useState<'all' | VideoRecommendationStatus>('all')
  const [skills, setSkills] = useState<StudentDashboardData['skillDefinitions']>([])
  const [skillId, setSkillId] = useState('')
  const [title, setTitle] = useState('')
  const [provider, setProvider] = useState('')
  const [url, setUrl] = useState('')
  const [teacherReason, setTeacherReason] = useState('')
  const [loading, setLoading] = useState(true)
  const [skillsLoading, setSkillsLoading] = useState(false)
  const [busyId, setBusyId] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  const load = useCallback(async () => {
    setLoading(true)
    setError('')
    try {
      const result = await listVideoRecommendations({ studentId: studentId || undefined })
      setRecommendations(result.recommendations ?? [])
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '视频讲解列表暂时无法读取。')
    } finally {
      setLoading(false)
    }
  }, [studentId])

  useEffect(() => { void load() }, [load])

  useEffect(() => {
    if (!studentId) { setSkills([]); setSkillId(''); return }
    let active = true
    setSkillsLoading(true)
    void teacherApi<{ dashboard: StudentDashboardData }>('student_preview_dashboard', { studentId })
      .then((result) => {
        if (!active) return
        const nextSkills = result.dashboard.skillDefinitions ?? []
        setSkills(nextSkills)
        setSkillId((current) => nextSkills.some((skill) => skill.id === current) ? current : nextSkills[0]?.id ?? '')
      })
      .catch((reason) => { if (active) setError(reason instanceof Error ? reason.message : '学生知识点暂时无法读取。') })
      .finally(() => { if (active) setSkillsLoading(false) })
    return () => { active = false }
  }, [studentId])

  async function submit(event: FormEvent) {
    event.preventDefault()
    setError('')
    setMessage('')
    const safeUrl = safeExternalVideoUrl(url)
    if (!studentId || !skillId || !title.trim() || !provider.trim() || !teacherReason.trim()) return setError('请把学生、知识点、标题、来源和安排原因填写完整。')
    if (!safeUrl) return setError('视频链接必须是完整的 https 安全地址。')
    const input: CreateVideoRecommendationInput = { studentId, skillId, title: title.trim(), provider: provider.trim(), url: safeUrl, teacherReason: teacherReason.trim() }
    setSaving(true)
    try {
      await createVideoRecommendation(input)
      setMessage('讲解已保存为待审核草稿。确认标题、链接和安排原因后再发布给学生。')
      setTitle(''); setProvider(''); setUrl(''); setTeacherReason('')
      await load()
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '讲解草稿保存失败。')
    } finally {
      setSaving(false)
    }
  }

  async function changeStatus(video: VideoRecommendation, action: 'publish' | 'withdraw') {
    setBusyId(video.id)
    setError('')
    setMessage('')
    try {
      if (action === 'publish') await publishVideoRecommendation(video.id)
      else await withdrawVideoRecommendation(video.id)
      setMessage(action === 'publish' ? '已发布给学生；家长端也会看到真实打开与进度状态。' : '已撤回；学生和家长端不再显示这条讲解。')
      await load()
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '状态更新失败。')
    } finally {
      setBusyId('')
    }
  }

  const selectedStudent = dashboard.students.find((student) => student.id === studentId)
  const counts = recommendations.reduce((all, video) => ({ ...all, [video.status]: (all[video.status] ?? 0) + 1 }), {} as Partial<Record<VideoRecommendationStatus, number>>)
  const visibleRecommendations = status === 'all' ? recommendations : recommendations.filter((video) => video.status === status)

  return <>
    <div className="teacher-page-head"><div><span className="eyebrow">甘老师决定内容，系统辅助送达与留痕</span><h1>视频讲解工作台</h1></div><button className="secondary-button" onClick={() => void load()} disabled={loading}><RefreshCw className={loading ? 'spin' : ''} />刷新</button></div>
    {error && <div className="inline-alert" role="alert">{error}</div>}
    {message && <div className="success-message" role="status"><CheckCircle2 />{message}</div>}
    <section className="teacher-panel video-compose-panel"><div className="panel-head"><div><h2>给学生安排一条讲解</h2><p>新建后先进入待审核，发布前仍可检查链接与表述。</p></div><PlusCircle /></div><form className="video-compose-form" onSubmit={submit}>
      <label>学生<select value={studentId} onChange={(event) => setStudentId(event.target.value)} required>{dashboard.students.map((student) => <option key={student.id} value={student.id}>{student.displayName} · {student.gradeBand}</option>)}</select></label>
      <label>对应知识点<select value={skillId} onChange={(event) => setSkillId(event.target.value)} disabled={skillsLoading || !skills.length} required><option value="">{skillsLoading ? '正在读取…' : skills.length ? '请选择知识点' : '暂无可用知识点'}</option>{skills.map((skill) => <option key={skill.id} value={skill.id}>{skill.title}</option>)}</select></label>
      <label className="video-form-wide">讲解标题<input value={title} onChange={(event) => setTitle(event.target.value)} maxLength={120} placeholder="学生一眼就能看懂要解决什么" required /></label>
      <label>来源平台<input value={provider} onChange={(event) => setProvider(event.target.value)} maxLength={60} placeholder="例如：甘老师录屏、哔哩哔哩" required /></label>
      <label>视频链接<input type="url" value={url} onChange={(event) => setUrl(event.target.value)} placeholder="https://…" required /></label>
      <label className="video-form-wide">为什么安排给这名学生<textarea value={teacherReason} onChange={(event) => setTeacherReason(event.target.value)} maxLength={300} placeholder={`写清与${selectedStudent?.displayName ?? '学生'}当前课堂进度或复习证据的关系；这段话学生和家长都能看到。`} required /></label>
      <div className="video-review-rule"><ShieldCheck /><p><b>发布规则：</b>系统不会自行决定教学内容。草稿经甘老师复核并发布后，学生才会看到；撤回后立即停止展示。</p></div>
      <button className="primary-button" disabled={saving || skillsLoading}>{saving ? <RefreshCw className="spin" /> : <PlusCircle />}{saving ? '正在保存…' : '保存为待审核'}</button>
    </form></section>
    <section className="teacher-panel video-audit-panel"><div className="panel-head"><div><h2>审核、发布与进度</h2><p>打开记录与看完反馈分开呈现，便于老师复核。</p></div><span>{visibleRecommendations.length} 条</span></div>
      <div className="video-filter" role="group" aria-label="筛选视频讲解状态">{(['all', 'draft', 'published', 'withdrawn'] as const).map((item) => <button key={item} className={status === item ? 'active' : ''} aria-pressed={status === item} onClick={() => setStatus(item)}>{item === 'all' ? '全部' : statusCopy[item]}{item !== 'all' && <span>{counts[item] ?? 0}</span>}</button>)}</div>
      {loading ? <div className="center-loading"><RefreshCw className="spin" />正在读取讲解安排…</div> : <div className="teacher-video-list">{visibleRecommendations.map((video) => {
        const view = videoProgressView(video)
        const safeUrl = safeExternalVideoUrl(video.url)
        return <article key={video.id} className={`teacher-video-item status-${video.status}`}><div className="teacher-video-item-head"><div><span className={`video-status ${video.status}`}>{statusCopy[video.status]}</span><span className={`video-progress-badge ${view.tone}`}>{view.label}</span></div><small>{video.publishedAt ? `发布于 ${formatEngagementTime(video.publishedAt)}` : '尚未发布'}</small></div><h3><ChemText>{video.title}</ChemText></h3><p className="video-skill"><VideoSkillLabel video={video} /> · {video.provider}</p><div className="teacher-video-reason"><ShieldCheck /><div><b>给学生和家长的安排原因</b><p><ChemText>{video.teacherReason}</ChemText></p></div></div><div className="teacher-video-progress"><Clock3 /><div><b>{view.label}</b><p>{view.detail}{progressOf(video).eventCount ? ` · 已记录 ${progressOf(video).eventCount} 次观看动作` : ''}</p></div></div><div className="audit-actions">{safeUrl && <a href={safeUrl} target="_blank" rel="noreferrer"><ExternalLink />检查链接</a>}{video.status === 'draft' && <button disabled={busyId === video.id} onClick={() => void changeStatus(video, 'publish')}><Send />发布</button>}{video.status === 'published' && <button disabled={busyId === video.id} onClick={() => void changeStatus(video, 'withdraw')}><Undo2 />撤回</button>}</div></article>
      })}{!visibleRecommendations.length && <div className="video-empty"><Film /><div><b>当前筛选下没有讲解</b><p>可以在上方先为学生建立一条待审核草稿。</p></div></div>}</div>}
    </section>
  </>
}
