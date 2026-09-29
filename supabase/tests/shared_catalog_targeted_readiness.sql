-- Compare all returned fields against the previous source-gated catalog, in a rolled-back transaction.
begin;
CREATE OR REPLACE FUNCTION public.chem_self_study_ready_catalog_rows(p_grade text)
 RETURNS TABLE(question_id text, mother_id text, skill_id text, skill_title text, concept_key text, concept_title text, sequence_no integer, source_release_id uuid, release_kind text, asset_refs jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select q.id::text, q.mother_id::text, q.skill_id::text, sk.title::text,
    q.concept_key::text,
    coalesce(
      c.concept_title,
      case q.concept_key
        when 'chemistry_research_object' then '化学研究的对象'
        when 'chemistry_scope_boundary' then '化学研究的范围与边界'
        when 'chemistry_society_contribution' then '化学对社会的贡献'
        when 'chemistry_society_role' then '化学与社会生活'
        when 'chemistry_development_and_responsibility' then '化学发展与绿色责任'
      end,
      t.title,
      sk.title
    )::text,
    coalesce(c.sequence_no, t.sort_order, 9999)::integer,
    q.source_release_id, r.release_kind, q.asset_refs::jsonb
  from app_private.chem_teaching_ready_questions q
  join app_private.chem_question_source_releases r on r.id = q.source_release_id
  join public.chem_skills sk on sk.id = q.skill_id and sk.active and sk.grade_band = q.grade_band
  left join lateral (
    select cc.concept_title, cc.sequence_no
    from public.chem_review_concept_catalog_rows() cc
    where cc.grade_band = q.grade_band and cc.concept_key = q.concept_key
    limit 1
  ) c on true
  left join lateral (
    select tt.title, tt.sort_order
    from app_private.chem_teaching_question_topics m
    join app_private.chem_teaching_topics tt on tt.id = m.topic_id
    where m.question_id = q.id
    order by length(tt.id) desc, tt.sort_order, tt.id
    limit 1
  ) t on true
  where q.grade_band = p_grade and q.concept_key is not null and q.mother_id is not null
    and q.source_release_id is not null
    and q.grade_band in ('初三', '高一', '高二', '高三');
$function$
;
create temp table baseline on commit drop as select g,to_jsonb(c) row from unnest(array['初三','高一','高二','高三']) g cross join lateral public.chem_self_study_ready_catalog_rows(g) c;
CREATE OR REPLACE FUNCTION public.chem_self_study_ready_catalog_rows(p_grade text)
 RETURNS TABLE(question_id text, mother_id text, skill_id text, skill_title text, concept_key text, concept_title text, sequence_no integer, source_release_id uuid, release_kind text, asset_refs jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with requested as materialized (
    select q.id, (row_number() over(order by q.id)-1)/500 batch
    from public.chem_questions q
    where q.grade_band=p_grade and p_grade in ('初三','高一','高二','高三')
      and q.review_status='approved' and q.scope_status='IN' and q.usable_for_review
      and q.concept_key is not null and q.mother_id is not null and q.source_release_id is not null
  ), batches as materialized (
    select array_agg(id order by id) ids from requested group by batch
  ), ready as materialized (
    select r.question_id from batches b
    cross join lateral public.chem_teaching_ready_question_ids(p_grade,b.ids) r
  )
  select q.id::text, q.mother_id::text, q.skill_id::text, sk.title::text,
    q.concept_key::text,
    coalesce(
      c.concept_title,
      case q.concept_key
        when 'chemistry_research_object' then '化学研究的对象'
        when 'chemistry_scope_boundary' then '化学研究的范围与边界'
        when 'chemistry_society_contribution' then '化学对社会的贡献'
        when 'chemistry_society_role' then '化学与社会生活'
        when 'chemistry_development_and_responsibility' then '化学发展与绿色责任'
      end,
      t.title,
      sk.title
    )::text,
    coalesce(c.sequence_no, t.sort_order, 9999)::integer,
    q.source_release_id, r.release_kind, q.asset_refs::jsonb
  from ready join public.chem_questions q on q.id=ready.question_id
  join app_private.chem_question_source_releases r on r.id = q.source_release_id
  join public.chem_skills sk on sk.id = q.skill_id and sk.active and sk.grade_band = q.grade_band
  left join lateral (
    select cc.concept_title, cc.sequence_no
    from public.chem_review_concept_catalog_rows() cc
    where cc.grade_band = q.grade_band and cc.concept_key = q.concept_key
    limit 1
  ) c on true
  left join lateral (
    select tt.title, tt.sort_order
    from app_private.chem_teaching_question_topics m
    join app_private.chem_teaching_topics tt on tt.id = m.topic_id
    where m.question_id = q.id
    order by length(tt.id) desc, tt.sort_order, tt.id
    limit 1
  ) t on true
  where q.grade_band = p_grade and q.concept_key is not null and q.mother_id is not null
    and q.source_release_id is not null
    and q.grade_band in ('初三', '高一', '高二', '高三');
$function$
;
do $qa$ declare n int; begin
 select count(*) into n from (
  (select * from baseline except select g,to_jsonb(c) from unnest(array['初三','高一','高二','高三']) g cross join lateral public.chem_self_study_ready_catalog_rows(g) c)
  union all
  (select g,to_jsonb(c) from unnest(array['初三','高一','高二','高三']) g cross join lateral public.chem_self_study_ready_catalog_rows(g) c except select * from baseline)
 ) d;
 if n<>0 then raise exception 'catalog parity mismatch %',n;end if;
end $qa$;
rollback;
