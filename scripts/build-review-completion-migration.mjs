import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { REVIEW_TOPICS, reviewSummaries } from './review-topic-map.mjs'

const d = (title, skills, minutes = 18) => ({ title, skills, minutes, mode: 'REVIEW' })
const history = {
  junior_foundation: [
    d('化学变化与物理变化', ['J_CHEM_LANG'],14), d('元素符号与粒子个数', ['J_CHEM_LANG'],14), d('质子数与元素身份', ['J09_ATOM'],15), d('原子和离子的转换', ['J09_ATOM'],15), d('实验安全与仪器选择', ['J_EXPERIMENT'],14), d('化学式与物质组成', ['J_CHEM_LANG','J09_ATOM'],17), d('读数与误差方向', ['J_EXPERIMENT'],15), d('宏观—微观—符号连接', ['J_CHEM_LANG','J09_ATOM'],17), d('气密性与操作顺序', ['J_EXPERIMENT'],16), d('初中基础阶段回收', ['J_CHEM_LANG','J09_ATOM','J_EXPERIMENT'],20), d('元素与原子结构回想', ['J09_ATOM'],15), d('初中化学基础当天回收', ['J_CHEM_LANG','J09_ATOM'],18),
  ],
  high1_current: [
    d('元素周期律：结构与位置', ['H1_PERIODIC'],16), d('元素周期律：同周期递变', ['H1_PERIODIC'],16), d('物质分类：分类标准', ['H1_CLASSIFY'],16), d('物质分类：纯净物与混合物', ['H1_CLASSIFY'],16), d('元素周期律：同主族递变', ['H1_PERIODIC'],17), d('物质分类：酸性与碱性氧化物', ['H1_CLASSIFY'],17), d('周期律与分类连接', ['H1_PERIODIC','H1_CLASSIFY'],19), d('电解质概念边界', ['H1_ELECTROLYTE_INTRO'],16), d('结构—位置—性质因果链', ['H1_PERIODIC'],18), d('第一讲阶段回收', ['H1_PERIODIC','H1_CLASSIFY','H1_ELECTROLYTE_INTRO'],21), d('元素周期律规律回想', ['H1_PERIODIC'],16), d('物质的量、阿伏加德罗常数与摩尔质量当天回收', ['H1_MOLE_INTRO'],18),
  ],
  high1_completed: [
    d('物质分类基础回想', ['H1_CLASSIFY'],16), d('元素周期律结构链', ['H1_PERIODIC'],17), d('氧化还原价态判断', ['H1_REDOX'],18), d('物质的量与摩尔', ['H1_MOLE_INTRO'],17), d('分类与周期律连接', ['H1_CLASSIFY','H1_PERIODIC'],19), d('氧化剂与还原剂', ['H1_REDOX'],18), d('阿伏加德罗常数与对象', ['H1_MOLE_INTRO'],18), d('电子守恒基础', ['H1_REDOX'],19), d('四模块交叉辨析', ['H1_CLASSIFY','H1_PERIODIC','H1_REDOX','H1_MOLE_INTRO'],22), d('第一阶段综合回收', ['H1_PERIODIC','H1_REDOX','H1_MOLE_INTRO'],22), d('元素周期律规律回想', ['H1_PERIODIC'],17), d('氧化还原逻辑回收', ['H1_REDOX'],18),
  ],
  high2_xb1_complete: [
    d('反应热与焓变', ['H2_THERMO'],18), d('反应速率表示', ['H2_RATE'],18), d('化学平衡状态', ['H2_EQUIL'],19), d('平衡常数表达式', ['H2_K'],20), d('弱电解质电离', ['H2_WEAK'],19), d('水的电离与pH', ['H2_PH_HYDRO'],20), d('盐类水解与守恒', ['H2_PH_HYDRO'],21), d('沉淀溶解平衡', ['H2_KSP'],20), d('原电池与电解池', ['H2_ELECTRO'],21), d('选择性必修一阶段回收', ['H2_THERMO','H2_EQUIL','H2_PH_HYDRO','H2_ELECTRO'],24), d('反应速率与平衡基础回收', ['H2_RATE','H2_EQUIL'],20), d('反应原理当天回收', ['H2_EQUIL','H2_K'],21),
  ],
  high3_quality_0827: [
    d('计量与NA基础清单', ['H3_STOICH'],18), d('离子反应与氧化还原', ['H3_ION_REDOX'],20), d('元素化合物转化', ['H3_INORGANIC'],20), d('热化学与速率', ['H3_THERMO_RATE'],20), d('化学平衡', ['H3_EQUILIBRIUM'],21), d('水溶液离子平衡', ['H3_AQ'],22), d('电化学', ['H3_ELECTRO'],20), d('实验综合', ['H3_EXPERIMENT'],22), d('无机工艺流程', ['H3_PROCESS'],22), d('结构与有机基础', ['H3_STRUCTURE','H3_ORGANIC'],21), d('高考化学核心能力回收', ['H3_STOICH','H3_ION_REDOX','H3_EQUILIBRIUM'],23), d('8·27质检倒排启动', ['H3_STOICH','H3_ION_REDOX'],22),
  ],
}

for (const [cohort, days] of Object.entries(history)) if (days.length !== 12) throw new Error(`${cohort} history has ${days.length} days`)
const quote = (value) => `'${String(value).replaceAll("'", "''")}'`
const historyRows = []
for (const [cohort, days] of Object.entries(history)) days.forEach((day, index) => {
  const summaries = reviewSummaries(day.skills, index)
  historyRows.push(`(${quote(cohort)},${index},${quote(day.title)},array[${day.skills.map(quote).join(',')}]::text[],array[${summaries.map(quote).join(',')}]::text[],${day.minutes})`)
})
const topicRows = Object.entries(REVIEW_TOPICS).map(([skillId, topics]) => `(${quote(skillId)},array[${topics.map(quote).join(',')}]::text[])`)

const sql = `-- Completes the REVIEW-only August calendar without changing the independent quiz site.\n` +
`begin;\n` +
`alter table public.chem_learning_plans add column if not exists knowledge_summaries text[] not null default array[]::text[];\n` +
`create temporary table review_history_template(cohort text,day_index integer,title text,skill_ids text[],knowledge_summaries text[],estimated_minutes smallint) on commit drop;\n` +
`insert into review_history_template values\n${historyRows.join(',\n')};\n` +
`insert into public.chem_learning_plans(student_id,plan_date,mode,title,skill_ids,knowledge_summaries,estimated_minutes,source,is_scheduled)\n` +
`select s.id,date '2026-08-01'+t.day_index,'REVIEW',t.title,t.skill_ids,t.knowledge_summaries,t.estimated_minutes,'mixed',true\n` +
`from public.chem_students_v2 s join review_history_template t on t.cohort=s.metadata->>'curriculumCohort'\n` +
`where s.record_status <> 'legacy' and not exists (select 1 from public.chem_learning_plans p where p.student_id=s.id and p.plan_date=date '2026-08-01'+t.day_index);\n` +
`create temporary table review_skill_topics(skill_id text primary key,topics text[]) on commit drop;\n` +
`insert into review_skill_topics values\n${topicRows.join(',\n')};\n` +
`update public.chem_learning_plans p set\n` +
`  mode='REVIEW',\n` +
`  title=replace(p.title,'小测','周检'),\n` +
`  knowledge_summaries=(\n` +
`    select array_agg(m.topics[1+mod(extract(doy from p.plan_date)::integer+n.n,cardinality(m.topics))] order by n.n)\n` +
`    from generate_series(0,greatest(3,least(5,cardinality(p.skill_ids)))-1) n(n)\n` +
`    join review_skill_topics m on m.skill_id=p.skill_ids[1+mod(n.n,cardinality(p.skill_ids))]\n` +
`  )\n` +
`from public.chem_students_v2 s\n` +
`where p.student_id=s.id and s.record_status <> 'legacy' and s.metadata->>'curriculumCohort' is not null\n` +
`  and p.plan_date between date '2026-08-01' and date '2026-09-09';\n` +
`commit;\n`

writeFileSync(resolve('supabase/migrations/20260812080000_complete_review_calendar.sql'), sql, 'utf8')
console.log(JSON.stringify({ cohorts: Object.keys(history).length, historyDays: historyRows.length, topicSkills: topicRows.length, start: '2026-08-01', end: '2026-09-09' }))
