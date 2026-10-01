-- Make fifteen already-reviewed original junior questions discoverable by topic.
-- Each leaf is supported by one exact source item; the section parent keeps a
-- useful practice pool while more same-type original questions are checked.
begin;

create temporary table junior_topic_route_fix (
  concept_key text primary key,
  topic_id text not null,
  parent_id text not null,
  title text not null,
  sort_order integer not null
) on commit drop;

insert into junior_topic_route_fix values
('metal_oxygen_reaction_gold','CHEM.J.KY.U06.S02.METAL_OXYGEN','CHEM.J.KY.U06.S02','金属与氧气反应：活泼性与条件',10),
('metal_acid_direct_product','CHEM.J.KY.U06.S02.METAL_ACID_PRODUCT','CHEM.J.KY.U06.S02','金属与酸反应：哪些盐能直接制得',20),
('magnesium_acid_heat_and_hydrogen','CHEM.J.KY.U06.S02.MAGNESIUM_ACID','CHEM.J.KY.U06.S02','镁与稀盐酸：放热和氢气',30),
('metal_activity_three_order','CHEM.J.KY.U06.S02.ACTIVITY_ORDER','CHEM.J.KY.U06.S02','用酸和盐溶液比较金属活动性',40),
('acid_separation_mobile_metals','CHEM.J.KY.U06.S02.ACID_SEPARATION','CHEM.J.KY.U06.S02','用酸分离活泼与不活泼金属',50),
('single_displacement_valence_change','CHEM.J.KY.U06.S02.DISPLACEMENT','CHEM.J.KY.U06.S02','置换反应与化合价变化',60),
('metal_silver_nitrate_valence','CHEM.J.KY.U06.S02.METAL_SILVER_NITRATE','CHEM.J.KY.U06.S02','金属与硝酸银：推断化合价',70),
('activity_order_predict_reaction','CHEM.J.KY.U06.S02.ACTIVITY_PREDICTION','CHEM.J.KY.U06.S02','按活动性顺序预测反应',80),
('fossil_vs_ethanol','CHEM.J.KY.U05.S04.FOSSIL_IDENTIFICATION','CHEM.J.KY.U05.S04','辨别化石燃料与乙醇',10),
('natural_gas_complete_combustion','CHEM.J.KY.U05.S04.NATURAL_GAS','CHEM.J.KY.U05.S04','天然气的完全燃烧',20),
('coal_emissions_environment','CHEM.J.KY.U05.S04.COAL_EMISSIONS','CHEM.J.KY.U05.S04','煤燃烧与环境问题',30),
('petroleum_fractionation_physical','CHEM.J.KY.U05.S04.PETROLEUM_FRACTIONATION','CHEM.J.KY.U05.S04','石油分馏是物理变化',40),
('combustion_air_supply','CHEM.J.KY.U05.S04.AIR_SUPPLY','CHEM.J.KY.U05.S04','燃烧不充分时调节空气供给',50),
('fossil_fuel_finite','CHEM.J.KY.U05.S04.FINITE_RESOURCES','CHEM.J.KY.U05.S04','化石燃料是有限资源',60),
('methane_hydrate_greenhouse','CHEM.J.KY.U05.S04.METHANE_HYDRATE','CHEM.J.KY.U05.S04','可燃冰与甲烷的温室效应',70);

do $guard$ begin
  if (select count(*) from junior_topic_route_fix) <> 15 then raise exception 'expected 15 topic routes'; end if;
  if (select count(*) from junior_topic_route_fix m join app_private.chem_teaching_topics t on t.id=m.parent_id) <> 15
    then raise exception 'parent topic missing'; end if;
  if (select count(*) from junior_topic_route_fix m join app_private.chem_teaching_ready_questions r on true
      join public.chem_questions q on q.id=r.id and q.concept_key=m.concept_key
      where q.grade_band='初三' and q.source_info->>'exam' in
      ('SRC-KY9-METAL-CHEMICAL-161A5BC7723AD31E','SRC-KY9-FOSSIL-2B7CD0573D9F5C47')) <> 15
    then raise exception 'source question match changed'; end if;
end $guard$;

insert into app_private.chem_teaching_topics(id,parent_id,title,grade_bands,sort_order,evidence)
select m.topic_id,m.parent_id,m.title,array['初三']::text[],m.sort_order,
  jsonb_build_object('mappingState','has_explicit_evidence',
    'includeBoundary',m.title,
    'excludeBoundary','仅对应原题已核实的这一细分知识点，不自动推断其他题也属于同类型。',
    'sourceEvidence',jsonb_build_array(jsonb_build_object('kind','verified_original_choice','questionId',q.id,'sourceLocator',q.source_info->>'locator')))
from junior_topic_route_fix m join public.chem_questions q on q.concept_key=m.concept_key
where q.grade_band='初三' and q.source_info->>'exam' in
  ('SRC-KY9-METAL-CHEMICAL-161A5BC7723AD31E','SRC-KY9-FOSSIL-2B7CD0573D9F5C47')
on conflict (id) do nothing;

insert into app_private.chem_teaching_question_topics(question_id,topic_id,evidence)
select q.id,t.topic_id,jsonb_build_object('method','source_visual_and_chemistry_review',
  'evidence',jsonb_build_object('sourceLocator',q.source_info->>'locator',
  'questionRevisionToken',q.question_revision_token,'conceptKey',q.concept_key),
  'sameTypeClaim',false,'questionRevisionToken',q.question_revision_token)
from junior_topic_route_fix t join public.chem_questions q on q.concept_key=t.concept_key
join app_private.chem_teaching_ready_questions ready on ready.id=q.id
where q.grade_band='初三' and q.source_info->>'exam' in
  ('SRC-KY9-METAL-CHEMICAL-161A5BC7723AD31E','SRC-KY9-FOSSIL-2B7CD0573D9F5C47')
on conflict (question_id,topic_id) do nothing;

insert into app_private.chem_teaching_question_topics(question_id,topic_id,evidence)
select q.id,t.parent_id,jsonb_build_object('method','verified_original_section_route',
  'evidence',jsonb_build_object('sourceLocator',q.source_info->>'locator',
  'questionRevisionToken',q.question_revision_token,'conceptKey',q.concept_key),
  'sameTypeClaim',false,'questionRevisionToken',q.question_revision_token)
from junior_topic_route_fix t join public.chem_questions q on q.concept_key=t.concept_key
join app_private.chem_teaching_ready_questions ready on ready.id=q.id
where q.grade_band='初三' and q.source_info->>'exam' in
  ('SRC-KY9-METAL-CHEMICAL-161A5BC7723AD31E','SRC-KY9-FOSSIL-2B7CD0573D9F5C47')
on conflict (question_id,topic_id) do nothing;

do $guard$ begin
  if (select count(*) from app_private.chem_teaching_question_topics qt
      join junior_topic_route_fix m on m.topic_id=qt.topic_id
      join public.chem_questions q on q.id=qt.question_id and q.concept_key=m.concept_key
      where q.grade_band='初三' and q.source_info->>'exam' in
      ('SRC-KY9-METAL-CHEMICAL-161A5BC7723AD31E','SRC-KY9-FOSSIL-2B7CD0573D9F5C47')) <> 15
    then raise exception 'leaf topic mapping incomplete'; end if;
end $guard$;

commit;
