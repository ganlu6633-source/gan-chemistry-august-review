import { useCallback, useEffect, useId, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { Check, CheckCircle2, Circle, Clock3, Flame, Route, Sparkles, Target } from 'lucide-react'
import { ABILITY_MAP_BLUEPRINTS, type AbilityMapRelation } from '../data/abilityMap'
import type { LearningPlanDay, SkillDefinition, StudentDashboardData, StudentSkillState } from '../domain/types'
import { ChemText } from './ChemText'

type MapFilter = 'all' | 'forming' | 'lit' | 'due'
type MapStatus = 'empty' | 'forming' | 'stable' | 'due' | 'recovered'
type DrawnRelation = AbilityMapRelation & { path: string }

const FILTERS: Array<{ id: MapFilter; label: string }> = [
  { id: 'all', label: '全景' },
  { id: 'forming', label: '正在形成' },
  { id: 'lit', label: '已点亮' },
  { id: 'due', label: '需要复习' },
]

const todayInChina = () => new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
const localDateKey = (value: string) => /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : new Date(value).toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
const shortDate = (date: string | null) => {
  if (!date) return '暂无'
  const local = localDateKey(date)
  return `${Number(local.slice(5, 7))}月${Number(local.slice(8, 10))}日`
}

function statusFor(state: StudentSkillState | undefined, today: string): MapStatus {
  if (!state) return 'empty'
  const reviewDue = Boolean(state.nextReviewAt && localDateKey(state.nextReviewAt) <= today && state.verifiedLevel > 0)
  if (state.stability === 'forgotten' || reviewDue) return 'due'
  if (state.stability === 'recovered') return 'recovered'
  if (state.stability === 'stable') return 'stable'
  if (state.verifiedLevel > 0 || state.stability === 'learning' || state.stability === 'verified') return 'forming'
  return 'empty'
}

function statusCopy(status: MapStatus) {
  if (status === 'forming') return '正在形成'
  if (status === 'stable') return '稳定掌握'
  if (status === 'due') return '该复习了'
  if (status === 'recovered') return '已经找回'
  return '待建立证据'
}

function StatusIcon({ status }: { status: MapStatus }) {
  if (status === 'stable') return <CheckCircle2 aria-hidden="true" />
  if (status === 'due') return <Clock3 aria-hidden="true" />
  if (status === 'recovered') return <Flame aria-hidden="true" />
  if (status === 'forming') return <Sparkles aria-hidden="true" />
  return <Circle aria-hidden="true" />
}

function matchesFilter(filter: MapFilter, status: MapStatus, level: number) {
  if (filter === 'all') return true
  if (filter === 'forming') return status === 'forming'
  if (filter === 'lit') return level > 0
  return status === 'due'
}

function planForSkill(plans: LearningPlanDay[], skillId: string, today: string) {
  const related = [...plans].filter((plan) => plan.skillIds.includes(skillId)).sort((a, b) => a.date.localeCompare(b.date))
  return related.find((plan) => plan.date === today) ?? related.find((plan) => plan.date > today) ?? related.at(-1)
}

function focusPlan(plans: LearningPlanDay[], today: string): { plan: LearningPlanDay | undefined; kind: 'today' | 'next' | 'recent' | 'none' } {
  const ordered = [...plans].sort((a, b) => a.date.localeCompare(b.date))
  const todayPlan = ordered.find((plan) => plan.date === today)
  if (todayPlan) return { plan: todayPlan, kind: 'today' }
  const nextPlan = ordered.find((plan) => plan.date > today)
  if (nextPlan) return { plan: nextPlan, kind: 'next' }
  const recentPlan = ordered.at(-1)
  return recentPlan ? { plan: recentPlan, kind: 'recent' } : { plan: undefined, kind: 'none' }
}

export function AbilityMap({ dashboard, onOpenPlan, busy = false }: { dashboard: StudentDashboardData; onOpenPlan?: (plan: LearningPlanDay) => void; busy?: boolean }) {
  const blueprint = ABILITY_MAP_BLUEPRINTS[dashboard.profile.gradeBand]
  const definitions = useMemo(() => new Map(dashboard.skillDefinitions.map((skill) => [skill.id, skill])), [dashboard.skillDefinitions])
  const states = useMemo(() => new Map(dashboard.skillStates.map((state) => [state.skillId, state])), [dashboard.skillStates])
  const stages = useMemo(() => {
    const mapped = new Set(blueprint.stages.flatMap((stage) => stage.skillIds))
    const unplaced = dashboard.skillDefinitions.filter((skill) => skill.gradeBand === dashboard.profile.gradeBand && !mapped.has(skill.id)).map((skill) => skill.id)
    return unplaced.length ? [...blueprint.stages, { id: `${dashboard.profile.gradeBand}-unplaced`, title: '新增能力', summary: '已经进入能力库，地图位置等待教学审核。', skillIds: unplaced }] : blueprint.stages
  }, [blueprint, dashboard.profile.gradeBand, dashboard.skillDefinitions])
  const visibleIds = useMemo(() => stages.flatMap((stage) => stage.skillIds).filter((id) => definitions.has(id)), [stages, definitions])
  const today = todayInChina()
  const currentPlanContext = focusPlan(dashboard.plans, today)
  const currentPlan = currentPlanContext.plan
  const currentSkillIds = useMemo(() => new Set(currentPlan?.skillIds.filter((id) => visibleIds.includes(id)) ?? []), [currentPlan, visibleIds])
  const currentSkillId = [...currentSkillIds][0]
  const currentStageIndex = stages.findIndex((stage) => stage.skillIds.some((id) => currentSkillIds.has(id)))
  const [selectedId, setSelectedId] = useState(currentSkillId ?? visibleIds[0] ?? '')
  const [filter, setFilter] = useState<MapFilter>('all')
  const markerKey = useId().replace(/:/g, '')
  const networkRef = useRef<HTMLDivElement | null>(null)
  const nodeRefs = useRef(new Map<string, HTMLButtonElement>())
  const [drawnRelations, setDrawnRelations] = useState<DrawnRelation[]>([])

  useEffect(() => {
    setSelectedId(currentSkillId ?? visibleIds[0] ?? '')
    setFilter('all')
  }, [dashboard.profile.id, currentSkillId, visibleIds])

  const locateCurrent = useCallback((behavior: ScrollBehavior = 'smooth') => {
    const node = currentSkillId ? nodeRefs.current.get(currentSkillId) : undefined
    if (node && typeof node.scrollIntoView === 'function') node.scrollIntoView({ block: 'center', behavior })
  }, [currentSkillId])

  useEffect(() => {
    if (!currentSkillId || currentStageIndex < 2) return
    const timer = window.setTimeout(() => {
      const node = nodeRefs.current.get(currentSkillId)
      if (!node || typeof node.scrollIntoView !== 'function') return
      const rect = node.getBoundingClientRect()
      if (rect.top < 82 || rect.bottom > window.innerHeight) locateCurrent('smooth')
    }, 180)
    return () => window.clearTimeout(timer)
  }, [currentStageIndex, dashboard.profile.id, currentSkillId, locateCurrent])

  useLayoutEffect(() => {
    const network = networkRef.current
    if (!network) return
    let frame = 0
    const draw = () => {
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(() => {
        const container = network.getBoundingClientRect()
        const next = blueprint.relations.flatMap<DrawnRelation>((relation) => {
          const from = nodeRefs.current.get(relation.from)?.getBoundingClientRect()
          const to = nodeRefs.current.get(relation.to)?.getBoundingClientRect()
          if (!from || !to || !container.width || !container.height) return []
          const fromCenter = { x: from.left - container.left + from.width / 2, y: from.top - container.top + from.height / 2 }
          const toCenter = { x: to.left - container.left + to.width / 2, y: to.top - container.top + to.height / 2 }
          const horizontal = Math.abs(toCenter.x - fromCenter.x) >= Math.abs(toCenter.y - fromCenter.y)
          if (horizontal) {
            const direction = toCenter.x >= fromCenter.x ? 1 : -1
            const x1 = fromCenter.x + direction * from.width / 2
            const x2 = toCenter.x - direction * to.width / 2
            const bend = x1 + (x2 - x1) / 2
            return [{ ...relation, path: `M ${x1} ${fromCenter.y} C ${bend} ${fromCenter.y}, ${bend} ${toCenter.y}, ${x2} ${toCenter.y}` }]
          }
          const direction = toCenter.y >= fromCenter.y ? 1 : -1
          const y1 = fromCenter.y + direction * from.height / 2
          const y2 = toCenter.y - direction * to.height / 2
          const bend = y1 + (y2 - y1) / 2
          return [{ ...relation, path: `M ${fromCenter.x} ${y1} C ${fromCenter.x} ${bend}, ${toCenter.x} ${bend}, ${toCenter.x} ${y2}` }]
        })
        setDrawnRelations(next)
      })
    }
    draw()
    const resizeObserver = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(draw)
    resizeObserver?.observe(network)
    window.addEventListener('resize', draw)
    return () => {
      cancelAnimationFrame(frame)
      resizeObserver?.disconnect()
      window.removeEventListener('resize', draw)
    }
  }, [blueprint, visibleIds])

  const selected = definitions.get(selectedId)
  const selectedState = states.get(selectedId)
  const selectedStatus = statusFor(selectedState, today)
  const relatedPlan = selected ? planForSkill(dashboard.plans, selected.id, today) : undefined
  const selectedRelations = selected ? blueprint.relations.filter((relation) => relation.from === selected.id || relation.to === selected.id) : []
  const namedSkill = (skillId: string) => definitions.get(skillId)?.title ?? skillId
  const relationCopy = (relation: AbilityMapRelation, skill: SkillDefinition) => {
    if (relation.from === skill.id) return relation.kind === 'main' ? `后续能力：${namedSkill(relation.to)}` : `支撑迁移到：${namedSkill(relation.to)}`
    return relation.kind === 'main' ? `前置能力：${namedSkill(relation.from)}` : `得到支撑于：${namedSkill(relation.from)}`
  }
  const locationCopy = currentPlanContext.kind === 'today' ? '你在这里' : currentPlanContext.kind === 'next' ? '下一步' : '最近复习'

  return <section className="ability-map-page" aria-labelledby="ability-map-title">
    <div className="ability-map-heading">
      <div className="page-title"><span className="eyebrow">把零散知识接成一条路</span><h1 id="ability-map-title">我的化学能力地图</h1><p>按阶段编号沿箭头前进，虚线表示会在综合题里提供支撑。灰色节点只是还没有形成证据，不代表不会。</p></div>
      <div className="ability-map-summary" aria-label="能力地图概况"><span><Route aria-hidden="true" /><b>{visibleIds.length}</b>个能力节点</span><span><Check aria-hidden="true" /><b>{visibleIds.filter((id) => (states.get(id)?.verifiedLevel ?? 0) > 0).length}</b>个已点亮</span></div>
    </div>

    <div className="ability-map-toolbar" role="group" aria-label="筛选和定位能力节点">
      {FILTERS.map((item) => <button key={item.id} type="button" aria-pressed={filter === item.id} onClick={() => setFilter(item.id)}>{item.label}</button>)}
      {currentSkillId && <button type="button" className="ability-locate" onClick={() => locateCurrent()}><Target aria-hidden="true" />定位今天</button>}
      <span className="ability-map-legend"><i className="main" />学习主线 <i className="support" />支撑与迁移</span>
    </div>

    <div className="ability-atlas" data-grade={dashboard.profile.gradeBand}>
      <div className="ability-atlas-intro"><span>{dashboard.profile.gradeBand}</span><div><h2><ChemText>{blueprint.title}</ChemText></h2><p><ChemText>{blueprint.subtitle}</ChemText></p></div></div>
      <div className="ability-map-network" ref={networkRef}>
        <svg className="ability-map-links" width="100%" height="100%" aria-hidden="true">
          <defs>
            <marker id={`${markerKey}-main`} markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto" markerUnits="strokeWidth"><polygon points="0 0, 8 4, 0 8" fill="#29a79b" /></marker>
            <marker id={`${markerKey}-support`} markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto" markerUnits="strokeWidth"><polygon points="0 0, 8 4, 0 8" fill="#4c8ca7" /></marker>
          </defs>
          {drawnRelations.map((relation) => <path key={`${relation.from}-${relation.to}`} className={relation.kind} d={relation.path} markerEnd={`url(#${markerKey}-${relation.kind})`} />)}
        </svg>
        {stages.map((stage, stageIndex) => <section className="ability-map-stage" key={stage.id} aria-labelledby={`${stage.id}-title`}>
          <header><span>{String(stageIndex + 1).padStart(2, '0')}</span><div><h3 id={`${stage.id}-title`}><ChemText>{stage.title}</ChemText></h3><p><ChemText>{stage.summary}</ChemText></p></div></header>
          <div className="ability-map-nodes">
            {stage.skillIds.flatMap((skillId) => {
              const skill = definitions.get(skillId)
              if (!skill) return []
              const state = states.get(skillId)
              const level = state?.verifiedLevel ?? 0
              const status = statusFor(state, today)
              const highlighted = filter === 'all' || matchesFilter(filter, status, level)
              const isCurrent = currentSkillIds.has(skillId)
              const progress = skill.maxLevel ? level / skill.maxLevel * 100 : 0
              return [<button
                type="button"
                key={skill.id}
                ref={(node) => { if (node) nodeRefs.current.set(skill.id, node); else nodeRefs.current.delete(skill.id) }}
                className={`ability-node status-${status} ${selectedId === skill.id ? 'is-selected' : ''} ${isCurrent ? 'is-current' : ''} ${highlighted ? '' : 'is-dimmed'}`}
                aria-pressed={selectedId === skill.id}
                aria-current={isCurrent ? 'step' : undefined}
                aria-label={`${skill.title}，${statusCopy(status)}，已验证L${level}，共L${skill.maxLevel}${isCurrent ? `，${locationCopy}` : ''}`}
                onClick={() => setSelectedId(skill.id)}
              >
                {isCurrent && <span className="ability-location"><Target aria-hidden="true" />{locationCopy}</span>}
                <span className="ability-node-icon" style={{ '--ability-progress': `${progress}%` } as React.CSSProperties}><StatusIcon status={status} /></span>
                <span className="ability-node-copy"><b><ChemText>{skill.title}</ChemText></b><small>{statusCopy(status)}</small></span>
                <span className="ability-level">L{level}<i>/ L{skill.maxLevel}</i></span>
              </button>]
            })}
          </div>
        </section>)}
      </div>
    </div>

    {selected && <section className="ability-detail" aria-live="polite" aria-labelledby="ability-detail-title">
      <div className={`ability-detail-status status-${selectedStatus}`}><StatusIcon status={selectedStatus} /><span>{statusCopy(selectedStatus)}</span></div>
      <div className="ability-detail-main"><span className="eyebrow">当前节点</span><h2 id="ability-detail-title"><ChemText>{selected.title}</ChemText></h2><p>已通过检验的能力为 <b>L{selectedState?.verifiedLevel ?? 0} / L{selected.maxLevel}</b>。只有真实完成并通过检验的层级才会在地图上点亮。</p>
        <div className="ability-level-track" aria-label={`已验证${selectedState?.verifiedLevel ?? 0}级，共${selected.maxLevel}级`}>{Array.from({ length: selected.maxLevel }, (_, index) => <i className={index < (selectedState?.verifiedLevel ?? 0) ? 'on' : ''} key={index}><span>L{index + 1}</span></i>)}</div>
      </div>
      <dl className="ability-detail-facts">
        <div><dt>上次检验</dt><dd>{shortDate(selectedState?.lastReviewedAt ?? null)}</dd></div>
        <div><dt>下次找回</dt><dd>{shortDate(selectedState?.nextReviewAt ?? null)}</dd></div>
        <div><dt>地图联系</dt><dd>{selectedRelations.length ? <ChemText>{selectedRelations.map((relation) => relationCopy(relation, selected)).join('；')}</ChemText> : '当前是独立入口节点'}</dd></div>
        <div><dt>关联安排</dt><dd>{relatedPlan ? <><span>{shortDate(relatedPlan.date)} · </span><ChemText>{relatedPlan.title}</ChemText></> : '计划会按课堂进度自动安排'}</dd></div>
      </dl>
      {selectedState?.teacherIntervention && <p className="ability-teacher-note">甘老师已关注这个节点，会结合课堂情况调整下一步。</p>}
      {relatedPlan && onOpenPlan && <button type="button" className="primary-button compact ability-plan-button" onClick={() => onOpenPlan(relatedPlan)} disabled={busy}>{busy ? '正在准备…' : '打开关联学习'}<Target aria-hidden="true" /></button>}
    </section>}

    <details className="ability-text-route"><summary>查看这张图的完整文字路线</summary><div>{stages.map((stage, index) => <section key={stage.id}><h3>{index + 1}. <ChemText>{stage.title}</ChemText></h3><p><ChemText>{stage.summary}</ChemText></p><ul>{stage.skillIds.filter((id) => definitions.has(id)).map((id) => <li key={id}><ChemText>{namedSkill(id)}</ChemText></li>)}</ul></section>)}<section className="ability-relation-list"><h3>能力怎样连接</h3><ul>{blueprint.relations.filter((relation) => definitions.has(relation.from) && definitions.has(relation.to)).map((relation) => <li key={`${relation.from}-${relation.to}`}><b><ChemText>{`${namedSkill(relation.from)} → ${namedSkill(relation.to)}`}</ChemText></b><span>{relation.kind === 'main' ? '学习主线' : '支撑与迁移'}</span></li>)}</ul></section><p><b>连线说明：</b>箭头指向下一步；实线是建议学习主线，虚线表示前面的能力会支撑后面的综合应用，它不等于严格的先修关系。</p></div></details>
  </section>
}
