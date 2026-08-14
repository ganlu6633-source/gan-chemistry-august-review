begin;

-- 让H2燃烧例题与专用能量图使用同一套、零歧义的高中表述。
-- 只更新REVIEW知识卡；不修改独立小测站、quiz_sessions或学生作答记录。
with rewritten as (
  select c.id,
         replace(
           replace(
             replace(
               c.structured_content::text,
               '能量图的峰表示活化能，始末高度差才是ΔH。',
               '曲线峰顶表示反应过程中能量最高的位置；反应物能量线到峰顶的高度差表示正反应活化能，生成物与反应物的高度差表示ΔH。'
             ),
             '生成物减反应物',
             '比较始末能量'
           ),
           '区分活化能',
           '区分两种高度差'
         )::jsonb as structured_content
  from public.chem_knowledge_cards c
  where c.id = 'KC_H2_THERMO'
    and c.skill_id = 'H2_THERMO'
    and c.review_status = 'approved'
)
update public.chem_knowledge_cards c
set structured_content = rewritten.structured_content,
    updated_at = now()
from rewritten
where c.id = rewritten.id;

do $verify$
declare
  target_count integer;
  example_count integer;
begin
  select count(*) into target_count
  from public.chem_knowledge_cards
  where id = 'KC_H2_THERMO'
    and skill_id = 'H2_THERMO'
    and review_status = 'approved'
    and structured_content::text not like '%能量图的峰表示活化能%'
    and structured_content::text not like '%始末高度差才是ΔH%'
    and structured_content::text like '%曲线峰顶表示反应过程中能量最高的位置%'
    and structured_content::text like '%反应物能量线到峰顶的高度差表示正反应活化能%'
    and structured_content::text like '%生成物与反应物的高度差表示ΔH%';

  select (
    length(structured_content::text)
    - length(replace(structured_content::text, '反应物能量线到峰顶的高度差表示正反应活化能', ''))
  ) / length('反应物能量线到峰顶的高度差表示正反应活化能')
  into example_count
  from public.chem_knowledge_cards
  where id = 'KC_H2_THERMO'
    and review_status = 'approved';

  if target_count <> 1 then
    raise exception 'Expected the approved H2_THERMO card to distinguish the activation-energy and enthalpy height differences';
  end if;
  if example_count <> 4 then
    raise exception 'Expected the clarified H2 combustion explanation in three knowledge points and one worked example, got %', example_count;
  end if;
end
$verify$;

commit;
