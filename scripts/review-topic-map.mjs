export const REVIEW_TOPICS = {
  J_CHEM_LANG: ['物理变化与化学变化', '元素符号的含义', '化学式与物质组成', '宏观—微观—符号转换', '性质、变化与用途'],
  J_EXPERIMENT: ['实验安全', '仪器选择', '操作先后顺序', '气密性检查', '读数与误差方向'],
  J09_ATOM: ['质子数与元素身份', '原子和离子', '电子得失与电荷', '粒子结构示意图', '元素、原子与离子关系'],
  H1_CLASSIFY: ['分类标准与分类树', '纯净物与混合物', '分散系与胶体', '酸性与碱性氧化物', '物质类别的交叉判断'],
  H1_PERIODIC: ['原子结构与位置', '同周期递变', '同主族递变', '结构—位置—性质', '性质事实验证规律'],
  H1_REDOX: ['化合价升降', '氧化剂与还原剂', '氧化还原产物', '电子守恒', '陌生反应迁移'],
  H1_ELECTROLYTE_INTRO: ['电解质的研究对象', '电解质与非电解质', '自身电离', '自由移动的离子', '导电与电解质边界'],
  H1_MOLE_INTRO: ['物质的量与摩尔', '阿伏加德罗常数', '微粒对象与粒子数', '摩尔质量及单位', '质量—物质的量换算'],
  H2_THERMO: ['焓变正负', '热化学方程式', '盖斯定律', '键能与反应热', '能量守恒'],
  H2_RATE: ['速率表示', '计量数与速率比', '浓度和压强影响', '温度与有效碰撞', '催化剂与活化能'],
  H2_EQUIL: ['平衡状态', '正逆速率', '平衡移动', '勒夏特列原理', '条件改变的瞬间判断'],
  H2_K: ['平衡常数表达式', '三段式', '反应商Q与K', '转化率', '温度与平衡常数'],
  H2_WEAK: ['弱电解质部分电离', '电离平衡', '稀释效应', '同离子效应', 'Ka与酸碱强弱'],
  H2_PH_HYDRO: ['水的电离', 'pH与离子浓度', '盐类水解', '三大守恒', '酸碱中和与滴定'],
  H2_KSP: ['溶解平衡', 'Ksp表达式', 'Qsp与沉淀', '同离子效应', '沉淀转化'],
  H2_ELECTRO: ['原电池与电解池', '正负极与阴阳极', '电极反应', '电子和离子方向', '金属腐蚀与防护'],
  H3_STOICH: ['物质的量枢纽', '阿伏加德罗常数判断', '气体条件', '溶液浓度', '守恒与反应计量'],
  H3_ION_REDOX: ['离子共存', '离子方程式', '少量与过量', '氧化还原配平', '电子、电荷与原子守恒'],
  H3_INORGANIC: ['元素价态', '物质类别', '反应条件', '无机转化网络', '物质制备与检验'],
  H3_THERMO_RATE: ['反应热', '热化学计算', '反应速率', '速率图像', '工业条件选择'],
  H3_EQUILIBRIUM: ['平衡移动', '平衡常数', '三段式计算', '平衡图像', '转化率与条件优化'],
  H3_AQ: ['弱电解质平衡', '水的电离与pH', '盐类水解', '离子浓度守恒', '沉淀溶解平衡'],
  H3_ELECTRO: ['原电池', '电解池', '电极方程式', '电子与离子迁移', '电化学定量'],
  H3_EXPERIMENT: ['实验目的与原理', '装置与操作', '现象与证据', '误差分析', '探究方案评价'],
  H3_PROCESS: ['原料预处理', '反应条件控制', '分离提纯', '循环利用', '产率与环保评价'],
  H3_STRUCTURE: ['核外电子排布', '元素周期性', '化学键与分子结构', '晶体结构', '结构与性质解释'],
  H3_ORGANIC: ['官能团与类别', '有机反应类型', '同分异构体', '合成路线', '有机实验与检验'],
}

export function reviewSummaries(skillIds, dayIndex) {
  const skills = skillIds.filter((skillId) => REVIEW_TOPICS[skillId])
  if (!skills.length) throw new Error(`No review topics for ${skillIds.join(',')}`)
  const count = Math.max(3, Math.min(5, skills.length))
  const summaries = []
  for (let offset = 0; summaries.length < count && offset < 20; offset += 1) {
    const skillId = skills[offset % skills.length]
    const topics = REVIEW_TOPICS[skillId]
    const topic = topics[(dayIndex + Math.floor(offset / skills.length) + offset) % topics.length]
    if (!summaries.includes(topic)) summaries.push(topic)
  }
  if (summaries.length < 3) throw new Error(`Insufficient review summaries for ${skillIds.join(',')}`)
  return summaries
}
