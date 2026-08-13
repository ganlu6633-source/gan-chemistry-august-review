-- 把高一、高二、高三复习卡的30秒文字梗概升级为关系图数据。
-- 只更新review复习知识卡，不修改独立小测系统。

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"tree","title":"物质分类总树","tree":{"label":"物质","children":[{"label":"混合物","children":[{"label":"分散系","children":[{"label":"溶液＜1 nm"},{"label":"胶体1～100 nm"},{"label":"浊液＞100 nm"}]}]},{"label":"纯净物","children":[{"label":"单质","children":[{"label":"金属单质"},{"label":"非金属单质"}]},{"label":"化合物","children":[{"label":"有机化合物"},{"label":"无机化合物","children":[{"label":"氧化物"},{"label":"酸"},{"label":"碱"},{"label":"盐"}]}]}]}]},"axes":[{"label":"化合物｜电离","items":["电解质","非电解质"]},{"label":"酸｜三条轴","items":["一/二/多元","强/弱","含氧/无氧"]},{"label":"碱｜三条轴","items":["一/二/三元","强/弱","易溶/微溶/难溶"]},{"label":"氧化物｜性质","items":["酸性","碱性","两性","不成盐"]},{"label":"盐｜组成","items":["正盐","酸式盐","碱式盐"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H1_CLASSIFY' and skill_id = 'H1_CLASSIFY' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"tree","title":"电解质判断树","tree":{"label":"研究对象","children":[{"label":"单质/混合物→退出"},{"label":"化合物","children":[{"label":"自身产生自由离子","children":[{"label":"是→电解质"},{"label":"否→非电解质"}]}]}]},"axes":[{"label":"导电条件","items":["水溶液","熔融状态"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H1_ELECTROLYTE_INTRO' and skill_id = 'H1_ELECTROLYTE_INTRO' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"compare","title":"周期表中的两条趋势线","groups":[{"label":"同周期 →","items":["核吸引增强","半径↓","金属性↓","非金属性↑"]},{"label":"同主族 ↓","items":["电子层增多","半径↑","金属性↑","非金属性↓"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H1_PERIODIC' and skill_id = 'H1_PERIODIC' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"balance","title":"氧化还原电子天平","center":"e⁻总数相等","groups":[{"label":"升价｜失电子","items":["被氧化","还原剂","氧化产物"]},{"label":"降价｜得电子","items":["被还原","氧化剂","还原产物"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H1_REDOX' and skill_id = 'H1_REDOX' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"flow","title":"离子反应完整路线","steps":[{"label":"限定化合物","caption":"01"},{"label":"列真实粒子","caption":"02"},{"label":"找反应推动力","caption":"03"},{"label":"写→拆→删","caption":"04"},{"label":"查事实/原子/电荷","caption":"05"}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H1_ELECTROLYTE' and skill_id = 'H1_ELECTROLYTE' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"network","title":"物质的量把宏观与微观接起来","center":"物质的量 n","groups":[{"label":"微观","items":["微粒数 N","N=nNₐ"]},{"label":"宏观","items":["质量 m","n=m/M"]},{"label":"对象","items":["分子/原子","离子/电子"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H1_MOLE_INTRO' and skill_id = 'H1_MOLE_INTRO' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"network","title":"所有已知量先汇入 n","center":"物质的量 n","groups":[{"label":"质量","items":["m/M"]},{"label":"微粒数","items":["N/Nₐ"]},{"label":"气体体积","items":["V/Vₘ"]},{"label":"溶液","items":["cV"]},{"label":"反应","items":["方程式系数比"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H1_MOLE' and skill_id = 'H1_MOLE' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"network","title":"钠与氯的两条物质主线","center":"价态与电子","groups":[{"label":"钠主线","items":["Na失1e⁻","Na₂O/Na₂O₂","Na₂CO₃/NaHCO₃"]},{"label":"氯主线","items":["Cl₂强氧化","氯水多粒子","HClO漂白消毒"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H1_NACL' and skill_id = 'H1_NACL' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"balance","title":"反应热的能量账本","center":"ΔH=后−前","groups":[{"label":"吸收","items":["反应物断键","能量输入"]},{"label":"释放","items":["生成物成键","能量输出"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H2_THERMO' and skill_id = 'H2_THERMO' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"network","title":"哪些因素改变反应速率","center":"反应速率","groups":[{"label":"浓度/分压","items":["碰撞频率↑"]},{"label":"温度","items":["活化分子比例↑"]},{"label":"催化剂","items":["活化能Ea↓"]},{"label":"计量关系","items":["速率比=系数比"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H2_RATE' and skill_id = 'H2_RATE' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"balance","title":"比较正逆速率决定移动","center":"比较大小","groups":[{"label":"v正＞v逆","items":["向右移动","直到新平衡"]},{"label":"v正＜v逆","items":["向左移动","直到新平衡"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H2_EQUIL' and skill_id = 'H2_EQUIL' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"compare","title":"Q与K一眼判方向","groups":[{"label":"Q＜K","items":["向正方向"]},{"label":"Q＝K","items":["已经平衡"]},{"label":"Q＞K","items":["向逆方向"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H2_K' and skill_id = 'H2_K' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"cycle","title":"弱电解质的动态电离","steps":[{"label":"弱电解质分子","caption":"01"},{"label":"部分电离","caption":"02"},{"label":"离子共存","caption":"03"},{"label":"稀释/同离子扰动","caption":"04"},{"label":"建立新平衡","caption":"05"}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H2_WEAK' and skill_id = 'H2_WEAK' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"network","title":"水溶液先列粒子再计算","center":"溶液粒子清单","groups":[{"label":"酸碱","items":["Kw与pH"]},{"label":"水解","items":["弱者的离子"]},{"label":"守恒","items":["电荷守恒","物料/质子守恒"]},{"label":"滴定","items":["反应→过量→平衡"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H2_PH_HYDRO' and skill_id = 'H2_PH_HYDRO' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"compare","title":"Qsp与Ksp决定沉淀方向","groups":[{"label":"Qsp＜Ksp","items":["继续溶解"]},{"label":"Qsp＝Ksp","items":["溶解平衡"]},{"label":"Qsp＞Ksp","items":["析出沉淀"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H2_KSP' and skill_id = 'H2_KSP' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"compare","title":"原电池与电解池共用两极规律","groups":[{"label":"阳极｜氧化","items":["原电池负极","电解池接正极"]},{"label":"阴极｜还原","items":["原电池正极","电解池接负极"]},{"label":"两条通道","items":["电子走导线","离子走电解质"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H2_ELECTRO' and skill_id = 'H2_ELECTRO' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"flow","title":"综合计量的最短路线","steps":[{"label":"识别已知量","caption":"01"},{"label":"全部换算为n","caption":"02"},{"label":"判断限制量","caption":"03"},{"label":"按系数比转移","caption":"04"},{"label":"优先找守恒","caption":"05"},{"label":"单位/数量级校验","caption":"06"}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H3_STOICH' and skill_id = 'H3_STOICH' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"flow","title":"离子与氧化还原综合路线","steps":[{"label":"翻译隐含条件","caption":"01"},{"label":"筛查实际反应","caption":"02"},{"label":"写→拆→删→查","caption":"03"},{"label":"标价判升降","caption":"04"},{"label":"配平电子","caption":"05"},{"label":"查原子/电荷/介质","caption":"06"}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H3_ION_REDOX' and skill_id = 'H3_ION_REDOX' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"network","title":"无机推断的三个控制轴","center":"具体产物","groups":[{"label":"价态","items":["决定氧化还原方向"]},{"label":"物质类别","items":["决定酸碱/离子反应"]},{"label":"反应条件","items":["决定最终产物"]},{"label":"检验闭环","items":["试剂→现象→结论"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H3_INORGANIC' and skill_id = 'H3_INORGANIC' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"network","title":"工业反应的多目标权衡","center":"工业条件","groups":[{"label":"热力学","items":["ΔH与平衡"]},{"label":"动力学","items":["Ea与速率"]},{"label":"工程","items":["能耗/成本","安全/产率"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H3_THERMO_RATE' and skill_id = 'H3_THERMO_RATE' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"cycle","title":"平衡受到扰动后的完整循环","steps":[{"label":"旧平衡","caption":"01"},{"label":"外界扰动","caption":"02"},{"label":"瞬时v正/v逆","caption":"03"},{"label":"Q与K判方向","caption":"04"},{"label":"定向移动","caption":"05"},{"label":"新平衡","caption":"06"}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H3_EQUILIBRIUM' and skill_id = 'H3_EQUILIBRIUM' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"network","title":"水溶液综合题的中心地图","center":"列全粒子","groups":[{"label":"平衡常数","items":["Kw/Ka/Kb/Kh/Ksp"]},{"label":"方向","items":["Q与K"]},{"label":"数量关系","items":["电荷/物料/质子守恒"]},{"label":"应用","items":["滴定四阶段","沉淀Qsp"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H3_AQ' and skill_id = 'H3_AQ' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"cycle","title":"充放电中的电子与离子闭环","steps":[{"label":"总反应","caption":"01"},{"label":"放电方向","caption":"02"},{"label":"阳极氧化","caption":"03"},{"label":"e⁻走外电路","caption":"04"},{"label":"离子走膜/电解质","caption":"05"},{"label":"阴极还原","caption":"06"},{"label":"充电反向","caption":"07"}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H3_ELECTRO' and skill_id = 'H3_ELECTRO' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"flow","title":"实验答案必须形成证据链","steps":[{"label":"实验目的","caption":"01"},{"label":"反应原理","caption":"02"},{"label":"装置/试剂","caption":"03"},{"label":"规范操作","caption":"04"},{"label":"现象→结论","caption":"05"},{"label":"误差与安全","caption":"06"}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H3_EXPERIMENT' and skill_id = 'H3_EXPERIMENT' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"flow","title":"工艺流程图从原料走到产品","steps":[{"label":"原料","caption":"01"},{"label":"浸取/转价","caption":"02"},{"label":"调pH除杂","caption":"03"},{"label":"过滤/洗涤","caption":"04"},{"label":"浓缩/结晶","caption":"05"},{"label":"产品/循环评价","caption":"06"}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H3_PROCESS' and skill_id = 'H3_PROCESS' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"tree","title":"结构决定性质的三层模型","tree":{"label":"结构决定性质","children":[{"label":"原子层","children":[{"label":"电子排布/周期趋势"}]},{"label":"分子层","children":[{"label":"构型/极性/作用力"}]},{"label":"晶体层","children":[{"label":"晶体类型"},{"label":"晶胞计算"}]}]},"axes":[{"label":"最终落点","items":["宏观性质"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H3_STRUCTURE' and skill_id = 'H3_STRUCTURE' and review_status = 'approved';

update public.chem_knowledge_cards
set structured_content = jsonb_set(structured_content, '{visualSummary}', $visual${"kind":"network","title":"有机推断同时追踪两条线","center":"读结构","groups":[{"label":"碳骨架","items":["碳数变化","碳链/位置异构"]},{"label":"官能团","items":["性质与反应类型","官能团转化"]},{"label":"综合输出","items":["同分异构体","合成路线"]}]}$visual$::jsonb, true),
    updated_at = now()
where id = 'KC_H3_ORGANIC' and skill_id = 'H3_ORGANIC' and review_status = 'approved';

do $verify$
declare
  visual_card_count integer;
begin
  select count(*) into visual_card_count
  from public.chem_knowledge_cards c
  join public.chem_skills s on s.id = c.skill_id
  where s.active = true
    and s.grade_band in ('高一', '高二', '高三')
    and c.id = 'KC_' || c.skill_id
    and c.review_status = 'approved'
    and c.structured_content->'visualSummary'->>'kind' in ('tree', 'flow', 'cycle', 'compare', 'network', 'balance')
    and length(coalesce(c.structured_content->'visualSummary'->>'title', '')) > 0;

  if visual_card_count <> 27 then
    raise exception 'Expected 27 visual knowledge cards, found %', visual_card_count;
  end if;
end
$verify$;
