-- Completes the REVIEW-only August calendar without changing the independent quiz site.
begin;
alter table public.chem_learning_plans add column if not exists knowledge_summaries text[] not null default array[]::text[];
create temporary table review_history_template(cohort text,start_date date,day_index integer,title text,skill_ids text[],knowledge_summaries text[],estimated_minutes smallint) on commit drop;
insert into review_history_template values
('junior_foundation',date '2026-08-01',0,'化学变化与物理变化',array['J_CHEM_LANG']::text[],array['物理变化与化学变化','化学式与物质组成','性质、变化与用途']::text[],14),
('junior_foundation',date '2026-08-01',1,'元素符号与粒子个数',array['J_CHEM_LANG']::text[],array['元素符号的含义','宏观—微观—符号转换','物理变化与化学变化']::text[],14),
('junior_foundation',date '2026-08-01',2,'质子数与元素身份',array['J09_ATOM']::text[],array['电子得失与电荷','元素、原子与离子关系','原子和离子']::text[],15),
('junior_foundation',date '2026-08-01',3,'原子和离子的转换',array['J09_ATOM']::text[],array['粒子结构示意图','质子数与元素身份','电子得失与电荷']::text[],15),
('junior_foundation',date '2026-08-01',4,'实验安全与仪器选择',array['J_EXPERIMENT']::text[],array['读数与误差方向','仪器选择','气密性检查']::text[],14),
('junior_foundation',date '2026-08-01',5,'化学式与物质组成',array['J_CHEM_LANG','J09_ATOM']::text[],array['物理变化与化学变化','原子和离子','宏观—微观—符号转换']::text[],17),
('junior_foundation',date '2026-08-01',6,'读数与误差方向',array['J_EXPERIMENT']::text[],array['仪器选择','气密性检查','实验安全']::text[],15),
('junior_foundation',date '2026-08-01',7,'宏观—微观—符号连接',array['J_CHEM_LANG','J09_ATOM']::text[],array['化学式与物质组成','粒子结构示意图','物理变化与化学变化']::text[],17),
('junior_foundation',date '2026-08-01',8,'气密性与操作顺序',array['J_EXPERIMENT']::text[],array['气密性检查','实验安全','操作先后顺序']::text[],16),
('junior_foundation',date '2026-08-01',9,'初中基础阶段回收',array['J_CHEM_LANG','J09_ATOM','J_EXPERIMENT']::text[],array['性质、变化与用途','质子数与元素身份','仪器选择']::text[],20),
('junior_foundation',date '2026-08-01',10,'元素与原子结构回想',array['J09_ATOM']::text[],array['质子数与元素身份','电子得失与电荷','元素、原子与离子关系']::text[],15),
('junior_foundation',date '2026-08-01',11,'初中化学基础当天回收',array['J_CHEM_LANG','J09_ATOM']::text[],array['元素符号的含义','电子得失与电荷','性质、变化与用途']::text[],18),
('high1_current',date '2026-08-15',0,'元素周期律：结构与位置',array['H1_PERIODIC']::text[],array['原子结构与位置','同主族递变','性质事实验证规律']::text[],16),
('high1_current',date '2026-08-15',1,'元素周期律：同周期递变',array['H1_PERIODIC']::text[],array['同周期递变','结构—位置—性质','原子结构与位置']::text[],16),
('high1_current',date '2026-08-15',2,'物质分类：分类标准',array['H1_CLASSIFY']::text[],array['分散系与胶体','物质类别的交叉判断','纯净物与混合物']::text[],16),
('high1_current',date '2026-08-15',3,'物质分类：纯净物与混合物',array['H1_CLASSIFY']::text[],array['酸性与碱性氧化物','分类标准与分类树','分散系与胶体']::text[],16),
('high1_current',date '2026-08-15',4,'元素周期律：同主族递变',array['H1_PERIODIC']::text[],array['性质事实验证规律','同周期递变','结构—位置—性质']::text[],17),
('high1_current',date '2026-08-15',5,'物质分类：酸性与碱性氧化物',array['H1_CLASSIFY']::text[],array['分类标准与分类树','分散系与胶体','物质类别的交叉判断']::text[],17),
('high1_current',date '2026-08-15',6,'周期律与分类连接',array['H1_PERIODIC','H1_CLASSIFY']::text[],array['同周期递变','分散系与胶体','性质事实验证规律']::text[],19),
('high1_current',date '2026-08-15',7,'电解质概念边界',array['H1_ELECTROLYTE_INTRO']::text[],array['自身电离','导电与电解质边界','电解质与非电解质']::text[],16),
('high1_current',date '2026-08-15',8,'结构—位置—性质因果链',array['H1_PERIODIC']::text[],array['结构—位置—性质','原子结构与位置','同主族递变']::text[],18),
('high1_current',date '2026-08-15',9,'第一讲阶段回收',array['H1_PERIODIC','H1_CLASSIFY','H1_ELECTROLYTE_INTRO']::text[],array['性质事实验证规律','分类标准与分类树','电解质与非电解质']::text[],21),
('high1_current',date '2026-08-15',10,'元素周期律规律回想',array['H1_PERIODIC']::text[],array['原子结构与位置','同主族递变','性质事实验证规律']::text[],16),
('high1_current',date '2026-08-15',11,'物质的量、阿伏加德罗常数与摩尔质量当天回收',array['H1_MOLE_INTRO']::text[],array['阿伏加德罗常数','摩尔质量及单位','物质的量与摩尔']::text[],18),
('high1_completed',date '2026-08-01',0,'物质分类基础回想',array['H1_CLASSIFY']::text[],array['分类标准与分类树','分散系与胶体','物质类别的交叉判断']::text[],16),
('high1_completed',date '2026-08-01',1,'元素周期律结构链',array['H1_PERIODIC']::text[],array['同周期递变','结构—位置—性质','原子结构与位置']::text[],17),
('high1_completed',date '2026-08-01',2,'氧化还原价态判断',array['H1_REDOX']::text[],array['氧化还原产物','陌生反应迁移','氧化剂与还原剂']::text[],18),
('high1_completed',date '2026-08-01',3,'物质的量与摩尔',array['H1_MOLE_INTRO']::text[],array['摩尔质量及单位','物质的量与摩尔','微粒对象与粒子数']::text[],17),
('high1_completed',date '2026-08-01',4,'分类与周期律连接',array['H1_CLASSIFY','H1_PERIODIC']::text[],array['物质类别的交叉判断','原子结构与位置','分散系与胶体']::text[],19),
('high1_completed',date '2026-08-01',5,'氧化剂与还原剂',array['H1_REDOX']::text[],array['化合价升降','氧化还原产物','陌生反应迁移']::text[],18),
('high1_completed',date '2026-08-01',6,'阿伏加德罗常数与对象',array['H1_MOLE_INTRO']::text[],array['阿伏加德罗常数','摩尔质量及单位','物质的量与摩尔']::text[],18),
('high1_completed',date '2026-08-01',7,'电子守恒基础',array['H1_REDOX']::text[],array['氧化还原产物','陌生反应迁移','氧化剂与还原剂']::text[],19),
('high1_completed',date '2026-08-01',8,'四模块交叉辨析',array['H1_CLASSIFY','H1_PERIODIC','H1_REDOX','H1_MOLE_INTRO']::text[],array['酸性与碱性氧化物','性质事实验证规律','化合价升降','阿伏加德罗常数']::text[],22),
('high1_completed',date '2026-08-01',9,'第一阶段综合回收',array['H1_PERIODIC','H1_REDOX','H1_MOLE_INTRO']::text[],array['性质事实验证规律','化合价升降','阿伏加德罗常数']::text[],22),
('high1_completed',date '2026-08-01',10,'元素周期律规律回想',array['H1_PERIODIC']::text[],array['原子结构与位置','同主族递变','性质事实验证规律']::text[],17),
('high1_completed',date '2026-08-01',11,'氧化还原逻辑回收',array['H1_REDOX']::text[],array['氧化剂与还原剂','电子守恒','化合价升降']::text[],18),
('high2_xb1_complete',date '2026-08-01',0,'反应热与焓变',array['H2_THERMO']::text[],array['焓变正负','盖斯定律','能量守恒']::text[],18),
('high2_xb1_complete',date '2026-08-01',1,'反应速率表示',array['H2_RATE']::text[],array['计量数与速率比','温度与有效碰撞','速率表示']::text[],18),
('high2_xb1_complete',date '2026-08-01',2,'化学平衡状态',array['H2_EQUIL']::text[],array['平衡移动','条件改变的瞬间判断','正逆速率']::text[],19),
('high2_xb1_complete',date '2026-08-01',3,'平衡常数表达式',array['H2_K']::text[],array['转化率','平衡常数表达式','反应商Q与K']::text[],20),
('high2_xb1_complete',date '2026-08-01',4,'弱电解质电离',array['H2_WEAK']::text[],array['Ka与酸碱强弱','电离平衡','同离子效应']::text[],19),
('high2_xb1_complete',date '2026-08-01',5,'水的电离与pH',array['H2_PH_HYDRO']::text[],array['水的电离','盐类水解','酸碱中和与滴定']::text[],20),
('high2_xb1_complete',date '2026-08-01',6,'盐类水解与守恒',array['H2_PH_HYDRO']::text[],array['pH与离子浓度','三大守恒','水的电离']::text[],21),
('high2_xb1_complete',date '2026-08-01',7,'沉淀溶解平衡',array['H2_KSP']::text[],array['Qsp与沉淀','沉淀转化','Ksp表达式']::text[],20),
('high2_xb1_complete',date '2026-08-01',8,'原电池与电解池',array['H2_ELECTRO']::text[],array['电子和离子方向','原电池与电解池','电极反应']::text[],21),
('high2_xb1_complete',date '2026-08-01',9,'选择性必修一阶段回收',array['H2_THERMO','H2_EQUIL','H2_PH_HYDRO','H2_ELECTRO']::text[],array['能量守恒','平衡状态','pH与离子浓度','电极反应']::text[],24),
('high2_xb1_complete',date '2026-08-01',10,'反应速率与平衡基础回收',array['H2_RATE','H2_EQUIL']::text[],array['速率表示','正逆速率','温度与有效碰撞']::text[],20),
('high2_xb1_complete',date '2026-08-01',11,'反应原理当天回收',array['H2_EQUIL','H2_K']::text[],array['正逆速率','反应商Q与K','条件改变的瞬间判断']::text[],21),
('high3_quality_0827',date '2026-08-01',0,'计量与NA基础清单',array['H3_STOICH']::text[],array['物质的量枢纽','气体条件','守恒与反应计量']::text[],18),
('high3_quality_0827',date '2026-08-01',1,'离子反应与氧化还原',array['H3_ION_REDOX']::text[],array['离子方程式','氧化还原配平','离子共存']::text[],20),
('high3_quality_0827',date '2026-08-01',2,'元素化合物转化',array['H3_INORGANIC']::text[],array['反应条件','物质制备与检验','物质类别']::text[],20),
('high3_quality_0827',date '2026-08-01',3,'热化学与速率',array['H3_THERMO_RATE']::text[],array['速率图像','反应热','反应速率']::text[],20),
('high3_quality_0827',date '2026-08-01',4,'化学平衡',array['H3_EQUILIBRIUM']::text[],array['转化率与条件优化','平衡常数','平衡图像']::text[],21),
('high3_quality_0827',date '2026-08-01',5,'水溶液离子平衡',array['H3_AQ']::text[],array['弱电解质平衡','盐类水解','沉淀溶解平衡']::text[],22),
('high3_quality_0827',date '2026-08-01',6,'电化学',array['H3_ELECTRO']::text[],array['电解池','电子与离子迁移','原电池']::text[],20),
('high3_quality_0827',date '2026-08-01',7,'实验综合',array['H3_EXPERIMENT']::text[],array['现象与证据','探究方案评价','装置与操作']::text[],22),
('high3_quality_0827',date '2026-08-01',8,'无机工艺流程',array['H3_PROCESS']::text[],array['循环利用','原料预处理','分离提纯']::text[],22),
('high3_quality_0827',date '2026-08-01',9,'结构与有机基础',array['H3_STRUCTURE','H3_ORGANIC']::text[],array['结构与性质解释','官能团与类别','化学键与分子结构']::text[],21),
('high3_quality_0827',date '2026-08-01',10,'高考化学核心能力回收',array['H3_STOICH','H3_ION_REDOX','H3_EQUILIBRIUM']::text[],array['物质的量枢纽','离子方程式','三段式计算']::text[],23),
('high3_quality_0827',date '2026-08-01',11,'8·27质检倒排启动',array['H3_STOICH','H3_ION_REDOX']::text[],array['阿伏加德罗常数判断','少量与过量','守恒与反应计量']::text[],22);
insert into public.chem_learning_plans(student_id,plan_date,mode,title,skill_ids,knowledge_summaries,estimated_minutes,source,is_scheduled)
select s.id,t.start_date+t.day_index,'REVIEW',t.title,t.skill_ids,t.knowledge_summaries,t.estimated_minutes,'mixed',true
from public.chem_students_v2 s join review_history_template t on t.cohort=s.metadata->>'curriculumCohort'
where s.record_status <> 'legacy' and not exists (select 1 from public.chem_learning_plans p where p.student_id=s.id and p.plan_date=t.start_date+t.day_index);
create temporary table review_skill_topics(skill_id text primary key,topics text[]) on commit drop;
insert into review_skill_topics values
('J_CHEM_LANG',array['物理变化与化学变化','元素符号的含义','化学式与物质组成','宏观—微观—符号转换','性质、变化与用途']::text[]),
('J_EXPERIMENT',array['实验安全','仪器选择','操作先后顺序','气密性检查','读数与误差方向']::text[]),
('J09_ATOM',array['质子数与元素身份','原子和离子','电子得失与电荷','粒子结构示意图','元素、原子与离子关系']::text[]),
('H1_CLASSIFY',array['分类标准与分类树','纯净物与混合物','分散系与胶体','酸性与碱性氧化物','物质类别的交叉判断']::text[]),
('H1_PERIODIC',array['原子结构与位置','同周期递变','同主族递变','结构—位置—性质','性质事实验证规律']::text[]),
('H1_REDOX',array['化合价升降','氧化剂与还原剂','氧化还原产物','电子守恒','陌生反应迁移']::text[]),
('H1_ELECTROLYTE_INTRO',array['电解质的研究对象','电解质与非电解质','自身电离','自由移动的离子','导电与电解质边界']::text[]),
('H1_MOLE_INTRO',array['物质的量与摩尔','阿伏加德罗常数','微粒对象与粒子数','摩尔质量及单位','质量—物质的量换算']::text[]),
('H2_THERMO',array['焓变正负','热化学方程式','盖斯定律','键能与反应热','能量守恒']::text[]),
('H2_RATE',array['速率表示','计量数与速率比','浓度和压强影响','温度与有效碰撞','催化剂与活化能']::text[]),
('H2_EQUIL',array['平衡状态','正逆速率','平衡移动','勒夏特列原理','条件改变的瞬间判断']::text[]),
('H2_K',array['平衡常数表达式','三段式','反应商Q与K','转化率','温度与平衡常数']::text[]),
('H2_WEAK',array['弱电解质部分电离','电离平衡','稀释效应','同离子效应','Ka与酸碱强弱']::text[]),
('H2_PH_HYDRO',array['水的电离','pH与离子浓度','盐类水解','三大守恒','酸碱中和与滴定']::text[]),
('H2_KSP',array['溶解平衡','Ksp表达式','Qsp与沉淀','同离子效应','沉淀转化']::text[]),
('H2_ELECTRO',array['原电池与电解池','正负极与阴阳极','电极反应','电子和离子方向','金属腐蚀与防护']::text[]),
('H3_STOICH',array['物质的量枢纽','阿伏加德罗常数判断','气体条件','溶液浓度','守恒与反应计量']::text[]),
('H3_ION_REDOX',array['离子共存','离子方程式','少量与过量','氧化还原配平','电子、电荷与原子守恒']::text[]),
('H3_INORGANIC',array['元素价态','物质类别','反应条件','无机转化网络','物质制备与检验']::text[]),
('H3_THERMO_RATE',array['反应热','热化学计算','反应速率','速率图像','工业条件选择']::text[]),
('H3_EQUILIBRIUM',array['平衡移动','平衡常数','三段式计算','平衡图像','转化率与条件优化']::text[]),
('H3_AQ',array['弱电解质平衡','水的电离与pH','盐类水解','离子浓度守恒','沉淀溶解平衡']::text[]),
('H3_ELECTRO',array['原电池','电解池','电极方程式','电子与离子迁移','电化学定量']::text[]),
('H3_EXPERIMENT',array['实验目的与原理','装置与操作','现象与证据','误差分析','探究方案评价']::text[]),
('H3_PROCESS',array['原料预处理','反应条件控制','分离提纯','循环利用','产率与环保评价']::text[]),
('H3_STRUCTURE',array['核外电子排布','元素周期性','化学键与分子结构','晶体结构','结构与性质解释']::text[]),
('H3_ORGANIC',array['官能团与类别','有机反应类型','同分异构体','合成路线','有机实验与检验']::text[]);
update public.chem_learning_plans p set
  mode='REVIEW',
  title=replace(p.title,'小测','周检'),
  knowledge_summaries=(
    select array_agg(m.topics[1+mod(extract(doy from p.plan_date)::integer+n.n,cardinality(m.topics))] order by n.n)
    from generate_series(0,greatest(3,least(5,cardinality(p.skill_ids)))-1) n(n)
    join review_skill_topics m on m.skill_id=p.skill_ids[1+mod(n.n,cardinality(p.skill_ids))]
  )
from public.chem_students_v2 s
where p.student_id=s.id and s.record_status <> 'legacy' and s.metadata->>'curriculumCohort' is not null
  and p.plan_date between date '2026-08-01' and date '2026-09-23';
commit;
