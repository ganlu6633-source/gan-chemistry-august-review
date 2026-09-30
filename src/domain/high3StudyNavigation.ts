import type { LearningPlanDay, SkillDefinition } from './types'

/** Curated against the released concept catalogue; a chapter is not a question type. */
export const HIGH3_TASK_TYPES = [
  { id: 'judgement', title: '判断正误与比较', detail: '性质、条件和比较依据，逐条辨清。', concepts: [
    'H3_AQ__C01', 'H3_AQ__C03', 'H3_AQ__C04', 'H3_EQUILIBRIUM__C02',
    'H3_INORGANIC__C01', 'H3_INORGANIC__C02', 'H3_ION_REDOX__C01', 'H3_ION_REDOX__C04',
    'H3_ORGANIC__C01', 'H3_ORGANIC__C05', 'H3_STRUCTURE__C01', 'H3_STRUCTURE__C03',
  ] },
  { id: 'equations', title: '方程式与配平', detail: '判断反应、检查写法，再核对守恒。', concepts: [
    'H3_ION_REDOX__C02', 'H3_ION_REDOX__C03', 'H3_ION_REDOX__C05', 'H3_ELECTRO__C03',
  ] },
  { id: 'quantity', title: '计数与定量计算', detail: '微粒数、浓度、电子数和晶胞定量。', concepts: [
    'H3_STOICH__C01', 'H3_STOICH__C02', 'H3_STOICH__C04', 'H3_STOICH__C05',
    'H3_ELECTRO__C05', 'H3_AQ__C02', 'H3_EQUILIBRIUM__C03', 'H3_STRUCTURE__C05',
  ] },
  { id: 'graphs', title: '图像与反应路径', detail: '读坐标、找变化，分析能量与反应机理。', concepts: [
    'H3_AQ__C05', 'H3_EQUILIBRIUM__C01', 'H3_EQUILIBRIUM__C04',
    'H3_THERMO_RATE__C01', 'H3_THERMO_RATE__C02', 'H3_THERMO_RATE__C03', 'H3_THERMO_RATE__C04', 'H3_THERMO_RATE__C05',
  ] },
  { id: 'structure', title: '结构识别与空间计数', detail: '构型、异构、高分子和晶胞，各有各的数法。', concepts: [
    'H3_ORGANIC__C03', 'H3_ORGANIC__C04', 'H3_STRUCTURE__C02', 'H3_STRUCTURE__C04',
  ] },
  { id: 'routes', title: '转化推断与流程分析', detail: '追踪物质去向，判断路线与资源利用。', concepts: [
    'H3_INORGANIC__C03', 'H3_INORGANIC__C05', 'H3_ORGANIC__C02',
    'H3_PROCESS__C01', 'H3_PROCESS__C04', 'H3_PROCESS__C05', 'H3_EQUILIBRIUM__C05',
  ] },
  { id: 'experiment', title: '实验操作与方案评价', detail: '制备、分离、检验、误差和实验结论。', concepts: [
    'H3_EXPERIMENT__C01', 'H3_EXPERIMENT__C02', 'H3_EXPERIMENT__C03', 'H3_EXPERIMENT__C04', 'H3_EXPERIMENT__C05',
    'H3_INORGANIC__C04', 'H3_STOICH__C03', 'H3_PROCESS__C02', 'H3_PROCESS__C03',
  ] },
  { id: 'devices', title: '电化学装置判断', detail: '判断电极、充放电和离子迁移方向。', concepts: [
    'H3_ELECTRO__C01', 'H3_ELECTRO__C02', 'H3_ELECTRO__C04',
  ] },
] as const

export const HIGH3_UNCLASSIFIED_TASK = { id: 'unclassified', title: '其他已开放练习', detail: '已能练习，题型归类还在补充。' }

export function high3TaskType(conceptKey: string) {
  return HIGH3_TASK_TYPES.find((type) => (type.concepts as readonly string[]).includes(conceptKey)) ?? HIGH3_UNCLASSIFIED_TASK
}

const HIGH3_SKILL_LABELS: Record<string, string> = {
  H3_INORGANIC: '元素与物质', H3_STOICH: '化学计量', H3_ION_REDOX: '离子反应与氧化还原',
  H3_ORGANIC: '有机化学', H3_STRUCTURE: '物质结构', H3_THERMO_RATE: '能量与反应机理',
  H3_PROCESS: '化工流程', H3_EXPERIMENT: '化学实验', H3_ELECTRO: '电化学',
  H3_AQ: '水溶液中的平衡', H3_EQUILIBRIUM: '反应速率与平衡',
}

export interface High3LearningStop { id: string; title: string; plans: LearningPlanDay[] }

/** Keep the student's actual lesson order. A later revisit stays a later stop. */
export function high3LearningStops(plans: LearningPlanDay[], skills: Pick<SkillDefinition, 'id' | 'title'>[]) {
  const skillNames = new Map(skills.map((skill) => [skill.id, skill.title]))
  const stops: High3LearningStop[] = []
  let lastKey = ''
  for (const plan of plans.filter((item) => item.isScheduled && item.deliveryMode !== 'self_study')
    .sort((a, b) => a.date.localeCompare(b.date) || a.id.localeCompare(b.id))) {
    // Target concepts describe today's focus; skillIds can include all previously
    // authorised review content and must not turn every lesson into a mixed set.
    const focusSkills = [...new Set(plan.targetConceptKeys?.length
      ? plan.targetConceptKeys.map((key) => key.split('__')[0]) : plan.skillIds)]
    const key = focusSkills.length === 1 ? focusSkills[0] : 'mixed'
    const title = key === 'mixed' ? '综合原题与回访' : skillNames.get(key) ?? HIGH3_SKILL_LABELS[key] ?? '老师安排的专题'
    if (key === lastKey && stops.length) stops[stops.length - 1].plans.push(plan)
    else stops.push({ id: plan.id, title, plans: [plan] })
    lastKey = key
  }
  return stops
}
