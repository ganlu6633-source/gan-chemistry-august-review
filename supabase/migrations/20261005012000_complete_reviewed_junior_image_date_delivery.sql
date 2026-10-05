-- Reviewed images use their OWN per-question source proof. The independent
-- textbook knowledge-card release remains required; native 21/7 rules are unchanged.
-- This migration never rewrites an issued step, first answer or frozen reserve.
CREATE OR REPLACE FUNCTION app_private.chem_junior_parent_source_identity(q public.chem_questions)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path='' AS $function$
 select case when q.source_kind='licensed_local' then coalesce(q.parent_source_item_key,q.source_item_key) else q.parent_source_item_key end;
$function$;
REVOKE ALL ON FUNCTION app_private.chem_junior_parent_source_identity(public.chem_questions) FROM public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION app_private.chem_junior_image_question_contract_ok(q public.chem_questions)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
 select exists (
   select 1 from app_private.chem_question_source_release_items item
   join app_private.chem_question_source_releases r on r.id=q.source_release_id
   join app_private.chem_question_assets problem on problem.question_id=q.id and problem.asset_kind='question_image'
   join app_private.chem_question_assets solution on solution.question_id=q.id and solution.asset_kind='analysis_image'
   where item.question_id=q.id and item.release_id=q.source_release_id and q.grade_band='初三' and q.textbook_version='科粤版'
     and q.source_kind='licensed_local' and q.render_mode='image_primary' and q.image_url is null
     and q.skill_id=q.knowledge_id and q.skill_id is not null
     and length(btrim(q.mother_id))>0 and length(btrim(q.same_type_key))>0
     and length(q.source_item_key)>=16 and length(app_private.chem_junior_parent_source_identity(q))>=16
     and q.question_revision_token ~ '^[0-9a-f]{64}$' and q.content_fingerprint ~ '^[0-9a-f]{64}$'
     and r.grade_band=q.grade_band and r.textbook_version=q.textbook_version
     and r.release_kind='teaching_material' and r.verified_at is not null and r.activated_at is not null
     and length(btrim(r.verification_actor))>0
     and not q.usable_for_class_quiz and not q.usable_for_exam_sprint and not q.usable_for_demo
     and jsonb_array_length(q.asset_refs)=2
     and item.question_asset_sha256=problem.sha256 and item.analysis_asset_sha256=solution.sha256
     and q.content_fingerprint=app_private.chem_h3_content_fingerprint(q.stem,q.options)
     and q.question_revision_token=app_private.chem_h3_question_revision_sha256(q,problem.sha256,solution.sha256)
     and item.item_sha256=app_private.chem_h3_release_item_sha256(q,item.canonical_source_id,problem.sha256,solution.sha256)
     and exists (select 1 from jsonb_array_elements(q.asset_refs) ref where ref->>'path'=problem.asset_path
       and ref->>'kind'=problem.asset_kind and ref->>'sha256'=problem.sha256
       and (ref->>'width')::integer=problem.width and (ref->>'height')::integer=problem.height)
     and exists (select 1 from jsonb_array_elements(q.asset_refs) ref where ref->>'path'=solution.asset_path
       and ref->>'kind'=solution.asset_kind and ref->>'sha256'=solution.sha256
       and (ref->>'width')::integer=solution.width and (ref->>'height')::integer=solution.height)
     and not exists(select 1 from jsonb_array_elements(q.options) opt
       where jsonb_typeof(opt)<>'string' or length(btrim(opt#>>'{}'))=0)
     and (select count(distinct btrim(opt#>>'{}')) from jsonb_array_elements(q.options) opt)=4
     and app_private.chem_junior_ready_card_id('科粤版',q.knowledge_id) is not null
 );
$function$;
REVOKE ALL ON FUNCTION app_private.chem_junior_image_question_contract_ok(public.chem_questions) FROM public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION app_private.chem_junior_image_question_delivery_ready(p_question_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
 select exists(select 1 from public.chem_questions q
   join app_private.chem_teaching_ready_questions ready on ready.id=q.id and ready.question_revision_token=q.question_revision_token
   where q.id=p_question_id and q.source_kind='licensed_local'
    and app_private.chem_junior_image_question_contract_ok(q));
$function$;
REVOKE ALL ON FUNCTION app_private.chem_junior_image_question_delivery_ready(text) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION app_private.chem_junior_lock_image_delivery_source(p_question_id text,p_textbook_version text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
declare q public.chem_questions%rowtype;
begin
 select * into q from public.chem_questions where id=p_question_id for share;
 if not found or p_textbook_version is distinct from '科粤版' or q.textbook_version is distinct from p_textbook_version
 then raise exception 'junior image textbook contract changed'; end if;
 -- Same lifecycle advisory locks are already held by issue, validate and answer.
 -- Lock the exact source/visual evidence before repeating the ready-view check.
 perform r.id from app_private.chem_question_source_releases r where r.id=q.source_release_id for share;
 perform i.question_id from app_private.chem_question_source_release_items i where i.question_id=q.id and i.release_id=q.source_release_id for share;
 perform a.asset_path from app_private.chem_question_assets a where a.question_id=q.id order by a.asset_path for share;
 perform d.question_id from app_private.chem_junior_question_source_documents d where d.question_id=q.id for share;
 perform v.question_id from app_private.chem_question_item_visual_reviews v where v.question_id=q.id for share;
 if not app_private.chem_junior_image_question_delivery_ready(q.id)
 then raise exception 'junior image source, assets, per-item review or knowledge card is unavailable'; end if;
end;
$function$;
REVOKE ALL ON FUNCTION app_private.chem_junior_lock_image_delivery_source(text,text) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.chem_junior_image_question_context(p_question_ids text[])
RETURNS TABLE(question_id text,revision_token text,source_release_id uuid,knowledge_id text,textbook_version text,card_source_release_id uuid,card_id text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $function$
begin
 if p_question_ids is null or cardinality(p_question_ids)>800 then raise exception 'invalid junior image context request'; end if;
 return query with ready_images as materialized (
  select ready.id,ready.question_revision_token from app_private.chem_teaching_ready_questions ready
  where ready.id=any(p_question_ids) and ready.grade_band='初三' and ready.source_kind='licensed_local' and ready.render_mode='image_primary'
 ) select q.id,q.question_revision_token,q.source_release_id,q.knowledge_id,q.textbook_version,p.source_release_id,
   app_private.chem_junior_ready_card_id(q.textbook_version,q.knowledge_id)
 from public.chem_questions q
 join ready_images ready on ready.id=q.id and ready.question_revision_token=q.question_revision_token
 cross join lateral public.chem_junior_verified_provenance_rows('科粤版',array[q.knowledge_id]) p
 where q.id=any(p_question_ids) and app_private.chem_junior_image_question_contract_ok(q)
   and p.knowledge_id=q.knowledge_id and p.verification_status='verified' and p.source_release_ready;
end;
$function$;
REVOKE ALL ON FUNCTION public.chem_junior_image_question_context(text[]) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.chem_junior_image_question_context(text[]) TO service_role;

-- The opaque issued-step capability authorizes only its exact snapshotted image.
-- Answered evidence stays readable if that version is later retired or held.
CREATE OR REPLACE FUNCTION public.chem_junior_step_question_asset_context(p_student_id uuid,p_plan_id uuid,p_step_id uuid,p_asset_path text,p_revision_token text)
RETURNS TABLE(question_id text,answered boolean) LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
declare st public.chem_junior_session_steps%rowtype; sess public.chem_junior_daily_sessions%rowtype; a app_private.chem_question_assets%rowtype;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release',0));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release',0));
 perform s.id from public.chem_students_v2 s where s.id=p_student_id for update;
 select s.* into sess from public.chem_junior_daily_sessions s
 where s.student_id=p_student_id and s.plan_day_id=p_plan_id for share;
 if not found then return; end if;
 select s.* into st from public.chem_junior_session_steps s where s.id=p_step_id and s.session_id=sess.id for share;
 if not found or st.question_snapshot->>'sourceKind'<>'licensed_local'
   or st.question_snapshot->>'renderMode'<>'image_primary'
   or st.question_snapshot->>'revisionToken' is distinct from p_revision_token then return; end if;
 select asset.* into a from app_private.chem_question_assets asset where asset.asset_path=p_asset_path
   and asset.question_id=st.question_id and asset.asset_kind='question_image' for share;
 if not found or not exists (select 1 from jsonb_array_elements(st.question_snapshot->'assetRefs') ref
   where ref->>'path'=a.asset_path and ref->>'kind'=a.asset_kind and ref->>'sha256'=a.sha256
     and (ref->>'width')::integer=a.width and (ref->>'height')::integer=a.height) then return; end if;
 if st.answered_at is null then
   perform * from public.chem_junior_validate_issued_step(sess.id,p_student_id,st.id);
 end if;
 return query select st.question_id,st.answered_at is not null;
end;
$function$;
REVOKE ALL ON FUNCTION public.chem_junior_step_question_asset_context(uuid,uuid,uuid,text,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.chem_junior_step_question_asset_context(uuid,uuid,uuid,text,text) TO service_role;


CREATE OR REPLACE FUNCTION app_private.chem_junior_question_delivery_ready(p_question_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select case when exists(select 1 from public.chem_questions image_q where image_q.id=p_question_id and image_q.source_kind='licensed_local')
 then app_private.chem_junior_image_question_delivery_ready(p_question_id) else exists(
   select 1 from public.chem_questions q
   join app_private.chem_question_source_releases r on r.id=q.source_release_id
   where q.id=p_question_id and q.review_status='approved' and q.scope_status='IN' and q.usable_for_review
     and r.status='active' and r.verification_status='full_visual_verified'
     and r.manifest_sha256=r.verification_manifest_sha256
     and jsonb_typeof(q.options)='array' and jsonb_array_length(q.options)=4
     and q.correct_option between 0 and 3 and length(btrim(q.stem))>0 and length(btrim(q.explanation))>0
     and q.content_fingerprint is not null and q.source_item_key is not null
     and q.grade_band='初三' and q.source_kind='user_provided_local' and q.render_mode='native' and q.textbook_version='科粤版'
     and app_private.chem_question_item_delivery_review_ready(q.id)
     and not exists(select 1 from public.chem_question_delivery_holds_for(array[q.id]) h where h.question_id=q.id)
     and exists(select 1 from public.chem_junior_verified_provenance_rows('科粤版',array[q.knowledge_id]) p
       where p.knowledge_id=q.knowledge_id and p.source_release_id=q.source_release_id
         and p.verification_status='verified' and p.source_release_ready)
 ) end;
$function$;

CREATE OR REPLACE FUNCTION public.chem_junior_practice_pool(p_student_id uuid, p_plan_id uuid, p_session_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF chem_questions
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare plan public.chem_learning_plans%rowtype; sess public.chem_junior_daily_sessions%rowtype;
begin
 select * into plan from public.chem_learning_plans where id=p_plan_id and student_id=p_student_id
   and delivery_mode='junior_adaptive';
 if not found or not app_private.chem_junior_plan_date_allowed(p_plan_id,p_student_id)
 then raise exception 'junior practice pool plan unavailable'; end if;
 if p_session_id is not null then
   select * into sess from public.chem_junior_daily_sessions
   where id=p_session_id and student_id=p_student_id and plan_day_id=p_plan_id;
   if not found then raise exception 'junior practice pool session ownership mismatch'; end if;
 else
   -- The teacher requests the pool before loading the real session in parallel.
   -- Resolve it by the owned plan so old frozen policies are not reinterpreted.
   select * into sess from public.chem_junior_daily_sessions
   where student_id=p_student_id and plan_day_id=p_plan_id;
   if found then p_session_id:=sess.id; end if;
 end if;
 return query
 with recursive ready_skills as materialized (
   select c.skill_id from public.chem_junior_bound_knowledge_cards('科粤版',null) c
 ), held as materialized (
   select h.question_id from public.chem_question_delivery_holds_for(array(
     select q.id from public.chem_questions q where q.grade_band='初三' and q.textbook_version='科粤版' and q.usable_for_review)) h
 ), image_candidates as materialized (
   select image.id,((row_number() over(order by image.id)-1)/800)::bigint as batch_number
   from public.chem_questions image
   join ready_skills ready on ready.skill_id=image.knowledge_id
   where image.grade_band='初三' and image.textbook_version='科粤版' and image.source_kind='licensed_local'
     and image.render_mode='image_primary' and image.usable_for_review
     and not exists(select 1 from held where held.question_id=image.id)
 ), image_batches as materialized (
   select candidate.batch_number,array_agg(candidate.id order by candidate.id) as question_ids
   from image_candidates candidate group by candidate.batch_number
 ), image_proofs as materialized (
   select proof.* from image_batches batch
   cross join lateral public.chem_junior_image_question_context(batch.question_ids) proof
 ), eligible as materialized (
   select q.* from public.chem_questions q
   join ready_skills ready on ready.skill_id=q.knowledge_id
   join app_private.chem_junior_knowledge_provenance p
     on p.knowledge_id=q.knowledge_id and p.textbook_version='科粤版'
       and p.source_release_id=q.source_release_id and p.verification_status='verified'
   where q.grade_band='初三' and q.textbook_version='科粤版'
     and q.source_kind='user_provided_local' and q.review_status='approved'
     and q.scope_status='IN' and q.usable_for_review and q.render_mode='native'
     and not exists(select 1 from held where held.question_id=q.id)
   union all
   select q.* from public.chem_questions q
   join ready_skills ready on ready.skill_id=q.knowledge_id
   join image_proofs proof
     on proof.question_id=q.id and proof.revision_token=q.question_revision_token
   where q.grade_band='初三' and q.textbook_version='科粤版'
     and q.source_kind='licensed_local'
     and not exists(select 1 from held where held.question_id=q.id)
 ), seeds as (
   select q.id from eligible q where q.knowledge_id=any(plan.skill_ids)
   union
   select q.id from eligible q join public.chem_junior_session_steps st on st.question_id=q.id
     where st.session_id=p_session_id
   union
   select q.id from eligible q join app_private.chem_junior_option_branches b
     on q.id=b.anchor_question_id where b.student_id=p_student_id
   union
   select q.id from app_private.chem_junior_option_branches b
     cross join lateral jsonb_array_elements(b.candidates) c
     join eligible q on q.id=c->>'questionId' and q.question_revision_token=c->>'revisionToken'
     where b.student_id=p_student_id
 ), reachable(id,depth) as (
   select seeds.id,0 from seeds
   union
   select q.id,path.depth+1 from reachable path
   join eligible anchor on anchor.id=path.id
   join app_private.chem_option_practice_bindings b on b.anchor_question_id=anchor.id
     and b.anchor_revision_token=anchor.question_revision_token and b.review_status='verified'
   cross join lateral jsonb_array_elements(b.candidates) c
   join eligible q on q.id=c->>'questionId' and q.question_revision_token=c->>'revisionToken'
   where path.depth<3 and (case when p_session_id is null then plan.question_count=8 and plan.round_limit=4
     else sess.recovery_round_limit=3 end)
 )
 select q.* from eligible q where exists(select 1 from reachable r where r.id=q.id) order by q.id;
end;$function$;

CREATE OR REPLACE FUNCTION public.chem_junior_issue_step(p_session_id uuid, p_student_id uuid, p_question_id text, p_sequence smallint, p_route_kind text, p_route_reason text, p_question_snapshot jsonb)
 RETURNS TABLE(step_id uuid, question_id text, sequence smallint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_required_card_ids text[];
  v_session public.chem_junior_daily_sessions%rowtype;
  v_plan public.chem_learning_plans%rowtype;
  v_curriculum public.chem_junior_curriculum_days%rowtype;
  v_question public.chem_questions%rowtype;
  v_provenance app_private.chem_junior_knowledge_provenance%rowtype;
  v_release app_private.chem_question_source_releases%rowtype;
  v_snapshot jsonb;
  v_step_id uuid;
  v_existing_count integer;
  v_max_sequence integer;
  v_unanswered_count integer;
  v_profile_id uuid;
  v_required_knowledge_count integer;
  v_required_card_count integer;
  repetition_state jsonb;
begin
  if p_session_id is null
    or p_student_id is null
    or length(pg_catalog.btrim(coalesce(p_question_id, ''))) = 0
    or p_sequence is null
    or p_sequence not between 1 and 30
    or p_route_kind is null
    or p_route_kind not in (
      'spaced_review',
      'new_learning',
      'advance',
      'stability_validation',
      'foundation_repair',
      'prior_error_recovery'
    )
    or length(pg_catalog.btrim(coalesce(p_route_reason, ''))) not between 1 and 1000
    or pg_catalog.jsonb_typeof(p_question_snapshot) is distinct from 'object'
  then
    raise exception 'invalid junior step issue request';
  end if;

  -- Use the exact lifecycle lock order before touching a session or source
  -- row. Activation holds these transaction locks while retiring/enabling a
  -- batch, so issue cannot observe or persist a half-swapped release.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  -- The session row is the serialization point for issue, resume, answer and
  -- finalization.  A blocked/completed/future session therefore fails before
  -- any source payload could be returned.
  perform s.id from public.chem_students_v2 s where s.id=p_student_id for update;
  select session.*
  into v_session
  from public.chem_junior_daily_sessions as session
  where session.id = p_session_id
    and session.student_id = p_student_id
    and session.status = 'active'
    and app_private.chem_junior_plan_date_allowed(session.plan_day_id,p_student_id)
  for update;

  if not found
    or length(pg_catalog.btrim(coalesce(v_session.textbook_version, ''))) = 0
    or v_session.textbook_version = '待确认'
  then
    raise exception 'junior session is unavailable for question issue';
  end if;

  -- A session is only an execution snapshot of its immutable daily plan. Lock
  -- and reassert every authorization-bearing plan field before consulting the
  -- profile, curriculum, step history or any question-bearing table.
  select plan.*
  into v_plan
  from public.chem_learning_plans as plan
  where plan.id = v_session.plan_day_id
    and plan.student_id = v_session.student_id
    and plan.student_id = p_student_id
    and plan.delivery_mode = 'junior_adaptive'
    and plan.plan_date = v_session.study_date
    and app_private.chem_junior_plan_date_allowed(plan.id,p_student_id)
    and plan.junior_curriculum_day_id = v_session.curriculum_day_id
    and plan.skill_ids = v_session.knowledge_skill_ids
    and plan.mode = 'REVIEW'
    and plan.question_count = v_session.initial_question_target
    and plan.round_limit = 1 + v_session.recovery_round_limit
  for share;

  if not found then
    raise exception 'junior session plan contract changed before question issue';
  end if;

  select student.id
  into v_profile_id
  from public.chem_students_v2 as student
  where student.id = p_student_id
    and student.grade_band = '初三'
    and student.record_status = 'active'
    and student.textbook_version = v_session.textbook_version
  for share;

  if not found or v_profile_id is null then
    raise exception 'junior student textbook no longer matches the active session';
  end if;

  select curriculum.*
  into v_curriculum
  from public.chem_junior_curriculum_days as curriculum
  where curriculum.id = v_session.curriculum_day_id
    and curriculum.textbook_version = v_session.textbook_version
    and curriculum.release_status = 'ready'
    and curriculum.knowledge_skill_ids = v_session.knowledge_skill_ids
  for share;

  if not found
    or cardinality(v_session.knowledge_skill_ids) <> 3
    or (
      select count(distinct requested.skill_id)
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
    ) <> 3
  then
    raise exception 'junior curriculum day is no longer ready or does not match the session';
  end if;

  -- Lock every existing step after the session serialization lock.  The
  -- count/max/unanswered assertions make a stale concurrent selector retry
  -- through the independently validated resume path.
  perform existing.id
  from public.chem_junior_session_steps as existing
  where existing.session_id = p_session_id
  order by existing.sequence
  for share;

  select
    count(*)::integer,
    coalesce(max(existing.sequence), 0)::integer,
    (count(*) filter (where existing.answered_at is null))::integer
  into v_existing_count, v_max_sequence, v_unanswered_count
  from public.chem_junior_session_steps as existing
  where existing.session_id = p_session_id;

  if v_unanswered_count <> 0
    or p_sequence <> v_existing_count + 1
    or p_sequence <> v_max_sequence + 1
  then
    raise exception using
      errcode = '40001',
      message = 'junior issue sequence is stale';
  end if;
  if p_sequence > v_session.hard_question_cap then
    raise exception 'junior session hard question cap reached';
  end if;

  select question.*
  into v_question
  from public.chem_questions as question
  where question.id = p_question_id
  for share;

  if not found then
    raise exception 'junior question is unavailable for issue';
  end if;
  if not app_private.chem_junior_question_delivery_ready(v_question.id) then
    raise exception 'junior question is not ready for delivery';
  end if;

  if v_question.grade_band <> '初三'
    or v_question.textbook_version is distinct from v_session.textbook_version
    or v_question.review_status <> 'approved'
    or v_question.scope_status <> 'IN'
    or not v_question.usable_for_review
    or not ((v_question.source_kind='user_provided_local' and v_question.render_mode='native'
      and v_question.image_url is null and v_question.asset_refs='[]'::jsonb)
      or (v_question.source_kind='licensed_local' and v_question.render_mode='image_primary'
        and app_private.chem_junior_image_question_delivery_ready(v_question.id)))
    or v_question.skill_id is null
    or v_question.knowledge_id is null
    or v_question.skill_id <> v_question.knowledge_id
    or length(pg_catalog.btrim(coalesce(v_question.mother_id, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.same_type_key, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.source_item_key, ''))) < 16
    or length(pg_catalog.btrim(coalesce(app_private.chem_junior_parent_source_identity(v_question), ''))) < 16
    or coalesce(v_question.content_fingerprint, '') !~ '^[0-9a-f]{64}$'
    or coalesce(v_question.question_revision_token, '') !~ '^[0-9a-f]{64}$'
    or v_question.source_release_id is null
    or length(pg_catalog.btrim(coalesce(v_question.stem, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.explanation, ''))) = 0
  then
    raise exception 'junior question no longer satisfies the native source contract';
  end if;

  if pg_catalog.jsonb_typeof(v_question.options) is distinct from 'array' then
    raise exception 'junior question options are not an array';
  end if;
  if pg_catalog.jsonb_array_length(v_question.options) <> 4
    or v_question.correct_option < 0
    or v_question.correct_option > 3
  then
    raise exception 'junior question option contract is invalid';
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
    where pg_catalog.jsonb_typeof(option_value.value) is distinct from 'string'
      or length(pg_catalog.btrim(option_value.value #>> '{}')) = 0
  ) then
    raise exception 'junior question contains a non-text or empty option';
  end if;
  if (
    select count(distinct pg_catalog.btrim(option_value.value #>> '{}'))
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
  ) <> 4 then
    raise exception 'junior question contains duplicated options';
  end if;

  if v_session.repetition_policy='spaced_review' then
    repetition_state:=app_private.chem_junior_repetition_state(v_question,
      app_private.chem_junior_repetition_history(p_student_id),p_session_id,
      v_session.repetition_policy,(now() at time zone 'Asia/Shanghai')::date);
    if repetition_state->>'eligible' is distinct from 'true' then raise exception 'junior_question_not_due'; end if;
    if p_route_kind not in ('foundation_repair','prior_error_recovery') and
      ((repetition_state->>'kind'='due_review') is distinct from (p_route_kind='spaced_review'))
    then raise exception 'junior repeat must be explicitly labelled spaced_review'; end if;
  elsif p_route_kind='spaced_review' then
    raise exception 'junior session has not opted into spaced review';
  end if;

  -- Recompute both native-content digests while the question row is locked.
  -- A matching snapshot is insufficient if a privileged writer corrupted a
  -- revision token together with the content it is meant to bind.
  if v_question.content_fingerprint is distinct from
      app_private.chem_h3_content_fingerprint(v_question.stem, v_question.options)
    or v_question.question_revision_token is distinct from
      (case when v_question.source_kind='user_provided_local' then app_private.chem_junior_native_revision_sha256(v_question)
      else (select app_private.chem_h3_question_revision_sha256(v_question,p.sha256,a.sha256)
        from app_private.chem_question_assets p join app_private.chem_question_assets a on a.question_id=p.question_id
        where p.question_id=v_question.id and p.asset_kind='question_image' and a.asset_kind='analysis_image') end)
  then
    raise exception 'junior question content digest is stale';
  end if;

  if v_question.source_kind='user_provided_local' then
  select release.*
  into v_release
  from app_private.chem_question_source_releases as release
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  where release.id = v_question.source_release_id
    and release.grade_band = '初三'
    and release.textbook_version = v_session.textbook_version
    and release.status = 'active'
    and release.verification_status = 'full_visual_verified'
    and release.verification_manifest_sha256 = release.manifest_sha256
    and release.revision_contract = 'v3_junior_native_text'
    and release.verified_at is not null
    and length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
    and release.activated_at is not null
  for share of release, rights;

  if not found then
    raise exception 'junior source release is not active and fully verified';
  end if;

  select provenance.*
  into v_provenance
  from app_private.chem_junior_knowledge_provenance as provenance
  where provenance.textbook_version = v_session.textbook_version
    and provenance.knowledge_id = v_question.knowledge_id
    and provenance.source_release_id = v_question.source_release_id
    and provenance.verification_status = 'verified'
    and provenance.reviewed_at is not null
  for share;

  if not found then
    raise exception 'junior textbook knowledge provenance is not verified';
  end if;

  -- Every non-recovery route must stay inside the three locked curriculum
  -- skills. A recovery route, including one for a current-day skill, needs a
  -- real earlier completed error/uncertain answer of the same type and a new
  -- value for all five source identities.
  else
    perform app_private.chem_junior_lock_image_delivery_source(v_question.id,v_session.textbook_version);
  end if;

  if p_route_kind = 'prior_error_recovery' then
    perform prior_step.id
    from public.chem_junior_daily_sessions as prior_session
    join public.chem_junior_session_steps as prior_step
      on prior_step.session_id = prior_session.id
    where prior_session.student_id = p_student_id
      and prior_session.id <> p_session_id
      and prior_session.status = 'completed'
      and prior_session.textbook_version = v_session.textbook_version
      and prior_session.completed_at is not null
      and prior_session.completed_at < v_session.started_at
      and prior_step.answered_at is not null
      and (not prior_step.correct or prior_step.uncertain)
      and prior_step.knowledge_id = v_question.knowledge_id
      and prior_step.same_type_key = v_question.same_type_key
      and prior_step.question_id is distinct from v_question.id
      and prior_step.mother_id is distinct from v_question.mother_id
      and prior_step.source_item_key is distinct from v_question.source_item_key
      and prior_step.parent_source_item_key is distinct from app_private.chem_junior_parent_source_identity(v_question)
      and prior_step.content_fingerprint is distinct from v_question.content_fingerprint
    order by prior_session.completed_at desc, prior_step.sequence desc
    limit 1
    for share of prior_session, prior_step;

    if not found then
      raise exception 'junior recovery route has no matching prior error evidence';
    end if;
  elsif p_route_kind='foundation_repair' and app_private.chem_junior_frozen_recovery_allows(
    p_student_id,p_session_id,v_question.id,v_question.question_revision_token,null,
    coalesce(nullif(pg_catalog.current_setting('app.chem_junior_practice_round',true),''),'0')::smallint) then
    null; -- Only the exact next frozen wrong-option route may cross today's curriculum.
  elsif not (v_question.knowledge_id = any(v_session.knowledge_skill_ids)) then
    raise exception 'junior non-recovery question is outside the locked curriculum skills';
  end if;

  -- Lock and require exactly one approved knowledge card for every current
  -- curriculum skill and for the selected recovery skill, if it is outside
  -- the current three. This closes the Edge card-read/change race.
  -- Lock all versions for the required skills before checking the bound approved
  -- version once per skill. Approval/content changes cannot race the check.
  perform card.id from public.chem_knowledge_cards card
    join (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) requested(skill_id)) required_raw) required on required.skill_id=card.skill_id
    order by card.skill_id,card.id for share of card;
  select count(*)::integer,array_agg(app_private.chem_junior_ready_card_id(v_session.textbook_version,required.skill_id) order by required.skill_id)
    into v_required_knowledge_count,v_required_card_ids
  from (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) requested(skill_id)) required_raw) required;
  select count(*)::integer into v_required_card_count from unnest(v_required_card_ids) id where id is not null;

  if v_required_card_count <> v_required_knowledge_count then
    raise exception 'junior knowledge-card approval contract changed before issue';
  end if;

  v_snapshot := pg_catalog.jsonb_build_object(
    'questionId', v_question.id,
    'motherId', v_question.mother_id,
    'skillId', v_question.skill_id,
    'knowledgeId', v_question.knowledge_id,
    'conceptKey', v_question.concept_key,
    'level', v_question.level,
    'gradeBand', v_question.grade_band,
    'textbookVersion', v_question.textbook_version,
    'stem', v_question.stem,
    'options', v_question.options,
    'correctOption', v_question.correct_option,
    'explanation', v_question.explanation,
    'scaffold', v_question.scaffold,
    'reviewStatus', v_question.review_status,
    'scopeStatus', v_question.scope_status,
    'sourceKind', v_question.source_kind,
    'renderMode', v_question.render_mode,
    'imageUrl', v_question.image_url,
    'assetRefs', v_question.asset_refs,
    'sourceReleaseId', v_question.source_release_id,
    'sourceItemKey', v_question.source_item_key,
    'parentSourceItemKey', v_question.parent_source_item_key,
    'sameTypeKey', v_question.same_type_key,
    'contentFingerprint', v_question.content_fingerprint,
    'revisionToken', v_question.question_revision_token,
    'routeKind', p_route_kind,
    'routeReason', p_route_reason
  );

  if p_question_snapshot is distinct from v_snapshot then
    raise exception 'junior issue snapshot does not match the locked source question';
  end if;

  if exists (
    select 1
    from public.chem_junior_session_steps as existing
    where existing.session_id = p_session_id
      and (
        existing.question_id = v_question.id
        or existing.mother_id = v_question.mother_id
        or existing.source_item_key = v_question.source_item_key
        or existing.parent_source_item_key = app_private.chem_junior_parent_source_identity(v_question)
        or existing.content_fingerprint = v_question.content_fingerprint
      )
  ) then
    raise exception 'junior source identity was already issued in this session';
  end if;

  if v_session.recovery_round_limit=3 and p_sequence>v_session.initial_question_target and coalesce(nullif(pg_catalog.current_setting('app.chem_junior_practice_round',true),''),'0')::integer=0 then raise exception 'junior recovery must use the strict option queue'; end if;
  perform app_private.chem_junior_reserve_daily_question(p_student_id,'junior:'||p_session_id::text||':'||p_sequence::text);
  perform pg_catalog.set_config('app.chem_junior_step_issue', 'on', true);
  insert into public.chem_junior_session_steps (
    session_id,
    sequence,
    question_id,
    mother_id,
    skill_id,
    knowledge_id,
    same_type_key,
    source_item_key,
    parent_source_item_key,
    content_fingerprint,
    level,
    route_kind,
    route_reason,
    practice_round,
    question_snapshot
  ) values (
    p_session_id,
    p_sequence,
    v_question.id,
    v_question.mother_id,
    v_question.skill_id,
    v_question.knowledge_id,
    v_question.same_type_key,
    v_question.source_item_key,
    app_private.chem_junior_parent_source_identity(v_question),
    v_question.content_fingerprint,
    v_question.level,
    p_route_kind,
    p_route_reason,
    coalesce(nullif(pg_catalog.current_setting('app.chem_junior_practice_round',true),''),'0')::smallint,
    v_snapshot
  )
  returning id
  into v_step_id;
  perform pg_catalog.set_config('app.chem_junior_step_issue', 'off', true);

  return query select v_step_id, v_question.id, p_sequence;
end;
$function$;

CREATE OR REPLACE FUNCTION public.chem_junior_validate_issued_step(p_session_id uuid, p_student_id uuid, p_step_id uuid)
 RETURNS TABLE(step_id uuid, question_id text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_required_card_ids text[];
  v_session public.chem_junior_daily_sessions%rowtype;
  v_plan public.chem_learning_plans%rowtype;
  v_curriculum public.chem_junior_curriculum_days%rowtype;
  v_step public.chem_junior_session_steps%rowtype;
  v_question public.chem_questions%rowtype;
  v_provenance app_private.chem_junior_knowledge_provenance%rowtype;
  v_release app_private.chem_question_source_releases%rowtype;
  v_snapshot jsonb;
  v_profile_id uuid;
  v_unanswered_count integer;
  v_required_knowledge_count integer;
  v_required_card_count integer;
begin
  if p_session_id is null or p_student_id is null or p_step_id is null then
    raise exception 'invalid junior issued-step validation request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  perform s.id from public.chem_students_v2 s where s.id=p_student_id for update;
  select session.*
  into v_session
  from public.chem_junior_daily_sessions as session
  where session.id = p_session_id
    and session.student_id = p_student_id
    and session.status = 'active'
    and app_private.chem_junior_plan_date_allowed(session.plan_day_id,p_student_id)
  for update;

  if not found
    or length(pg_catalog.btrim(coalesce(v_session.textbook_version, ''))) = 0
    or v_session.textbook_version = '待确认'
  then
    raise exception 'junior session is unavailable for resume';
  end if;

  -- Resume is a disclosure path too. A previously issued payload remains
  -- unavailable unless the locked plan is still the exact parent snapshot of
  -- the active session.
  select plan.*
  into v_plan
  from public.chem_learning_plans as plan
  where plan.id = v_session.plan_day_id
    and plan.student_id = v_session.student_id
    and plan.student_id = p_student_id
    and plan.delivery_mode = 'junior_adaptive'
    and plan.plan_date = v_session.study_date
    and app_private.chem_junior_plan_date_allowed(plan.id,p_student_id)
    and plan.junior_curriculum_day_id = v_session.curriculum_day_id
    and plan.skill_ids = v_session.knowledge_skill_ids
    and plan.mode = 'REVIEW'
    and plan.question_count = v_session.initial_question_target
    and plan.round_limit = 1 + v_session.recovery_round_limit
  for share;

  if not found then
    raise exception 'junior session plan contract changed before resume';
  end if;

  select student.id
  into v_profile_id
  from public.chem_students_v2 as student
  where student.id = p_student_id
    and student.grade_band = '初三'
    and student.record_status = 'active'
    and student.textbook_version = v_session.textbook_version
  for share;

  if not found or v_profile_id is null then
    raise exception 'junior student textbook no longer matches the active session';
  end if;

  select curriculum.*
  into v_curriculum
  from public.chem_junior_curriculum_days as curriculum
  where curriculum.id = v_session.curriculum_day_id
    and curriculum.textbook_version = v_session.textbook_version
    and curriculum.release_status = 'ready'
    and curriculum.knowledge_skill_ids = v_session.knowledge_skill_ids
  for share;

  if not found
    or cardinality(v_session.knowledge_skill_ids) <> 3
    or (
      select count(distinct requested.skill_id)
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
    ) <> 3
  then
    raise exception 'junior curriculum day is no longer ready or does not match the session';
  end if;

  select step.*
  into v_step
  from public.chem_junior_session_steps as step
  where step.id = p_step_id
    and step.session_id = p_session_id
  for share;

  if not found
    or v_step.answered_at is not null
    or v_step.selected_option is not null
    or v_step.uncertain is not null
    or v_step.duration_sec is not null
    or v_step.correct is not null
    or v_step.sequence not between 1 and v_session.hard_question_cap
  then
    raise exception 'junior issued step is unavailable for resume';
  end if;

  select (count(*) filter (where step.answered_at is null))::integer
  into v_unanswered_count
  from public.chem_junior_session_steps as step
  where step.session_id = p_session_id;

  if v_unanswered_count <> 1 then
    raise exception 'junior session does not have exactly one resumable step';
  end if;

  select question.*
  into v_question
  from public.chem_questions as question
  where question.id = v_step.question_id
  for share;

  if not found then
    raise exception 'junior issued question is unavailable';
  end if;
  if not app_private.chem_junior_question_delivery_ready(v_question.id) then
    raise exception 'junior issued question is not ready for delivery';
  end if;

  if v_question.grade_band <> '初三'
    or v_question.textbook_version is distinct from v_session.textbook_version
    or v_question.review_status <> 'approved'
    or v_question.scope_status <> 'IN'
    or not v_question.usable_for_review
    or not ((v_question.source_kind='user_provided_local' and v_question.render_mode='native'
      and v_question.image_url is null and v_question.asset_refs='[]'::jsonb)
      or (v_question.source_kind='licensed_local' and v_question.render_mode='image_primary'
        and app_private.chem_junior_image_question_delivery_ready(v_question.id)))
    or v_question.skill_id is null
    or v_question.knowledge_id is null
    or v_question.skill_id <> v_question.knowledge_id
    or length(pg_catalog.btrim(coalesce(v_question.mother_id, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.same_type_key, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.source_item_key, ''))) < 16
    or length(pg_catalog.btrim(coalesce(app_private.chem_junior_parent_source_identity(v_question), ''))) < 16
    or coalesce(v_question.content_fingerprint, '') !~ '^[0-9a-f]{64}$'
    or coalesce(v_question.question_revision_token, '') !~ '^[0-9a-f]{64}$'
    or v_question.source_release_id is null
    or length(pg_catalog.btrim(coalesce(v_question.stem, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.explanation, ''))) = 0
  then
    raise exception 'junior issued question no longer satisfies the native source contract';
  end if;

  if pg_catalog.jsonb_typeof(v_question.options) is distinct from 'array' then
    raise exception 'junior issued question options are not an array';
  end if;
  if pg_catalog.jsonb_array_length(v_question.options) <> 4
    or v_question.correct_option < 0
    or v_question.correct_option > 3
  then
    raise exception 'junior issued question option contract is invalid';
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
    where pg_catalog.jsonb_typeof(option_value.value) is distinct from 'string'
      or length(pg_catalog.btrim(option_value.value #>> '{}')) = 0
  ) then
    raise exception 'junior issued question contains a non-text or empty option';
  end if;
  if (
    select count(distinct pg_catalog.btrim(option_value.value #>> '{}'))
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
  ) <> 4 then
    raise exception 'junior issued question contains duplicated options';
  end if;

  if v_question.content_fingerprint is distinct from
      app_private.chem_h3_content_fingerprint(v_question.stem, v_question.options)
    or v_question.question_revision_token is distinct from
      (case when v_question.source_kind='user_provided_local' then app_private.chem_junior_native_revision_sha256(v_question)
      else (select app_private.chem_h3_question_revision_sha256(v_question,p.sha256,a.sha256)
        from app_private.chem_question_assets p join app_private.chem_question_assets a on a.question_id=p.question_id
        where p.question_id=v_question.id and p.asset_kind='question_image' and a.asset_kind='analysis_image') end)
  then
    raise exception 'junior issued question content digest is stale';
  end if;

  if v_question.source_kind='user_provided_local' then
  select release.*
  into v_release
  from app_private.chem_question_source_releases as release
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  where release.id = v_question.source_release_id
    and release.grade_band = '初三'
    and release.textbook_version = v_session.textbook_version
    and release.status = 'active'
    and release.verification_status = 'full_visual_verified'
    and release.verification_manifest_sha256 = release.manifest_sha256
    and release.revision_contract = 'v3_junior_native_text'
    and release.verified_at is not null
    and length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
    and release.activated_at is not null
  for share of release, rights;

  if not found then
    raise exception 'junior issued source release is no longer active and verified';
  end if;

  select provenance.*
  into v_provenance
  from app_private.chem_junior_knowledge_provenance as provenance
  where provenance.textbook_version = v_session.textbook_version
    and provenance.knowledge_id = v_question.knowledge_id
    and provenance.source_release_id = v_question.source_release_id
    and provenance.verification_status = 'verified'
    and provenance.reviewed_at is not null
  for share;

  if not found then
    raise exception 'junior issued textbook provenance is no longer verified';
  end if;

  else
    perform app_private.chem_junior_lock_image_delivery_source(v_question.id,v_session.textbook_version);
  end if;

  if v_step.route_kind = 'prior_error_recovery' then
    perform prior_step.id
    from public.chem_junior_daily_sessions as prior_session
    join public.chem_junior_session_steps as prior_step
      on prior_step.session_id = prior_session.id
    where prior_session.student_id = p_student_id
      and prior_session.id <> p_session_id
      and prior_session.status = 'completed'
      and prior_session.textbook_version = v_session.textbook_version
      and prior_session.completed_at is not null
      and prior_session.completed_at < v_session.started_at
      and prior_step.answered_at is not null
      and (not prior_step.correct or prior_step.uncertain)
      and prior_step.knowledge_id = v_question.knowledge_id
      and prior_step.same_type_key = v_question.same_type_key
      and prior_step.question_id is distinct from v_question.id
      and prior_step.mother_id is distinct from v_question.mother_id
      and prior_step.source_item_key is distinct from v_question.source_item_key
      and prior_step.parent_source_item_key is distinct from app_private.chem_junior_parent_source_identity(v_question)
      and prior_step.content_fingerprint is distinct from v_question.content_fingerprint
    order by prior_session.completed_at desc, prior_step.sequence desc
    limit 1
    for share of prior_session, prior_step;

    if not found then
      raise exception 'junior issued recovery step no longer has prior error evidence';
    end if;
  elsif v_step.route_kind='foundation_repair' and app_private.chem_junior_frozen_recovery_allows(
    p_student_id,p_session_id,v_question.id,v_question.question_revision_token,v_step.id,v_step.practice_round) then
    null;
  elsif not (v_question.knowledge_id = any(v_session.knowledge_skill_ids)) then
    raise exception 'junior issued non-recovery step is outside the locked curriculum skills';
  end if;

  -- Lock all versions for the required skills before checking the bound approved
  -- version once per skill. Approval/content changes cannot race the check.
  perform card.id from public.chem_knowledge_cards card
    join (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) requested(skill_id)) required_raw) required on required.skill_id=card.skill_id
    order by card.skill_id,card.id for share of card;
  select count(*)::integer,array_agg(app_private.chem_junior_ready_card_id(v_session.textbook_version,required.skill_id) order by required.skill_id)
    into v_required_knowledge_count,v_required_card_ids
  from (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) requested(skill_id)) required_raw) required;
  select count(*)::integer into v_required_card_count from unnest(v_required_card_ids) id where id is not null;

  if v_required_card_count <> v_required_knowledge_count then
    raise exception 'junior knowledge-card approval contract changed before resume';
  end if;

  v_snapshot := pg_catalog.jsonb_build_object(
    'questionId', v_question.id,
    'motherId', v_question.mother_id,
    'skillId', v_question.skill_id,
    'knowledgeId', v_question.knowledge_id,
    'conceptKey', v_question.concept_key,
    'level', v_question.level,
    'gradeBand', v_question.grade_band,
    'textbookVersion', v_question.textbook_version,
    'stem', v_question.stem,
    'options', v_question.options,
    'correctOption', v_question.correct_option,
    'explanation', v_question.explanation,
    'scaffold', v_question.scaffold,
    'reviewStatus', v_question.review_status,
    'scopeStatus', v_question.scope_status,
    'sourceKind', v_question.source_kind,
    'renderMode', v_question.render_mode,
    'imageUrl', v_question.image_url,
    'assetRefs', v_question.asset_refs,
    'sourceReleaseId', v_question.source_release_id,
    'sourceItemKey', v_question.source_item_key,
    'parentSourceItemKey', v_question.parent_source_item_key,
    'sameTypeKey', v_question.same_type_key,
    'contentFingerprint', v_question.content_fingerprint,
    'revisionToken', v_question.question_revision_token,
    'routeKind', v_step.route_kind,
    'routeReason', v_step.route_reason
  );

  if v_step.question_id is distinct from v_question.id
    or v_step.mother_id is distinct from v_question.mother_id
    or v_step.skill_id is distinct from v_question.skill_id
    or v_step.knowledge_id is distinct from v_question.knowledge_id
    or v_step.same_type_key is distinct from v_question.same_type_key
    or v_step.source_item_key is distinct from v_question.source_item_key
    or v_step.parent_source_item_key is distinct from app_private.chem_junior_parent_source_identity(v_question)
    or v_step.content_fingerprint is distinct from v_question.content_fingerprint
    or v_step.level is distinct from v_question.level
    or v_step.question_snapshot is distinct from v_snapshot
  then
    raise exception 'junior issued step no longer matches its locked source snapshot';
  end if;

  perform app_private.chem_junior_reserve_daily_question(p_student_id,'junior:'||p_session_id::text||':'||v_step.sequence::text);
  return query select v_step.id, v_question.id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.chem_junior_record_step(p_session_id uuid, p_student_id uuid, p_step_id uuid, p_selected_option smallint, p_uncertain boolean, p_duration_sec integer, p_revision_token text)
 RETURNS TABLE(step_id uuid, question_id text, selected_option smallint, uncertain boolean, duration_sec integer, correct boolean, answered_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_required_card_ids text[];
  v_session public.chem_junior_daily_sessions%rowtype;
  v_plan public.chem_learning_plans%rowtype;
  v_curriculum public.chem_junior_curriculum_days%rowtype;
  v_step public.chem_junior_session_steps%rowtype;
  v_question public.chem_questions%rowtype;
  v_provenance app_private.chem_junior_knowledge_provenance%rowtype;
  v_release app_private.chem_question_source_releases%rowtype;
  v_snapshot jsonb;
  v_profile_id uuid;
  v_required_knowledge_count integer;
  v_required_card_count integer;
  v_correct boolean;
  v_duration integer;
begin
  if p_session_id is null
    or p_student_id is null
    or p_step_id is null
    or p_selected_option is null
    or p_uncertain is null
    or p_duration_sec is null
    or p_duration_sec < 0
    or p_duration_sec > 3600 then
    raise exception 'invalid junior step answer';
  end if;

  -- Match activation/issue lock order.  The source locks prevent a release
  -- swap while an answer is being authorized; the session row then
  -- serializes issue, resume, answer and finalization for this learner.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  perform s.id from public.chem_students_v2 s where s.id=p_student_id for update;
  select session.*
  into v_session
  from public.chem_junior_daily_sessions as session
  where session.id = p_session_id
    and session.student_id = p_student_id
    and session.status = 'active'
    and app_private.chem_junior_plan_date_allowed(session.plan_day_id,p_student_id)
  for update;

  if not found
    or pg_catalog.length(pg_catalog.btrim(coalesce(v_session.textbook_version, ''))) = 0
    or v_session.textbook_version = '待确认'
  then
    raise exception 'junior session step is unavailable';
  end if;

  -- The session is only an execution snapshot.  Re-lock and reassert its
  -- complete parent-plan authorization before reading a mutable profile,
  -- curriculum/card approval or any source-bearing row.
  select plan.*
  into v_plan
  from public.chem_learning_plans as plan
  where plan.id = v_session.plan_day_id
    and plan.student_id = v_session.student_id
    and plan.student_id = p_student_id
    and plan.delivery_mode = 'junior_adaptive'
    and plan.plan_date = v_session.study_date
    and app_private.chem_junior_plan_date_allowed(plan.id,p_student_id)
    and plan.junior_curriculum_day_id = v_session.curriculum_day_id
    and plan.skill_ids = v_session.knowledge_skill_ids
    and plan.mode = 'REVIEW'
    and plan.question_count = v_session.initial_question_target
    and plan.round_limit = 1 + v_session.recovery_round_limit
  for share;

  if not found then
    raise exception 'junior session plan contract changed before answer recording';
  end if;

  select student.id
  into v_profile_id
  from public.chem_students_v2 as student
  where student.id = p_student_id
    and student.grade_band = '初三'
    and student.record_status = 'active'
    and student.textbook_version = v_session.textbook_version
  for share;

  if not found or v_profile_id is null then
    raise exception 'junior student textbook no longer matches the active session';
  end if;

  select curriculum.*
  into v_curriculum
  from public.chem_junior_curriculum_days as curriculum
  where curriculum.id = v_session.curriculum_day_id
    and curriculum.textbook_version = v_session.textbook_version
    and curriculum.release_status = 'ready'
    and curriculum.knowledge_skill_ids = v_session.knowledge_skill_ids
  for share;

  if not found
    or cardinality(v_session.knowledge_skill_ids) <> 3
    or (
      select count(distinct requested.skill_id)
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
    ) <> 3
  then
    raise exception 'junior curriculum day is no longer ready or does not match the session';
  end if;

  -- The session lock makes this required-skill set stable even though the
  -- step rows are deliberately not locked until after the cards.  Include
  -- recovery knowledge outside today's three and require one, not merely at
  -- least one, approved card for every required skill.
  -- Lock all versions for the required skills before checking the bound approved
  -- version once per skill. Approval/content changes cannot race the check.
  perform card.id from public.chem_knowledge_cards card
    join (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids) requested(skill_id)
      union all select st.knowledge_id from public.chem_junior_session_steps st where st.session_id=p_session_id) required_raw) required on required.skill_id=card.skill_id
    order by card.skill_id,card.id for share of card;
  select count(*)::integer,array_agg(app_private.chem_junior_ready_card_id(v_session.textbook_version,required.skill_id) order by required.skill_id)
    into v_required_knowledge_count,v_required_card_ids
  from (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids) requested(skill_id)
      union all select st.knowledge_id from public.chem_junior_session_steps st where st.session_id=p_session_id) required_raw) required;
  select count(*)::integer into v_required_card_count from unnest(v_required_card_ids) id where id is not null;

  if v_required_card_count <> v_required_knowledge_count then
    raise exception 'junior knowledge-card approval contract changed before answer recording';
  end if;

  -- Lock source-bearing rows only after all current authorization rows.  The
  -- separate statements make the step -> question -> provenance -> release
  -- order explicit and keep every source/snapshot gate ahead of writes.
  select step.*
  into v_step
  from public.chem_junior_session_steps as step
  where step.id = p_step_id
    and step.session_id = p_session_id
  for update;

  if not found then
    raise exception 'junior session step is unavailable';
  end if;
  if v_step.answered_at is not null then
    raise exception 'junior session step is already locked';
  end if;

  select question.*
  into v_question
  from public.chem_questions as question
  where question.id = v_step.question_id
  for share;

  if not found then
    raise exception 'junior source question is unavailable';
  end if;
  if not app_private.chem_junior_question_delivery_ready(v_question.id) then
    raise exception 'junior source question is not ready for an answer';
  end if;

  if v_question.grade_band is distinct from '初三'
    or v_question.textbook_version is distinct from v_session.textbook_version
    or v_question.review_status is distinct from 'approved'
    or v_question.scope_status is distinct from 'IN'
    or v_question.usable_for_review is distinct from true
    or not ((v_question.source_kind='user_provided_local' and v_question.render_mode='native'
      and v_question.image_url is null and v_question.asset_refs='[]'::jsonb)
      or (v_question.source_kind='licensed_local' and v_question.render_mode='image_primary'
        and app_private.chem_junior_image_question_delivery_ready(v_question.id)))
    or v_question.skill_id is distinct from v_step.skill_id
    or v_question.knowledge_id is distinct from v_step.knowledge_id
    or v_question.skill_id is distinct from v_question.knowledge_id
    or v_question.mother_id is distinct from v_step.mother_id
    or v_question.same_type_key is distinct from v_step.same_type_key
    or v_question.source_item_key is distinct from v_step.source_item_key
    or app_private.chem_junior_parent_source_identity(v_question) is distinct from v_step.parent_source_item_key
    or v_question.content_fingerprint is distinct from v_step.content_fingerprint
    or v_question.level is distinct from v_step.level
    or v_question.source_release_id is null
    or pg_catalog.length(pg_catalog.btrim(coalesce(v_question.stem, ''))) = 0
    or pg_catalog.length(pg_catalog.btrim(coalesce(v_question.explanation, ''))) = 0
  then
    raise exception 'junior question no longer satisfies the native source contract';
  end if;

  if pg_catalog.jsonb_typeof(v_question.options) is distinct from 'array' then
    raise exception 'junior question options are not an array';
  end if;
  if pg_catalog.jsonb_array_length(v_question.options) <> 4
    or v_question.correct_option not between 0 and 3
  then
    raise exception 'junior question option contract is invalid';
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
    where pg_catalog.jsonb_typeof(option_value.value) is distinct from 'string'
      or pg_catalog.length(pg_catalog.btrim(option_value.value #>> '{}')) = 0
  ) then
    raise exception 'junior question contains a non-text or empty option';
  end if;
  if (
    select count(distinct pg_catalog.btrim(option_value.value #>> '{}'))
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
  ) <> 4 then
    raise exception 'junior question contains duplicated options';
  end if;

  if v_question.content_fingerprint is distinct from
      app_private.chem_h3_content_fingerprint(v_question.stem, v_question.options)
    or v_question.question_revision_token is distinct from
      (case when v_question.source_kind='user_provided_local' then app_private.chem_junior_native_revision_sha256(v_question)
      else (select app_private.chem_h3_question_revision_sha256(v_question,p.sha256,a.sha256)
        from app_private.chem_question_assets p join app_private.chem_question_assets a on a.question_id=p.question_id
        where p.question_id=v_question.id and p.asset_kind='question_image' and a.asset_kind='analysis_image') end)
  then
    raise exception 'junior question content digest is stale';
  end if;

  if v_question.source_kind='user_provided_local' then
  select provenance.*
  into v_provenance
  from app_private.chem_junior_knowledge_provenance as provenance
  where provenance.textbook_version = v_session.textbook_version
    and provenance.knowledge_id = v_step.knowledge_id
    and provenance.source_release_id = v_question.source_release_id
    and provenance.verification_status = 'verified'
    and provenance.reviewed_at is not null
  for share;

  if not found then
    raise exception 'junior textbook knowledge provenance is not verified';
  end if;

  select release.*
  into v_release
  from app_private.chem_question_source_releases as release
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  where release.id = v_question.source_release_id
    and release.id = v_provenance.source_release_id
    and release.grade_band = '初三'
    and release.textbook_version = v_session.textbook_version
    and release.status = 'active'
    and release.verification_status = 'full_visual_verified'
    and release.verification_manifest_sha256 = release.manifest_sha256
    and release.revision_contract = 'v3_junior_native_text'
    and release.verified_at is not null
    and pg_catalog.length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
    and release.activated_at is not null
  for share of release, rights;

  if not found then
    raise exception 'junior source release is not active and fully verified';
  end if;

  else
    perform app_private.chem_junior_lock_image_delivery_source(v_question.id,v_session.textbook_version);
  end if;

  v_snapshot := pg_catalog.jsonb_build_object(
    'questionId', v_question.id,
    'motherId', v_question.mother_id,
    'skillId', v_question.skill_id,
    'knowledgeId', v_question.knowledge_id,
    'conceptKey', v_question.concept_key,
    'level', v_question.level,
    'gradeBand', v_question.grade_band,
    'textbookVersion', v_question.textbook_version,
    'stem', v_question.stem,
    'options', v_question.options,
    'correctOption', v_question.correct_option,
    'explanation', v_question.explanation,
    'scaffold', v_question.scaffold,
    'reviewStatus', v_question.review_status,
    'scopeStatus', v_question.scope_status,
    'sourceKind', v_question.source_kind,
    'renderMode', v_question.render_mode,
    'imageUrl', v_question.image_url,
    'assetRefs', v_question.asset_refs,
    'sourceReleaseId', v_question.source_release_id,
    'sourceItemKey', v_question.source_item_key,
    'parentSourceItemKey', v_question.parent_source_item_key,
    'sameTypeKey', v_question.same_type_key,
    'contentFingerprint', v_question.content_fingerprint,
    'revisionToken', v_question.question_revision_token,
    'routeKind', v_step.route_kind,
    'routeReason', v_step.route_reason
  );

  if v_step.question_snapshot is distinct from v_snapshot
    or coalesce(v_step.question_snapshot ->> 'revisionToken', '')
      <> coalesce(v_question.question_revision_token, '')
  then
    raise exception 'junior immutable question snapshot changed';
  end if;
  if p_selected_option not between 0 and 3 then
    raise exception 'junior selected option is outside the immutable option set';
  end if;
  if v_question.question_revision_token is distinct from p_revision_token then
    raise exception 'junior source question revision changed';
  end if;

  perform app_private.chem_junior_reserve_daily_question(p_student_id,'junior:'||p_session_id::text||':'||v_step.sequence::text);
  v_duration := least(3600, greatest(0, p_duration_sec));
  v_correct := p_selected_option = v_question.correct_option;

  perform pg_catalog.set_config('app.chem_junior_step_answer', 'on', true);
  update public.chem_junior_session_steps as updated
  set selected_option = p_selected_option,
      uncertain = p_uncertain,
      duration_sec = v_duration,
      correct = v_correct,
      answered_at = now(),
      updated_at = now()
  where updated.id = p_step_id
  returning
    updated.id,
    updated.question_id,
    updated.selected_option,
    updated.uncertain,
    updated.duration_sec,
    updated.correct,
    updated.answered_at
  into
    step_id,
    question_id,
    selected_option,
    uncertain,
    duration_sec,
    correct,
    answered_at;
  perform pg_catalog.set_config('app.chem_junior_step_answer', 'off', true);

  insert into public.chem_student_skill_state (
    student_id,
    skill_id,
    stability,
    consecutive_errors,
    next_review_at,
    last_reviewed_at,
    teacher_intervention,
    updated_at
  ) values (
    p_student_id,
    v_step.skill_id,
    'learning',
    case when v_correct and not p_uncertain then 0 else 1 end,
    now() + interval '1 day',
    now(),
    false,
    now()
  )
  on conflict (student_id, skill_id) do update set
    stability = 'learning',
    consecutive_errors = case
      when v_correct and not p_uncertain
        then public.chem_student_skill_state.consecutive_errors
      else public.chem_student_skill_state.consecutive_errors + 1
    end,
    next_review_at = least(
      coalesce(public.chem_student_skill_state.next_review_at, now() + interval '1 day'),
      now() + interval '1 day'
    ),
    last_reviewed_at = now(),
    teacher_intervention = public.chem_student_skill_state.teacher_intervention
      or (
        (not v_correct or p_uncertain)
        and public.chem_student_skill_state.consecutive_errors + 1 >= 3
      ),
    updated_at = now();

  return next;
end;
$function$;

CREATE OR REPLACE FUNCTION public.chem_junior_finalize_session(p_session_id uuid, p_student_id uuid)
 RETURNS TABLE(completed boolean, total_questions integer, correct_questions integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_required_card_ids text[];
  v_session public.chem_junior_daily_sessions%rowtype;
  v_plan public.chem_learning_plans%rowtype;
  v_curriculum public.chem_junior_curriculum_days%rowtype;
  v_plan_mode text;
  v_profile_id uuid;
  v_total integer;
  v_answered integer;
  v_correct integer;
  v_attempt_id uuid;
  v_answer_ledger_count integer;
  v_completed_at timestamptz;
  v_required_skill_count integer;
  v_required_card_count integer;
  v_verified_provenance_count integer;
  v_current_contract_count integer;
begin
  if p_session_id is null or p_student_id is null then
    raise exception 'invalid junior session finalization';
  end if;

  -- Use the same global lifecycle locks as activation, issue, validation and
  -- answer recording before taking the per-session serialization lock.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  -- Reconcile the private first-option queue before deriving mastery. The
  -- original 12/15, source-rights and exact-snapshot checks below are unchanged.
  perform public.chem_junior_option_state(p_student_id,p_session_id);

  perform s.id from public.chem_students_v2 s where s.id=p_student_id for update;
  select session.*
  into v_session
  from public.chem_junior_daily_sessions as session
  where session.id = p_session_id
    and session.student_id = p_student_id
    and session.status in ('active', 'completed')
    and app_private.chem_junior_plan_date_allowed(session.plan_day_id,p_student_id)
  for update;

  if not found
    or pg_catalog.length(pg_catalog.btrim(coalesce(v_session.textbook_version, ''))) = 0
    or v_session.textbook_version = '待确认'
  then
    raise exception 'junior session is unavailable';
  end if;

  -- Re-lock the complete authorization snapshot before touching steps or an
  -- existing attempt.  Even an idempotent retry must prove that the current
  -- plan/profile/curriculum/card contract still authorizes this student.
  select plan.*
  into v_plan
  from public.chem_learning_plans as plan
  where plan.id = v_session.plan_day_id
    and plan.student_id = v_session.student_id
    and plan.student_id = p_student_id
    and plan.delivery_mode = 'junior_adaptive'
    and plan.plan_date = v_session.study_date
    and app_private.chem_junior_plan_date_allowed(plan.id,p_student_id)
    and plan.junior_curriculum_day_id = v_session.curriculum_day_id
    and plan.skill_ids = v_session.knowledge_skill_ids
    and plan.mode = 'REVIEW'
    and plan.question_count = v_session.initial_question_target
    and plan.round_limit = 1 + v_session.recovery_round_limit
  for share;

  if not found then
    raise exception 'junior session plan contract changed before finalization';
  end if;
  v_plan_mode := v_plan.mode;

  select student.id
  into v_profile_id
  from public.chem_students_v2 as student
  where student.id = p_student_id
    and student.grade_band = '初三'
    and student.record_status = 'active'
    and student.textbook_version = v_session.textbook_version
  for share;

  if not found or v_profile_id is null then
    raise exception 'junior student textbook no longer matches the session';
  end if;

  select curriculum.*
  into v_curriculum
  from public.chem_junior_curriculum_days as curriculum
  where curriculum.id = v_session.curriculum_day_id
    and curriculum.textbook_version = v_session.textbook_version
    and curriculum.release_status = 'ready'
    and curriculum.knowledge_skill_ids = v_session.knowledge_skill_ids
  for share;

  if not found
    or cardinality(v_session.knowledge_skill_ids) <> 3
    or (
      select count(distinct requested.skill_id)
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
    ) <> 3
  then
    raise exception 'junior curriculum day is no longer ready or does not match the session';
  end if;

  -- The locked session makes the union stable before step locks are taken.
  -- It includes the current three skills plus every actual recovery skill.
  -- Row locks precede every approval/hash decision, including all actual
  -- recovery skills. Hash the bound version only once per required skill.
  perform card.id from public.chem_knowledge_cards card
    join (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids) requested(skill_id)
      union all select existing.knowledge_id from public.chem_junior_session_steps existing where existing.session_id=p_session_id) raw_required) required on required.skill_id=card.skill_id
    order by card.skill_id,card.id for share of card;
  select count(*)::integer,array_agg(app_private.chem_junior_ready_card_id(v_session.textbook_version,required.skill_id) order by required.skill_id)
    into v_required_skill_count,v_required_card_ids from (select distinct skill_id from (select requested.skill_id from unnest(v_session.knowledge_skill_ids) requested(skill_id)
      union all select existing.knowledge_id from public.chem_junior_session_steps existing where existing.session_id=p_session_id) raw_required) required;
  select count(*)::integer into v_required_card_count
    from unnest(v_required_card_ids) card_id where card_id is not null;

  if v_required_card_count <> v_required_skill_count then
    raise exception 'junior knowledge-card approval contract changed before finalization';
  end if;

  -- Lock all issued steps, then their question, provenance and release rows in
  -- that order.  The following validation reads only rows held by these locks.
  perform step.id
  from public.chem_junior_session_steps as step
  where step.session_id = p_session_id
  order by step.sequence
  for update;

  select
    count(*)::integer,
    (count(*) filter (where step.answered_at is not null))::integer,
    (count(*) filter (where step.correct))::integer
  into v_total, v_answered, v_correct
  from public.chem_junior_session_steps as step
  where step.session_id = p_session_id;

  if v_total not between v_session.initial_question_target and v_session.hard_question_cap
    or v_answered <> v_total then
    raise exception 'junior session is not ready to finalize';
  end if;

  perform question.id
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id
  where step.session_id = p_session_id
  order by question.id
  for share of question;

  perform provenance.knowledge_id
  from app_private.chem_junior_knowledge_provenance as provenance
  join (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required
    on required.skill_id = provenance.knowledge_id
  where provenance.textbook_version = v_session.textbook_version
  order by provenance.knowledge_id
  for share of provenance;

  perform release.id
  from app_private.chem_question_source_releases as release
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  where release.id in (
    select provenance.source_release_id
    from app_private.chem_junior_knowledge_provenance as provenance
    where provenance.textbook_version = v_session.textbook_version
      and provenance.knowledge_id in (
        select required.skill_id
        from (
          select requested.skill_id
          from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
          union
          select existing.knowledge_id
          from public.chem_junior_session_steps as existing
          where existing.session_id = p_session_id
        ) as required
      )
    union
    select question.source_release_id
    from public.chem_junior_session_steps as step
    join public.chem_questions as question
      on question.id = step.question_id
    where step.session_id = p_session_id
  )
  order by release.id
  for share of release, rights;

  -- Every current or recovery knowledge route must still resolve to one
  -- verified provenance row on an active, fully verified native release.
  perform provenance.knowledge_id
  from (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required
  join app_private.chem_junior_knowledge_provenance as provenance
    on provenance.textbook_version = v_session.textbook_version
   and provenance.knowledge_id = required.skill_id
   and provenance.verification_status = 'verified'
   and provenance.reviewed_at is not null
  join app_private.chem_question_source_releases as release
    on release.id = provenance.source_release_id
   and release.grade_band = '初三'
   and release.textbook_version = v_session.textbook_version
   and release.status = 'active'
   and release.verification_status = 'full_visual_verified'
   and release.verification_manifest_sha256 = release.manifest_sha256
   and release.revision_contract = 'v3_junior_native_text'
   and release.verified_at is not null
   and pg_catalog.length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
   and release.activated_at is not null
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0;
  get diagnostics v_verified_provenance_count = row_count;
  if v_verified_provenance_count <> v_required_skill_count then
    raise exception 'junior verified provenance is no longer active';
  end if;

  perform app_private.chem_junior_lock_image_delivery_source(q.id,v_session.textbook_version)
  from public.chem_junior_session_steps st join public.chem_questions q on q.id=st.question_id
  where st.session_id=p_session_id and q.source_kind='licensed_local';

  -- Revalidate every original and its exact issue snapshot while all source
  -- rows remain locked.  The CASE wrappers keep malformed JSON fail-closed
  -- without invoking array functions on a non-array value.
  with session_original_ids as materialized (
    select distinct st.question_id from public.chem_junior_session_steps st
    where st.session_id=p_session_id and st.answered_at is not null
  ), ready_original_ids as materialized (
    select original.question_id from session_original_ids original
    where app_private.chem_junior_question_delivery_ready(original.question_id)
  )
  select count(*)::integer
  into v_current_contract_count
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id
  join ready_original_ids as ready_question
    on ready_question.question_id = question.id
  join app_private.chem_junior_knowledge_provenance as provenance
    on provenance.textbook_version = v_session.textbook_version
   and provenance.knowledge_id = step.knowledge_id
   and (question.source_kind='licensed_local' or provenance.source_release_id = question.source_release_id)
   and provenance.verification_status = 'verified'
  join app_private.chem_question_source_releases as release
    on release.id = provenance.source_release_id
   and release.grade_band = '初三'
   and release.textbook_version = v_session.textbook_version
   and release.status = 'active'
   and release.verification_status = 'full_visual_verified'
   and release.verification_manifest_sha256 = release.manifest_sha256
   and release.revision_contract = 'v3_junior_native_text'
   and release.verified_at is not null
   and pg_catalog.length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
   and release.activated_at is not null
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  where step.session_id = p_session_id
    and step.answered_at is not null
    and question.grade_band = '初三'
    and question.textbook_version = v_session.textbook_version
    and question.review_status = 'approved'
    and question.scope_status = 'IN'
    and question.usable_for_review
    and ((question.source_kind='user_provided_local' and question.render_mode='native' and question.image_url is null and question.asset_refs='[]'::jsonb)
      or (question.source_kind='licensed_local' and app_private.chem_junior_image_question_delivery_ready(question.id)))
    and question.skill_id = step.skill_id
    and question.knowledge_id = step.knowledge_id
    and question.skill_id = question.knowledge_id
    and question.mother_id = step.mother_id
    and question.same_type_key = step.same_type_key
    and question.source_item_key = step.source_item_key
    and app_private.chem_junior_parent_source_identity(question) = step.parent_source_item_key
    and question.content_fingerprint = step.content_fingerprint
    and question.level = step.level
    and question.source_release_id is not null
    and pg_catalog.length(pg_catalog.btrim(coalesce(question.stem, ''))) > 0
    and pg_catalog.length(pg_catalog.btrim(coalesce(question.explanation, ''))) > 0
    and pg_catalog.jsonb_typeof(question.options) = 'array'
    and case
      when pg_catalog.jsonb_typeof(question.options) = 'array'
        then pg_catalog.jsonb_array_length(question.options)
      else -1
    end = 4
    and question.correct_option between 0 and 3
    and not exists (
      select 1
      from pg_catalog.jsonb_array_elements(
        case
          when pg_catalog.jsonb_typeof(question.options) = 'array' then question.options
          else '[]'::jsonb
        end
      ) as option_value(value)
      where pg_catalog.jsonb_typeof(option_value.value) is distinct from 'string'
        or pg_catalog.length(pg_catalog.btrim(option_value.value #>> '{}')) = 0
    )
    and (
      select count(distinct pg_catalog.btrim(option_value.value #>> '{}'))
      from pg_catalog.jsonb_array_elements(
        case
          when pg_catalog.jsonb_typeof(question.options) = 'array' then question.options
          else '[]'::jsonb
        end
      ) as option_value(value)
    ) = 4
    and question.content_fingerprint =
      app_private.chem_h3_content_fingerprint(question.stem, question.options)
    and question.question_revision_token =
      (case when question.source_kind='user_provided_local' then app_private.chem_junior_native_revision_sha256(question)
       else (select app_private.chem_h3_question_revision_sha256(question,p.sha256,a.sha256)
        from app_private.chem_question_assets p join app_private.chem_question_assets a on a.question_id=p.question_id
        where p.question_id=question.id and p.asset_kind='question_image' and a.asset_kind='analysis_image') end)
    and step.question_snapshot = pg_catalog.jsonb_build_object(
      'questionId', question.id,
      'motherId', question.mother_id,
      'skillId', question.skill_id,
      'knowledgeId', question.knowledge_id,
      'conceptKey', question.concept_key,
      'level', question.level,
      'gradeBand', question.grade_band,
      'textbookVersion', question.textbook_version,
      'stem', question.stem,
      'options', question.options,
      'correctOption', question.correct_option,
      'explanation', question.explanation,
      'scaffold', question.scaffold,
      'reviewStatus', question.review_status,
      'scopeStatus', question.scope_status,
      'sourceKind', question.source_kind,
      'renderMode', question.render_mode,
      'imageUrl', question.image_url,
      'assetRefs', question.asset_refs,
      'sourceReleaseId', question.source_release_id,
      'sourceItemKey', question.source_item_key,
      'parentSourceItemKey', question.parent_source_item_key,
      'sameTypeKey', question.same_type_key,
      'contentFingerprint', question.content_fingerprint,
      'revisionToken', question.question_revision_token,
      'routeKind', step.route_kind,
      'routeReason', step.route_reason
    )
    and coalesce(step.question_snapshot ->> 'revisionToken', '') =
      coalesce(question.question_revision_token, '');

  if v_current_contract_count <> v_total then
    raise exception 'junior source evidence contract changed before finalization';
  end if;

  -- Only now may a completed retry return.  The existing attempt lookup is
  -- intentionally after all present-tense authorization and source locks so
  -- completion never bypasses a revoked plan/profile/curriculum/card/release.
  select attempt.id
  into v_attempt_id
  from public.chem_learning_attempts as attempt
  where attempt.junior_session_id = p_session_id
    and attempt.student_id = p_student_id
    and attempt.plan_day_id = v_session.plan_day_id
  for share;

  if v_attempt_id is not null then
    if v_session.status <> 'completed' then
      raise exception 'junior attempt exists for a session that is not completed';
    end if;
    select count(*)::integer
    into v_answer_ledger_count
    from public.chem_attempt_answers as answer
    where answer.attempt_id = v_attempt_id;
    if v_answer_ledger_count <> v_total then
      raise exception 'junior immutable answer ledger is incomplete';
    end if;
    return query select true, v_total, v_correct;
    return;
  end if;

  if v_session.status = 'completed' then
    raise exception 'completed junior session has no immutable attempt ledger';
  end if;

  v_completed_at := coalesce(v_session.completed_at, now());
  v_attempt_id := gen_random_uuid();

  insert into public.chem_learning_attempts (
    id,
    student_id,
    plan_day_id,
    attempt_kind,
    sequence,
    mode,
    started_at,
    completed_at,
    first_score,
    junior_session_id
  ) values (
    v_attempt_id,
    p_student_id,
    v_session.plan_day_id,
    'scheduled',
    0,
    v_plan_mode,
    v_session.started_at,
    v_completed_at,
    v_correct,
    p_session_id
  );

  insert into public.chem_attempt_answers (
    attempt_id,
    question_id,
    mother_id,
    skill_id,
    concept_key,
    level,
    correct,
    uncertain,
    duration_sec,
    selected_option,
    question_snapshot,
    created_at
  )
  select
    v_attempt_id,
    step.question_id,
    step.mother_id,
    step.skill_id,
    coalesce(nullif(step.question_snapshot ->> 'conceptKey', ''), question.concept_key),
    step.level,
    step.correct,
    step.uncertain,
    step.duration_sec,
    step.selected_option,
    coalesce(step.question_snapshot, '{}'::jsonb)
      || jsonb_build_object(
        'version', 2,
        'source', 'junior_adaptive_session',
        'capturedAt', step.created_at,
        'answeredAt', step.answered_at,
        'questionId', step.question_id,
        'motherId', step.mother_id,
        'skillId', step.skill_id,
        'knowledgeId', step.knowledge_id,
        'level', step.level,
        'gradeBand', coalesce(nullif(step.question_snapshot ->> 'gradeBand', ''), question.grade_band),
        'textbookVersion', v_session.textbook_version,
        'stem', coalesce(nullif(step.question_snapshot ->> 'stem', ''), question.stem),
        'options', case
          when jsonb_typeof(step.question_snapshot -> 'options') = 'array'
            then step.question_snapshot -> 'options'
          else question.options
        end,
        'correctOption', case
          when jsonb_typeof(step.question_snapshot -> 'correctOption') = 'number'
            then (step.question_snapshot ->> 'correctOption')::smallint
          else question.correct_option
        end,
        'explanation', coalesce(nullif(step.question_snapshot ->> 'explanation', ''), question.explanation),
        'scaffold', coalesce(step.question_snapshot ->> 'scaffold', question.scaffold),
        'sourceKind', coalesce(step.question_snapshot->>'sourceKind',question.source_kind),
        'assetRefs', coalesce(step.question_snapshot->'assetRefs','[]'::jsonb),
        'imageUrl', step.question_snapshot->'imageUrl',
        'sourceInfo', case when question.source_kind='licensed_local' then question.source_info else null end,
        'sourceReleaseId', coalesce(
          nullif(step.question_snapshot ->> 'sourceReleaseId', ''),
          question.source_release_id::text
        ),
        'sameTypeKey', step.same_type_key,
        'sourceItemKey', step.source_item_key,
        'parentSourceItemKey', step.parent_source_item_key,
        'contentFingerprint', step.content_fingerprint,
        'revisionToken', coalesce(
          nullif(step.question_snapshot ->> 'revisionToken', ''),
          question.question_revision_token
        ),
        'renderMode', coalesce(nullif(step.question_snapshot ->> 'renderMode', ''), question.render_mode),
        'routeKind', step.route_kind,
        'routeReason', step.route_reason,
        'sequence', step.sequence
      ),
    step.answered_at
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id
  where step.session_id = p_session_id
  order by step.sequence;

  select count(*)::integer
  into v_answer_ledger_count
  from public.chem_attempt_answers as answer
  where answer.attempt_id = v_attempt_id;

  if v_answer_ledger_count <> v_total then
    raise exception 'junior immutable answer ledger is incomplete';
  end if;

  with requested_skills as (
    select distinct unnest(v_session.knowledge_skill_ids) as skill_id
  ),
  verified_provenance as (
    select requested.skill_id, provenance.source_release_id
    from requested_skills as requested
    join app_private.chem_junior_knowledge_provenance as provenance
      on provenance.textbook_version = v_session.textbook_version
      and provenance.knowledge_id = requested.skill_id
      and provenance.verification_status = 'verified'
    join app_private.chem_question_source_releases as release
      on release.id = provenance.source_release_id
      and release.grade_band = '初三'
      and release.textbook_version = v_session.textbook_version
      and release.status = 'active'
      and release.verification_status = 'full_visual_verified'
      and release.verification_manifest_sha256 = release.manifest_sha256
      and release.revision_contract = 'v3_junior_native_text'
      and release.verified_at is not null
      and pg_catalog.length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
      and release.activated_at is not null
    join app_private.chem_junior_source_release_rights as rights
      on rights.release_id = release.id
      and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
      and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
      and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  ),
  foundation_levels as (
    select provenance.skill_id, min(question.level)::smallint as foundation_level
    from verified_provenance as provenance
    join public.chem_questions as question
      on (question.source_release_id = provenance.source_release_id or (question.source_kind='licensed_local' and app_private.chem_junior_image_question_delivery_ready(question.id)))
      and question.skill_id = provenance.skill_id
      and question.knowledge_id = provenance.skill_id
      and question.grade_band = '初三'
      and question.textbook_version = v_session.textbook_version
      and question.review_status = 'approved'
      and question.scope_status = 'IN'
      and question.usable_for_review
      and app_private.chem_junior_question_delivery_ready(question.id)
    group by provenance.skill_id
  ),
  original_evidence as (
    select step.*
    from public.chem_junior_session_steps as step
    join verified_provenance as provenance
      on provenance.skill_id = step.skill_id
    join public.chem_questions as question
      on question.id = step.question_id
      and (question.source_release_id = provenance.source_release_id or (question.source_kind='licensed_local' and app_private.chem_junior_image_question_delivery_ready(question.id)))
      and question.skill_id = step.skill_id
      and question.knowledge_id = step.knowledge_id
      and question.grade_band = '初三'
      and question.textbook_version = v_session.textbook_version
      and question.review_status = 'approved'
      and question.scope_status = 'IN'
      and question.usable_for_review
      and app_private.chem_junior_question_delivery_ready(question.id)
      and question.mother_id = step.mother_id
      and question.source_item_key = step.source_item_key
      and app_private.chem_junior_parent_source_identity(question) = step.parent_source_item_key
      and question.content_fingerprint = step.content_fingerprint
      and question.question_revision_token is not distinct from nullif(step.question_snapshot ->> 'revisionToken', '')
    where step.session_id = p_session_id
  ),
  evidence as (
    select
      requested.skill_id,
      foundation.foundation_level,
      count(distinct original.question_id) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_question_count,
      count(distinct original.mother_id) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_mother_count,
      count(distinct original.source_item_key) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_source_count,
      count(distinct original.parent_source_item_key) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_parent_count,
      count(distinct original.content_fingerprint) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_fingerprint_count,
      count(distinct original.question_id) filter (
        where original.correct
          and not original.uncertain
          and original.level > foundation.foundation_level
      ) as higher_question_count,
      max(original.level) filter (
        where original.correct
          and not original.uncertain
          and original.level > foundation.foundation_level
      )::smallint as achieved_level,
      (
        select count(*)::integer
        from public.chem_junior_session_steps as all_step
        where all_step.session_id = p_session_id
          and all_step.skill_id = requested.skill_id
          and (not all_step.correct or all_step.uncertain)
      ) as error_or_uncertain_count
    from requested_skills as requested
    left join foundation_levels as foundation
      on foundation.skill_id = requested.skill_id
    left join original_evidence as original
      on original.skill_id = requested.skill_id
    group by requested.skill_id, foundation.foundation_level
  ),
  demonstrated as (
    select evidence.*,
      app_private.chem_junior_demonstrated_level(v_session.textbook_version,evidence.skill_id,
        v_session.repetition_policy,evidence.foundation_level,
        least(evidence.foundation_question_count,evidence.foundation_mother_count,
          evidence.foundation_source_count,evidence.foundation_parent_count,evidence.foundation_fingerprint_count),
        evidence.higher_question_count,evidence.achieved_level) as demonstrated_level
    from evidence
  ),
  mastery as (
    select demonstrated.*,
      demonstrated.demonstrated_level > 0
        and not exists (
          select 1 from app_private.chem_junior_option_branches b
          where b.student_id=p_student_id and b.knowledge_id=demonstrated.skill_id
            and b.status <> 'consolidated'
        ) as mastered
    from demonstrated
  )
  insert into public.chem_student_skill_state (
    student_id,
    skill_id,
    verified_level,
    candidate_level,
    stability,
    consecutive_errors,
    next_review_at,
    review_interval_index,
    last_reviewed_at,
    teacher_intervention,
    updated_at
  )
  select
    p_student_id,
    mastery.skill_id,
    case when mastery.mastered then mastery.demonstrated_level else 0 end,
    case when mastery.mastered then mastery.demonstrated_level else null end,
    case when mastery.mastered then 'verified' else 'learning' end,
    mastery.error_or_uncertain_count,
    now() + case when mastery.mastered then interval '3 days' else interval '1 day' end,
    case when mastery.mastered then 1 else 0 end,
    now(),
    not mastery.mastered and mastery.error_or_uncertain_count >= 3,
    now()
  from mastery
  on conflict (student_id, skill_id) do update set
    verified_level = case
      when excluded.stability = 'verified'
        then greatest(public.chem_student_skill_state.verified_level, excluded.verified_level)
      else public.chem_student_skill_state.verified_level
    end,
    candidate_level = case
      when excluded.stability = 'verified' then excluded.candidate_level
      else null
    end,
    stability = case
      when excluded.stability = 'verified' then 'verified'
      when public.chem_student_skill_state.verified_level > 0
        and excluded.consecutive_errors > 0 then 'forgotten'
      else 'learning'
    end,
    consecutive_errors = case
      when excluded.stability = 'verified' then 0
      else greatest(
        public.chem_student_skill_state.consecutive_errors,
        excluded.consecutive_errors
      )
    end,
    next_review_at = excluded.next_review_at,
    review_interval_index = case
      when excluded.stability = 'verified'
        then least(4, public.chem_student_skill_state.review_interval_index + 1)
      else 0
    end,
    last_reviewed_at = now(),
    teacher_intervention = public.chem_student_skill_state.teacher_intervention
      or excluded.teacher_intervention,
    updated_at = now();

  update public.chem_junior_daily_sessions
  set status = 'completed',
      completed_at = v_completed_at,
      blocked_reason_code = null,
      blocked_reason_detail = null,
      blocked_at = null,
      updated_at = now()
  where id = p_session_id;

  return query select true, v_total, v_correct;
end;
$function$;

CREATE OR REPLACE FUNCTION public.chem_junior_option_state(p_student_id uuid, p_session_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  sess public.chem_junior_daily_sessions%rowtype;
  anchor record; branch app_private.chem_junior_option_branches%rowtype;
  binding app_private.chem_option_practice_bindings%rowtype;
  candidate jsonb; q public.chem_questions%rowtype;
  chosen jsonb; n integer; good integer; has_error boolean; last_three_good boolean;
  target integer; issued_count integer; next_id text; next_revision text;
  result jsonb := '[]'; branch_status text; branch_reason text;
  daily_issued integer; ordinary_answered integer; new_policy boolean;
  repetition_history jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release',0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release',0));
  -- A student row serializes queue allocation across days/tabs before sessions.
  perform s.id from public.chem_students_v2 s where s.id=p_student_id and s.grade_band='初三'
    and s.record_status='active' and coalesce((s.metadata->>'demo')::boolean,false)=false for update;
  if not found then raise exception 'junior option student is not eligible'; end if;
  select * into sess from public.chem_junior_daily_sessions s where s.id=p_session_id and s.student_id=p_student_id for update;
  if not found then raise exception 'junior option session ownership mismatch'; end if;
  select count(*) into issued_count from public.chem_junior_session_steps s where s.session_id=p_session_id;

  select count(*) into daily_issued from app_private.chem_junior_daily_budget_keys(p_student_id);
  select count(*) into ordinary_answered from public.chem_junior_session_steps where session_id=p_session_id and practice_round=0 and answered_at is not null;
  new_policy:=sess.recovery_round_limit=3;
  repetition_history:=app_private.chem_junior_repetition_history(p_student_id);

  -- Legacy reserves never recurse. New sessions recurse only through round 3.
  for anchor in select st.*,ds.recovery_round_limit from public.chem_junior_session_steps st
    join public.chem_junior_daily_sessions ds on ds.id=st.session_id
    where ds.student_id=p_student_id and ds.textbook_version=sess.textbook_version
      and st.answered_at is not null and (st.correct=false or (ds.recovery_round_limit=3 and st.uncertain))
      and ((ds.recovery_round_limit=0 and not exists(select 1 from app_private.chem_junior_option_steps os where os.step_id=st.id))
        or (ds.recovery_round_limit=3 and st.practice_round<3))
      and (new_policy or st.practice_round=0)
      and not exists(select 1 from app_private.chem_junior_option_branches b where b.anchor_step_id=st.id)
    order by st.answered_at,st.id
  loop
    insert into app_private.chem_junior_option_branches(student_id,anchor_step_id,anchor_session_id,anchor_question_id,anchor_revision_token,selected_option,knowledge_id,recovery_round)
    values(p_student_id,anchor.id,anchor.session_id,anchor.question_id,coalesce(anchor.question_snapshot->>'revisionToken',''),anchor.selected_option,anchor.knowledge_id,case when anchor.recovery_round_limit=3 then anchor.practice_round+1 else 1 end);
  end loop;

  for branch in select * from app_private.chem_junior_option_branches b where b.student_id=p_student_id order by case when new_policy then b.recovery_round else 1 end,b.created_at,b.id for update
  loop
    -- An empty gap may acquire a newly reviewed pool, but a nonempty pool is
    -- frozen for the lifetime of this first-option branch, including next day.
    if jsonb_array_length(branch.candidates)=0 and (not new_policy or ordinary_answered>=sess.initial_question_target) then
      select * into binding from app_private.chem_option_practice_bindings b
        where b.anchor_question_id=branch.anchor_question_id and b.option_index=branch.selected_option
          and b.anchor_revision_token=branch.anchor_revision_token and b.review_status='verified';
      chosen := '[]';
      if found then
        for candidate in select value from jsonb_array_elements(binding.candidates)
        loop
          select reviewed_candidate.* into q from (
          select question.* from public.chem_questions question
            join app_private.chem_question_source_releases r on r.id=question.source_release_id and r.status='active'
              and r.verification_status='full_visual_verified' and r.revision_contract='v3_junior_native_text'
            join app_private.chem_junior_knowledge_provenance p on p.knowledge_id=question.knowledge_id
              and p.textbook_version=sess.textbook_version and p.source_release_id=r.id and p.verification_status='verified'
            where question.id=candidate->>'questionId' and question.question_revision_token=candidate->>'revisionToken'
              and question.grade_band='初三' and question.textbook_version=sess.textbook_version
              and question.source_kind='user_provided_local' and question.review_status='approved'
              and question.scope_status='IN' and question.usable_for_review and question.render_mode='native'
              and not exists(select 1 from public.chem_question_delivery_holds_for(array[question.id]) h where h.question_id=question.id)
          union all
          select image.* from public.chem_questions image
          where image.id=candidate->>'questionId' and image.question_revision_token=candidate->>'revisionToken'
            and image.grade_band='初三' and image.textbook_version=sess.textbook_version
            and image.source_kind='licensed_local' and app_private.chem_junior_image_question_delivery_ready(image.id)
          ) reviewed_candidate;
          if not found then continue; end if;
          if (app_private.chem_junior_repetition_state(q,repetition_history,p_session_id,sess.repetition_policy,
              (now() at time zone 'Asia/Shanghai')::date)->>'eligible') is distinct from 'true'
            or exists(select 1 from public.chem_questions a where a.id=branch.anchor_question_id
              and (a.id=q.id or a.mother_id=q.mother_id or a.source_item_key=q.source_item_key
                or app_private.chem_junior_parent_source_identity(a)=app_private.chem_junior_parent_source_identity(q) or a.content_fingerprint=q.content_fingerprint))
            or exists(select 1 from public.chem_junior_session_steps st where st.session_id=branch.anchor_session_id
              and (st.question_id=q.id or st.mother_id=q.mother_id or st.source_item_key=q.source_item_key or st.parent_source_item_key=app_private.chem_junior_parent_source_identity(q) or st.content_fingerprint=q.content_fingerprint))
            or exists(select 1 from jsonb_array_elements(chosen) c join public.chem_questions prior on prior.id=c->>'questionId'
              where prior.id=q.id or prior.mother_id=q.mother_id or prior.source_item_key=q.source_item_key or app_private.chem_junior_parent_source_identity(prior)=app_private.chem_junior_parent_source_identity(q) or prior.content_fingerprint=q.content_fingerprint)
            or exists(select 1 from app_private.chem_junior_option_branches other cross join lateral jsonb_array_elements(other.candidates) c
              join public.chem_questions reserved on reserved.id=c->>'questionId'
              where other.student_id=p_student_id and other.id<>branch.id and other.status in ('practicing','pending','reserve_gap')
                and (reserved.id=q.id or reserved.mother_id=q.mother_id or reserved.source_item_key=q.source_item_key or app_private.chem_junior_parent_source_identity(reserved)=app_private.chem_junior_parent_source_identity(q) or reserved.content_fingerprint=q.content_fingerprint))
          then continue; end if;
          chosen := chosen || jsonb_build_array(candidate);
        end loop;
        if jsonb_array_length(chosen)>=3 then
          update app_private.chem_junior_option_branches set candidates=chosen,binding_snapshot=to_jsonb(binding),knowledge_point=binding.knowledge_point,updated_at=now() where id=branch.id returning * into branch;
        end if;
      end if;
    end if;

    select count(*) filter(where st.answered_at is not null),count(*) filter(where st.correct=true and (not new_policy or not st.uncertain)),coalesce(bool_or((st.correct=false or (new_policy and st.uncertain)) and os.position<=3),false)
      into n,good,has_error from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id where os.branch_id=branch.id;
    select count(*)=3 and bool_and(t.correct) into last_three_good from (
      select st.correct and (not new_policy or not st.uncertain) as correct from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id
      where os.branch_id=branch.id and st.answered_at is not null order by os.position desc limit 3
    ) t;
    target := case when has_error then greatest(3,least(5,jsonb_array_length(branch.candidates))) else 3 end;
    next_id := null; next_revision := null;
    branch_status := 'practicing'; branch_reason := '';
    if new_policy and ordinary_answered<sess.initial_question_target and jsonb_array_length(branch.candidates)=0
      then branch_status:='pending'; branch_reason:='initial_round_in_progress';
    elsif jsonb_array_length(branch.candidates)<3 then branch_status:='reserve_gap'; branch_reason:='fewer_than_three_verified_fresh_originals';
    elsif n>=target then
      if last_three_good then branch_status:='consolidated';
      else branch_status:='needs_practice'; branch_reason:='reviewed_reserves_exhausted_without_three_consecutive_correct'; end if;
    else
      next_id:=branch.candidates->n->>'questionId'; next_revision:=branch.candidates->n->>'revisionToken';
      select * into q from public.chem_questions question where question.id=next_id;
      if not found or q.question_revision_token is distinct from next_revision or not q.usable_for_review
        or not app_private.chem_junior_question_delivery_ready(q.id)
        or exists(select 1 from public.chem_question_delivery_holds_for(array[next_id]) h where h.question_id=next_id)
      then branch_status:='reserve_gap'; branch_reason:='reserved_original_unavailable';
      elsif sess.repetition_policy='spaced_review'
        and (app_private.chem_junior_repetition_state(q,repetition_history,p_session_id,sess.repetition_policy,
          (now() at time zone 'Asia/Shanghai')::date)->>'eligible') is distinct from 'true'
        and not exists(select 1 from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id
          where os.branch_id=branch.id and st.session_id=p_session_id and st.question_id=q.id and st.answered_at is null)
      then branch_status:='pending'; branch_reason:='review_interval_not_due';
      elsif not (q.knowledge_id=any(sess.knowledge_skill_ids))
        and not app_private.chem_junior_frozen_recovery_allows(p_student_id,p_session_id,q.id,q.question_revision_token) then branch_status:='pending'; branch_reason:='waiting_for_compatible_curriculum';
      elsif new_policy and ordinary_answered<sess.initial_question_target then branch_status:='pending'; branch_reason:='initial_round_in_progress';
      elsif new_policy and exists(select 1 from jsonb_array_elements(result) prior where prior->>'status'='practicing' and (prior->>'recoveryRound')::integer<branch.recovery_round)
        then branch_status:='pending'; branch_reason:='waiting_for_previous_recovery_round';
      elsif sess.status<>'active' or issued_count>=sess.hard_question_cap or (app_private.chem_junior_budget_enabled(p_student_id) and daily_issued>=30) then branch_status:='pending'; branch_reason:='daily_limit_carry_forward';
      end if;
    end if;
    update app_private.chem_junior_option_branches set status=branch_status,reason=branch_reason,target_count=target,updated_at=now() where id=branch.id;
    result:=result||jsonb_build_array(jsonb_build_object('branchId',branch.id,'anchorStepId',branch.anchor_step_id,'anchorSessionId',branch.anchor_session_id,
      'recoveryRound',branch.recovery_round,'knowledgeId',branch.knowledge_id,'knowledgePoint',branch.knowledge_point,'optionIndex',branch.selected_option,
      'status',branch_status,'reason',branch_reason,'answered',n,'correct',good,'total',target,
      'candidates',branch.candidates,'nextQuestionId',next_id,'nextRevisionToken',next_revision));
  end loop;
  return jsonb_build_object('branches',result,'dailyIssuedCount',daily_issued,'dailyBudgetEnabled',app_private.chem_junior_budget_enabled(p_student_id),'pendingStepCountedToday',exists(select 1 from public.chem_junior_session_steps st join app_private.chem_junior_daily_budget_keys(p_student_id) k on k.event_key='junior:'||st.session_id::text||':'||st.sequence::text where st.session_id=p_session_id and st.answered_at is null),'stepContexts',coalesce((select jsonb_agg(jsonb_build_object('stepId',os.step_id,'branchId',os.branch_id,'position',os.position,'recoveryRound',st.practice_round)) from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id where st.session_id=p_session_id),'[]'::jsonb));
end; $function$;

-- Only explicitly audited original fill-in / judgement adaptations are expanded to four grades.
CREATE OR REPLACE FUNCTION public.chem_activate_teaching_material_release(p_release_id uuid, p_manifest_sha256 text)
 RETURNS TABLE(release_id uuid, activated_questions integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_question_count integer;
  v_distinct_count integer;
  v_computed_manifest text;
  v_release_manifest text;
  v_release_status text;
  v_release_expected integer;
  v_verification_status text;
  v_verification_manifest text;
  v_verification_actor text;
  v_verified_at timestamptz;
  v_skill_ids text[];
  v_expected_skill_ids text[];
  v_grade_band text;
  v_expected_concept_count integer;
begin
  if p_release_id is null or coalesce(p_manifest_sha256, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid release identity';
  end if;

  -- Serialize release switches.  Every assertion and both the old/new pool
  -- updates run in this function's transaction, so a failed assertion leaves
  -- the currently active REVIEW pool unchanged.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release', 0));

  select r.manifest_sha256, r.status, r.expected_question_count,
    r.verification_status, r.verification_manifest_sha256,
    r.verification_actor, r.verified_at, r.grade_band
  into v_release_manifest, v_release_status, v_release_expected,
    v_verification_status, v_verification_manifest,
    v_verification_actor, v_verified_at, v_grade_band
  from app_private.chem_question_source_releases r
  where r.id = p_release_id
    and r.grade_band in ('初三','高一','高二','高三') and r.release_kind='teaching_material'
  for update;

  if not found
    or v_release_manifest <> p_manifest_sha256
    or v_release_status <> 'staged'
    or v_release_expected not between 1 and 5000
    or v_verification_status <> 'full_visual_verified'
    or v_verification_manifest is distinct from p_manifest_sha256
    or length(btrim(coalesce(v_verification_actor, ''))) < 8
    or v_verified_at is null
  then
    raise exception 'release is missing, unverified, already activated, or manifest hash does not match';
  end if;

  -- Freeze the entire staged release while it is being verified.  The parent
  -- release row lock also blocks concurrent FK inserts; these deterministic
  -- child locks close the check-to-activate race for updates and deletes.
  perform q.id
  from public.chem_questions q
  where q.source_release_id = p_release_id
  order by q.id
  for update;

  perform a.asset_path
  from app_private.chem_question_assets a
  join public.chem_questions q on q.id = a.question_id
  where q.source_release_id = p_release_id
  order by a.asset_path
  for update of a;

  perform ri.question_id
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id
  order by ri.question_id
  for update;

  select count(*) into v_question_count
  from public.chem_questions q
  where q.source_release_id = p_release_id;
  if v_question_count <> v_release_expected then
    raise exception 'release must contain exactly % questions, found %', v_release_expected, v_question_count;
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        q.grade_band <> v_grade_band
        or q.source_kind <> 'licensed_local'
        or q.review_status <> 'approved'
        or q.scope_status <> 'IN'
        or q.usable_for_review
        or q.usable_for_class_quiz
        or q.usable_for_exam_sprint
        or q.usable_for_demo
        or q.mother_id is null
        or q.concept_key is null
        or q.concept_key !~ ('^'||q.skill_id||'__[A-Z0-9_]+$')
        or length(btrim(coalesce(q.stem, ''))) = 0
        or length(btrim(coalesce(q.explanation, ''))) = 0
        or jsonb_typeof(q.options) <> 'array'
        or case when jsonb_typeof(q.options) = 'array' then
          jsonb_array_length(q.options) <> 4
          or exists (
            select 1 from jsonb_array_elements(q.options) option_value
            where jsonb_typeof(option_value) <> 'string'
          )
          else true end
        or q.correct_option not between 0 and 3
        or coalesce(q.content_fingerprint, '') !~ '^[0-9a-f]{64}$'
        or coalesce(q.question_revision_token, '') !~ '^[0-9a-f]{64}$'
        or q.render_mode <> 'image_primary'
        or jsonb_array_length(q.asset_refs) <> 2
      )
  ) then
    raise exception 'release contains an unapproved, ineligible, non-four-option, or prematurely enabled question';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    cross join lateral jsonb_array_elements_text(q.options) option_text
    where q.source_release_id = p_release_id
      and length(btrim(option_text)) = 0
  ) then
    raise exception 'release contains an empty answer option';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        select count(distinct btrim(option_text))
        from jsonb_array_elements_text(q.options) option_text
      ) <> 4
  ) then
    raise exception 'release contains duplicated answer options';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and q.content_fingerprint is distinct from
        app_private.chem_h3_content_fingerprint(q.stem, q.options)
  ) then
    raise exception 'content fingerprint must equal the normalized stem and four options';
  end if;

  if exists(select 1 from public.chem_questions q join public.chem_skills sk on sk.id=q.skill_id
    where q.source_release_id=p_release_id and (sk.grade_band<>q.grade_band or not sk.active)) then
    raise exception 'material skill metadata must match its source grade';
  end if;
  select count(distinct q.id) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'question ids are not unique inside release'; end if;
  select count(distinct q.mother_id) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'mother ids are not unique inside release'; end if;
  select count(distinct q.source_item_key) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'source item identities are not unique inside release'; end if;
  select count(distinct q.content_fingerprint) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'content fingerprints are not unique inside release'; end if;
  select count(distinct q.question_revision_token) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'question revision tokens are not unique inside release'; end if;

  select count(*) into v_question_count
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id;
  if v_question_count <> v_release_expected then
    raise exception 'release ledger must contain exactly % items, found %', v_release_expected, v_question_count;
  end if;

  select count(distinct ri.canonical_source_id) into v_distinct_count
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id;
  if v_distinct_count <> v_release_expected then
    raise exception 'canonical source identities are not unique inside release';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    left join app_private.chem_question_source_release_items ri
      on ri.release_id = p_release_id
     and ri.question_id = q.id
    where q.source_release_id = p_release_id
      and ri.question_id is null
  ) then
    raise exception 'release ledger is missing a staged question';
  end if;

  -- Every descriptor must resolve to the exact binary metadata recorded on
  -- that question.  A non-native question additionally needs a question-side
  -- visual; an analysis image alone is not enough to make the stem readable.
  if exists (
    select 1
    from public.chem_questions q
    cross join lateral jsonb_array_elements(q.asset_refs) ref
    where q.source_release_id = p_release_id
      and (
        coalesce(btrim(ref->>'alt'), '') = ''
        or coalesce(ref->>'path', '') !~ '^[a-zA-Z0-9/_-]{16,200}$'
        or coalesce(ref->>'kind', '') not in ('question_image','formula_fallback','source_scan','analysis_image')
        or coalesce(ref->>'sha256', '') !~ '^[0-9a-f]{64}$'
        or (select count(*) from jsonb_object_keys(ref)) <> 6
        or exists (
          select 1 from jsonb_object_keys(ref) key_name
          where key_name not in ('kind','path','alt','sha256','width','height')
        )
      )
  ) then
    raise exception 'release contains a malformed or inaccessible asset descriptor';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        (select count(*) from jsonb_object_keys(q.source_info)) <> 12
        or exists (
          select 1 from jsonb_object_keys(q.source_info) key_name
          where key_name not in (
            'title','exam','year','questionNo','locator','transcriptionPolicy',
            'optionTranscriptionPolicy','transcriptionAuditMethod','sourcePairingStatus',
            'sourceMarkerStyle','sourceMarkerLabel','conceptLabel'
          )
        )
        or coalesce(q.source_info->>'transcriptionPolicy', '') not in (
          'source_image_authoritative',
          'teacher_verified_exact_reflow_of_registered_source',
          'teacher_verified_multiple_choice_adaptation',
          'source_crop_sanitized',
          'source_native_minimal_scientific_errata'
        )
        or (q.source_info->>'transcriptionPolicy'='source_native_minimal_scientific_errata'
          and (coalesce(q.source_info->>'sourceMarkerLabel','') !~ '(修正版|校正版)'
            or coalesce(q.source_info->>'transcriptionAuditMethod','') !~ '独立.*来源'
            or coalesce(q.source_info->>'transcriptionAuditMethod','') !~ '科学.*核查'))
        or coalesce(btrim(q.source_info->>'optionTranscriptionPolicy'), '') = ''
        or coalesce(btrim(q.source_info->>'transcriptionAuditMethod'), '') = ''
        or coalesce(q.source_info->>'sourcePairingStatus', '') not in ('EXACT','SOURCE_NATIVE_PAIR')
        or coalesce(q.source_info->>'sourceMarkerStyle', '') not in ('bracketed','plain_answer_analysis')
        or coalesce(btrim(q.source_info->>'sourceMarkerLabel'), '') = ''
        or coalesce(btrim(q.source_info->>'conceptLabel'), '') = ''
      )
  ) then
    raise exception 'release contains an incomplete or non-canonical public source record';
  end if;

  -- A genuine source fill-in may be presented as four choices only with explicit provenance.
  if exists (
    select 1 from public.chem_questions q
    where q.source_release_id=p_release_id
      and q.source_info->>'transcriptionPolicy'='teacher_verified_multiple_choice_adaptation'
      and (
        q.grade_band not in ('初三','高一','高二','高三') or q.source_kind<>'licensed_local' or q.render_mode<>'image_primary'
        or case (q.source_info->>'transcriptionAuditMethod')::jsonb->>'kind'
          when 'native_fill_in_to_four_choices' then position('原填空改四选' in coalesce(q.source_info->>'title',''))=0
          when 'native_true_false_to_four_choices' then
            position('原判断改四选' in coalesce(q.source_info->>'title',''))=0
            or jsonb_typeof((q.source_info->>'transcriptionAuditMethod')::jsonb->'originalTrueFalseKey') is distinct from 'boolean'
            or (q.source_info->>'transcriptionAuditMethod')::jsonb->'correctChoiceStatesOriginalJudgement' is distinct from 'true'::jsonb
          else true end
        or q.source_info->>'sourcePairingStatus' not in ('EXACT','SOURCE_NATIVE_PAIR')
        or case (q.source_info->>'transcriptionAuditMethod')::jsonb->>'kind'
          when 'native_fill_in_to_four_choices' then
            q.source_info->>'optionTranscriptionPolicy' is distinct from 'native_fill_in_to_four_choices: all choices adapted; A/B/C/D distractors explicitly generated; original conditions and correct answer preserved'
          when 'native_true_false_to_four_choices' then
            q.source_info->>'optionTranscriptionPolicy' is distinct from 'native_true_false_to_four_choices: all choices adapted; A/B/C/D distractors explicitly generated; original judgement, conditions and correct answer preserved'
          else true end
        or coalesce((q.source_info->>'transcriptionAuditMethod')::jsonb->>'kind','') not in ('native_fill_in_to_four_choices','native_true_false_to_four_choices')
        or coalesce(btrim((q.source_info->>'transcriptionAuditMethod')::jsonb->>'originalPrompt'),'')=''
        or coalesce(btrim((q.source_info->>'transcriptionAuditMethod')::jsonb->>'originalCorrectAnswer'),'')=''
        or (q.source_info->>'transcriptionAuditMethod')::jsonb->'generatedOptions' is distinct from 'true'::jsonb
        or (q.source_info->>'transcriptionAuditMethod')::jsonb->'originalConditionsUnchanged' is distinct from 'true'::jsonb
        or (q.source_info->>'transcriptionAuditMethod')::jsonb->'correctChoiceMatchesOriginal' is distinct from 'true'::jsonb
        or (q.source_info->>'sourcePairingStatus'='SOURCE_NATIVE_PAIR'
          and (q.source_info->>'transcriptionAuditMethod')::jsonb->'nativeStudentTeacherProofRetained' is distinct from 'true'::jsonb)
        or (q.source_info->>'sourcePairingStatus'='EXACT'
          and (
            (q.source_info->>'transcriptionAuditMethod')::jsonb->>'originalSourceMode' is distinct from 'same_native_question_and_key'
            or (q.source_info->>'transcriptionAuditMethod')::jsonb->'nativeSameDocumentQuestionAndKeyProofRetained' is distinct from 'true'::jsonb
            or coalesce((q.source_info->>'transcriptionAuditMethod')::jsonb->>'nativeOriginalDocumentSha256','') !~ '^[0-9a-f]{64}$'
          ))
      )
  ) then
    raise exception 'Source fill-in choice adaptation lacks explicit original prompt, key, generated choices or native provenance';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        jsonb_array_length(q.asset_refs) <> 2
        or jsonb_array_length(q.asset_refs) <> (
          select count(distinct ref->>'path')
          from jsonb_array_elements(q.asset_refs) ref
        )
        or (select count(*) from jsonb_array_elements(q.asset_refs) ref where ref->>'kind' = 'question_image') <> 1
        or (select count(*) from jsonb_array_elements(q.asset_refs) ref where ref->>'kind' = 'analysis_image') <> 1
        or (select count(*) from jsonb_array_elements(q.asset_refs) ref where ref->>'kind' not in ('question_image','analysis_image')) <> 0
      )
  ) then
    raise exception 'every release question must have exactly one question image and one analysis image';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    cross join lateral jsonb_array_elements(q.asset_refs) ref
    left join app_private.chem_question_assets a
      on a.question_id = q.id
     and a.asset_path = ref->>'path'
     and a.asset_kind = ref->>'kind'
     and a.sha256 = ref->>'sha256'
     and a.width::text = ref->>'width'
     and a.height::text = ref->>'height'
    where q.source_release_id = p_release_id
      and a.asset_path is null
  ) then
    raise exception 'release contains a missing or metadata-mismatched private asset';
  end if;

  if exists (
    select 1
    from app_private.chem_question_assets a
    join public.chem_questions q on q.id = a.question_id
    where q.source_release_id = p_release_id
      and encode(extensions.digest(decode(a.payload_base64, 'base64'), 'sha256'), 'hex') <> a.sha256
  ) then
    raise exception 'private asset payload does not match its SHA-256 digest';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    left join lateral (
      select
        count(*) as asset_count,
        count(*) filter (where a.asset_kind = 'question_image') as question_count,
        count(*) filter (where a.asset_kind = 'analysis_image') as analysis_count
      from app_private.chem_question_assets a
      where a.question_id = q.id
    ) counts on true
    where q.source_release_id = p_release_id
      and (
        counts.asset_count <> 2
        or counts.question_count <> 1
        or counts.analysis_count <> 1
      )
  ) then
    raise exception 'private asset store must contain exactly the two declared images per question';
  end if;

  if exists (
    select 1
    from app_private.chem_question_assets a
    join public.chem_questions q on q.id = a.question_id
    where q.source_release_id = p_release_id
      and a.mime_type <> 'image/webp'
  ) then
    raise exception 'release assets must use the audited lossless WebP transport';
  end if;

  if exists (
    select 1
    from app_private.chem_question_source_release_items ri
    join public.chem_questions q
      on q.id = ri.question_id
     and q.source_release_id = ri.release_id
    join app_private.chem_question_assets question_asset
      on question_asset.question_id = q.id
     and question_asset.asset_kind = 'question_image'
    join app_private.chem_question_assets analysis_asset
      on analysis_asset.question_id = q.id
     and analysis_asset.asset_kind = 'analysis_image'
    where ri.release_id = p_release_id
      and (
        ri.question_asset_sha256 <> question_asset.sha256
        or ri.analysis_asset_sha256 <> analysis_asset.sha256
        or q.question_revision_token is distinct from
          app_private.chem_h3_question_revision_sha256(
            q,
            question_asset.sha256,
            analysis_asset.sha256
          )
        or ri.item_sha256 <> app_private.chem_h3_release_item_sha256(
          q,
          ri.canonical_source_id,
          question_asset.sha256,
          analysis_asset.sha256
        )
      )
  ) then
    raise exception 'release revision token or ledger digest does not match the staged question and assets';
  end if;

  select pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        pg_catalog.string_agg(ri.item_sha256, E'\n' order by ri.question_id),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
  into v_computed_manifest
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id;

  if v_computed_manifest is distinct from v_release_manifest
    or v_computed_manifest is distinct from p_manifest_sha256
  then
    raise exception 'release manifest does not match the staged source items';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and q.render_mode <> 'native'
      and not exists (
        select 1
        from jsonb_array_elements(q.asset_refs) ref
        join app_private.chem_question_assets a
          on a.question_id = q.id
         and a.asset_path = ref->>'path'
         and a.asset_kind = ref->>'kind'
        where ref->>'kind' in ('question_image','formula_fallback','source_scan')
      )
  ) then
    raise exception 'every non-native question must have a verified question-side asset';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        not exists (
          select 1
          from jsonb_array_elements(q.asset_refs) ref
          join app_private.chem_question_assets a
            on a.question_id = q.id
           and a.asset_path = ref->>'path'
           and a.asset_kind = 'question_image'
          where ref->>'kind' = 'question_image'
        )
        or not exists (
          select 1
          from jsonb_array_elements(q.asset_refs) ref
          join app_private.chem_question_assets a
            on a.question_id = q.id
           and a.asset_path = ref->>'path'
           and a.asset_kind = 'analysis_image'
          where ref->>'kind' = 'analysis_image'
        )
      )
  ) then
    raise exception 'every source-backed question must have both question and analysis images';
  end if;

  -- A staged teaching-material revision may have the same normalized stem and
  -- options as its damaged predecessor when only the explanation/image changes.
  -- Retire only an explicitly held, exact-lineage predecessor in this same
  -- release switch. Unrelated or unheld duplicates still fail the unique index.
  perform old_q.id
  from public.chem_questions new_q
  join public.chem_questions old_q
    on old_q.source_item_key = new_q.parent_source_item_key
   and old_q.grade_band = new_q.grade_band
   and old_q.content_fingerprint = new_q.content_fingerprint
   and old_q.id <> new_q.id
  where new_q.source_release_id = p_release_id
    and old_q.usable_for_review
  order by old_q.id
  for update of old_q;

  if exists (
    select 1
    from public.chem_questions new_q
    join public.chem_questions old_q
      on old_q.source_item_key = new_q.parent_source_item_key
     and old_q.grade_band = new_q.grade_band
     and old_q.content_fingerprint = new_q.content_fingerprint
     and old_q.id <> new_q.id
    where new_q.source_release_id = p_release_id
      and old_q.usable_for_review
      and not exists (
        select 1 from app_private.chem_question_delivery_holds h
        where h.anchor_question_id = old_q.id
          and h.resolved_at is null
      )
  ) then
    raise exception 'same-fingerprint predecessor must be explicitly held before a revision replaces it';
  end if;

  
  if exists (
    select 1 from public.chem_questions question
    where question.source_release_id = p_release_id
      and not app_private.chem_question_item_delivery_review_ready(question.id)
  ) then
    raise exception 'release contains a question without current item-level source review';
  end if;

  perform pg_catalog.set_config('app.chem_release_activation', 'on', true);

  update public.chem_questions old_q
  set usable_for_review = false,
      usable_for_class_quiz = false,
      usable_for_exam_sprint = false,
      usable_for_demo = false,
      updated_at = now()
  from public.chem_questions new_q
  where new_q.source_release_id = p_release_id
    and old_q.source_item_key = new_q.parent_source_item_key
    and old_q.grade_band = new_q.grade_band
    and old_q.content_fingerprint = new_q.content_fingerprint
    and old_q.id <> new_q.id
    and old_q.usable_for_review
    and exists (
      select 1 from app_private.chem_question_delivery_holds h
      where h.anchor_question_id = old_q.id
          and h.resolved_at is null
    );

  update public.chem_questions
  set usable_for_review = true,
      updated_at = now()
  where source_release_id = p_release_id;
  get diagnostics v_question_count = row_count;
  if v_question_count <> v_release_expected then
    raise exception 'activation updated %, expected %', v_question_count, v_release_expected;
  end if;

  update app_private.chem_question_source_releases
  set status = 'active', activated_at = now(), retired_at = null
  where id = p_release_id;
  get diagnostics v_distinct_count = row_count;
  if v_distinct_count <> 1 then
    raise exception 'release activation status update affected %, expected 1', v_distinct_count;
  end if;

  select count(*) into v_question_count
  from public.chem_questions q
  where q.grade_band = v_grade_band
    and q.usable_for_review
    and q.source_release_id = p_release_id;
  if v_question_count <> v_release_expected then
    raise exception 'postcondition failed: active release exposes %, expected %', v_question_count, v_release_expected;
  end if;

  -- Do not leave the narrowly scoped activation bypass enabled for any later
  -- statements when a caller invokes this function inside a larger transaction.
  perform pg_catalog.set_config('app.chem_release_activation', 'off', true);

  return query select p_release_id, v_question_count;
end;
$function$;

REVOKE ALL ON FUNCTION public.chem_junior_issue_step(uuid,uuid,text,smallint,text,text,jsonb) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.chem_junior_issue_step(uuid,uuid,text,smallint,text,text,jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.chem_junior_validate_issued_step(uuid,uuid,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.chem_junior_validate_issued_step(uuid,uuid,uuid) TO service_role;

REVOKE ALL ON FUNCTION public.chem_junior_record_step(uuid,uuid,uuid,smallint,boolean,integer,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.chem_junior_record_step(uuid,uuid,uuid,smallint,boolean,integer,text) TO service_role;

REVOKE ALL ON FUNCTION public.chem_junior_finalize_session(uuid,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.chem_junior_finalize_session(uuid,uuid) TO service_role;

REVOKE ALL ON FUNCTION public.chem_junior_option_state(uuid,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.chem_junior_option_state(uuid,uuid) TO service_role;

REVOKE ALL ON FUNCTION public.chem_junior_practice_pool(uuid,uuid,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.chem_junior_practice_pool(uuid,uuid,uuid) TO service_role;

REVOKE ALL ON FUNCTION public.chem_activate_teaching_material_release(uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.chem_activate_teaching_material_release(uuid,text) TO service_role;

NOTIFY pgrst,'reload schema';
