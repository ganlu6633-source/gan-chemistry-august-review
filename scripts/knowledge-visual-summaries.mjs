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
  H1_PERIODIC: compare(
    '元素周期律完整趋势图',
    group('同周期 →', '层数不变·核电荷↑', '半径总体↓', '金属性↓｜非金属性↑'),
    group('最高价氧化物', 'Na₂O→MgO→Al₂O₃→SiO₂→P₄O₁₀→SO₃→Cl₂O₇'),
    group('对应水化物', 'NaOH→Mg(OH)₂→Al(OH)₃→H₂SiO₃→H₃PO₄→H₂SO₄→HClO₄', '碱性减弱→两性→酸性增强', '“对应”不等于一定能由氧化物直接加水得到'),
    group('气态氢化物', '同周期：SiH₄＜PH₃＜H₂S＜HCl', '同主族：HF＞HCl＞HBr＞HI', '热稳定性≠水溶液酸性≠还原性'),
    group('同主族 ↓', '电子层↑·屏蔽↑', '半径↑', '金属性↑｜非金属性↓', '同族非金属简单氢化物：热稳定性↓、还原性通常↑'),
    group('价态与通式', '最高正价一般+1～+7（O、F不套）', '最低负价通常−4/−3/−2/−1', 'RH₄/RH₃/H₂R/HR', '最高正价+|最低负价|=8（限定相应主族非金属）'),
    group('证据与半径边界', '反应难易/置换/含氧体系/氢化物', '同电子离子：核电荷↑半径↓', '相同条件并排除氧化膜等干扰'),
  ),
  H1_REDOX: balance(
    '氧化还原电子天平',
    '失电子总数＝得电子总数',
    group('升价链', '化合价升高', '失电子', '被氧化', '发生氧化反应', '反应物是还原剂', '生成氧化产物'),
    group('降价链', '化合价降低', '得电子', '被还原', '发生还原反应', '反应物是氧化剂', '生成还原产物'),
  ),
  H1_ELECTROLYTE: flow('离子反应完整路线', '限定化合物', '列真实粒子', '找反应推动力', '写→拆→删', '查事实/原子/电荷'),
  H1_MOLE_INTRO: network('物质的量把宏观与微观接起来', '物质的量 n', group('微观', '微粒数 N', 'N=nN_A'), group('宏观', '质量 m', 'n=m/M'), group('对象', '分子/原子', '离子/电子', '质子/中子', '离子晶体的化学式单位')),
  H1_MOLE: network('所有已知量先汇入 n', '物质的量 n', group('质量', 'm/M'), group('微粒数', 'N/N_A'), group('气体体积', 'V/Vₘ'), group('溶液', 'cV'), group('反应', '方程式系数比')),
  H1_NACL: network('钠与氯的完整物质网络', '价态与电子', group('钠主线', 'Na失1e⁻', 'Na₂O/Na₂O₂', 'Na₂CO₃/NaHCO₃', '焰色：Na黄/K紫'), group('氯气主线', 'Cl₂强氧化', '与金属/H₂', '氯水多粒子'), group('含氯消毒剂', '冷稀碱→ClO⁻', '热浓碱→ClO₃⁻', '漂白粉/84→HClO')),
  H2_THERMO: balance('反应热的能量账本', 'ΔH=后−前', group('吸收', '反应物断键', '能量输入'), group('释放', '生成物成键', '能量输出')),
  H2_RATE: network('哪些因素改变反应速率', '反应速率', group('浓度/分压', '碰撞频率↑'), group('温度', '活化分子比例↑'), group('催化剂', '活化能Ea↓'), group('计量关系', '速率比=系数比')),
  H2_EQUIL: balance('反应方向与平衡的两层判断', '方向≠快慢', group('能否自发｜定性', '焓变因素', '熵变因素', '温度改变倾向'), group('v正＞v逆', '向右移动', '直到新平衡'), group('v正＜v逆', '向左移动', '直到新平衡')),
  H2_K: compare('Q与K一眼判方向', group('Q＜K', '向正方向'), group('Q＝K', '已经平衡'), group('Q＞K', '向逆方向')),
  H2_WEAK: cycle('弱电解质的动态电离', '弱电解质分子', '部分电离', '离子共存', '稀释/同离子扰动', '建立新平衡'),
  H2_PH_HYDRO: network('水溶液先列粒子再计算', '溶液粒子清单', group('酸碱', 'Kw与pH'), group('水解', '弱者的离子'), group('守恒', '电荷守恒', '物料/质子守恒'), group('滴定', '反应→过量→平衡')),
  H2_KSP: compare('Qsp与Ksp决定沉淀方向', group('Qsp＜Ksp', '继续溶解'), group('Qsp＝Ksp', '溶解平衡'), group('Qsp＞Ksp', '析出沉淀')),
  H2_ELECTRO: compare('电化学四条主线', group('阳极｜氧化', '原电池负极', '电解池接正极'), group('阴极｜还原', '原电池正极', '电解池接负极'), group('水溶液电解', '判放电粒子', '合并总反应', '看pH/浓度', '加合适物质复原'), group('金属与腐蚀', '镀件作阴极', '粗金属作阳极', '酸性析H₂', '中性吸O₂')),
  H3_STOICH: flow('综合计量的最短路线', '识别已知量', '全部换算为n', '判断限制量', '按系数比转移', '优先找守恒', '单位/数量级校验'),
  H3_ION_REDOX: flow('离子与氧化还原综合路线', '翻译隐含条件', '筛查实际反应', '写→拆→删→查', '标价判升降', '配平电子', '查原子/电荷/介质'),
  H3_INORGANIC: network('常见元素价态—类别网络', '条件决定产物', group('Al', 'Al³⁺', 'Al(OH)₃', '含铝酸根'), group('Fe', 'Fe⁰/Fe²⁺/Fe³⁺', '沉淀颜色', 'KSCN检验'), group('S', 'SO₂多重性质', '浓H₂SO₄', 'SO₄²⁻检验'), group('N', 'NH₃/NH₄⁺', 'NO/NO₂', 'HNO₃'), group('C/Si', 'CO₂阶段反应', 'SiO₂边界', '资源冶炼')),
  H3_THERMO_RATE: network('方向、速率与工业条件', '多目标权衡', group('反应方向｜定性', '焓变因素', '熵变因素', '温度改变倾向'), group('动力学', 'Ea与速率', '自发≠快速'), group('平衡', 'Q/K与组成', '催化剂不改K'), group('工程', '能耗/成本', '安全/产率')),
  H3_EQUILIBRIUM: cycle('平衡受到扰动后的完整循环', '旧平衡', '外界扰动', '瞬时v正/v逆', 'Q与K判方向', '定向移动', '新平衡'),
  H3_AQ: network('水溶液综合题的中心地图', '列全粒子', group('平衡常数', 'Kw/Ka/Kb/Kh/Ksp'), group('方向', 'Q与K'), group('数量关系', '电荷/物料/质子守恒'), group('应用', '滴定四阶段', '沉淀Qsp')),
  H3_ELECTRO: network('电化学综合四线图', '电子守恒', group('电极', '阳极氧化', '阴极还原'), group('通道', 'e⁻走外电路', '离子走膜/溶液'), group('水溶液电解', '放电竞争', 'pH/浓度', '溶液复原'), group('腐蚀', '析氢路径', '吸氧路径', '防护')),
  H3_EXPERIMENT: network('实验操作先按目的选', '实验目的', group('固液分离', '过滤/洗涤', '蒸发/结晶'), group('互溶液体', '蒸馏/分馏', '温度计位置', '冷凝水下进上出'), group('不互溶液体', '萃取/分液', '振荡放气', '下层先放'), group('证据链', '装置/操作', '现象→结论', '误差与安全')),
  H3_PROCESS: flow('工艺流程图从原料走到产品', '原料', '浸取/转价', '调pH除杂', '过滤/洗涤', '浓缩/结晶', '产品/循环评价'),
  H3_STRUCTURE: {
    kind: 'tree', title: '结构决定性质与证据的完整树', tree: { label: '结构决定性质', children: [{ label: '原子层', children: [{ label: '电子云/轨道' }, { label: '基态/激发态/光谱' }, { label: '电离能/电负性' }] }, { label: '分子层', children: [{ label: 'Lewis/VSEPR/杂化' }, { label: '极性/氢键' }, { label: '配合物' }] }, { label: '晶体层', children: [{ label: '晶体类型/非晶体' }, { label: '晶胞计算' }, { label: 'X射线衍射证据' }] }] }, axes: [group('最终落点', '宏观性质', '结构测定证据')],
  },
  H3_ORGANIC: network('有机化学完整证据网络', '结构与转化', group('结构证据', '质谱看相对分子质量', '红外看官能团', '¹H NMR看等效氢'), group('碳骨架', '苯与芳香烃', '顺反/手性识别', '异构枚举'), group('官能团', '酚/醛/酯', '性质与反应类型', '官能团转化'), group('大分子', '糖/油脂/蛋白质', '核酸', '加聚/缩聚'), group('综合输出', '合成路线', '实验与检验')),
}

const expectedIds = [
  'H1_ELECTROLYTE_INTRO', 'H1_PERIODIC', 'H1_REDOX', 'H1_ELECTROLYTE', 'H1_MOLE_INTRO', 'H1_MOLE', 'H1_NACL',
  'H2_THERMO', 'H2_RATE', 'H2_EQUIL', 'H2_K', 'H2_WEAK', 'H2_PH_HYDRO', 'H2_KSP', 'H2_ELECTRO',
  'H3_STOICH', 'H3_ION_REDOX', 'H3_INORGANIC', 'H3_THERMO_RATE', 'H3_EQUILIBRIUM', 'H3_AQ', 'H3_ELECTRO', 'H3_EXPERIMENT', 'H3_PROCESS', 'H3_STRUCTURE', 'H3_ORGANIC',
]

if (Object.keys(knowledgeVisualSummaries).length !== expectedIds.length || expectedIds.some((id) => !knowledgeVisualSummaries[id])) {
  throw new Error('30秒图解映射未完整覆盖26张生成知识卡。')
}
