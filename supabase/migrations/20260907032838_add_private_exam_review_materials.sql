-- Exam source pages and worked analyses stay private and out of static hosting.
create table app_private.chem_exam_materials (
  id text primary key check (id ~ '^[a-z0-9_-]{1,100}$'),
  title text not null,
  content jsonb not null check (jsonb_typeof(content->'units')='array'),
  page_images jsonb not null default '[]'::jsonb,
  published_at timestamptz not null default now(),
  active boolean not null default true
);
create table app_private.chem_exam_recalls (
  student_id uuid not null references public.chem_students_v2(id),
  material_id text not null references app_private.chem_exam_materials(id),
  unit_id text not null,
  response text not null check (char_length(response) between 8 and 3000),
  self_rating text not null check (self_rating in ('understood','needs_help')),
  response_count integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (student_id,material_id,unit_id)
);
alter table app_private.chem_exam_materials enable row level security;
alter table app_private.chem_exam_recalls enable row level security;
revoke all on app_private.chem_exam_materials,app_private.chem_exam_recalls from public,anon,authenticated;
grant usage on schema app_private to service_role;
grant select on app_private.chem_exam_materials to service_role;
grant select,insert,update on app_private.chem_exam_recalls to service_role;

create function public.chem_get_exam_material(p_student_id uuid)
returns jsonb language sql security invoker set search_path='' as $function$
  select jsonb_build_object(
    'material',m.content||jsonb_build_object('id',m.id,'title',m.title,'pageCount',jsonb_array_length(m.page_images)),
    'recalls',coalesce((select jsonb_agg(jsonb_build_object('unitId',r.unit_id,'response',r.response,'selfRating',r.self_rating,'responseCount',r.response_count,'updatedAt',r.updated_at)) from app_private.chem_exam_recalls r where r.student_id=s.id and r.material_id=m.id),'[]'::jsonb),
    'evidence',coalesce((select jsonb_agg(jsonb_build_object('questionId',a.question_id,'correct',a.correct,'uncertain',a.uncertain,'completedAt',t.completed_at)) from public.chem_attempt_answers a join public.chem_learning_attempts t on t.id=a.attempt_id where t.student_id=s.id and t.mode='REVIEW' and t.completed_at>=m.published_at),'[]'::jsonb)
  ) from public.chem_students_v2 s join app_private.chem_exam_materials m on m.id=s.metadata->'reviewProgram'->>'examMaterialId'
  where s.id=p_student_id and s.record_status='active' and m.active;
$function$;

create function public.chem_get_exam_material_page(p_student_id uuid,p_page integer)
returns jsonb language sql security invoker set search_path='' as $function$
  select m.page_images->(p_page-1) from public.chem_students_v2 s
  join app_private.chem_exam_materials m on m.id=s.metadata->'reviewProgram'->>'examMaterialId'
  where s.id=p_student_id and s.record_status='active' and m.active
    and p_page between 1 and jsonb_array_length(m.page_images);
$function$;

create function public.chem_record_exam_recall(p_student_id uuid,p_unit_id text,p_response text,p_self_rating text)
returns jsonb language plpgsql security invoker set search_path='' as $function$
declare material_key text;
begin
  if char_length(btrim(p_response)) not between 8 and 3000 or p_self_rating not in ('understood','needs_help') then raise exception 'Invalid self-check response'; end if;
  select m.id into material_key from public.chem_students_v2 s join app_private.chem_exam_materials m on m.id=s.metadata->'reviewProgram'->>'examMaterialId'
    where s.id=p_student_id and s.record_status='active' and m.active and s.metadata->'reviewProgram'->>'participating'='true'
    and exists(select 1 from jsonb_array_elements(m.content->'units') u where u->>'id'=p_unit_id);
  if material_key is null then raise exception 'This self-check is not assigned to the student'; end if;
  insert into app_private.chem_exam_recalls(student_id,material_id,unit_id,response,self_rating)
    values(p_student_id,material_key,p_unit_id,btrim(p_response),p_self_rating)
  on conflict(student_id,material_id,unit_id) do update set response=excluded.response,self_rating=excluded.self_rating,response_count=chem_exam_recalls.response_count+1,updated_at=now();
  -- A written self-check is not a marked answer and never updates mastery or attempts.
  return jsonb_build_object('ok',true,'gradingStatus','ungraded_self_check');
end;
$function$;
revoke all on function public.chem_get_exam_material(uuid),public.chem_get_exam_material_page(uuid,integer),public.chem_record_exam_recall(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.chem_get_exam_material(uuid),public.chem_get_exam_material_page(uuid,integer),public.chem_record_exam_recall(uuid,text,text,text) to service_role;
