import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'

const d = (title, skills, minutes = 18, mode = 'REVIEW') => ({ title, skills, minutes, mode })
const cohorts = {
  junior_foundation: [
    d('化学变化与物理变化：抓住新物质', ['J_CHEM_LANG'],14), d('元素符号与粒子个数', ['J_CHEM_LANG'],14), d('质子、电子与离子', ['J09_ATOM'],16), d('实验安全与规范操作', ['J_EXPERIMENT'],14), d('化学式、化合价与物质组成', ['J_CHEM_LANG','J09_ATOM'],18), d('量筒、加热与气密性', ['J_EXPERIMENT'],16), d('第一周基础小测', ['J_CHEM_LANG','J09_ATOM'],18,'CLASS_QUIZ'),
    d('元素名称与符号双向回收', ['J_CHEM_LANG'],14), d('原子结构与元素身份', ['J09_ATOM'],16), d('原子和离子的转换', ['J09_ATOM'],16), d('实验目的与操作顺序', ['J_EXPERIMENT'],16), d('宏观—微观—符号三重表征', ['J_CHEM_LANG','J09_ATOM'],18), d('实验误差方向初步', ['J_EXPERIMENT'],16), d('第二周迁移小测', ['J_CHEM_LANG','J_EXPERIMENT'],18,'CLASS_QUIZ'),
    d('易混化学用语集中辨析', ['J_CHEM_LANG'],15), d('粒子结构综合判断', ['J09_ATOM'],18), d('气体制取基本逻辑', ['J_EXPERIMENT'],18), d('变化、性质和用途关系', ['J_CHEM_LANG'],16), d('元素与实验交叉训练', ['J09_ATOM','J_EXPERIMENT'],20), d('错题同类新题回收', ['J_CHEM_LANG','J09_ATOM'],18), d('第三周稳定性小测', ['J09_ATOM','J_EXPERIMENT'],18,'CLASS_QUIZ'),
    d('化学用语累计复习', ['J_CHEM_LANG'],15), d('原子结构累计复习', ['J09_ATOM'],16), d('实验操作累计复习', ['J_EXPERIMENT'],16), d('三模块连接训练', ['J_CHEM_LANG','J09_ATOM'],20), d('薄弱点自适应回收', ['J_CHEM_LANG','J_EXPERIMENT'],18), d('考前清单式轻复习', ['J09_ATOM','J_EXPERIMENT'],14), d('四周综合验收', ['J_CHEM_LANG','J09_ATOM','J_EXPERIMENT'],22,'CLASS_QUIZ'),
  ],
  high1_current: [
    d('物质分类：先定标准再判断', ['H1_CLASSIFY'],16), d('纯净物、混合物与分散系', ['H1_CLASSIFY'],16), d('氧化物与电解质分类边界', ['H1_CLASSIFY','H1_ELECTROLYTE'],18), d('原子结构连接周期表位置', ['H1_PERIODIC'],18), d('同周期性质递变', ['H1_PERIODIC'],18), d('同主族性质递变', ['H1_PERIODIC'],18), d('第一周分类与周期律小测', ['H1_CLASSIFY','H1_PERIODIC'],20,'CLASS_QUIZ'),
    d('结构—位置—性质因果链', ['H1_PERIODIC'],18), d('化合价与氧化还原判断', ['H1_REDOX'],18), d('氧化剂、还原剂四身份', ['H1_REDOX'],18), d('电子守恒与基础配平', ['H1_REDOX'],20), d('周期律解释元素性质', ['H1_PERIODIC'],18), d('分类与氧化还原交叉', ['H1_CLASSIFY','H1_REDOX'],20), d('第二周规律迁移小测', ['H1_PERIODIC','H1_REDOX'],20,'CLASS_QUIZ'),
    d('电解质与非电解质', ['H1_ELECTROLYTE'],16), d('强电解质拆分规则', ['H1_ELECTROLYTE'],18), d('离子方程式三重守恒', ['H1_ELECTROLYTE'],20), d('物质的量作为换算枢纽', ['H1_MOLE'],18), d('质量—物质的量—粒子数', ['H1_MOLE'],20), d('气体体积与溶液浓度', ['H1_MOLE'],20), d('第三周基础计算小测', ['H1_ELECTROLYTE','H1_MOLE'],22,'CLASS_QUIZ'),
    d('分类、周期律综合回看', ['H1_CLASSIFY','H1_PERIODIC'],18), d('氧化还原与离子反应连接', ['H1_REDOX','H1_ELECTROLYTE'],22), d('物质的量多步换算', ['H1_MOLE'],22), d('钠的价态与反应网络预习', ['H1_NACL'],16), d('氯及含氯物质预习', ['H1_NACL'],16), d('四模块错因回收', ['H1_CLASSIFY','H1_REDOX'],18), d('四周综合验收', ['H1_PERIODIC','H1_ELECTROLYTE','H1_MOLE'],24,'CLASS_QUIZ'),
  ],
  high1_completed: [
    d('已学四模块快速诊断：分类', ['H1_CLASSIFY'],16), d('已学四模块快速诊断：周期律', ['H1_PERIODIC'],18), d('已学四模块快速诊断：氧化还原', ['H1_REDOX'],18), d('已学四模块快速诊断：物质的量', ['H1_MOLE'],20), d('分类与周期律连接', ['H1_CLASSIFY','H1_PERIODIC'],20), d('氧化还原与计量连接', ['H1_REDOX','H1_MOLE'],22), d('第一周四模块诊断小测', ['H1_CLASSIFY','H1_PERIODIC','H1_REDOX','H1_MOLE'],24,'CLASS_QUIZ'),
    d('周期律陌生元素迁移', ['H1_PERIODIC'],20), d('电子守恒与陌生方程式', ['H1_REDOX'],22), d('多步物质的量换算', ['H1_MOLE'],22), d('分类边界与胶体', ['H1_CLASSIFY'],18), d('电解质与离子反应补全', ['H1_ELECTROLYTE'],18), d('离子方程式少量过量基础', ['H1_ELECTROLYTE'],20), d('第二周迁移小测', ['H1_REDOX','H1_ELECTROLYTE','H1_MOLE'],24,'CLASS_QUIZ'),
    d('离子共存与反应事实', ['H1_ELECTROLYTE'],20), d('周期律与氧化还原综合', ['H1_PERIODIC','H1_REDOX'],22), d('气体摩尔体积条件辨析', ['H1_MOLE'],20), d('浓度与反应计量', ['H1_MOLE','H1_ELECTROLYTE'],22), d('四模块高频错因回收', ['H1_CLASSIFY','H1_REDOX'],20), d('同能力不同母题验证', ['H1_PERIODIC','H1_MOLE'],22), d('第三周稳定性小测', ['H1_ELECTROLYTE','H1_MOLE'],24,'CLASS_QUIZ'),
    d('钠及其化合物转化网', ['H1_NACL'],18), d('氯及其化合物转化网', ['H1_NACL'],18), d('元素化合物与氧化还原', ['H1_NACL','H1_REDOX'],22), d('累计分类与周期律', ['H1_CLASSIFY','H1_PERIODIC'],20), d('累计离子与计量', ['H1_ELECTROLYTE','H1_MOLE'],22), d('考前清单式轻复习', ['H1_PERIODIC','H1_REDOX'],16), d('四周综合验收', ['H1_CLASSIFY','H1_PERIODIC','H1_REDOX','H1_ELECTROLYTE','H1_MOLE'],26,'CLASS_QUIZ'),
  ],
  high2_xb1_complete: [
    d('选择性必修一诊断：反应热', ['H2_THERMO'],18), d('速率表示与影响因素', ['H2_RATE'],18), d('化学平衡建立与移动', ['H2_EQUIL'],20), d('平衡常数与三段式', ['H2_K'],22), d('热化学与速率连接', ['H2_THERMO','H2_RATE'],22), d('速率—平衡—K关系辨析', ['H2_RATE','H2_EQUIL','H2_K'],24), d('第一周反应原理小测', ['H2_THERMO','H2_RATE','H2_EQUIL','H2_K'],26,'CLASS_QUIZ'),
    d('弱电解质电离平衡', ['H2_WEAK'],20), d('水的电离与pH', ['H2_PH_HYDRO'],20), d('盐类水解与守恒', ['H2_PH_HYDRO'],22), d('难溶电解质与Ksp', ['H2_KSP'],20), d('弱酸弱碱与滴定', ['H2_WEAK','H2_PH_HYDRO'],22), d('水溶液三大守恒', ['H2_PH_HYDRO','H2_KSP'],24), d('第二周水溶液小测', ['H2_WEAK','H2_PH_HYDRO','H2_KSP'],26,'CLASS_QUIZ'),
    d('原电池方向与电极反应', ['H2_ELECTRO'],20), d('电解池与电解产物', ['H2_ELECTRO'],22), d('金属腐蚀与防护', ['H2_ELECTRO'],18), d('电化学电子守恒计算', ['H2_ELECTRO'],22), d('平衡图像与工业条件', ['H2_EQUIL','H2_K'],22), d('反应原理综合连接', ['H2_THERMO','H2_ELECTRO'],24), d('第三周电化学小测', ['H2_ELECTRO','H2_EQUIL'],26,'CLASS_QUIZ'),
    d('反应热与平衡累计回看', ['H2_THERMO','H2_EQUIL'],20), d('速率与K累计回看', ['H2_RATE','H2_K'],20), d('弱电解质与水解累计', ['H2_WEAK','H2_PH_HYDRO'],22), d('Ksp与电化学累计', ['H2_KSP','H2_ELECTRO'],22), d('选择性必修一薄弱点回收', ['H2_EQUIL','H2_PH_HYDRO'],22), d('考前清单式轻复习', ['H2_RATE','H2_ELECTRO'],16), d('四周选择性必修一验收', ['H2_THERMO','H2_EQUIL','H2_PH_HYDRO','H2_ELECTRO'],28,'CLASS_QUIZ'),
  ],
  high3_quality_0827: [
    d('8·27质检倒排：计量与NA', ['H3_STOICH'],20), d('倒排：离子反应与氧化还原', ['H3_ION_REDOX'],22), d('倒排：元素化合物转化', ['H3_INORGANIC'],22), d('倒排：热化学与速率', ['H3_THERMO_RATE'],22), d('倒排：化学平衡', ['H3_EQUILIBRIUM'],24), d('倒排：水溶液离子平衡', ['H3_AQ'],24), d('质检第一轮限时小测', ['H3_STOICH','H3_ION_REDOX','H3_EQUILIBRIUM'],28,'CLASS_QUIZ'),
    d('倒排：电化学', ['H3_ELECTRO'],22), d('倒排：实验综合', ['H3_EXPERIMENT'],24), d('倒排：无机工艺流程', ['H3_PROCESS'],24), d('倒排：结构与性质', ['H3_STRUCTURE'],20), d('倒排：有机基础', ['H3_ORGANIC'],20), d('质检高频错因清单', ['H3_ION_REDOX','H3_AQ','H3_EXPERIMENT'],24), d('质检前最后综合检验', ['H3_EQUILIBRIUM','H3_PROCESS','H3_ELECTRO'],28,'CLASS_QUIZ'),
    d('8·27质检当天：核心清单轻回看', ['H3_STOICH','H3_ION_REDOX'],10), d('质检后：计量与离子订正框架', ['H3_STOICH','H3_ION_REDOX'],20), d('质检后：元素与流程订正框架', ['H3_INORGANIC','H3_PROCESS'],22), d('质检后：反应原理订正框架', ['H3_THERMO_RATE','H3_EQUILIBRIUM'],22), d('质检后：水溶液与电化学订正框架', ['H3_AQ','H3_ELECTRO'],24), d('质检后：实验表达规范', ['H3_EXPERIMENT'],22), d('第三周错题迁移小测', ['H3_PROCESS','H3_AQ','H3_EXPERIMENT'],28,'CLASS_QUIZ'),
    d('新一轮：计量—守恒综合', ['H3_STOICH','H3_ION_REDOX'],22), d('新一轮：元素—流程综合', ['H3_INORGANIC','H3_PROCESS'],24), d('新一轮：速率—平衡综合', ['H3_THERMO_RATE','H3_EQUILIBRIUM'],24), d('新一轮：水溶液—电化学综合', ['H3_AQ','H3_ELECTRO'],24), d('结构与有机基础回收', ['H3_STRUCTURE','H3_ORGANIC'],20), d('实验与计算表达回收', ['H3_EXPERIMENT','H3_STOICH'],22), d('四周质检周期综合验收', ['H3_ION_REDOX','H3_EQUILIBRIUM','H3_AQ','H3_EXPERIMENT'],30,'CLASS_QUIZ'),
  ],
}

for (const [name, days] of Object.entries(cohorts)) if (days.length !== 28) throw new Error(`${name} has ${days.length} days`)
const quote = (value) => `'${String(value).replaceAll("'", "''")}'`
const rows = []
for (const [cohort, days] of Object.entries(cohorts)) days.forEach((day, index) => rows.push(`(${quote(cohort)},${index},${quote(day.mode)},${quote(day.title)},array[${day.skills.map(quote).join(',')}]::text[],${day.minutes})`))
const sql = `-- Generated by scripts/build-four-week-plans.mjs.\nbegin;\ncreate temporary table four_week_plan_template(cohort text,day_index integer,mode text,title text,skill_ids text[],estimated_minutes smallint) on commit drop;\ninsert into four_week_plan_template values\n${rows.join(',\n')};\ndelete from public.chem_learning_plans p using public.chem_students_v2 s where p.student_id=s.id and p.plan_date between date '2026-08-13' and date '2026-09-09' and s.metadata->>'curriculumCohort' in (${Object.keys(cohorts).map(quote).join(',')});\ninsert into public.chem_learning_plans(student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,is_scheduled)\nselect s.id,date '2026-08-13'+t.day_index,t.mode,t.title,t.skill_ids,t.estimated_minutes,'mixed',true\nfrom public.chem_students_v2 s join four_week_plan_template t on t.cohort=s.metadata->>'curriculumCohort';\ncommit;\n`
writeFileSync(resolve('supabase/migrations/20260812044632_generate_four_week_student_plans.sql'), sql, 'utf8')
console.log(JSON.stringify({ cohorts: Object.keys(cohorts).length, templateDays: rows.length, start: '2026-08-13', end: '2026-09-09' }))
