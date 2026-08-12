import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { reviewSummaries } from './review-topic-map.mjs'

const d = (title, skills, minutes = 18, mode = 'REVIEW') => ({ title: title.replaceAll('小测', '周检'), skills, minutes, mode: mode === 'CLASS_QUIZ' ? 'REVIEW' : mode })
const cohortStarts = { high1_current: '2026-08-27' }
const defaultStart = '2026-08-13'
const cohorts = {
  junior_foundation: [
    d('化学变化与物理变化：抓住新物质', ['J_CHEM_LANG'],14), d('元素符号与粒子个数', ['J_CHEM_LANG'],14), d('质子、电子与离子', ['J09_ATOM'],16), d('实验安全与规范操作', ['J_EXPERIMENT'],14), d('化学式、化合价与物质组成', ['J_CHEM_LANG','J09_ATOM'],18), d('量筒、加热与气密性', ['J_EXPERIMENT'],16), d('第一周基础小测', ['J_CHEM_LANG','J09_ATOM'],18,'CLASS_QUIZ'),
    d('元素名称与符号双向回收', ['J_CHEM_LANG'],14), d('原子结构与元素身份', ['J09_ATOM'],16), d('原子和离子的转换', ['J09_ATOM'],16), d('实验目的与操作顺序', ['J_EXPERIMENT'],16), d('宏观—微观—符号三重表征', ['J_CHEM_LANG','J09_ATOM'],18), d('实验误差方向初步', ['J_EXPERIMENT'],16), d('第二周迁移小测', ['J_CHEM_LANG','J_EXPERIMENT'],18,'CLASS_QUIZ'),
    d('易混化学用语集中辨析', ['J_CHEM_LANG'],15), d('粒子结构综合判断', ['J09_ATOM'],18), d('气体制取基本逻辑', ['J_EXPERIMENT'],18), d('变化、性质和用途关系', ['J_CHEM_LANG'],16), d('元素与实验交叉训练', ['J09_ATOM','J_EXPERIMENT'],20), d('错题同类新题回收', ['J_CHEM_LANG','J09_ATOM'],18), d('第三周稳定性小测', ['J09_ATOM','J_EXPERIMENT'],18,'CLASS_QUIZ'),
    d('化学用语累计复习', ['J_CHEM_LANG'],15), d('原子结构累计复习', ['J09_ATOM'],16), d('实验操作累计复习', ['J_EXPERIMENT'],16), d('三模块连接训练', ['J_CHEM_LANG','J09_ATOM'],20), d('薄弱点自适应回收', ['J_CHEM_LANG','J_EXPERIMENT'],18), d('考前清单式轻复习', ['J09_ATOM','J_EXPERIMENT'],14), d('四周综合验收', ['J_CHEM_LANG','J09_ATOM','J_EXPERIMENT'],22,'CLASS_QUIZ'),
  ],
  high1_current: [
    d('物质的量：对象、单位与1 mol', ['H1_MOLE_INTRO'],16), d('阿伏加德罗常数与微粒数', ['H1_MOLE_INTRO'],16), d('摩尔质量：单位与数值辨析', ['H1_MOLE_INTRO'],16), d('质量—物质的量一步换算', ['H1_MOLE_INTRO'],18), d('物质的量三概念连接', ['H1_MOLE_INTRO'],18), d('元素周期律间隔回收', ['H1_PERIODIC'],18), d('第一周已学内容小测', ['H1_MOLE_INTRO','H1_PERIODIC','H1_CLASSIFY'],22,'CLASS_QUIZ'),
    d('分类标准与分类树', ['H1_CLASSIFY'],16), d('纯净物、混合物与分散系', ['H1_CLASSIFY'],16), d('酸性与碱性氧化物边界', ['H1_CLASSIFY'],18), d('电解质与非电解质概念边界', ['H1_ELECTROLYTE_INTRO'],16), d('同周期与同主族递变', ['H1_PERIODIC'],18), d('结构—位置—性质因果链', ['H1_PERIODIC'],18), d('第二周第一讲内容小测', ['H1_CLASSIFY','H1_ELECTROLYTE_INTRO','H1_PERIODIC'],22,'CLASS_QUIZ'),
    d('微粒数—物质的量双向换算', ['H1_MOLE_INTRO'],18), d('质量—摩尔质量—物质的量', ['H1_MOLE_INTRO'],18), d('先判断对象再使用Nₐ', ['H1_MOLE_INTRO'],18), d('摩尔质量易错单位', ['H1_MOLE_INTRO'],16), d('周期律与分类交叉辨析', ['H1_PERIODIC','H1_CLASSIFY'],20), d('四条已学主线错因回收', ['H1_MOLE_INTRO','H1_PERIODIC','H1_CLASSIFY','H1_ELECTROLYTE_INTRO'],22), d('第三周稳定性小测', ['H1_MOLE_INTRO','H1_PERIODIC'],22,'CLASS_QUIZ'),
    d('物质分类与电解质累计', ['H1_CLASSIFY','H1_ELECTROLYTE_INTRO'],18), d('元素周期律累计回看', ['H1_PERIODIC'],18), d('物质的量基础累计回看', ['H1_MOLE_INTRO'],18), d('分类—周期律—计量连接', ['H1_CLASSIFY','H1_PERIODIC','H1_MOLE_INTRO'],22), d('薄弱点自适应回收', ['H1_MOLE_INTRO','H1_ELECTROLYTE_INTRO'],18), d('考前清单式轻复习', ['H1_PERIODIC','H1_MOLE_INTRO'],16), d('四周已学内容综合验收', ['H1_CLASSIFY','H1_ELECTROLYTE_INTRO','H1_PERIODIC','H1_MOLE_INTRO'],24,'CLASS_QUIZ'),
  ],
  high1_completed: [
    d('已学四模块快速诊断：分类', ['H1_CLASSIFY'],16), d('已学四模块快速诊断：周期律', ['H1_PERIODIC'],18), d('已学四模块快速诊断：氧化还原', ['H1_REDOX'],18), d('已学四模块快速诊断：物质的量', ['H1_MOLE_INTRO'],20), d('分类与周期律连接', ['H1_CLASSIFY','H1_PERIODIC'],20), d('氧化还原与计量连接', ['H1_REDOX','H1_MOLE_INTRO'],22), d('第一周四模块诊断小测', ['H1_CLASSIFY','H1_PERIODIC','H1_REDOX','H1_MOLE_INTRO'],24,'CLASS_QUIZ'),
    d('周期律陌生元素迁移', ['H1_PERIODIC'],20), d('电子守恒与陌生方程式', ['H1_REDOX'],22), d('微粒数与物质的量换算', ['H1_MOLE_INTRO'],20), d('分类边界与胶体', ['H1_CLASSIFY'],18), d('氧化数判断与变价识别', ['H1_REDOX'],18), d('质量—物质的量一步换算', ['H1_MOLE_INTRO'],20), d('第二周迁移小测', ['H1_REDOX','H1_MOLE_INTRO','H1_PERIODIC'],24,'CLASS_QUIZ'),
    d('摩尔质量单位与对象辨析', ['H1_MOLE_INTRO'],18), d('周期律与氧化还原综合', ['H1_PERIODIC','H1_REDOX'],22), d('分类标准切换与边界', ['H1_CLASSIFY'],18), d('电子守恒基础迁移', ['H1_REDOX'],20), d('四模块高频错因回收', ['H1_CLASSIFY','H1_REDOX'],20), d('同能力不同母题验证', ['H1_PERIODIC','H1_MOLE_INTRO'],22), d('第三周稳定性小测', ['H1_CLASSIFY','H1_MOLE_INTRO'],24,'CLASS_QUIZ'),
    d('物质分类累计回看', ['H1_CLASSIFY'],18), d('元素周期律累计回看', ['H1_PERIODIC'],18), d('氧化还原累计回看', ['H1_REDOX'],20), d('物质的量基础累计回看', ['H1_MOLE_INTRO'],18), d('四模块连接与薄弱点回收', ['H1_CLASSIFY','H1_PERIODIC','H1_REDOX','H1_MOLE_INTRO'],24), d('考前清单式轻复习', ['H1_PERIODIC','H1_REDOX'],16), d('四周已学四模块综合验收', ['H1_CLASSIFY','H1_PERIODIC','H1_REDOX','H1_MOLE_INTRO'],26,'CLASS_QUIZ'),
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
for (const [cohort, days] of Object.entries(cohorts)) days.forEach((day, index) => {
  const summaries = reviewSummaries(day.skills, index + 12)
  rows.push(`(${quote(cohort)},date ${quote(cohortStarts[cohort] ?? defaultStart)},${index},${quote(day.mode)},${quote(day.title)},array[${day.skills.map(quote).join(',')}]::text[],array[${summaries.map(quote).join(',')}]::text[],${day.minutes})`)
})
const sql = `-- Generated by scripts/build-four-week-plans.mjs.\nbegin;\nalter table public.chem_learning_plans add column if not exists knowledge_summaries text[] not null default array[]::text[];\ncreate temporary table four_week_plan_template(cohort text,start_date date,day_index integer,mode text,title text,skill_ids text[],knowledge_summaries text[],estimated_minutes smallint) on commit drop;\ninsert into four_week_plan_template values\n${rows.join(',\n')};\ndelete from public.chem_learning_plans p using public.chem_students_v2 s,(select cohort,min(start_date) start_date from four_week_plan_template group by cohort) d where p.student_id=s.id and d.cohort=s.metadata->>'curriculumCohort' and p.plan_date between d.start_date and d.start_date+27;\ninsert into public.chem_learning_plans(student_id,plan_date,mode,title,skill_ids,knowledge_summaries,estimated_minutes,source,is_scheduled)\nselect s.id,t.start_date+t.day_index,t.mode,t.title,t.skill_ids,t.knowledge_summaries,t.estimated_minutes,'mixed',true\nfrom public.chem_students_v2 s join four_week_plan_template t on t.cohort=s.metadata->>'curriculumCohort';\ncommit;\n`
writeFileSync(resolve('supabase/migrations/20260812044632_generate_four_week_student_plans.sql'), sql, 'utf8')
console.log(JSON.stringify({ cohorts: Object.keys(cohorts).length, templateDays: rows.length, defaultStart, high1CurrentStart: cohortStarts.high1_current }))
