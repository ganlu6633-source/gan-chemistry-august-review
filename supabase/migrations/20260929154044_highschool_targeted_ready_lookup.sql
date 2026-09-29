-- Apply every existing high-school delivery gate to the requested IDs only.
-- Avoid evaluating source holds for the entire bank on each answer; junior logic is unchanged.
create or replace function public.chem_teaching_ready_question_ids(p_grade text, p_question_ids text[])
returns table(question_id text, source_release_id uuid)
language plpgsql stable security definer set search_path = ''
as $function$
begin
  if p_grade is null or p_grade not in ('初三','高一','高二','高三')
    or cardinality(p_question_ids) is null or cardinality(p_question_ids) not between 1 and 1000
  then return; end if;
  if p_grade <> '初三' then
    return query
    with requested as materialized (
      select q.* from public.chem_questions q
      where q.grade_band=p_grade and q.id=any(p_question_ids)
    ), held as materialized (
      select distinct h.question_id
      from public.chem_question_delivery_holds_for(array(select id from requested)) h
    )
    select q.id,q.source_release_id
    from requested q
    join app_private.chem_question_source_releases r on r.id=q.source_release_id
    left join held on held.question_id=q.id
    where q.review_status='approved' and q.scope_status='IN' and q.usable_for_review
      and r.status='active' and r.verification_status='full_visual_verified'
      and r.manifest_sha256=r.verification_manifest_sha256
      and jsonb_typeof(q.options)='array' and jsonb_array_length(q.options)=4
      and q.correct_option between 0 and 3
      and length(btrim(q.stem))>0 and length(btrim(q.explanation))>0
      and q.content_fingerprint is not null and q.source_item_key is not null
      and held.question_id is null
      and app_private.chem_question_item_delivery_review_ready(q.id)
      and q.source_kind='licensed_local' and q.render_mode='image_primary'
      and (r.release_kind='teaching_material' or exists (
        select 1 from public.chem_active_verified_source_releases() a
        where a.source_release_id=q.source_release_id and a.grade_band=q.grade_band
      ));
    return;
  end if;
  return query
  with requested as materialized (
    select q.* from public.chem_questions q
    where q.grade_band = '初三' and q.id = any(p_question_ids)
  ), held as materialized (
    select distinct h.question_id
    from public.chem_question_delivery_holds_for(array(select id from requested)) h
  ), knowledge_batches as materialized (
    select array_agg(knowledge_id order by knowledge_id) knowledge_ids
    from (
      select knowledge_id, (row_number() over (order by knowledge_id) - 1) / 20 batch
      from (select distinct knowledge_id from requested where knowledge_id is not null) k
    ) numbered group by batch
  ), junior_ready as materialized (
    select p.knowledge_id, p.source_release_id
    from knowledge_batches b
    cross join lateral public.chem_junior_verified_provenance_rows('科粤版', b.knowledge_ids) p
    where p.source_release_ready and p.verification_status = 'verified'
  )
  select q.id, q.source_release_id
  from requested q
  join app_private.chem_question_source_releases r on r.id = q.source_release_id
  left join held on held.question_id = q.id
  where q.review_status = 'approved' and q.scope_status = 'IN' and q.usable_for_review
    and r.status = 'active' and r.verification_status = 'full_visual_verified'
    and r.manifest_sha256 = r.verification_manifest_sha256
    and jsonb_typeof(q.options) = 'array' and jsonb_array_length(q.options) = 4
    and q.correct_option >= 0 and q.correct_option <= 3
    and length(btrim(q.stem)) > 0 and length(btrim(q.explanation)) > 0
    and q.content_fingerprint is not null and q.source_item_key is not null
    and held.question_id is null
    and app_private.chem_question_item_delivery_review_ready(q.id)
    and q.source_kind = 'user_provided_local' and q.render_mode = 'native'
    and q.textbook_version = '科粤版'
    and exists (
      select 1 from junior_ready a
      where a.knowledge_id = q.knowledge_id and a.source_release_id = q.source_release_id
    );
end;
$function$;


revoke all on function public.chem_teaching_ready_question_ids(text,text[]) from public, anon, authenticated;
grant execute on function public.chem_teaching_ready_question_ids(text,text[]) to service_role;
