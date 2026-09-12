-- Expand each material's topic IDs once and hash-join the topic tree.
-- Retains distinct material/ancestor counting and exactly the same totals.
CREATE OR REPLACE FUNCTION public.chem_teacher_management(p_action text, p_data jsonb, p_actor_hash text, p_actor_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid; v_ref public.chem_students_v2; v_s public.chem_students_v2; v_before jsonb; v_result jsonb; v_p app_private.chem_teaching_previews;
 v_op text=p_data->>'operation'; v_name text=btrim(p_data->>'displayName'); v_grade text=p_data->>'gradeBand'; v_class uuid=nullif(p_data->>'classId','')::uuid;
 v_ids uuid[]; v_student_id uuid; v_day record; v_plan record; v_date date; v_program jsonb; v_assign jsonb; v_qids text[]; v_skills text[]; v_concepts text[];
 v_keep uuid[]; v_dynamic jsonb; v_title text; v_min date; v_max date; v_today date=(now() at time zone 'Asia/Shanghai')::date;
 v_codes jsonb; v_sc text; v_gc text; v_page integer; v_size integer; v_total bigint; v_rows jsonb; v_applied integer=0;
begin
 if p_actor_hash !~ '^[0-9a-f]{64}$' or length(btrim(p_actor_name))=0 then raise exception '教师身份无效'; end if;
 -- All changes and preview publication share a transaction lock. Learner evidence is also rechecked at apply.
 perform pg_advisory_xact_lock(66820260908);
 if p_action='teaching_catalog' then
   return jsonb_build_object('catalogVersion',coalesce((select max(updated_at)::text from app_private.chem_teaching_topics),''),
    'topics',coalesce((with recursive tree(ancestor,descendant) as (
       select id,id from app_private.chem_teaching_topics union all
       select tree.ancestor,t.id from tree join app_private.chem_teaching_topics t on t.parent_id=tree.descendant
      ), ready as materialized(select id from app_private.chem_teaching_ready_questions),
      qr as (select tr.ancestor,count(distinct q.id) qty from tree tr join app_private.chem_teaching_question_topics m on m.topic_id=tr.descendant join ready q on q.id=m.question_id group by tr.ancestor),
      mr as (select i.ancestor,sum(i.candidate_count) qty from (select distinct tr.ancestor,m.id,m.candidate_count from app_private.chem_teaching_materials m cross join lateral unnest(m.topic_ids) topic(id) join tree tr on tr.descendant=topic.id where m.status='needs_review') i group by i.ancestor)
      select jsonb_agg(jsonb_build_object('id',t.id,'parentId',t.parent_id,'title',t.title,'gradeBands',t.grade_bands,'order',t.sort_order,'readyQuestionCount',coalesce(qr.qty,0),'pendingQuestionCount',coalesce(mr.qty,0)) order by t.sort_order,t.id)
      from app_private.chem_teaching_topics t left join qr on qr.ancestor=t.id left join mr on mr.ancestor=t.id),'[]'),
    'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'gradeBand',c.grade_band,'memberCount',(select count(*) from public.chem_students_v2 s where s.teaching_class_id=c.id and s.record_status='active' and coalesce(s.metadata#>>'{reviewProgram,participating}','false')='true'),'planItems',coalesce((select jsonb_agg(i) from jsonb_array_elements(c.plan_items) i where i->>'date'>=v_today::text),'[]')) order by c.grade_band,c.name) from app_private.chem_teaching_classes c),'[]'),
    'students',coalesce((select jsonb_agg(jsonb_build_object('currentPlans',coalesce((select jsonb_agg(jsonb_build_object('id',pl.id,'date',pl.plan_date,'title',pl.title,'questionCount',pl.question_count,'started',app_private.chem_teaching_plan_started(pl.id),'isScheduled',pl.is_scheduled,'inCurrentProgram',pl.is_scheduled and pl.plan_date between coalesce((s.metadata#>>'{reviewProgram,startDate}')::date,pl.plan_date) and coalesce((s.metadata#>>'{reviewProgram,endDate}')::date,pl.plan_date)) order by pl.plan_date,pl.id) from public.chem_learning_plans pl where pl.student_id=s.id and pl.mode='REVIEW' and pl.plan_date>=v_today),'[]'),'id',s.id,'displayName',s.display_name,'gradeBand',s.grade_band,'classId',s.teaching_class_id,'className',coalesce(c.name,''),'status',case when s.record_status='active' and coalesce(s.metadata#>>'{reviewProgram,participating}','false')='true' then 'active' else 'archived' end,
      'progressSummary',coalesce((select string_agg(distinct t.title,'、') from jsonb_array_elements(s.teaching_plan_items) i join app_private.chem_teaching_topics t on t.id=i->>'topicId'),(select string_agg(distinct p.title,'；') from public.chem_learning_plans p where p.student_id=s.id and p.plan_date>=v_today and p.mode='REVIEW'), '暂未安排'),
      'topicIds',coalesce((select jsonb_agg(distinct i->>'topicId') from jsonb_array_elements(s.teaching_plan_items) i),'[]'),'planItems',coalesce((select jsonb_agg(i) from jsonb_array_elements(s.teaching_plan_items) i where i->>'date'>=v_today::text and not exists(select 1 from public.chem_learning_plans p where p.student_id=s.id and p.mode='REVIEW' and p.plan_date::text=i->>'date' and app_private.chem_teaching_plan_started(p.id))),'[]'),'textbookVersion',s.textbook_version) order by s.grade_band,s.display_name) from public.chem_students_v2 s left join app_private.chem_teaching_classes c on c.id=s.teaching_class_id where not coalesce((s.metadata->>'demo')::boolean,false)),'[]'));
 elsif p_action='list_teaching_materials' then
   v_page=greatest(1,coalesce((p_data->>'page')::integer,1)); v_size=least(50,greatest(5,coalesce((p_data->>'pageSize')::integer,25)));
   select count(*) into v_total from app_private.chem_teaching_materials m where (coalesce(p_data->>'topicId','')='' or p_data->>'topicId'=any(m.topic_ids)) and (coalesce(p_data->>'search','')='' or m.title ilike '%'||left(p_data->>'search',120)||'%');
   select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'title',m.title,'sourceLocation',coalesce(m.source_locations->>0,''),'topicTitles',coalesce((select jsonb_agg(title order by sort_order) from app_private.chem_teaching_topics where id=any(m.topic_ids)),'[]'),'status',m.status,'candidateCount',m.candidate_count,'duplicateCopies',m.duplicate_copies) order by m.title,m.id),'[]') into v_rows
     from (select * from app_private.chem_teaching_materials m where (coalesce(p_data->>'topicId','')='' or p_data->>'topicId'=any(m.topic_ids)) and (coalesce(p_data->>'search','')='' or m.title ilike '%'||left(p_data->>'search',120)||'%') order by m.title,m.id limit v_size offset (v_page-1)*v_size) m;
   return jsonb_build_object('materials',v_rows,'total',v_total,'page',v_page,'pageSize',v_size);
 elsif p_action='manage_class' then
   v_name=btrim(p_data->>'name'); if coalesce(length(v_name),0) not between 1 and 60 or v_grade is null or v_grade not in ('初三','高一','高二','高三') then raise exception '请填写班级名称和年段'; end if;
   if v_op='create' then insert into app_private.chem_teaching_classes(name,grade_band) values(v_name,v_grade) returning id into v_id;
   elsif v_op='update' then
     v_id=(p_data->>'classId')::uuid;
     if exists(select 1 from public.chem_students_v2 where teaching_class_id=v_id and grade_band<>v_grade) then raise exception '班级年段须与班内学生一致'; end if;
     update app_private.chem_teaching_classes set name=v_name,grade_band=v_grade,updated_at=now() where id=v_id;
     if not found then raise exception '班级不存在'; end if;
   else raise exception '班级操作无效'; end if;
   insert into app_private.chem_teaching_changes(actor_name,action,target_id,after_state) values(p_actor_name,p_action,v_id::text,p_data);
   return jsonb_build_object('classId',v_id,'message','班级已保存');
 elsif p_action='manage_student' then
   v_id=nullif(p_data->>'studentId','')::uuid;
   if v_op<>'create' then select * into strict v_s from public.chem_students_v2 where id=v_id for update; v_before=to_jsonb(v_s); end if;
   if coalesce((v_s.metadata->>'demo')::boolean,false) then raise exception '演示档案不能在此修改'; end if;
   if v_op in ('create','update') then
     if coalesce(length(v_name),0) not between 1 and 40 or v_grade is null or v_grade not in ('初三','高一','高二','高三') then raise exception '请填写学生姓名和年段'; end if;
     if exists(select 1 from public.chem_students_v2 where display_name=v_name and id is distinct from v_id and record_status='active' and not coalesce((metadata->>'demo')::boolean,false)) then raise exception '已有同名在读学生，请先检查档案，避免重复建档'; end if;
     if v_class is not null and not exists(select 1 from app_private.chem_teaching_classes where id=v_class and grade_band=v_grade) then raise exception '请选择与学生同年段的班级'; end if;
     if nullif(p_data->>'referenceStudentId','') is not null then
       select * into strict v_ref from public.chem_students_v2 where id=(p_data->>'referenceStudentId')::uuid and record_status='active' and coalesce(metadata#>>'{reviewProgram,participating}','false')='true' and grade_band=v_grade and not coalesce((metadata->>'demo')::boolean,false);
       if v_ref.id=v_id then raise exception '不能参照自己'; end if;
       if not p_data ? 'classId' then v_class=v_ref.teaching_class_id; end if;
     end if;
     if v_op='create' then
       insert into public.chem_students_v2(display_name,grade_band,textbook_version,teaching_class_id,metadata)
        values(v_name,v_grade,coalesce(v_ref.textbook_version,case when v_grade='初三' then '科粤版' else '待确认' end),v_class,jsonb_build_object('source','teacher_management','teacherSchedulingManaged',true,'reviewProgram',jsonb_build_object('participating',true,'startDate',v_today,'endDate',v_today))) returning id into v_id;
     else
       if v_s.grade_band<>v_grade and v_ref.id is null and exists(select 1 from public.chem_learning_plans p where p.student_id=v_id and p.plan_date>=v_today and p.mode='REVIEW' and p.delivery_mode='legacy_round' and jsonb_typeof(v_s.metadata#>'{reviewProgram,questionAssignments}'->p.plan_date::text) is distinct from 'array') then raise exception '该生后续课程按原年段动态取题。更改年段时请选择新年段的参考学生，或先清空后续安排再重新排课。'; end if;
       if v_s.grade_band<>v_grade and exists(select 1 from public.chem_learning_plans p where p.student_id=v_id and p.plan_date>=v_today and app_private.chem_teaching_plan_started(p.id)) then raise exception '该生有进行中的题组，请完成后再更改年段'; end if;
       update public.chem_learning_plans set teaching_managed=true,teaching_source_grade=coalesce(teaching_source_grade,v_s.grade_band) where student_id=v_id and plan_date>=v_today and delivery_mode='legacy_round' and v_s.grade_band<>v_grade;
       update public.chem_students_v2 set display_name=v_name,grade_band=v_grade,teaching_class_id=v_class,
        textbook_version=case when v_ref.id is not null then v_ref.textbook_version when v_grade='初三' then '科粤版' when v_s.grade_band='初三' then '待确认' else textbook_version end,updated_at=now() where id=v_id;
     end if;
     insert into public.chem_student_aliases(student_id,alias) values(v_id,v_name) on conflict do nothing;
     if v_ref.id is not null then
       if exists(select 1 from public.chem_learning_plans p where p.student_id=v_id and p.plan_date>=v_today and p.mode='REVIEW' and app_private.chem_teaching_plan_started(p.id)) then raise exception '已有进行中的题组，不能覆盖起始进度'; end if;
       delete from public.chem_learning_plans where student_id=v_id and plan_date>=v_today and mode='REVIEW';
       insert into public.chem_learning_plans(student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,is_scheduled,knowledge_summaries,question_count,round_limit,max_question_level,target_concept_keys,delivery_mode,junior_curriculum_day_id,teaching_managed,teaching_source_grade)
        select v_id,plan_date,mode,title,skill_ids,estimated_minutes,source,is_scheduled,knowledge_summaries,question_count,round_limit,max_question_level,target_concept_keys,delivery_mode,junior_curriculum_day_id,teaching_managed,teaching_source_grade from public.chem_learning_plans where student_id=v_ref.id and plan_date>=v_today and mode='REVIEW';
       select coalesce(jsonb_object_agg(key,value),'{}') into v_assign from jsonb_each(coalesce(v_ref.metadata#>'{reviewProgram,questionAssignments}','{}')) where key>=v_today::text;
       select metadata->'reviewProgram' into v_program from public.chem_students_v2 where id=v_id;
       v_program=coalesce(v_program,'{}')||jsonb_build_object('participating',true,'choiceOnly',true,'startDate',greatest(v_today,coalesce((v_ref.metadata#>>'{reviewProgram,startDate}')::date,v_today)),'endDate',greatest(v_today,coalesce((v_ref.metadata#>>'{reviewProgram,endDate}')::date,v_today)),'allowedSkillIds',coalesce(v_ref.metadata#>'{reviewProgram,allowedSkillIds}','null'),'juniorUnitIds',coalesce(v_ref.metadata#>'{reviewProgram,juniorUnitIds}','null'),'questionAssignments',v_assign);
       if v_ref.metadata#>'{reviewProgram,dynamicAssignmentDates}' is not null then v_program=v_program||jsonb_build_object('dynamicAssignmentDates',v_ref.metadata#>'{reviewProgram,dynamicAssignmentDates}'); end if;
       if not (v_ref.metadata->'reviewProgram') ? 'questionAssignments' then v_program=v_program-'questionAssignments'; end if;
       if not (v_ref.metadata->'reviewProgram') ? 'allowedSkillIds' then v_program=v_program-'allowedSkillIds'; end if;
       if not (v_ref.metadata->'reviewProgram') ? 'juniorUnitIds' then v_program=v_program-'juniorUnitIds'; end if;
       update public.chem_students_v2 set metadata=jsonb_set(metadata,'{reviewProgram}',v_program)||jsonb_build_object('teacherSchedulingManaged',coalesce((v_ref.metadata->>'teacherSchedulingManaged')::boolean,false),'startingProgressReference',jsonb_build_object('studentId',v_ref.id,'copiedAt',now()),'confirmedLearnedSkillIds',coalesce(v_ref.metadata->'confirmedLearnedSkillIds','[]')),teaching_plan_items=v_ref.teaching_plan_items,updated_at=now() where id=v_id;
     end if;
     if v_op='create' then
       v_sc=lpad((('x'||encode(extensions.gen_random_bytes(4),'hex'))::bit(32)::bigint%100000000)::text,8,'0'); v_gc=lpad((('x'||encode(extensions.gen_random_bytes(4),'hex'))::bit(32)::bigint%100000000)::text,8,'0');
       while v_gc=v_sc loop v_gc=lpad((('x'||encode(extensions.gen_random_bytes(4),'hex'))::bit(32)::bigint%100000000)::text,8,'0'); end loop;
       perform public.chem_rotate_access_code(v_id,'student',v_sc); perform public.chem_rotate_access_code(v_id,'guardian',v_gc);
       v_codes=jsonb_build_object('studentCode',v_sc,'guardianCode',v_gc);
     end if;
   elsif v_op='archive' then
     update public.chem_students_v2 set record_status='archived',metadata=jsonb_set(metadata,'{reviewProgram}',coalesce(metadata->'reviewProgram','{}')||'{"participating":false}'),updated_at=now() where id=v_id;
     update app_private.chem_access_codes set active=false where student_id=v_id;
     update app_private.chem_app_sessions set revoked_at=now() where student_id=v_id and revoked_at is null;
   elsif v_op='restore' then
     if exists(select 1 from public.chem_students_v2 where display_name=v_s.display_name and record_status='active' and id<>v_id) then raise exception '已有同名在读档案，请先核对'; end if;
     update public.chem_students_v2 set record_status='active',metadata=jsonb_set(metadata,'{reviewProgram}',coalesce(metadata->'reviewProgram','{}')||'{"participating":true}'),updated_at=now() where id=v_id;
     update app_private.chem_access_codes set active=true,failed_count=0,locked_until=null where student_id=v_id;
   else raise exception '学生操作无效'; end if;
   insert into app_private.chem_teaching_changes(actor_name,action,target_id,before_state,after_state)
     select p_actor_name,p_action||':'||v_op,v_id::text,v_before,to_jsonb(s) from public.chem_students_v2 s where id=v_id;
   return jsonb_build_object('studentId',v_id,'accessCodes',v_codes,'message',case v_op when 'archive' then '学生已移出在读名单，历史记录保留' when 'restore' then '学生已恢复，原登录码可用' when 'create' then '学生已添加，个人学习记录从零开始' else '学生档案已保存' end);
 elsif p_action='preview_teaching_plan' then
   v_result=app_private.chem_build_teaching_preview(p_data); v_ids=array(select jsonb_array_elements_text(v_result->'studentIds')::uuid);
   if (v_result->>'canApply')::boolean then
     insert into app_private.chem_teaching_previews(actor_hash,request,result,state_hash) values(p_actor_hash,p_data,v_result,app_private.chem_teaching_state_hash(v_ids)) returning id into v_id;
   end if;
   return (v_result-'studentIds')||jsonb_build_object('previewToken',v_id);
 elsif p_action='apply_teaching_plan' then
   select * into strict v_p from app_private.chem_teaching_previews where id=(p_data->>'previewToken')::uuid and actor_hash=p_actor_hash for update;
   if v_p.applied_at is not null then return jsonb_build_object('message','该安排已经保存','appliedPlans',(v_p.result#>>'{summary,planCount}')::integer,'affectedStudents',(v_p.result#>>'{summary,studentCount}')::integer); end if;
   if v_p.expires_at<now() then raise exception '预览已过期，请重新预览'; end if;
   v_ids=array(select jsonb_array_elements_text(v_p.result->'studentIds')::uuid);
   perform 1 from public.chem_students_v2 where id=any(v_ids) order by id for update;
   perform 1 from public.chem_learning_plans where student_id=any(v_ids) order by id for update;
   v_result=app_private.chem_build_teaching_preview(v_p.request);
   if v_result is distinct from v_p.result or app_private.chem_teaching_state_hash(v_ids)<>v_p.state_hash then raise exception '学生进度、班级或题库在预览后有变化，请重新预览；原计划未改动'; end if;
   v_keep=array(select jsonb_array_elements_text(coalesce(v_p.request->'keepExistingPlanIds','[]'))::uuid);
   foreach v_student_id in array v_ids loop
     select to_jsonb(s) into v_before from public.chem_students_v2 s where id=v_student_id;
     select coalesce(metadata->'reviewProgram','{}') into v_program from public.chem_students_v2 where id=v_student_id;
     v_assign=coalesce(v_program->'questionAssignments','{}');
     select coalesce(jsonb_agg(pl.plan_date::text),'[]') into v_dynamic from public.chem_learning_plans pl
       where pl.student_id=v_student_id and pl.mode='REVIEW' and pl.id=any(v_keep) and not pl.teaching_managed
       and (not (v_assign ? pl.plan_date::text) or coalesce(v_program->'dynamicAssignmentDates','[]') ? pl.plan_date::text);
     update public.chem_learning_plans set is_scheduled=false where student_id=v_student_id and id=any(v_keep) and not app_private.chem_teaching_plan_started(id)
       and plan_date not between coalesce((v_program->>'startDate')::date,v_today) and coalesce((v_program->>'endDate')::date,v_today);

     for v_plan in select * from public.chem_learning_plans where student_id=v_student_id and mode='REVIEW' and plan_date>=v_today and not(id=any(v_keep)) and not app_private.chem_teaching_plan_started(id) loop
       v_assign=v_assign-v_plan.plan_date::text; delete from public.chem_learning_plans where id=v_plan.id;
     end loop;
     for v_day in select r->>'date' as plan_date,string_agg(r->>'title',' · ' order by n) title,min(r->>'sourceGrade') source_grade,
        jsonb_agg(r->'questionIds' order by n) id_arrays from jsonb_array_elements(v_result->'rows') with ordinality a(r,n) where r->>'studentId'=v_student_id::text group by 1 order by 1 loop
       v_qids=array(select jsonb_array_elements_text(a) from jsonb_array_elements(v_day.id_arrays) a);
       select array_agg(distinct skill_id order by skill_id),array_agg(distinct concept_key order by concept_key) filter(where concept_key is not null) into v_skills,v_concepts from public.chem_questions where id=any(v_qids);
       insert into public.chem_learning_plans(student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,question_count,round_limit,max_question_level,target_concept_keys,teaching_managed,teaching_source_grade)
        values(v_student_id,v_day.plan_date::date,'REVIEW',v_day.title,v_skills,least(60,greatest(5,cardinality(v_qids)*4)),'course',cardinality(v_qids),1,8,coalesce(v_concepts,'{}'),true,v_day.source_grade);
       v_assign=v_assign||jsonb_build_object(v_day.plan_date,to_jsonb(v_qids)); v_applied=v_applied+1;
     end loop;
     select min(plan_date),max(plan_date) into v_min,v_max from public.chem_learning_plans where student_id=v_student_id and mode='REVIEW' and plan_date>=v_today and is_scheduled;
     select array_agg(distinct k order by k) into v_skills from public.chem_learning_plans p cross join unnest(p.skill_ids) k where student_id=v_student_id and mode='REVIEW' and k ~ '^H[123]_[A-Z0-9_]+$';
     v_program=v_program||jsonb_build_object('participating',true,'choiceOnly',true,'startDate',least(coalesce((v_program->>'startDate')::date,v_min,v_today),coalesce(v_min,v_today)),'endDate',greatest(coalesce(v_max,v_today),coalesce((v_program->>'endDate')::date,v_today)),'questionAssignments',v_assign,'dynamicAssignmentDates',v_dynamic,'allowedSkillIds',coalesce(v_skills,'{}'));
     update public.chem_students_v2 set metadata=jsonb_set(metadata,'{reviewProgram}',v_program)||'{"teacherSchedulingManaged":true}'::jsonb,teaching_plan_items=v_p.request->'items',updated_at=now() where id=v_student_id;
     insert into app_private.chem_teaching_changes(actor_name,action,target_id,before_state,after_state) select p_actor_name,p_action,v_student_id::text,v_before,to_jsonb(s) from public.chem_students_v2 s where id=v_student_id;
   end loop;
   if v_p.request->>'targetType'='class' then update app_private.chem_teaching_classes set plan_items=v_p.request->'items',updated_at=now() where id=(v_p.request->>'targetId')::uuid; end if;
   update app_private.chem_teaching_previews set applied_at=now() where id=v_p.id;
   return jsonb_build_object('message','课程已保存，历史学习记录保留','appliedPlans',v_applied,'affectedStudents',cardinality(v_ids));
 end if;
 raise exception '未知的课程管理操作';
end $function$
;
