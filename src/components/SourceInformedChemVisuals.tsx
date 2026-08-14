import type { ComponentType, CSSProperties } from 'react'
import { ChemText } from './ChemText'
import { supportsSourceInformedChemVisual, type SourceInformedChemSkillId } from './sourceInformedChemVisualSupport'

const colors = {
  ink: '#0e2e3d',
  muted: '#506b77',
  teal: '#087f7a',
  tealSoft: '#e4f6f3',
  blue: '#176b87',
  blueSoft: '#e8f4f9',
  amber: '#b76a00',
  amberSoft: '#fff3dc',
  red: '#b8463f',
  redSoft: '#fff0ed',
  border: '#bed9df',
  paper: '#fbfefe',
}

const figureStyle: CSSProperties = {
  boxSizing: 'border-box',
  width: '100%',
  minWidth: 0,
  margin: 0,
  padding: 'clamp(0.85rem, 2.5vw, 1.4rem)',
  border: `1px solid ${colors.border}`,
  borderRadius: '1.15rem',
  background: `linear-gradient(150deg, ${colors.paper}, #eef9fa)`,
  color: colors.ink,
  overflowWrap: 'anywhere',
}

const cardGridStyle: CSSProperties = {
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 13.5rem), 1fr))',
  gap: '0.75rem',
  width: '100%',
  minWidth: 0,
}

const cardStyle: CSSProperties = {
  boxSizing: 'border-box',
  minWidth: 0,
  padding: '0.85rem',
  border: `1px solid ${colors.border}`,
  borderRadius: '0.9rem',
  background: '#fff',
  overflowWrap: 'anywhere',
}

function VisualHeading({ title, subtitle }: { title: string; subtitle: string }) {
  return <figcaption style={{ display: 'grid', gap: '0.25rem', marginBottom: '1rem' }}>
    <span style={{ color: colors.teal, fontSize: '0.8rem', fontWeight: 800, letterSpacing: '0.04em' }}>一轮复习图形逻辑 · 原创建模</span>
    <b style={{ fontSize: 'clamp(1.05rem, 3vw, 1.35rem)' }}>{title}</b>
    <span style={{ color: colors.muted, lineHeight: 1.65 }}>{subtitle}</span>
  </figcaption>
}

function Formula({ children }: { children: string }) {
  return <span style={{ fontFamily: '"Cambria Math", "Times New Roman", serif', fontWeight: 750 }}><ChemText>{children}</ChemText></span>
}

function QuantityCard({
  symbol,
  title,
  unit,
  formula,
  tone = 'teal',
}: {
  symbol: string
  title: string
  unit: string
  formula: string
  tone?: 'teal' | 'blue' | 'amber'
}) {
  const background = tone === 'blue' ? colors.blueSoft : tone === 'amber' ? colors.amberSoft : colors.tealSoft
  const foreground = tone === 'blue' ? colors.blue : tone === 'amber' ? colors.amber : colors.teal
  return <section style={{ ...cardStyle, display: 'grid', gap: '0.38rem', background }}>
    <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: '0.5rem', flexWrap: 'wrap' }}>
      <strong style={{ color: foreground, fontSize: '1.08rem' }}>{title}</strong>
      <span style={{ color: foreground, fontSize: '1.3rem', fontWeight: 900 }}><Formula>{symbol}</Formula></span>
    </div>
    <small style={{ color: colors.muted }}>常用单位：{unit}</small>
    <div style={{ paddingTop: '0.3rem', borderTop: `1px dashed ${colors.border}`, fontSize: '1.03rem' }}><Formula>{formula}</Formula></div>
  </section>
}

function ParticleCluster({ count = 8, fill = colors.teal }: { count?: number; fill?: string }) {
  const positions = [
    [25, 28], [50, 21], [75, 30], [20, 55], [48, 50], [78, 57], [34, 76], [66, 78],
  ]
  return <svg viewBox="0 0 100 100" role="img" aria-label="许多微观粒子组成一个可计量的粒子集合" style={{ width: '5.2rem', maxWidth: '100%', height: 'auto', flex: '0 0 auto' }}>
    <rect x="3" y="3" width="94" height="94" rx="17" fill="#fff" stroke={colors.border} strokeWidth="2" />
    {positions.slice(0, count).map(([cx, cy], index) => <circle key={`${cx}-${cy}`} cx={cx} cy={cy} r="7" fill={fill} opacity={0.74 + index * 0.025} />)}
  </svg>
}

export function MoleIntroVisual() {
  return <figure style={figureStyle} aria-label="物质的量、阿伏加德罗常数与摩尔质量关系图">
    <VisualHeading title="先认对象，再让物质的量 n 做中转站" subtitle="把看得见的质量与数不清的微粒接在一起；每次换算先回到 n，就不会混用公式。" />
    <div style={{ ...cardStyle, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 'clamp(0.7rem, 3vw, 1.4rem)', flexWrap: 'wrap', marginBottom: '0.8rem', background: colors.tealSoft }}>
      <ParticleCluster />
      <div style={{ minWidth: 0, flex: '1 1 15rem' }}>
        <b style={{ display: 'block', color: colors.teal, fontSize: '1.1rem' }}>1 mol 是“一大包指定微粒”</b>
        <p style={{ margin: '0.35rem 0 0', color: colors.muted, lineHeight: 1.65 }}>
          <Formula>1 mol指定微粒含N_A个该微粒，N_A≈6.02×10²³ mol⁻¹</Formula>。必须先说清是分子、原子、离子、电子、质子、中子，还是离子晶体的化学式单位。
        </p>
      </div>
    </div>
    <div style={cardGridStyle}>
      <QuantityCard symbol="N" title="微粒数" unit="个（计数时通常不写单位）" formula="N=nN_A；n=N/N_A" />
      <QuantityCard symbol="n" title="物质的量（中转站）" unit="mol" formula="n=N/N_A=m/M" tone="blue" />
      <QuantityCard symbol="m" title="质量" unit="g" formula="m=nM；n=m/M" tone="amber" />
      <QuantityCard symbol="M" title="摩尔质量" unit="g·mol⁻¹" formula="M=m/n" tone="amber" />
    </div>
    <div style={{ ...cardStyle, marginTop: '0.8rem', borderLeft: `0.35rem solid ${colors.blue}` }}>
      <b style={{ color: colors.blue }}>示范：18 g H₂O到底数什么？</b>
      <p style={{ margin: '0.45rem 0 0', lineHeight: 1.75 }}><Formula>m=18 g → n=m/M=18/18=1 mol → N(H₂O分子)=nN_A=N_A</Formula>。若问氢原子数，还要乘每个水分子中的2个H：<Formula>N(H原子)=2N_A</Formula>。</p>
    </div>
  </figure>
}

function GasBox({ label, particleFill, particles }: { label: string; particleFill: string; particles: Array<[number, number]> }) {
  return <svg viewBox="0 0 220 145" role="img" aria-label={label} style={{ display: 'block', width: '100%', height: 'auto', minWidth: 0 }}>
    <rect x="12" y="20" width="196" height="96" rx="12" fill="#fff" stroke={colors.border} strokeWidth="3" />
    <path d="M12 20h196M12 116h196" stroke={colors.blue} strokeWidth="4" />
    {particles.map(([cx, cy], index) => <circle key={`${cx}-${cy}`} cx={cx} cy={cy} r="9" fill={particleFill} opacity={0.82 + (index % 2) * 0.12} />)}
    <text x="110" y="138" textAnchor="middle" fill={colors.ink} fontSize="14" fontWeight="700">{label}</text>
  </svg>
}

export function GasMolarVolumeVisual() {
  const particlesA: Array<[number, number]> = [[42, 46], [86, 70], [130, 44], [175, 78], [48, 94], [142, 91]]
  const particlesB: Array<[number, number]> = [[35, 62], [73, 41], [107, 83], [145, 55], [181, 93], [62, 98]]
  return <figure style={figureStyle} aria-label="气体摩尔体积的条件闸门与换算关系图">
    <VisualHeading title="先过条件闸门，再使用气体摩尔体积" subtitle="22.4 L·mol⁻¹不是所有物质、所有条件下的通用常数；物态、温度、压强缺一不可。" />
    <div style={{ ...cardGridStyle, marginBottom: '0.8rem' }}>
      <section style={{ ...cardStyle, borderTop: `0.35rem solid ${colors.blue}` }}><b style={{ color: colors.blue }}>闸门 1｜对象</b><p style={{ margin: '0.4rem 0 0', lineHeight: 1.65 }}>题目研究的必须是<strong>气体</strong>。标准状况下H₂O是液体，不能套22.4 L·mol⁻¹。</p></section>
      <section style={{ ...cardStyle, borderTop: `0.35rem solid ${colors.blue}` }}><b style={{ color: colors.blue }}>闸门 2｜温压</b><p style={{ margin: '0.4rem 0 0', lineHeight: 1.65 }}>高中常用标准状况：<strong>0 ℃、101 kPa</strong>，两个条件要同时满足。</p></section>
      <section style={{ ...cardStyle, borderTop: `0.35rem solid ${colors.teal}` }}><b style={{ color: colors.teal }}>通过后使用</b><p style={{ margin: '0.4rem 0 0', lineHeight: 1.65 }}><Formula>V_m≈22.4 L·mol⁻¹；V=nV_m；n=V/V_m</Formula></p></section>
    </div>
    <div style={{ ...cardStyle, display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 14rem), 1fr))', alignItems: 'center', gap: '0.8rem', background: colors.blueSoft }}>
      <GasBox label="气体 A：1 mol" particleFill={colors.teal} particles={particlesA} />
      <div style={{ minWidth: 0, textAlign: 'center', lineHeight: 1.7 }}><b style={{ color: colors.blue }}>同温、同压</b><div style={{ fontSize: '1.4rem', color: colors.blue }}>⇄</div><span>相同物质的量的气体<br />体积相同</span></div>
      <GasBox label="气体 B：1 mol" particleFill={colors.amber} particles={particlesB} />
    </div>
    <div style={{ ...cardStyle, marginTop: '0.8rem', borderLeft: `0.35rem solid ${colors.amber}` }}>
      <b style={{ color: colors.amber }}>示范：标准状况下 11.2 L O₂</b>
      <p style={{ margin: '0.45rem 0 0', lineHeight: 1.75 }}><Formula>n(O₂)=V/V_m=11.2/22.4=0.5 mol</Formula>；氧分子数为<Formula>0.5N_A</Formula>，氧原子数为<Formula>1.0N_A</Formula>。先分清“分子”还是“原子”。</p>
    </div>
  </figure>
}

type RedoxTrackStep = { label: string; note: string }

function RedoxTrack({ title, tone, soft, steps }: { title: string; tone: string; soft: string; steps: RedoxTrackStep[] }) {
  return <section style={{ ...cardStyle, borderTop: `0.4rem solid ${tone}`, background: soft }} aria-label={title}>
    <h3 style={{ color: tone, margin: '0 0 0.7rem', fontSize: '1.05rem' }}>{title}</h3>
    <ol style={{ ...cardGridStyle, gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 8.5rem), 1fr))', listStyle: 'none', margin: 0, padding: 0 }}>
      {steps.map((step, index) => <li key={step.label} style={{ ...cardStyle, position: 'relative', paddingTop: '2rem' }}>
        <span style={{ position: 'absolute', top: '0.55rem', left: '0.65rem', display: 'grid', placeItems: 'center', width: '1.25rem', height: '1.25rem', borderRadius: '50%', background: tone, color: '#fff', fontSize: '0.72rem', fontWeight: 900 }}>{index + 1}</span>
        <b style={{ color: tone, display: 'block' }}>{step.label}</b>
        <small style={{ display: 'block', marginTop: '0.28rem', color: colors.muted, lineHeight: 1.55 }}>{step.note}</small>
      </li>)}
    </ol>
  </section>
}

export function RedoxVisual() {
  const oxidation: RedoxTrackStep[] = [
    { label: '化合价升高', note: '例如 Fe：0 → +2' },
    { label: '失电子', note: 'Fe − 2e⁻ → Fe²⁺' },
    { label: '被氧化', note: '反应物 Fe 的变化' },
    { label: '发生氧化反应', note: '过程名称要写完整' },
    { label: '作还原剂', note: '还原剂自身被氧化' },
    { label: '生成氧化产物', note: 'Fe²⁺ 是氧化产物' },
  ]
  const reduction: RedoxTrackStep[] = [
    { label: '化合价降低', note: '例如 Cu：+2 → 0' },
    { label: '得电子', note: 'Cu²⁺ + 2e⁻ → Cu' },
    { label: '被还原', note: '反应物 Cu²⁺ 的变化' },
    { label: '发生还原反应', note: '过程名称要写完整' },
    { label: '作氧化剂', note: '氧化剂自身被还原' },
    { label: '生成还原产物', note: 'Cu 是还原产物' },
  ]
  return <figure style={figureStyle} aria-label="氧化还原反应双轨关系与电子守恒图">
    <VisualHeading title="升失氧，降得还：沿同一条轨道把六个身份接全" subtitle="先标反应前后化合价，再确定电子得失；剂与性质名称一致，其余概念与发生的变化相反。" />
    <div style={{ display: 'grid', gap: '0.85rem' }}>
      <RedoxTrack title="氧化轨｜升价 → 失电子 → 被氧化 → 氧化反应 → 还原剂 → 氧化产物" tone={colors.red} soft={colors.redSoft} steps={oxidation} />
      <div style={{ ...cardStyle, display: 'flex', justifyContent: 'center', alignItems: 'center', gap: '0.65rem', flexWrap: 'wrap', background: '#fff' }}>
        <span style={{ color: colors.red, fontWeight: 800 }}>失电子总数</span><b style={{ fontSize: '1.3rem' }}>=</b><span style={{ color: colors.blue, fontWeight: 800 }}>得电子总数</span><small style={{ flexBasis: '100%', textAlign: 'center', color: colors.muted }}>电子守恒是配平与定量计算的核心校验线</small>
      </div>
      <RedoxTrack title="还原轨｜降价 → 得电子 → 被还原 → 还原反应 → 氧化剂 → 还原产物" tone={colors.blue} soft={colors.blueSoft} steps={reduction} />
    </div>
    <div style={{ ...cardStyle, marginTop: '0.85rem', display: 'grid', gap: '0.5rem', borderLeft: `0.35rem solid ${colors.teal}` }}>
      <b style={{ color: colors.teal }}>完整示范｜Fe + Cu²⁺ → Fe²⁺ + Cu</b>
      <p style={{ margin: 0, lineHeight: 1.72 }}><strong>Fe：</strong>0价升到+2价，失2e⁻，被氧化，发生氧化反应；Fe是还原剂，Fe²⁺是氧化产物。</p>
      <p style={{ margin: 0, lineHeight: 1.72 }}><strong>Cu²⁺：</strong>+2价降到0价，得2e⁻，被还原，发生还原反应；Cu²⁺是氧化剂，Cu是还原产物。</p>
      <p style={{ margin: 0, color: colors.muted, lineHeight: 1.65 }}><strong>最后校验：</strong>Fe失2e⁻ = Cu²⁺得2e⁻；再检查原子数和总电荷均守恒。</p>
    </div>
  </figure>
}

const visuals: Record<SourceInformedChemSkillId, ComponentType> = {
  H1_MOLE_INTRO: MoleIntroVisual,
  H1_GAS_MOLAR_VOLUME: GasMolarVolumeVisual,
  H1_REDOX: RedoxVisual,
}

/**
 * Native, responsive diagrams distilled from the reasoning patterns in the
 * teacher's first-round review materials. Returning null keeps integration
 * explicit for skills that do not yet have a dedicated visual.
 */
export function SourceInformedChemVisual({ skillId }: { skillId: string }) {
  if (!supportsSourceInformedChemVisual(skillId)) return null
  const Visual = visuals[skillId]
  return <Visual />
}
