begin;

-- 学生语言以苏教版一轮讲义为准：先写反应前的初始温度、
-- 混合后的最高温度，再写二者之差；不直接引入未解释的简称。
with rewritten as (
  select c.id,
         jsonb_set(
           jsonb_set(
             c.structured_content,
             '{sections}',
             (
               select jsonb_agg(
                        case
                          when section_value->>'title' = '实验测反应热的逻辑'
                            then $section${
                              "title":"实验测反应热的逻辑",
                              "summary":"测量反应前后温度的变化只是手段，目标是体系释放或吸收的热量。",
                              "items":[
                                {
                                  "label":"核心关系",
                                  "rule":"分别测量反应前酸溶液和碱溶液的温度，取二者的平均值作为反应前的初始温度T₁；测量混合后的最高温度T₂；反应前后的温度差ΔT=T₂−T₁。一定近似下q=mcΔT，再按实际反应的物质的量换算摩尔反应热。",
                                  "examples":["【示范：测量中和反应放出的热量】分别测量反应前酸溶液和碱溶液的温度，取二者的平均值作为反应前的初始温度T₁；测量混合后的最高温度T₂；反应前后的温度差ΔT=T₂−T₁。用q=mcΔT求溶液吸收的热量，再取相反号并按实际反应的物质的量换算摩尔反应热。若保温效果不好，热量散失到环境中，T₂偏低，ΔT偏小，算出的反应放出的热量也偏小；放热反应的ΔH为负，所以算出的ΔH数值偏大，更接近0。"],
                                  "visualSteps":["核心关系","测酸、碱反应前温度并取平均T₁","测混合后最高温度T₂","ΔT=T₂−T₁","沿公式判断误差"]
                                },
                                {
                                  "label":"减少散热",
                                  "rule":"使用保温容器、迅速混合、及时读最高或最低温度，减少与环境热交换。",
                                  "examples":["【示范：测量中和反应放出的热量】分别测量反应前酸溶液和碱溶液的温度，取二者的平均值作为反应前的初始温度T₁；测量混合后的最高温度T₂；反应前后的温度差ΔT=T₂−T₁。用q=mcΔT求溶液吸收的热量，再取相反号并按实际反应的物质的量换算摩尔反应热。若保温效果不好，热量散失到环境中，T₂偏低，ΔT偏小，算出的反应放出的热量也偏小；放热反应的ΔH为负，所以算出的ΔH数值偏大，更接近0。"],
                                  "visualSteps":["减少散热","测酸、碱反应前温度并取平均T₁","测混合后最高温度T₂","ΔT=T₂−T₁","沿公式判断误差"]
                                },
                                {
                                  "label":"误差方向",
                                  "rule":"若保温效果不好，热量散失到环境中，混合后的最高温度T₂偏低，因此ΔT偏小，算出的反应放出的热量也偏小。放热反应的ΔH为负，所以算出的ΔH数值偏大，更接近0。",
                                  "caution":"先沿T₂→ΔT→反应放出的热量传递误差，再结合ΔH的负号判断数值方向。",
                                  "examples":["【示范：测量中和反应放出的热量】分别测量反应前酸溶液和碱溶液的温度，取二者的平均值作为反应前的初始温度T₁；测量混合后的最高温度T₂；反应前后的温度差ΔT=T₂−T₁。用q=mcΔT求溶液吸收的热量，再取相反号并按实际反应的物质的量换算摩尔反应热。若保温效果不好，热量散失到环境中，T₂偏低，ΔT偏小，算出的反应放出的热量也偏小；放热反应的ΔH为负，所以算出的ΔH数值偏大，更接近0。"],
                                  "visualSteps":["误差方向","测酸、碱反应前温度并取平均T₁","测混合后最高温度T₂","ΔT=T₂−T₁","沿公式判断误差"]
                                }
                              ]
                            }$section$::jsonb
                          else section_value
                        end
                        order by section_order
                      )
               from jsonb_array_elements(c.structured_content->'sections')
                    with ordinality as sections(section_value, section_order)
             )
           ),
           '{workedExamples}',
           (
             select jsonb_agg(
                      case
                        when example_value->>'substance' = '量热杯测中和热'
                          then $example${
                            "substance":"测量中和反应放出的热量",
                            "path":"分别测量反应前酸溶液和碱溶液的温度，取二者的平均值作为反应前的初始温度T₁；测量混合后的最高温度T₂；反应前后的温度差ΔT=T₂−T₁。用q=mcΔT求溶液吸收的热量，再取相反号并按实际反应的物质的量换算摩尔反应热。若保温效果不好，热量散失到环境中，T₂偏低，ΔT偏小，算出的反应放出的热量也偏小；放热反应的ΔH为负，所以算出的ΔH数值偏大，更接近0。",
                            "labels":["测酸、碱反应前温度并取平均T₁","测混合后最高温度T₂","ΔT=T₂−T₁","沿公式判断误差"]
                          }$example$::jsonb
                        else example_value
                      end
                      order by example_order
                    )
             from jsonb_array_elements(c.structured_content->'workedExamples')
                  with ordinality as examples(example_value, example_order)
           )
         ) as structured_content
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

update public.chem_questions
set stem = case id
      when 'Q5R_H3_THERMO_RATE_23' then '判断：反应热测定中，T₁为反应前酸、碱溶液温度的平均值，T₂为混合后的最高温度。若热量散失到环境中，T₂和ΔT=T₂−T₁都会偏小，因此算出的反应放出的热量也偏小。'
      when 'Q5R_H3_THERMO_RATE_25' then '判断：中和热测定中用铜质搅拌棒代替玻璃搅拌棒，铜会吸收一部分热量，使混合后的最高温度T₂偏低。'
      else stem
    end,
    explanation = case id
      when 'Q5R_H3_THERMO_RATE_23' then '正确。热量散失使T₂偏低，进而使ΔT和算出的反应放出的热量偏小；放热反应的ΔH为负，所以算出的ΔH数值偏大，更接近0。'
      when 'Q5R_H3_THERMO_RATE_25' then '正确。T₁为反应前酸、碱溶液温度的平均值，反应前后的温度差ΔT=T₂−T₁；因此ΔT和算出的反应放出的热量偏小。放热反应的ΔH为负，所以算出的ΔH数值偏大，更接近0。'
      else explanation
    end,
    updated_at = now()
where id in ('Q5R_H3_THERMO_RATE_23', 'Q5R_H3_THERMO_RATE_25')
  and review_status = 'approved'
  and scope_status = 'IN'
  and usable_for_review = true;

do $verify$
declare
  updated_card_count integer;
  updated_question_count integer;
begin
  select count(*) into updated_card_count
  from public.chem_knowledge_cards
  where id = 'KC_H2_THERMO'
    and review_status = 'approved'
    and structured_content::text like '%反应前后的温度差ΔT=T₂−T₁%'
    and structured_content::text like '%算出的ΔH数值偏大，更接近0%';

  select count(*) into updated_question_count
  from public.chem_questions
  where id in ('Q5R_H3_THERMO_RATE_23', 'Q5R_H3_THERMO_RATE_25')
    and review_status = 'approved'
    and scope_status = 'IN'
    and usable_for_review = true
    and concat_ws(' ', stem, explanation) like '%ΔT=T₂−T₁%';

  if updated_card_count <> 1 then
    raise exception 'Expected the approved H2_THERMO card to use the fully defined temperature difference';
  end if;
  if updated_question_count <> 2 then
    raise exception 'Expected two REVIEW questions to use the fully defined temperature difference';
  end if;
  if exists (
    select 1
    from public.chem_knowledge_cards
    where review_status = 'approved'
      and structured_content::text like '%温升%'
  ) then
    raise exception 'Approved student knowledge cards still contain an unexplained shorthand';
  end if;
  if exists (
    select 1
    from public.chem_questions
    where review_status = 'approved'
      and scope_status = 'IN'
      and usable_for_review = true
      and concat_ws(' ', stem, explanation, scaffold) like '%温升%'
  ) then
    raise exception 'Usable REVIEW questions still contain an unexplained shorthand';
  end if;
end
$verify$;

commit;
