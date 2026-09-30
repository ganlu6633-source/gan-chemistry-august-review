-- An issued but unanswered choice session is already frozen learning state.
create or replace function app_private.chem_teaching_plan_started(p_plan_id uuid)
returns boolean language sql stable set search_path='' as $function$
 select exists(select 1 from public.chem_learning_attempts where plan_day_id=p_plan_id)
 or exists(select 1 from app_private.chem_question_answer_locks where plan_day_id=p_plan_id)
 or exists(select 1 from public.chem_junior_daily_sessions where plan_day_id=p_plan_id)
 or exists(select 1 from app_private.chem_choice_training_sessions where plan_id=p_plan_id);
$function$;

-- Preserve the existing teacher-management authorization, audit and historical
-- merge behavior. Modify only the reference student's future-plan cloning.
do $migration$
declare
 definition text := pg_get_functiondef('public.chem_teacher_management(text,jsonb,text,text)'::regprocedure);
 old_clone text := $old$       insert into public.chem_learning_plans(student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,is_scheduled,knowledge_summaries,question_count,round_limit,max_question_level,target_concept_keys,delivery_mode,junior_curriculum_day_id,teaching_managed,teaching_source_grade)
        select v_id,plan_date,mode,title,skill_ids,estimated_minutes,source,is_scheduled,knowledge_summaries,question_count,round_limit,max_question_level,target_concept_keys,delivery_mode,junior_curriculum_day_id,teaching_managed,teaching_source_grade from public.chem_learning_plans where student_id=v_ref.id and plan_date>=v_today and mode='REVIEW';$old$;
 new_clone text := $new$       for v_plan in select * from public.chem_learning_plans
        where student_id=v_ref.id and plan_date>=v_today and mode='REVIEW' order by plan_date,id loop
         insert into public.chem_learning_plans(student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,is_scheduled,knowledge_summaries,question_count,round_limit,max_question_level,target_concept_keys,delivery_mode,junior_curriculum_day_id,teaching_managed,teaching_source_grade)
          values(v_id,v_plan.plan_date,v_plan.mode,v_plan.title,v_plan.skill_ids,v_plan.estimated_minutes,v_plan.source,v_plan.is_scheduled,v_plan.knowledge_summaries,v_plan.question_count,v_plan.round_limit,v_plan.max_question_level,v_plan.target_concept_keys,v_plan.delivery_mode,v_plan.junior_curriculum_day_id,v_plan.teaching_managed,v_plan.teaching_source_grade)
          returning id into v_cloned_plan_id;
         -- Only configuration is copied. The enabled policy guard rechecks the
         -- new owner, grade, plan contract and every current source revision.
         insert into app_private.chem_choice_training_policy(plan_id,grade_band,policy_version,source_release_ids,
          preferred_base_ids,authorized_base_pool_ids,focus_skill_ids,authorized_skill_ids,
          allow_advance_study,repetition_policy,source_note)
         select v_cloned_plan_id,c.grade_band,c.policy_version,c.source_release_ids,
          c.preferred_base_ids,c.authorized_base_pool_ids,c.focus_skill_ids,c.authorized_skill_ids,
          c.allow_advance_study,c.repetition_policy,c.source_note||' | cloned from reference plan '||v_plan.id::text
         from app_private.chem_choice_training_policy c where c.plan_id=v_plan.id;
       end loop;$new$;
 old_program text := $old$       v_program=v_program||jsonb_build_object('dynamicAssignmentDates',v_dynamic);$old$;
 new_program text := $new$       v_program=v_program||jsonb_build_object('dynamicAssignmentDates',v_dynamic,
        'allowAdvanceStudy',v_ref.metadata#>'{reviewProgram,allowAdvanceStudy}' is not distinct from 'true'::jsonb);$new$;
begin
 definition:=replace(definition,E'\r\n',E'\n');
 if (length(definition)-length(replace(definition,old_clone,'')))/length(old_clone)<>1
  or (length(definition)-length(replace(definition,old_program,'')))/length(old_program)<>1
  or strpos(definition,'declare v_id uuid;')=0
 then raise exception 'teacher reference clone implementation changed; review migration before applying';end if;
 definition:=replace(definition,'declare v_id uuid;','declare v_cloned_plan_id uuid; v_id uuid;');
 definition:=replace(definition,old_clone,new_clone);
 definition:=replace(definition,old_program,new_program);
 execute definition;
end $migration$;
