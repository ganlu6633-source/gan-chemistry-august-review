const step = (label, caption) => ({ label, ...(caption ? { caption } : {}) })
const group = (label, ...items) => ({ label, items })
const flow = (title, ...labels) => ({ kind: 'flow', title, steps: labels.map((label, index) => step(label, String(index + 1).padStart(2, '0'))) })
const cycle = (title, ...labels) => ({ kind: 'cycle', title, steps: labels.map((label, index) => step(label, String(index + 1).padStart(2, '0'))) })
const compare = (title, ...groups) => ({ kind: 'compare', title, groups })
const network = (title, center, ...groups) => ({ kind: 'network', title, center, groups })
const balance = (title, center, ...groups) => ({ kind: 'balance', title, center, groups })

export const classificationVisualSummary = {
  kind: 'tree',
  title: '物质分类总树',
  tree: {
    label: '物质',
    children: [
      {
        label: '混合物',
        children: [{ label: '分散系', children: [{ label: '溶液＜1 nm' }, { label: '胶体1～100 nm' }, { label: '浊液＞100 nm' }] }],
      },
      {
        label: '纯净物',
        children: [
          { label: '单质', children: [{ label: '金属单质' }, { label: '非金属单质' }] },
          {
            label: '化合物',
            children: [
              { label: '有机化合物' },
              { label: '无机化合物', children: [{ label: '氧化物' }, { label: '酸' }, { label: '碱' }, { label: '盐' }] },
            ],
          },
        ],
      },
    ],
  },
  axes: [
    group('化合物｜电离', '电解质', '非电解质'),
    group('酸｜三条轴', '一/二/多元', '强/弱', '含氧/无氧'),
    group('碱｜三条轴', '一/二/三元', '强/弱', '易溶/微溶/难溶'),
    group('氧化物｜性质', '酸性', '碱性', '两性', '不成盐'),
    group('盐｜组成', '正盐', '酸式盐', '碱式盐'),
  ],
}

export const knowledgeVisualSummaries = {
  H1_ELECTROLYTE_INTRO: {
    kind: 'tree', title: '电解质判断树', tree: { label: '研究对象', children: [{ label: '单质/混合物→退出' }, { label: '化合物', children: [{ label: '自身产生自由离子', children: [{ label: '是→电解质' }, { label: '否→非电解质' }] }] }] }, axes: [group('导电条件', '水溶液', '熔融状态')],
  },
  H1_PERIODIC: compare('周期表中的两条趋势线', group('同周期 →', '核吸引增强', '半径↓', '金属性↓', '非金属性↑'), group('同主族 ↓', '电子层增多', '半径↑', '金属性↑', '非金属性↓')),
  H1_REDOX: balance('氧化还原电子天平', 'e⁻总数相等', group('升价｜失电子', '被氧化', '还原剂', '氧化产物'), group('降价｜得电子', '被还原', '氧化剂', '还原产物')),
  H1_ELECTROLYTE: flow('离子反应完整路线', '限定化合物', '列真实粒子', '找反应推动力', '写→拆→删', '查事实/原子/电荷'),
  H1_MOLE_INTRO: network('物质的量把宏观与微观接起来', '物质的量 n', group('微观', '微粒数 N', 'N=nNₐ'), group('宏观', '质量 m', 'n=m/M'), group('对象', '分子/原子', '离子/电子')),
  H1_MOLE: network('所有已知量先汇入 n', '物质的量 n', group('质量', 'm/M'), group('微粒数', 'N/Nₐ'), group('气体体积', 'V/Vₘ'), group('溶液', 'cV'), group('反应', '方程式系数比')),
  H1_NACL: network('钠与氯的两条物质主线', '价态与电子', group('钠主线', 'Na失1e⁻', 'Na₂O/Na₂O₂', 'Na₂CO₃/NaHCO₃'), group('氯主线', 'Cl₂强氧化', '氯水多粒子', 'HClO漂白消毒')),
  H2_THERMO: balance('反应热的能量账本', 'ΔH=后−前', group('吸收', '反应物断键', '能量输入'), group('释放', '生成物成键', '能量输出')),
  H2_RATE: network('哪些因素改变反应速率', '反应速率', group('浓度/分压', '碰撞频率↑'), group('温度', '活化分子比例↑'), group('催化剂', '活化能Ea↓'), group('计量关系', '速率比=系数比')),
  H2_EQUIL: balance('比较正逆速率决定移动', '比较大小', group('v正＞v逆', '向右移动', '直到新平衡'), group('v正＜v逆', '向左移动', '直到新平衡')),
  H2_K: compare('Q与K一眼判方向', group('Q＜K', '向正方向'), group('Q＝K', '已经平衡'), group('Q＞K', '向逆方向')),
  H2_WEAK: cycle('弱电解质的动态电离', '弱电解质分子', '部分电离', '离子共存', '稀释/同离子扰动', '建立新平衡'),
  H2_PH_HYDRO: network('水溶液先列粒子再计算', '溶液粒子清单', group('酸碱', 'Kw与pH'), group('水解', '弱者的离子'), group('守恒', '电荷守恒', '物料/质子守恒'), group('滴定', '反应→过量→平衡')),
  H2_KSP: compare('Qsp与Ksp决定沉淀方向', group('Qsp＜Ksp', '继续溶解'), group('Qsp＝Ksp', '溶解平衡'), group('Qsp＞Ksp', '析出沉淀')),
  H2_ELECTRO: compare('原电池与电解池共用两极规律', group('阳极｜氧化', '原电池负极', '电解池接正极'), group('阴极｜还原', '原电池正极', '电解池接负极'), group('两条通道', '电子走导线', '离子走电解质')),
  H3_STOICH: flow('综合计量的最短路线', '识别已知量', '全部换算为n', '判断限制量', '按系数比转移', '优先找守恒', '单位/数量级校验'),
  H3_ION_REDOX: flow('离子与氧化还原综合路线', '翻译隐含条件', '筛查实际反应', '写→拆→删→查', '标价判升降', '配平电子', '查原子/电荷/介质'),
  H3_INORGANIC: network('无机推断的三个控制轴', '具体产物', group('价态', '决定氧化还原方向'), group('物质类别', '决定酸碱/离子反应'), group('反应条件', '决定最终产物'), group('检验闭环', '试剂→现象→结论')),
  H3_THERMO_RATE: network('工业反应的多目标权衡', '工业条件', group('热力学', 'ΔH与平衡'), group('动力学', 'Ea与速率'), group('工程', '能耗/成本', '安全/产率')),
  H3_EQUILIBRIUM: cycle('平衡受到扰动后的完整循环', '旧平衡', '外界扰动', '瞬时v正/v逆', 'Q与K判方向', '定向移动', '新平衡'),
  H3_AQ: network('水溶液综合题的中心地图', '列全粒子', group('平衡常数', 'Kw/Ka/Kb/Kh/Ksp'), group('方向', 'Q与K'), group('数量关系', '电荷/物料/质子守恒'), group('应用', '滴定四阶段', '沉淀Qsp')),
  H3_ELECTRO: cycle('充放电中的电子与离子闭环', '总反应', '放电方向', '阳极氧化', 'e⁻走外电路', '离子走膜/电解质', '阴极还原', '充电反向'),
  H3_EXPERIMENT: flow('实验答案必须形成证据链', '实验目的', '反应原理', '装置/试剂', '规范操作', '现象→结论', '误差与安全'),
  H3_PROCESS: flow('工艺流程图从原料走到产品', '原料', '浸取/转价', '调pH除杂', '过滤/洗涤', '浓缩/结晶', '产品/循环评价'),
  H3_STRUCTURE: {
    kind: 'tree', title: '结构决定性质的三层模型', tree: { label: '结构决定性质', children: [{ label: '原子层', children: [{ label: '电子排布/周期趋势' }] }, { label: '分子层', children: [{ label: '构型/极性/作用力' }] }, { label: '晶体层', children: [{ label: '晶体类型' }, { label: '晶胞计算' }] }] }, axes: [group('最终落点', '宏观性质')],
  },
  H3_ORGANIC: network('有机推断同时追踪两条线', '读结构', group('碳骨架', '碳数变化', '碳链/位置异构'), group('官能团', '性质与反应类型', '官能团转化'), group('综合输出', '同分异构体', '合成路线')),
}

const expectedIds = [
  'H1_ELECTROLYTE_INTRO', 'H1_PERIODIC', 'H1_REDOX', 'H1_ELECTROLYTE', 'H1_MOLE_INTRO', 'H1_MOLE', 'H1_NACL',
  'H2_THERMO', 'H2_RATE', 'H2_EQUIL', 'H2_K', 'H2_WEAK', 'H2_PH_HYDRO', 'H2_KSP', 'H2_ELECTRO',
  'H3_STOICH', 'H3_ION_REDOX', 'H3_INORGANIC', 'H3_THERMO_RATE', 'H3_EQUILIBRIUM', 'H3_AQ', 'H3_ELECTRO', 'H3_EXPERIMENT', 'H3_PROCESS', 'H3_STRUCTURE', 'H3_ORGANIC',
]

if (Object.keys(knowledgeVisualSummaries).length !== expectedIds.length || expectedIds.some((id) => !knowledgeVisualSummaries[id])) {
  throw new Error('30秒图解映射未完整覆盖26张生成知识卡。')
}
