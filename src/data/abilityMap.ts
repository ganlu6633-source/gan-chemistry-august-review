import type { GradeBand } from '../domain/types'

export type AbilityMapRelationKind = 'main' | 'support'

export interface AbilityMapStage {
  id: string
  title: string
  summary: string
  skillIds: string[]
}

export interface AbilityMapRelation {
  from: string
  to: string
  kind: AbilityMapRelationKind
}

export interface AbilityMapBlueprint {
  title: string
  subtitle: string
  stages: AbilityMapStage[]
  relations: AbilityMapRelation[]
}

export const ABILITY_MAP_BLUEPRINTS: Record<GradeBand, AbilityMapBlueprint> = {
  初三: {
    title: '化学启蒙路线',
    subtitle: '从化学语言出发，连接微粒认识与实验操作。',
    stages: [
      { id: 'junior-language', title: '读懂化学', summary: '先能读、能写、能判断物质变化。', skillIds: ['J_CHEM_LANG'] },
      { id: 'junior-particle', title: '看见微粒', summary: '用原子结构解释元素和物质。', skillIds: ['J09_ATOM'] },
      { id: 'junior-lab', title: '走进实验', summary: '把规范操作变成可靠证据。', skillIds: ['J_EXPERIMENT'] },
    ],
    relations: [
      { from: 'J_CHEM_LANG', to: 'J09_ATOM', kind: 'main' },
      { from: 'J_CHEM_LANG', to: 'J_EXPERIMENT', kind: 'support' },
    ],
  },
  高一: {
    title: '高一化学基础主干',
    subtitle: '分类、规律、反应语言和计量最终汇入元素化合物。',
    stages: [
      { id: 'h1-foundation', title: '认识物质', summary: '先建立分类树，再看元素结构与周期规律。', skillIds: ['H1_CLASSIFY', 'H1_PERIODIC'] },
      { id: 'h1-change', title: '理解微粒与变化', summary: '从电离、电子转移和物质的量理解反应。', skillIds: ['H1_ELECTROLYTE_INTRO', 'H1_REDOX', 'H1_MOLE_INTRO'] },
      { id: 'h1-language', title: '表达与计算', summary: '把微观变化写成方程式，把宏观数量换成物质的量。', skillIds: ['H1_ELECTROLYTE', 'H1_MOLE'] },
      { id: 'h1-transfer', title: '迁移到元素世界', summary: '用规律、电子、离子和计量解释钠与氯。', skillIds: ['H1_NACL'] },
    ],
    relations: [
      { from: 'H1_CLASSIFY', to: 'H1_ELECTROLYTE_INTRO', kind: 'main' },
      { from: 'H1_ELECTROLYTE_INTRO', to: 'H1_ELECTROLYTE', kind: 'main' },
      { from: 'H1_MOLE_INTRO', to: 'H1_MOLE', kind: 'main' },
      { from: 'H1_PERIODIC', to: 'H1_NACL', kind: 'support' },
      { from: 'H1_REDOX', to: 'H1_NACL', kind: 'support' },
      { from: 'H1_ELECTROLYTE', to: 'H1_NACL', kind: 'support' },
      { from: 'H1_MOLE', to: 'H1_NACL', kind: 'support' },
    ],
  },
  高二: {
    title: '选择性必修一·反应原理地图',
    subtitle: '从能量和快慢进入平衡，再走向水溶液与电化学。',
    stages: [
      { id: 'h2-energy', title: '能量与快慢', summary: '分清反应能量、反应方向和速率因素。', skillIds: ['H2_THERMO', 'H2_RATE'] },
      { id: 'h2-equilibrium', title: '平衡框架', summary: '从动态平衡走到K、Q和转化率。', skillIds: ['H2_EQUIL', 'H2_K'] },
      { id: 'h2-aqueous', title: '水溶液中的平衡', summary: '把电离、水解和沉淀放进同一套平衡语言。', skillIds: ['H2_WEAK', 'H2_PH_HYDRO', 'H2_KSP'] },
      { id: 'h2-electro', title: '能量转化与电子流', summary: '用氧化还原解释原电池、电解池与腐蚀防护。', skillIds: ['H2_ELECTRO'] },
    ],
    relations: [
      { from: 'H2_RATE', to: 'H2_EQUIL', kind: 'main' },
      { from: 'H2_EQUIL', to: 'H2_K', kind: 'main' },
      { from: 'H2_K', to: 'H2_WEAK', kind: 'main' },
      { from: 'H2_WEAK', to: 'H2_PH_HYDRO', kind: 'main' },
      { from: 'H2_PH_HYDRO', to: 'H2_KSP', kind: 'main' },
      { from: 'H2_THERMO', to: 'H2_EQUIL', kind: 'support' },
      { from: 'H2_THERMO', to: 'H2_ELECTRO', kind: 'support' },
    ],
  },
  高三: {
    title: '高考化学综合能力地图',
    subtitle: '基础工具、反应原理、实验流程和选修模块在综合题中汇合。',
    stages: [
      { id: 'h3-tools', title: '底层工具', summary: '先把计量、离子和电子守恒变成通用工具。', skillIds: ['H3_STOICH', 'H3_ION_REDOX'] },
      { id: 'h3-principle', title: '核心反应原理', summary: '把能量、速率、平衡、水溶液和电化学接成主线。', skillIds: ['H3_THERMO_RATE', 'H3_EQUILIBRIUM', 'H3_AQ', 'H3_ELECTRO'] },
      { id: 'h3-context', title: '综合真实情境', summary: '元素网络、实验探究与工艺流程互相支撑。', skillIds: ['H3_INORGANIC', 'H3_EXPERIMENT', 'H3_PROCESS'] },
      { id: 'h3-elective', title: '结构与有机', summary: '用结构决定性质，用官能团追踪反应路线。', skillIds: ['H3_STRUCTURE', 'H3_ORGANIC'] },
    ],
    relations: [
      { from: 'H3_STOICH', to: 'H3_ION_REDOX', kind: 'main' },
      { from: 'H3_THERMO_RATE', to: 'H3_EQUILIBRIUM', kind: 'main' },
      { from: 'H3_EQUILIBRIUM', to: 'H3_AQ', kind: 'main' },
      { from: 'H3_ION_REDOX', to: 'H3_INORGANIC', kind: 'main' },
      { from: 'H3_INORGANIC', to: 'H3_PROCESS', kind: 'main' },
      { from: 'H3_ION_REDOX', to: 'H3_ELECTRO', kind: 'support' },
      { from: 'H3_STOICH', to: 'H3_PROCESS', kind: 'support' },
      { from: 'H3_EQUILIBRIUM', to: 'H3_PROCESS', kind: 'support' },
      { from: 'H3_EXPERIMENT', to: 'H3_PROCESS', kind: 'support' },
      { from: 'H3_STRUCTURE', to: 'H3_INORGANIC', kind: 'support' },
      { from: 'H3_STRUCTURE', to: 'H3_ORGANIC', kind: 'support' },
    ],
  },
}

export function validateAbilityMapBlueprint(gradeBand: GradeBand, knownSkillIds: string[]) {
  const blueprint = ABILITY_MAP_BLUEPRINTS[gradeBand]
  const ids = blueprint.stages.flatMap((stage) => stage.skillIds)
  const duplicateIds = ids.filter((id, index) => ids.indexOf(id) !== index)
  const known = new Set(knownSkillIds)
  const danglingRelations = blueprint.relations.filter((relation) => !known.has(relation.from) || !known.has(relation.to))
  return { duplicateIds: [...new Set(duplicateIds)], danglingRelations }
}
