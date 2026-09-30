-- A reference plan can outlive an individual source's delivery approval.
-- Rebuild only the NEW learner's configuration from the still-ready subset of
-- the SAME reference pool. Never revive held sources or copy learning history.
create function app_private.chem_clone_choice_policy(p_reference_plan_id uuid,p_target_plan_id uuid)
returns void language plpgsql set search_path='' as $function$
declare
 reference app_private.chem_choice_training_policy;
 target_plan public.chem_learning_plans;
 ready_pool jsonb; ready_ids text[]; preferred text[]:='{}'; identities text[]:='{}';
 q jsonb; qid text; focus_found boolean:=false;
begin
 select * into reference from app_private.chem_choice_training_policy where plan_id=p_reference_plan_id;
 if reference.plan_id is null then return; end if;
 select * into strict target_plan from public.chem_learning_plans where id=p_target_plan_id;
 -- Keeping reference order also keeps the unchanged-policy clone identical.
 select coalesce(jsonb_agg(to_jsonb(source_q) order by original.ordinality),'[]'),
   coalesce(array_agg(source_q.id order by original.ordinality),'{}')
 into ready_pool,ready_ids
 from unnest(reference.authorized_base_pool_ids) with ordinality original(id,ordinality)
 join public.chem_questions source_q on source_q.id=original.id
 join public.chem_teaching_ready_question_ids(reference.grade_band,reference.authorized_base_pool_ids) ready on ready.question_id=source_q.id
 where source_q.grade_band=reference.grade_band and source_q.source_release_id=any(reference.source_release_ids)
   and source_q.skill_id=any(reference.authorized_skill_ids)
   and source_q.source_kind='licensed_local' and source_q.render_mode='image_primary'
   and nullif(source_q.mother_id,'') is not null and app_private.chem_choice_parent_identity(to_jsonb(source_q)) is not null
   and (target_plan.max_question_level is null or source_q.level<=target_plan.max_question_level);
 if cardinality(ready_ids)<8 then raise exception '参照进度中的可用原题不足八道，请先补齐题源再同步进度'; end if;
 -- Preserve every still-usable preferred question and its order when possible.
 for qid in select unnest(reference.preferred_base_ids) loop
   select value into q from jsonb_array_elements(ready_pool) where value->>'id'=qid;
   if q is null then continue; end if;
   if identities && app_private.chem_choice_identities(q) then continue; end if;
   preferred:=array_append(preferred,qid); identities:=identities||app_private.chem_choice_identities(q);
   focus_found:=focus_found or (q->>'skill_id'=any(reference.focus_skill_ids)
    and (cardinality(coalesce(target_plan.target_concept_keys,'{}'))=0
      or q->>'concept_key'=any(target_plan.target_concept_keys)));
 end loop;
 -- If the focus original disappeared, make one current focus original the
 -- first selection. This may replace a former review-only preferred question.
 if not focus_found then
   select value into q from jsonb_array_elements(ready_pool)
   where value->>'skill_id'=any(reference.focus_skill_ids)
    and (cardinality(coalesce(target_plan.target_concept_keys,'{}'))=0
      or value->>'concept_key'=any(target_plan.target_concept_keys)) limit 1;
   if q is null then raise exception '参照进度的这个细知识点暂缺可用原题，请先补齐题源再同步进度'; end if;
   preferred:=array[q->>'id']; identities:=app_private.chem_choice_identities(q); focus_found:=true;
   for q in select value from jsonb_array_elements(ready_pool)
    order by coalesce(array_position(reference.preferred_base_ids,value->>'id'),1001),
      array_position(ready_ids,value->>'id') loop
     if identities && app_private.chem_choice_identities(q) then continue; end if;
     preferred:=array_append(preferred,q->>'id'); identities:=identities||app_private.chem_choice_identities(q);
     exit when cardinality(preferred)=8;
   end loop;
 elsif cardinality(preferred)<8 then
   for q in select value from jsonb_array_elements(ready_pool) loop
     if identities && app_private.chem_choice_identities(q) then continue; end if;
     preferred:=array_append(preferred,q->>'id'); identities:=identities||app_private.chem_choice_identities(q);
     exit when cardinality(preferred)=8;
   end loop;
 end if;
 if cardinality(preferred)<>8 or not focus_found then raise exception '参照进度中的可用原题不足八道，请先补齐题源再同步进度'; end if;
 -- The existing enabled policy guard independently rechecks all current source
 -- gates, target owner/grade/level, and legacy-history constraints on insertion.
 insert into app_private.chem_choice_training_policy(plan_id,grade_band,policy_version,source_release_ids,
  preferred_base_ids,authorized_base_pool_ids,focus_skill_ids,authorized_skill_ids,
  allow_advance_study,repetition_policy,source_note)
 values(p_target_plan_id,reference.grade_band,reference.policy_version,reference.source_release_ids,
  preferred,ready_ids,reference.focus_skill_ids,reference.authorized_skill_ids,
  reference.allow_advance_study,reference.repetition_policy,
  reference.source_note||' | cloned from reference plan '||p_reference_plan_id::text||' using current ready reference sources');
end $function$;
revoke all on function app_private.chem_clone_choice_policy(uuid,uuid) from public,anon,authenticated,service_role;

do $migration$
declare
 definition text:=replace(pg_get_functiondef('public.chem_teacher_management(text,jsonb,text,text)'::regprocedure),E'\r\n',E'\n');
 old_clone text:=$old$         -- Only configuration is copied. The enabled policy guard rechecks the
         -- new owner, grade, plan contract and every current source revision.
         insert into app_private.chem_choice_training_policy(plan_id,grade_band,policy_version,source_release_ids,
          preferred_base_ids,authorized_base_pool_ids,focus_skill_ids,authorized_skill_ids,
          allow_advance_study,repetition_policy,source_note)
         select v_cloned_plan_id,c.grade_band,c.policy_version,c.source_release_ids,
          c.preferred_base_ids,c.authorized_base_pool_ids,c.focus_skill_ids,c.authorized_skill_ids,
          c.allow_advance_study,c.repetition_policy,c.source_note||' | cloned from reference plan '||v_plan.id::text
         from app_private.chem_choice_training_policy c where c.plan_id=v_plan.id;$old$;
begin
 if (length(definition)-length(replace(definition,old_clone,'')))/length(old_clone)<>1 then
  raise exception 'teacher reference policy clone implementation changed; review migration before applying';
 end if;
 execute replace(definition,old_clone,'         perform app_private.chem_clone_choice_policy(v_plan.id,v_cloned_plan_id);');
end $migration$;
