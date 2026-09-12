-- Teacher-only curriculum controls. Raw library metadata is never public.
create table app_private.chem_teaching_topics (
 id text primary key, parent_id text references app_private.chem_teaching_topics(id),
 title text not null, grade_bands text[] not null, sort_order integer not null default 0,
 evidence jsonb not null default '{}', updated_at timestamptz not null default now()
);
create table app_private.chem_teaching_question_topics (
 question_id text references public.chem_questions(id) on delete restrict,
 topic_id text references app_private.chem_teaching_topics(id) on delete cascade,
 evidence jsonb not null default '{}', primary key(question_id,topic_id)
);
create index on app_private.chem_teaching_question_topics(topic_id);
create table app_private.chem_teaching_materials (
 id text primary key, title text not null, source_locations jsonb not null default '[]',
 topic_ids text[] not null default '{}', status text not null default 'needs_review' check(status in ('ready','needs_review')),
 candidate_count bigint not null default 0 check(candidate_count>=0), duplicate_copies integer not null default 1,
 metadata jsonb not null default '{}', updated_at timestamptz not null default now()
);
create index on app_private.chem_teaching_materials using gin(topic_ids);
create table app_private.chem_teaching_classes (
 id uuid primary key default gen_random_uuid(), name text not null,
 grade_band text not null check(grade_band in ('初三','高一','高二','高三')),
 plan_items jsonb not null default '[]', updated_at timestamptz not null default now(), unique(name,grade_band)
);
alter table public.chem_students_v2 add column teaching_class_id uuid references app_private.chem_teaching_classes(id);
alter table public.chem_students_v2 add column teaching_plan_items jsonb not null default '[]';
alter table public.chem_students_v2 drop constraint chem_students_v2_record_status_check;
alter table public.chem_students_v2 add constraint chem_students_v2_record_status_check check(record_status in ('active','legacy','pending','archived'));
create index on public.chem_students_v2(teaching_class_id);
alter table public.chem_learning_plans add column teaching_managed boolean not null default false;
alter table public.chem_learning_plans add column teaching_source_grade text check(teaching_source_grade in ('初三','高一','高二','高三'));
alter table public.chem_learning_plans add constraint chem_teaching_source_required check(not teaching_managed or teaching_source_grade is not null);
create table app_private.chem_teaching_previews (
 id uuid primary key default gen_random_uuid(), actor_hash text not null, request jsonb not null,
 result jsonb not null, state_hash text not null, expires_at timestamptz not null default now()+interval '30 minutes', applied_at timestamptz
);
create table app_private.chem_teaching_changes (
 id bigint generated always as identity primary key, actor_name text not null, action text not null,
 target_id text, before_state jsonb, after_state jsonb, created_at timestamptz not null default now()
);
alter table app_private.chem_teaching_topics enable row level security;
alter table app_private.chem_teaching_question_topics enable row level security;
alter table app_private.chem_teaching_materials enable row level security;
alter table app_private.chem_teaching_classes enable row level security;
alter table app_private.chem_teaching_previews enable row level security;
alter table app_private.chem_teaching_changes enable row level security;

create function app_private.chem_teaching_plan_started(p_plan_id uuid) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from public.chem_learning_attempts where plan_day_id=p_plan_id)
 or exists(select 1 from app_private.chem_question_answer_locks where plan_day_id=p_plan_id)
 or exists(select 1 from public.chem_junior_daily_sessions where plan_day_id=p_plan_id);
$$;
create function app_private.chem_teaching_identities(p_id text,p_mother text,p_source text,p_fingerprint text,p_parent text)
 returns text[] language sql immutable set search_path='' as $$
 select array_remove(array['id:'||nullif(p_id,''),'mother:'||nullif(p_mother,''),'source:'||nullif(p_source,''),
 'fp:'||nullif(p_fingerprint,''),'source:'||nullif(p_parent,'')],null);
$$;
create view app_private.chem_teaching_ready_questions as
 select q.* from public.chem_questions q
 join app_private.chem_question_source_releases r on r.id=q.source_release_id
 where q.review_status='approved' and q.scope_status='IN' and q.usable_for_review
 and r.status='active' and r.verification_status='full_visual_verified' and r.manifest_sha256=r.verification_manifest_sha256
 and jsonb_typeof(q.options)='array' and jsonb_array_length(q.options)=4 and q.correct_option between 0 and 3
 and length(btrim(q.stem))>0 and length(btrim(q.explanation))>0 and q.content_fingerprint is not null and q.source_item_key is not null
 and not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=q.id)
 and ((q.grade_band in ('高一','高二','高三') and q.source_kind='licensed_local' and q.render_mode='image_primary'
       and exists(select 1 from public.chem_active_verified_source_releases() a where a.source_release_id=q.source_release_id and a.grade_band=q.grade_band))
   or (q.grade_band='初三' and q.source_kind='user_provided_local' and q.render_mode='native' and q.textbook_version='科粤版'
       and exists(select 1 from public.chem_junior_verified_provenance_rows('科粤版',array[q.knowledge_id]) a
          where a.source_release_id=q.source_release_id and a.source_release_ready and a.verification_status='verified')));

create function app_private.chem_teaching_state_hash(p_ids uuid[]) returns text language sql stable set search_path='' as $$
 select md5(jsonb_build_object(
 'students',(select jsonb_agg(to_jsonb(s) order by s.id) from public.chem_students_v2 s where s.id=any(p_ids)),
 'plans',(select jsonb_agg(to_jsonb(p) order by p.id) from public.chem_learning_plans p where p.student_id=any(p_ids)),
 'attempts',(select jsonb_agg(to_jsonb(a) order by a.id) from public.chem_learning_attempts a where a.student_id=any(p_ids)),
 'locks',(select jsonb_agg(to_jsonb(l) order by l.plan_day_id,l.question_id) from app_private.chem_question_answer_locks l where l.student_id=any(p_ids)),
 'junior',(select jsonb_agg(to_jsonb(j) order by j.id) from public.chem_junior_daily_sessions j where j.student_id=any(p_ids)),
 'releases',(select jsonb_agg(to_jsonb(r) order by r.id) from app_private.chem_question_source_releases r where r.status='active'),
 'topics',(select max(updated_at) from app_private.chem_teaching_topics)
 )::text);
$$;

create function app_private.chem_build_teaching_preview(p_data jsonb) returns jsonb language plpgsql set search_path='' as $$
declare v_ids uuid[]; v_item jsonb; v_rows jsonb='[]'; v_warnings jsonb='[]'; v_student record; v_topic record; v_q record;
 v_date date; v_count integer; v_selected text[]; v_used text[]; v_all_used text[]; v_reason text; v_grade text;
 v_can boolean=true; v_day record; v_today date=(now() at time zone 'Asia/Shanghai')::date;
begin
 if p_data->>'targetType'='student' then
   select array_agg(id order by id) into v_ids from public.chem_students_v2 where id=(p_data->>'targetId')::uuid and record_status='active' and not coalesce((metadata->>'demo')::boolean,false);
 elsif p_data->>'targetType'='class' then
   select array_agg(id order by id) into v_ids from public.chem_students_v2 where teaching_class_id=(p_data->>'targetId')::uuid and record_status='active' and not coalesce((metadata->>'demo')::boolean,false);
 else raise exception '请选择学生或班级'; end if;
 if coalesce(cardinality(v_ids),0)=0 then raise exception '该目标没有在读学生'; end if;
 if p_data->'replaceFuture' is distinct from 'true'::jsonb then raise exception '排课请求缺少替换范围'; end if;
 if jsonb_typeof(p_data->'items') is distinct from 'array' or jsonb_array_length(p_data->'items')>200 then raise exception '课程列表无效或超过200项'; end if;
 for v_item in select value from jsonb_array_elements(p_data->'items') loop
   if (v_item->>'date') !~ '^\d{4}-\d{2}-\d{2}$' or (v_item->>'questionCount') !~ '^[1-8]$' then raise exception '请填写有效日期和1—8道题'; end if;
   v_date=(v_item->>'date')::date;
   if v_date<v_today or v_date>v_today+730 then raise exception '只能调整今天至未来两年的课程'; end if;
   if not exists(select 1 from app_private.chem_teaching_topics where id=v_item->>'topicId') then raise exception '课程知识点已不存在，请刷新目录'; end if;
 end loop;
 for v_student in select * from public.chem_students_v2 where id=any(v_ids) order by id loop
   select coalesce(array_agg(distinct k),'{}') into v_all_used from (
     select unnest(app_private.chem_teaching_identities(a.question_id,a.mother_id,coalesce(a.question_snapshot->>'sourceItemKey',q.source_item_key),coalesce(a.question_snapshot->>'contentFingerprint',q.content_fingerprint),coalesce(a.question_snapshot->>'parentSourceItemKey',q.parent_source_item_key))) k
       from public.chem_attempt_answers a join public.chem_learning_attempts h on h.id=a.attempt_id left join public.chem_questions q on q.id=a.question_id where h.student_id=v_student.id
     union all select unnest(app_private.chem_teaching_identities(q.id,q.mother_id,q.source_item_key,q.content_fingerprint,q.parent_source_item_key))
       from app_private.chem_question_answer_locks l join public.chem_questions q on q.id=l.question_id where l.student_id=v_student.id
     union all select unnest(app_private.chem_teaching_identities(st.question_id,st.mother_id,st.source_item_key,st.content_fingerprint,st.parent_source_item_key))
       from public.chem_junior_session_steps st join public.chem_junior_daily_sessions se on se.id=st.session_id where se.student_id=v_student.id
   ) h;
   if exists(select 1 from public.chem_learning_plans p where p.student_id=v_student.id and p.mode='REVIEW' and p.plan_date>=v_today and app_private.chem_teaching_plan_started(p.id)) then
      v_warnings=v_warnings||jsonb_build_array(v_student.display_name||'：已开始的题组与历史记录会保留。');
   end if;
   for v_item in select value from jsonb_array_elements(p_data->'items') with ordinality a(value,n) order by value->>'date',n loop
     v_date=(v_item->>'date')::date; v_count=(v_item->>'questionCount')::integer; v_selected='{}'; v_reason=null; v_grade=null;
     select * into v_topic from app_private.chem_teaching_topics where id=v_item->>'topicId';
     if exists(select 1 from public.chem_learning_plans p where p.student_id=v_student.id and p.mode='REVIEW' and p.plan_date=v_date and app_private.chem_teaching_plan_started(p.id)) then
       v_reason='该日期已经开始作答，请换一个未开始的日期。';
     else
       -- Prefer the student's own source grade; choose a single attested source release per day.
       select q.grade_band into v_grade from app_private.chem_teaching_ready_questions q
         join app_private.chem_teaching_question_topics m on m.question_id=q.id where m.topic_id=v_topic.id
         group by q.grade_band order by (q.grade_band=v_student.grade_band) desc,count(*) desc,q.grade_band limit 1;
       for v_q in select q.* from app_private.chem_teaching_ready_questions q join app_private.chem_teaching_question_topics m on m.question_id=q.id
         where m.topic_id=v_topic.id and q.grade_band=v_grade order by q.level,q.id loop
         v_used=app_private.chem_teaching_identities(v_q.id,v_q.mother_id,v_q.source_item_key,v_q.content_fingerprint,v_q.parent_source_item_key);
         if v_all_used && v_used then continue; end if;
         v_selected=array_append(v_selected,v_q.id); v_all_used=v_all_used||v_used;
         exit when cardinality(v_selected)=v_count;
       end loop;
       if cardinality(v_selected)<v_count then v_reason=format('需要%s道独立原题，目前只有%s道已核对且该生未做过的题。待核对材料不能下发。',v_count,cardinality(v_selected)); end if;
     end if;
     if v_reason is not null then v_can=false; end if;
     v_rows=v_rows||jsonb_build_array(jsonb_build_object('studentId',v_student.id,'studentName',v_student.display_name,'date',v_date,'title',v_topic.title,'topicId',v_topic.id,'questionCount',v_count,'questionIds',v_selected,'sourceGrade',v_grade,'status',case when v_reason is null then 'ready' else 'blocked' end,'reason',v_reason));
   end loop;
 end loop;
 for v_day in select r->>'studentId' student_id,r->>'date' as plan_date,sum((r->>'questionCount')::integer) qty,count(distinct r->>'sourceGrade') grades from jsonb_array_elements(v_rows) r group by 1,2 loop
   if v_day.qty>8 or v_day.grades>1 then
     v_can=false; v_warnings=v_warnings||jsonb_build_array(v_day.plan_date||'：同日合并最多8道基础题，同一天请选择同一套年段题源的内容。');
   end if;
 end loop;
 return jsonb_build_object('canApply',v_can,'rows',v_rows,'warnings',v_warnings,'studentIds',v_ids,'summary',jsonb_build_object('studentCount',cardinality(v_ids),'planCount',(select count(distinct (r->>'studentId',r->>'date')) from jsonb_array_elements(v_rows) r),'questionCount',coalesce((select sum((r->>'questionCount')::integer) from jsonb_array_elements(v_rows) r),0)));
end $$;

create function public.chem_teacher_management(p_action text,p_data jsonb,p_actor_hash text,p_actor_name text)
 returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_ref public.chem_students_v2; v_s public.chem_students_v2; v_before jsonb; v_result jsonb; v_p app_private.chem_teaching_previews;
 v_op text=p_data->>'operation'; v_name text=btrim(p_data->>'displayName'); v_grade text=p_data->>'gradeBand'; v_class uuid=nullif(p_data->>'classId','')::uuid;
 v_ids uuid[]; v_student_id uuid; v_day record; v_plan record; v_date date; v_program jsonb; v_assign jsonb; v_qids text[]; v_skills text[]; v_concepts text[];
 v_title text; v_min date; v_max date; v_today date=(now() at time zone 'Asia/Shanghai')::date;
 v_codes jsonb; v_sc text; v_gc text; v_page integer; v_size integer; v_total bigint; v_rows jsonb; v_applied integer=0;
begin
 if p_actor_hash !~ '^[0-9a-f]{64}$' or length(btrim(p_actor_name))=0 then raise exception '教师身份无效'; end if;
 -- All changes and preview publication share a transaction lock. Learner evidence is also rechecked at apply.
 perform pg_advisory_xact_lock(66820260908);
 if p_action='teaching_catalog' then
   return jsonb_build_object('catalogVersion',coalesce((select max(updated_at)::text from app_private.chem_teaching_topics),''),
    'topics',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'parentId',t.parent_id,'title',t.title,'gradeBands',t.grade_bands,'order',t.sort_order,
      'readyQuestionCount',(select count(distinct q.id) from app_private.chem_teaching_question_topics m join app_private.chem_teaching_ready_questions q on q.id=m.question_id where m.topic_id=t.id),
      'pendingQuestionCount',coalesce((select sum(candidate_count) from app_private.chem_teaching_materials m where t.id=any(m.topic_ids) and m.status='needs_review'),0)) order by t.sort_order,t.id) from app_private.chem_teaching_topics t),'[]'),
    'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'gradeBand',c.grade_band,'memberCount',(select count(*) from public.chem_students_v2 s where s.teaching_class_id=c.id and s.record_status='active'),'planItems',c.plan_items) order by c.grade_band,c.name) from app_private.chem_teaching_classes c),'[]'),
    'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'displayName',s.display_name,'gradeBand',s.grade_band,'classId',s.teaching_class_id,'className',coalesce(c.name,''),'status',case when s.record_status='active' and coalesce(s.metadata#>>'{reviewProgram,participating}','true')='true' then 'active' else 'archived' end,
      'progressSummary',coalesce((select string_agg(distinct t.title,'、') from jsonb_array_elements(s.teaching_plan_items) i join app_private.chem_teaching_topics t on t.id=i->>'topicId'),(select string_agg(distinct p.title,'；') from public.chem_learning_plans p where p.student_id=s.id and p.plan_date>=v_today and p.mode='REVIEW'), '暂未安排'),
      'topicIds',coalesce((select jsonb_agg(distinct i->>'topicId') from jsonb_array_elements(s.teaching_plan_items) i),'[]'),'planItems',s.teaching_plan_items,'textbookVersion',s.textbook_version) order by s.grade_band,s.display_name) from public.chem_students_v2 s left join app_private.chem_teaching_classes c on c.id=s.teaching_class_id where not coalesce((s.metadata->>'demo')::boolean,false)),'[]'));
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
       select * into strict v_ref from public.chem_students_v2 where id=(p_data->>'referenceStudentId')::uuid and record_status='active' and grade_band=v_grade and not coalesce((metadata->>'demo')::boolean,false);
       if v_ref.id=v_id then raise exception '不能参照自己'; end if;
       if not p_data ? 'classId' then v_class=v_ref.teaching_class_id; end if;
     end if;
     if v_op='create' then
       insert into public.chem_students_v2(display_name,grade_band,textbook_version,teaching_class_id,metadata)
        values(v_name,v_grade,coalesce(v_ref.textbook_version,case when v_grade='初三' then '科粤版' else '待确认' end),v_class,jsonb_build_object('source','teacher_management','reviewProgram',jsonb_build_object('participating',true,'startDate',v_today,'endDate',v_today))) returning id into v_id;
     else
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
       update public.chem_students_v2 set metadata=jsonb_set(metadata,'{reviewProgram}',v_program)||jsonb_build_object('startingProgressReference',jsonb_build_object('studentId',v_ref.id,'copiedAt',now()),'confirmedLearnedSkillIds',coalesce(v_ref.metadata->'confirmedLearnedSkillIds','[]')),teaching_plan_items=v_ref.teaching_plan_items,updated_at=now() where id=v_id;
     end if;
     if v_op='create' then
       v_sc=lpad((floor(random()*100000000)::bigint)::text,8,'0'); v_gc=lpad((floor(random()*100000000)::bigint)::text,8,'0');
       while v_gc=v_sc loop v_gc=lpad((floor(random()*100000000)::bigint)::text,8,'0'); end loop;
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
   foreach v_student_id in array v_ids loop
     select to_jsonb(s) into v_before from public.chem_students_v2 s where id=v_student_id;
     select coalesce(metadata->'reviewProgram','{}') into v_program from public.chem_students_v2 where id=v_student_id;
     v_assign=coalesce(v_program->'questionAssignments','{}');
     for v_plan in select * from public.chem_learning_plans where student_id=v_student_id and mode='REVIEW' and plan_date>=v_today and not app_private.chem_teaching_plan_started(id) loop
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
     select min(plan_date),max(plan_date) into v_min,v_max from public.chem_learning_plans where student_id=v_student_id and mode='REVIEW' and plan_date>=v_today;
     select array_agg(distinct k order by k) into v_skills from public.chem_learning_plans p cross join unnest(p.skill_ids) k where student_id=v_student_id and mode='REVIEW';
     v_program=v_program||jsonb_build_object('participating',true,'choiceOnly',true,'startDate',least(coalesce((v_program->>'startDate')::date,v_min,v_today),coalesce(v_min,v_today)),'endDate',greatest(coalesce(v_max,v_today),coalesce((v_program->>'endDate')::date,v_today)),'questionAssignments',v_assign,'allowedSkillIds',coalesce(v_skills,'{}'));
     update public.chem_students_v2 set metadata=jsonb_set(metadata,'{reviewProgram}',v_program),teaching_plan_items=v_p.request->'items',updated_at=now() where id=v_student_id;
     insert into app_private.chem_teaching_changes(actor_name,action,target_id,before_state,after_state) select p_actor_name,p_action,v_student_id::text,v_before,to_jsonb(s) from public.chem_students_v2 s where id=v_student_id;
   end loop;
   if v_p.request->>'targetType'='class' then update app_private.chem_teaching_classes set plan_items=v_p.request->'items',updated_at=now() where id=(v_p.request->>'targetId')::uuid; end if;
   update app_private.chem_teaching_previews set applied_at=now() where id=v_p.id;
   return jsonb_build_object('message','课程已保存，历史学习记录保留','appliedPlans',v_applied,'affectedStudents',cardinality(v_ids));
 end if;
 raise exception '未知的课程管理操作';
end $$;
revoke all on function public.chem_teacher_management(text,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.chem_teacher_management(text,jsonb,text,text) to service_role;
revoke all on all tables in schema app_private from public,anon,authenticated;
revoke all on function app_private.chem_teaching_plan_started(uuid),app_private.chem_teaching_identities(text,text,text,text,text),app_private.chem_teaching_state_hash(uuid[]),app_private.chem_build_teaching_preview(jsonb) from public,anon,authenticated;
