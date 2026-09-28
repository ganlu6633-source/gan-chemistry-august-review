-- U+FFFD in OCR text can hide a missing scientific character. Report it as a
-- candidate, including options, without deciding whether the source is wrong.
create or replace view app_private.chem_future_plan_source_qa_audit
with (security_invoker = true)
as
with fixed_assignment as materialized (
  select p.id as plan_id,p.student_id,p.plan_date,
         p.teaching_source_grade,s.grade_band as student_grade,
         j.value as question_id,j.ordinality as question_position
  from public.chem_learning_plans p
  join public.chem_students_v2 s on s.id=p.student_id
  cross join lateral jsonb_array_elements_text(coalesce(
    s.metadata#>array['reviewProgram','questionAssignments',p.plan_date::text],
    '[]'::jsonb)) with ordinality j(value,ordinality)
  where p.is_scheduled
    and p.plan_date >= (now() at time zone 'Asia/Shanghai')::date
), used_questions as materialized (
  select distinct question_id from fixed_assignment
), source_check as materialized (
  select u.question_id,q.grade_band,q.source_release_id,q.source_item_key,
         q.question_revision_token,q.source_info->>'locator' as source_locator,
         ready.id is not null as currently_ready,
         case when q.id is null then false
              else app_private.chem_question_item_visual_reviewed(q.id) end as current_revision_visually_reviewed,
         array_remove(array[
           case when q.id is not null and exists (
             select 1 from jsonb_array_elements_text(q.options) option_text
             where btrim(option_text) ~ '^[A-D][.．、]?$'
           ) then 'bare_letter_option' end,
           case when q.stem ~ '催化[[:space:]]*的分解|可能是与发生|与[[:space:]]*的总和|证明易转化为'
                  or q.explanation ~ '证明易转化为[[:space:]]*[:：]|[：:][[:space:]]*[+＋]'
                then 'missing_formula_phrase' end,
           case when q.explanation ~ '[：:][[:space:]]*[+＋][0-9]+[=＝]'
                then 'orphaned_reaction_fragment' end,
           case when position(chr(65533) in coalesce(q.stem,''))>0
                  or position(chr(65533) in coalesce(q.explanation,''))>0
                  or exists (
                    select 1 from jsonb_array_elements_text(coalesce(q.options,'[]'::jsonb)) option_text
                    where position(chr(65533) in option_text)>0
                  )
                then 'unicode_replacement_character' end,
           case when (select count(*) from regexp_matches(coalesce(q.stem,''), '反应[ⅠⅡⅢⅣIVX]+[：:]', 'g')) >= 2
                  and coalesce(q.stem,'') !~ '[→⇌↔⇄=＝]'
                then 'reaction_table_arrows_missing' end,
           case when exists (
             select 1 from jsonb_array_elements(coalesce(q.asset_refs,'[]'::jsonb)) ref
             where ref->>'kind'='analysis_image'
               and (ref->>'width') ~ '^[0-9]+$' and (ref->>'height') ~ '^[0-9]+$'
               and (ref->>'width')::numeric > 0
               and (ref->>'height')::numeric/(ref->>'width')::numeric > 2.0
           ) then 'tall_analysis_image_check_crop' end
         ]::text[],null) as heuristic_flags
  from used_questions u
  left join public.chem_questions q on q.id=u.question_id
  left join app_private.chem_teaching_ready_questions ready on ready.id=u.question_id
)
select plan_id,student_id,plan_date,question_position,question_id,
       coalesce(teaching_source_grade,student_grade) as expected_grade,
       grade_band,source_release_id,source_item_key,question_revision_token,
       source_locator,currently_ready,current_revision_visually_reviewed,
       heuristic_flags,
       case when grade_band is null then 'missing_question'
            when not currently_ready then 'not_ready_or_held'
            when grade_band is distinct from coalesce(teaching_source_grade,student_grade) then 'grade_mismatch'
            when not current_revision_visually_reviewed then 'needs_individual_visual_review'
            when cardinality(heuristic_flags)>0 then 'heuristic_candidate_already_reviewed'
            else 'source_reviewed' end as qa_status
from fixed_assignment a
join source_check c using(question_id);

revoke all on app_private.chem_future_plan_source_qa_audit from public,anon,authenticated;
grant select on app_private.chem_future_plan_source_qa_audit to service_role;
