-- Flexible unified-login codes, private recovery phrases, and privacy-safe demo grades.
-- All callable helpers below are service-role only. The browser never receives a hash.

alter table app_private.chem_access_codes
  add column if not exists access_scope text not null default 'unified',
  add column if not exists recovery_secret_hash text,
  add column if not exists recovery_failed_count integer not null default 0,
  add column if not exists recovery_locked_until timestamptz,
  add column if not exists recovery_set_at timestamptz,
  add column if not exists last_recovered_at timestamptz;

alter table app_private.chem_app_sessions
  add column if not exists access_scope text not null default 'unified';

do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'chem_access_codes_access_scope_check'
      and conrelid = 'app_private.chem_access_codes'::regclass
  ) then
    alter table app_private.chem_access_codes
      add constraint chem_access_codes_access_scope_check
      check (access_scope in ('unified','quiz_audit'));
  end if;

  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'chem_app_sessions_access_scope_check'
      and conrelid = 'app_private.chem_app_sessions'::regclass
  ) then
    alter table app_private.chem_app_sessions
      add constraint chem_app_sessions_access_scope_check
      check (access_scope in ('unified','quiz_audit'));
  end if;
end $$;

drop index if exists app_private.chem_access_codes_teacher_name_unique;
create unique index if not exists chem_access_codes_teacher_name_scope_unique
  on app_private.chem_access_codes(lower(principal_name),access_scope)
  where role='teacher' and active;

create table if not exists app_private.chem_recovery_attempts (
  id bigint generated always as identity primary key,
  fingerprint_hash text not null,
  succeeded boolean not null,
  attempted_at timestamptz not null default now()
);

create index if not exists chem_recovery_attempts_fingerprint_idx
  on app_private.chem_recovery_attempts(fingerprint_hash,attempted_at desc);

alter table app_private.chem_recovery_attempts enable row level security;
drop policy if exists chem_recovery_attempts_deny_client_access on app_private.chem_recovery_attempts;
create policy chem_recovery_attempts_deny_client_access
  on app_private.chem_recovery_attempts
  for all to public
  using (false)
  with check (false);
revoke all on table app_private.chem_recovery_attempts from public,anon,authenticated;
revoke all on sequence app_private.chem_recovery_attempts_id_seq from public,anon,authenticated;

create or replace function public.chem_exchange_access_code(
  p_name text,
  p_code text,
  p_fingerprint_hash text,
  p_token_hash text,
  p_expires_at timestamptz
)
returns table(student_id uuid, access_role text, principal_name text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  candidate app_private.chem_access_codes%rowtype;
  recent_failures integer;
  normalized_input text;
  canonical_student_name text;
  session_name text;
begin
  normalized_input := lower(regexp_replace(btrim(coalesce(p_name,'')), '\s+', '', 'g'));

  select count(*) into recent_failures
  from app_private.chem_login_attempts
  where fingerprint_hash=p_fingerprint_hash
    and not succeeded
    and attempted_at>now()-interval '15 minutes';
  if recent_failures>=10 then return; end if;

  if p_code !~ '^[0-9]{6,12}$' or char_length(normalized_input) not between 1 and 30 then
    insert into app_private.chem_login_attempts(fingerprint_hash,succeeded)
    values(p_fingerprint_hash,false);
    return;
  end if;

  for candidate in
    select * from app_private.chem_access_codes
    where active
      and access_scope='unified'
      and code_prefix=left(p_code,2)
      and coalesce(locked_until,'-infinity'::timestamptz)<=now()
    order by case when role='teacher' then 0 else 1 end,created_at
  loop
    if candidate.code_hash=extensions.crypt(p_code,candidate.code_hash) then
      if candidate.role='teacher' then
        -- There is one private teacher code. The entered non-empty name is only
        -- the session label, so the teacher may use any convenient name.
        session_name := btrim(p_name);
      elsif candidate.role='student' then
        canonical_student_name := null;
        select s.display_name into canonical_student_name
        from public.chem_students_v2 s
        where s.id=candidate.student_id
          and (
            lower(regexp_replace(btrim(s.display_name), '\s+', '', 'g'))=normalized_input
            or exists (
              select 1 from public.chem_student_aliases a
              where a.student_id=s.id
                and lower(regexp_replace(btrim(a.alias), '\s+', '', 'g'))=normalized_input
            )
          );
        if canonical_student_name is null then continue; end if;
        session_name := canonical_student_name;
      else
        insert into app_private.chem_guardian_contacts(student_id,display_name,normalized_name)
        values(candidate.student_id,btrim(p_name),normalized_input)
        on conflict on constraint chem_guardian_contacts_student_id_normalized_name_key do update
          set display_name=excluded.display_name,
              last_seen_at=now(),
              login_count=app_private.chem_guardian_contacts.login_count+1
        returning display_name into session_name;
      end if;

      update app_private.chem_access_codes
      set failed_count=0,locked_until=null,last_used_at=now()
      where id=candidate.id;
      insert into app_private.chem_login_attempts(fingerprint_hash,succeeded)
      values(p_fingerprint_hash,true);
      insert into app_private.chem_app_sessions(
        access_code_id,student_id,role,token_hash,expires_at,principal_name,access_scope
      ) values(
        candidate.id,candidate.student_id,candidate.role,p_token_hash,p_expires_at,session_name,'unified'
      );
      return query select candidate.student_id,candidate.role,session_name;
      return;
    end if;
  end loop;

  insert into app_private.chem_login_attempts(fingerprint_hash,succeeded)
  values(p_fingerprint_hash,false);
end $$;

create or replace function public.chem_resolve_app_session(p_token_hash text)
returns table(student_id uuid, access_role text, expires_at timestamptz, principal_name text)
language sql
security definer
set search_path = ''
as $$
  update app_private.chem_app_sessions
  set last_seen_at=now()
  where token_hash=p_token_hash
    and access_scope='unified'
    and revoked_at is null
    and expires_at>now()
  returning chem_app_sessions.student_id,
            chem_app_sessions.role,
            chem_app_sessions.expires_at,
            chem_app_sessions.principal_name;
$$;

create or replace function public.chem_rotate_access_code(
  p_student_id uuid,
  p_role text,
  p_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_role not in ('student','guardian')
     or p_code !~ '^[0-9]{6,12}$'
     or exists (
       select 1 from app_private.chem_access_codes c
       where c.role='teacher' and c.access_scope='unified' and c.active
         and c.code_hash=extensions.crypt(p_code,c.code_hash)
     ) then
    raise exception 'invalid access code request';
  end if;

  insert into app_private.chem_access_codes(
    student_id,role,code_hash,code_prefix,access_scope,active,failed_count,locked_until,rotated_at
  ) values(
    p_student_id,p_role,extensions.crypt(p_code,extensions.gen_salt('bf',12)),left(p_code,2),'unified',true,0,null,now()
  )
  on conflict(student_id,role) do update set
    code_hash=excluded.code_hash,
    code_prefix=excluded.code_prefix,
    access_scope='unified',
    active=true,
    failed_count=0,
    locked_until=null,
    rotated_at=now();

  update app_private.chem_app_sessions
  set revoked_at=now()
  where student_id=p_student_id
    and role=p_role
    and access_scope='unified'
    and revoked_at is null;
end $$;

create or replace function public.chem_rotate_teacher_access_code(
  p_name text,
  p_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_input text;
  teacher_code_id uuid;
begin
  normalized_input := lower(regexp_replace(btrim(coalesce(p_name,'')), '\s+', '', 'g'));
  if p_code !~ '^[0-9]{6,12}$' or char_length(normalized_input) not between 1 and 30 then
    raise exception 'invalid teacher access code request';
  end if;

  if exists (
    select 1 from app_private.chem_access_codes c
    where c.role in ('student','guardian')
      and c.access_scope='unified'
      and c.active
      and c.code_hash=extensions.crypt(p_code,c.code_hash)
  ) then
    raise exception 'teacher access code conflicts with an existing account';
  end if;

  select id into teacher_code_id
  from app_private.chem_access_codes
  where role='teacher' and access_scope='unified'
  order by active desc,created_at
  limit 1
  for update;

  if teacher_code_id is null then
    insert into app_private.chem_access_codes(
      student_id,role,principal_name,code_hash,code_prefix,access_scope,active,failed_count,locked_until,rotated_at
    ) values(
      null,'teacher',btrim(p_name),extensions.crypt(p_code,extensions.gen_salt('bf',12)),left(p_code,2),'unified',true,0,null,now()
    ) returning id into teacher_code_id;
  else
    update app_private.chem_access_codes
    set principal_name=btrim(p_name),
        code_hash=extensions.crypt(p_code,extensions.gen_salt('bf',12)),
        code_prefix=left(p_code,2),
        access_scope='unified',
        active=true,
        failed_count=0,
        locked_until=null,
        rotated_at=now()
    where id=teacher_code_id;
  end if;

  update app_private.chem_app_sessions
  set revoked_at=now()
  where access_code_id=teacher_code_id
    and access_scope='unified'
    and revoked_at is null;
end $$;

create or replace function public.chem_change_own_access_code(
  p_token_hash text,
  p_current_code text,
  p_new_code text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  app_session app_private.chem_app_sessions%rowtype;
  candidate app_private.chem_access_codes%rowtype;
begin
  if p_current_code !~ '^[0-9]{6,12}$'
     or p_new_code !~ '^[0-9]{6,12}$'
     or exists (
       select 1 from app_private.chem_access_codes c
       where c.role='teacher' and c.access_scope='unified' and c.active
         and c.code_hash=extensions.crypt(p_new_code,c.code_hash)
     )
     or p_current_code=p_new_code then
    return false;
  end if;

  select * into app_session
  from app_private.chem_app_sessions
  where token_hash=p_token_hash
    and access_scope='unified'
    and role='student'
    and revoked_at is null
    and expires_at>now()
  for update;
  if not found then return false; end if;

  if exists (
    select 1 from public.chem_students_v2 s
    where s.id=app_session.student_id
      and coalesce((s.metadata->>'demo')::boolean,false)
  ) then
    return false;
  end if;

  select * into candidate
  from app_private.chem_access_codes
  where id=app_session.access_code_id
    and role='student'
    and access_scope='unified'
    and active
    and coalesce(locked_until,'-infinity'::timestamptz)<=now()
  for update;
  if not found then return false; end if;

  if candidate.code_hash<>extensions.crypt(p_current_code,candidate.code_hash) then
    update app_private.chem_access_codes
    set failed_count=failed_count+1,
        locked_until=case when failed_count+1>=5 then now()+interval '15 minutes' else locked_until end
    where id=candidate.id;
    return false;
  end if;

  update app_private.chem_access_codes
  set code_hash=extensions.crypt(p_new_code,extensions.gen_salt('bf',12)),
      code_prefix=left(p_new_code,2),
      failed_count=0,
      locked_until=null,
      rotated_at=now()
  where id=candidate.id;

  update app_private.chem_app_sessions
  set revoked_at=now()
  where access_code_id=candidate.id
    and access_scope='unified'
    and token_hash<>p_token_hash
    and revoked_at is null;
  return true;
end $$;

create or replace function public.chem_set_recovery_secret(
  p_token_hash text,
  p_current_code text,
  p_recovery_secret text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  app_session app_private.chem_app_sessions%rowtype;
  candidate app_private.chem_access_codes%rowtype;
  clean_secret text;
begin
  clean_secret := btrim(coalesce(p_recovery_secret,''));
  if p_current_code !~ '^[0-9]{6,12}$'
     or char_length(clean_secret) not between 6 and 40
     or clean_secret ~ '^[0-9]+$'
     or clean_secret=p_current_code then
    return false;
  end if;

  select * into app_session
  from app_private.chem_app_sessions
  where token_hash=p_token_hash
    and access_scope='unified'
    and role='student'
    and revoked_at is null
    and expires_at>now()
  for update;
  if not found then return false; end if;

  if exists (
    select 1 from public.chem_students_v2 s
    where s.id=app_session.student_id
      and coalesce((s.metadata->>'demo')::boolean,false)
  ) then
    return false;
  end if;

  select * into candidate
  from app_private.chem_access_codes
  where id=app_session.access_code_id
    and role='student'
    and access_scope='unified'
    and active
    and coalesce(locked_until,'-infinity'::timestamptz)<=now()
  for update;
  if not found then return false; end if;

  if candidate.code_hash<>extensions.crypt(p_current_code,candidate.code_hash) then
    update app_private.chem_access_codes
    set failed_count=failed_count+1,
        locked_until=case when failed_count+1>=5 then now()+interval '15 minutes' else locked_until end
    where id=candidate.id;
    return false;
  end if;

  update app_private.chem_access_codes
  set recovery_secret_hash=extensions.crypt(clean_secret,extensions.gen_salt('bf',12)),
      recovery_failed_count=0,
      recovery_locked_until=null,
      recovery_set_at=now(),
      failed_count=0,
      locked_until=null
  where id=candidate.id;
  return true;
end $$;

create or replace function public.chem_recover_access_code(
  p_name text,
  p_recovery_secret text,
  p_new_code text,
  p_fingerprint_hash text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  candidate app_private.chem_access_codes%rowtype;
  recent_failures integer;
  normalized_input text;
  clean_secret text;
begin
  normalized_input := lower(regexp_replace(btrim(coalesce(p_name,'')), '\s+', '', 'g'));
  clean_secret := btrim(coalesce(p_recovery_secret,''));

  select count(*) into recent_failures
  from app_private.chem_recovery_attempts
  where fingerprint_hash=p_fingerprint_hash
    and not succeeded
    and attempted_at>now()-interval '30 minutes';
  if recent_failures>=5 then return false; end if;

  if char_length(normalized_input) not between 1 and 30
     or char_length(clean_secret) not between 6 and 40
     or p_new_code !~ '^[0-9]{6,12}$'
     or exists (
       select 1 from app_private.chem_access_codes c
       where c.role='teacher' and c.access_scope='unified' and c.active
         and c.code_hash=extensions.crypt(p_new_code,c.code_hash)
     ) then
    insert into app_private.chem_recovery_attempts(fingerprint_hash,succeeded)
    values(p_fingerprint_hash,false);
    return false;
  end if;

  for candidate in
    select c.*
    from app_private.chem_access_codes c
    join public.chem_students_v2 s on s.id=c.student_id
    where c.role='student'
      and c.access_scope='unified'
      and c.active
      and not coalesce((s.metadata->>'demo')::boolean,false)
      and c.recovery_secret_hash is not null
      and coalesce(c.recovery_locked_until,'-infinity'::timestamptz)<=now()
      and (
        lower(regexp_replace(btrim(s.display_name), '\s+', '', 'g'))=normalized_input
        or exists (
          select 1 from public.chem_student_aliases a
          where a.student_id=s.id
            and lower(regexp_replace(btrim(a.alias), '\s+', '', 'g'))=normalized_input
        )
      )
    for update of c
  loop
    if candidate.recovery_secret_hash=extensions.crypt(clean_secret,candidate.recovery_secret_hash) then
      update app_private.chem_access_codes
      set code_hash=extensions.crypt(p_new_code,extensions.gen_salt('bf',12)),
          code_prefix=left(p_new_code,2),
          failed_count=0,
          locked_until=null,
          recovery_failed_count=0,
          recovery_locked_until=null,
          rotated_at=now(),
          last_recovered_at=now()
      where id=candidate.id;
      update app_private.chem_app_sessions
      set revoked_at=now()
      where access_code_id=candidate.id
        and access_scope='unified'
        and revoked_at is null;
      insert into app_private.chem_recovery_attempts(fingerprint_hash,succeeded)
      values(p_fingerprint_hash,true);
      return true;
    end if;

    update app_private.chem_access_codes
    set recovery_failed_count=recovery_failed_count+1,
        recovery_locked_until=case
          when recovery_failed_count+1>=5 then now()+interval '30 minutes'
          else recovery_locked_until
        end
    where id=candidate.id;
  end loop;

  insert into app_private.chem_recovery_attempts(fingerprint_hash,succeeded)
  values(p_fingerprint_hash,false);
  return false;
end $$;

-- One public, non-personal profile per grade. Only the original demo login can
-- switch among these records; none receives a standalone access code.
insert into public.chem_students_v2(
  id,display_name,grade_band,record_status,enrollment_start_date,textbook_version,
  needs_initial_diagnostic,missing_fields,metadata
) values
  ('00000000-0000-4000-8000-000000000002','演示学生','高二','active',current_date,'苏教版',false,'{}',
   '{"demo":true,"demoGrade":true,"curriculumCohort":"high2_selective1_complete"}'::jsonb),
  ('00000000-0000-4000-8000-000000000003','演示学生','高三','active',current_date,'苏教版',false,'{}',
   '{"demo":true,"demoGrade":true,"curriculumCohort":"high3_exam_sprint"}'::jsonb)
on conflict(id) do update set
  display_name=excluded.display_name,
  grade_band=excluded.grade_band,
  record_status='active',
  textbook_version='苏教版',
  needs_initial_diagnostic=false,
  metadata=public.chem_students_v2.metadata || excluded.metadata,
  updated_at=now();

with demo_targets(student_id,grade_band) as (
  values
    ('00000000-0000-4000-8000-000000000002'::uuid,'高二'::text),
    ('00000000-0000-4000-8000-000000000003'::uuid,'高三'::text)
), source_students as (
  select t.student_id,t.grade_band,(
    select s.id
    from public.chem_students_v2 s
    where s.grade_band=t.grade_band
      and not coalesce((s.metadata->>'demo')::boolean,false)
    order by (select count(*) from public.chem_learning_plans p0 where p0.student_id=s.id) desc,s.id::text
    limit 1
  ) source_student_id
  from demo_targets t
)
insert into public.chem_learning_plans(
  student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,is_scheduled,knowledge_summaries
)
select
  ss.student_id,p.plan_date,p.mode,p.title,p.skill_ids,p.estimated_minutes,p.source,p.is_scheduled,p.knowledge_summaries
from source_students ss
join public.chem_learning_plans p on p.student_id=ss.source_student_id
on conflict(student_id,plan_date,mode,title) do update set
  skill_ids=excluded.skill_ids,
  estimated_minutes=excluded.estimated_minutes,
  source=excluded.source,
  is_scheduled=excluded.is_scheduled,
  knowledge_summaries=excluded.knowledge_summaries;

-- The private teacher credential is rotated out-of-band after this migration.
-- It is intentionally absent from version control; quiz-audit remains untouched.

revoke all on function public.chem_exchange_access_code(text,text,text,text,timestamptz) from public,anon,authenticated;
revoke all on function public.chem_resolve_app_session(text) from public,anon,authenticated;
revoke all on function public.chem_rotate_access_code(uuid,text,text) from public,anon,authenticated;
revoke all on function public.chem_rotate_teacher_access_code(text,text) from public,anon,authenticated;
revoke all on function public.chem_change_own_access_code(text,text,text) from public,anon,authenticated;
revoke all on function public.chem_set_recovery_secret(text,text,text) from public,anon,authenticated;
revoke all on function public.chem_recover_access_code(text,text,text,text) from public,anon,authenticated;

grant execute on function public.chem_exchange_access_code(text,text,text,text,timestamptz) to service_role;
grant execute on function public.chem_resolve_app_session(text) to service_role;
grant execute on function public.chem_rotate_access_code(uuid,text,text) to service_role;
grant execute on function public.chem_rotate_teacher_access_code(text,text) to service_role;
grant execute on function public.chem_change_own_access_code(text,text,text) to service_role;
grant execute on function public.chem_set_recovery_secret(text,text,text) to service_role;
grant execute on function public.chem_recover_access_code(text,text,text,text) to service_role;

do $$
begin
  if not exists (
    select 1 from app_private.chem_access_codes c
    where c.role='teacher'
      and c.access_scope='unified'
      and c.active
  ) then
    raise exception 'Unified teacher credential verification failed';
  end if;

  if (select count(*) from public.chem_students_v2 where coalesce((metadata->>'demo')::boolean,false)) < 3 then
    raise exception 'Three-grade demo profile verification failed';
  end if;

  if exists (
    select 1
    from (values
      ('00000000-0000-4000-8000-000000000002'::uuid),
      ('00000000-0000-4000-8000-000000000003'::uuid)
    ) d(student_id)
    where (select count(*) from public.chem_learning_plans p where p.student_id=d.student_id) < 28
  ) then
    raise exception 'Demo learning-plan verification failed';
  end if;
end $$;
