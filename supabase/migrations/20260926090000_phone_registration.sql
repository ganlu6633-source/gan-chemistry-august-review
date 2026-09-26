-- Phone registration is teacher approved. Passwords and phone numbers stay in the private schema.
create table app_private.chem_registration_requests (
  id uuid primary key default gen_random_uuid(),
  role text not null check (role in ('student','guardian')),
  display_name text not null,
  phone text not null,
  password_hash text not null,
  grade_band text check (grade_band in ('初三','高一','高二','高三')),
  child_name text,
  child_phone text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  student_id uuid references public.chem_students_v2(id),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by text,
  check ((role='student' and grade_band is not null and child_name is null and child_phone is null)
      or (role='guardian' and grade_band is null and child_name is not null and child_phone is not null))
);
create unique index chem_registration_one_pending_phone on app_private.chem_registration_requests(role,phone) where status='pending';
create index chem_registration_pending_date on app_private.chem_registration_requests(created_at) where status='pending';

create table app_private.chem_phone_accounts (
  id uuid primary key default gen_random_uuid(),
  role text not null check (role in ('student','guardian')),
  phone text not null,
  display_name text not null,
  password_hash text not null,
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  active boolean not null default true,
  failed_count integer not null default 0,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  unique(role,phone)
);
create unique index chem_phone_one_student_account on app_private.chem_phone_accounts(student_id) where role='student' and active;
create table app_private.chem_student_phones (
  student_id uuid primary key references public.chem_students_v2(id) on delete cascade,
  phone text not null unique,
  verified_by_teacher_at timestamptz not null default now()
);
create table app_private.chem_registration_attempts (
  id bigint generated always as identity primary key,
  fingerprint_hash text not null,
  attempted_at timestamptz not null default now()
);
create index chem_registration_attempts_fingerprint on app_private.chem_registration_attempts(fingerprint_hash,attempted_at desc);

alter table app_private.chem_registration_requests enable row level security;
alter table app_private.chem_phone_accounts enable row level security;
alter table app_private.chem_student_phones enable row level security;
alter table app_private.chem_registration_attempts enable row level security;
revoke all on app_private.chem_registration_requests,app_private.chem_phone_accounts,app_private.chem_student_phones,app_private.chem_registration_attempts from public,anon,authenticated;
revoke all on sequence app_private.chem_registration_attempts_id_seq from public,anon,authenticated;

create function public.chem_submit_registration(p_data jsonb,p_fingerprint_hash text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_role text=p_data->>'role'; v_name text=btrim(p_data->>'displayName'); v_phone text=p_data->>'phone';
  v_password text=p_data->>'password'; v_grade text=p_data->>'gradeBand'; v_child_name text=btrim(p_data->>'childName');
  v_child_phone text=p_data->>'childPhone';
begin
  perform pg_advisory_xact_lock(hashtext(p_fingerprint_hash));
  if p_fingerprint_hash !~ '^[0-9a-f]{64}$' or
     (select count(*) from app_private.chem_registration_attempts where fingerprint_hash=p_fingerprint_hash and attempted_at>now()-interval '1 hour')>=5 then return false; end if;
  insert into app_private.chem_registration_attempts(fingerprint_hash) values(p_fingerprint_hash);
  if v_role is null or v_role not in ('student','guardian') or char_length(v_name) not between 1 and 30 or v_name is null or
     v_phone is null or v_phone !~ '^1[3-9][0-9]{9}$' or v_password is null or char_length(v_password) not between 6 and 12 or
     v_password ~ '[[:cntrl:]]' or v_password <> btrim(v_password) or
     (v_role='student' and (v_grade not in ('初三','高一','高二','高三') or v_grade is null)) or
     (v_role='guardian' and (v_child_name is null or char_length(v_child_name) not between 1 and 40 or v_child_phone is null or v_child_phone !~ '^1[3-9][0-9]{9}$')) then return false; end if;
  if exists(select 1 from app_private.chem_phone_accounts where role=v_role and phone=v_phone) then return true; end if;
  insert into app_private.chem_registration_requests(role,display_name,phone,password_hash,grade_band,child_name,child_phone)
  values(v_role,v_name,v_phone,extensions.crypt(v_password,extensions.gen_salt('bf',10)),
    case when v_role='student' then v_grade else null end,
    case when v_role='guardian' then v_child_name else null end,
    case when v_role='guardian' then v_child_phone else null end)
  on conflict (role,phone) where status='pending' do nothing;
  return true;
end $$;

create function public.chem_exchange_phone_password(p_role text,p_phone text,p_password text,p_fingerprint_hash text,p_token_hash text,p_expires_at timestamptz)
returns table(student_id uuid,access_role text,principal_name text)
language plpgsql security definer set search_path='' as $$
declare v_account app_private.chem_phone_accounts%rowtype; v_code uuid; v_name text;
begin
  if p_fingerprint_hash !~ '^[0-9a-f]{64}$' or p_token_hash !~ '^[0-9a-f]{64}$' or
     p_expires_at>now()+interval '12 hours' or p_expires_at<=now() or
     (select count(*) from app_private.chem_login_attempts where fingerprint_hash=p_fingerprint_hash and not succeeded and attempted_at>now()-interval '15 minutes')>=10 then return; end if;
  if p_role not in ('student','guardian') or p_phone !~ '^1[3-9][0-9]{9}$' or char_length(p_password) not between 6 and 12 then return; end if;
  select a.* into v_account from app_private.chem_phone_accounts a
  join public.chem_students_v2 s on s.id=a.student_id and s.record_status='active'
  where a.role=p_role and a.phone=p_phone and a.active and coalesce(a.locked_until,'-infinity'::timestamptz)<=now() for update of a;
  if not found or v_account.password_hash<>extensions.crypt(p_password,v_account.password_hash) then
    insert into app_private.chem_login_attempts(fingerprint_hash,succeeded) values(p_fingerprint_hash,false);
    if v_account.id is not null then update app_private.chem_phone_accounts set failed_count=failed_count+1,
      locked_until=case when failed_count>=4 then now()+interval '15 minutes' else null end where id=v_account.id; end if;
    return;
  end if;
  select id into v_code from app_private.chem_access_codes where student_id=v_account.student_id and role=v_account.role and active;
  if v_code is null then return; end if;
  update app_private.chem_phone_accounts set failed_count=0,locked_until=null where id=v_account.id;
  insert into app_private.chem_login_attempts(fingerprint_hash,succeeded) values(p_fingerprint_hash,true);
  v_name:=v_account.display_name;
  if p_role='guardian' then
    insert into app_private.chem_guardian_contacts(student_id,display_name,normalized_name)
    values(v_account.student_id,v_name,lower(regexp_replace(v_name,'\s+','','g')))
    on conflict on constraint chem_guardian_contacts_student_id_normalized_name_key do update
      set last_seen_at=now(),login_count=app_private.chem_guardian_contacts.login_count+1;
  end if;
  insert into app_private.chem_app_sessions(access_code_id,student_id,role,token_hash,expires_at,principal_name,access_scope)
    values(v_code,v_account.student_id,p_role,p_token_hash,p_expires_at,v_name,'unified');
  return query select v_account.student_id,p_role,v_name;
end $$;

create function public.chem_list_registration_requests(p_actor_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from app_private.chem_app_sessions where token_hash=p_actor_hash and role='teacher' and revoked_at is null and expires_at>now() and access_scope='unified') then raise exception '教师身份已失效'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'role',role,'displayName',display_name,'phone',phone,
    'gradeBand',grade_band,'childName',child_name,'childPhone',child_phone,'createdAt',created_at) order by created_at)
    from app_private.chem_registration_requests where status='pending'),'[]'::jsonb);
end $$;

create function public.chem_review_registration(p_request_id uuid,p_decision text,p_student_id uuid,p_class_id uuid,p_reference_student_id uuid,p_actor_hash text,p_actor_name text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_request app_private.chem_registration_requests%rowtype; v_student public.chem_students_v2%rowtype; v_created jsonb; v_student_id uuid=p_student_id;
begin
  if not exists(select 1 from app_private.chem_app_sessions where token_hash=p_actor_hash and role='teacher' and revoked_at is null and expires_at>now() and access_scope='unified') then raise exception '教师身份已失效'; end if;
  select * into v_request from app_private.chem_registration_requests where id=p_request_id and status='pending' for update;
  if not found then raise exception '申请已处理，请刷新列表'; end if;
  if p_decision='reject' then
    update app_private.chem_registration_requests set status='rejected',reviewed_at=now(),reviewed_by=p_actor_name where id=p_request_id;
    return jsonb_build_object('message','已拒绝申请');
  end if;
  if p_decision<>'approve' then raise exception '审核操作无效'; end if;
  if v_request.role='student' and v_student_id is null then
    v_created:=public.chem_teacher_management('manage_student',jsonb_build_object('operation','create','displayName',v_request.display_name,
      'gradeBand',v_request.grade_band,'classId',p_class_id,'referenceStudentId',p_reference_student_id),p_actor_hash,p_actor_name);
    v_student_id:=(v_created->>'studentId')::uuid;
  end if;
  if v_student_id is null then raise exception '请先选择对应学生'; end if;
  select * into v_student from public.chem_students_v2 where id=v_student_id and record_status='active' for update;
  if not found then raise exception '学生档案不存在'; end if;
  if v_request.role='student' and (v_student.display_name<>v_request.display_name or v_student.grade_band<>v_request.grade_band) then raise exception '学生姓名或年段与档案不一致'; end if;
  if v_request.role='guardian' and v_student.display_name<>v_request.child_name then raise exception '孩子姓名与档案不一致'; end if;
  if exists(select 1 from app_private.chem_student_phones where student_id=v_student_id and phone<>case when v_request.role='student' then v_request.phone else v_request.child_phone end) then raise exception '孩子手机号与已核对号码不一致'; end if;
  if exists(select 1 from app_private.chem_student_phones where phone=case when v_request.role='student' then v_request.phone else v_request.child_phone end and student_id<>v_student_id) then raise exception '该孩子手机号已绑定其他档案'; end if;
  insert into app_private.chem_student_phones(student_id,phone) values(v_student_id,case when v_request.role='student' then v_request.phone else v_request.child_phone end) on conflict(student_id) do nothing;
  if exists(select 1 from app_private.chem_phone_accounts where role=v_request.role and phone=v_request.phone) then raise exception '该手机号已有账号'; end if;
  if v_request.role='student' and exists(select 1 from app_private.chem_phone_accounts where role='student' and student_id=v_student_id and active) then raise exception '该学生已有手机号账号'; end if;
  if not exists(select 1 from app_private.chem_access_codes where student_id=v_student_id and role=v_request.role and active) then raise exception '学生档案缺少可用登录码，请先在权限设置中生成'; end if;
  insert into app_private.chem_phone_accounts(role,phone,display_name,password_hash,student_id)
    values(v_request.role,v_request.phone,v_request.display_name,v_request.password_hash,v_student_id);
  if v_request.role='guardian' then
    insert into app_private.chem_guardian_contacts(student_id,display_name,normalized_name)
    values(v_student_id,v_request.display_name,lower(regexp_replace(v_request.display_name,'\s+','','g')))
    on conflict on constraint chem_guardian_contacts_student_id_normalized_name_key do nothing;
  end if;
  update app_private.chem_registration_requests set status='approved',student_id=v_student_id,reviewed_at=now(),reviewed_by=p_actor_name where id=p_request_id;
  return jsonb_build_object('message','已开通手机号登录','studentId',v_student_id);
end $$;

revoke all on function public.chem_submit_registration(jsonb,text),public.chem_exchange_phone_password(text,text,text,text,text,timestamptz),
  public.chem_list_registration_requests(text),public.chem_review_registration(uuid,text,uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.chem_submit_registration(jsonb,text),public.chem_exchange_phone_password(text,text,text,text,text,timestamptz),
  public.chem_list_registration_requests(text),public.chem_review_registration(uuid,text,uuid,uuid,uuid,text,text) to service_role;
