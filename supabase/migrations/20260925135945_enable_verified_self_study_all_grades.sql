-- A self-selected practice plan must remain pinned to the exact verified
-- source release from which its questions were offered. Old plans with NULL
-- retain the previous primary-release behavior until they are completed.
alter table public.chem_learning_plans
  add column self_study_release_id uuid references app_private.chem_question_source_releases(id);

alter table public.chem_learning_plans
  add constraint chem_self_study_release_only
  check (self_study_release_id is null or delivery_mode = 'self_study');

-- Only the server's service role can enumerate ready originals. The answer
-- and explanation never leave this function for the student catalog.
create function public.chem_self_study_ready_catalog_rows(p_grade text)
returns table (
  question_id text,
  mother_id text,
  skill_id text,
  skill_title text,
  concept_key text,
  concept_title text,
  sequence_no integer,
  source_release_id uuid,
  release_kind text,
  asset_refs jsonb
)
language sql stable security definer
set search_path = ''
as $function$
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
$function$;

revoke all on function public.chem_self_study_ready_catalog_rows(text) from public, anon, authenticated;
grant execute on function public.chem_self_study_ready_catalog_rows(text) to service_role;
