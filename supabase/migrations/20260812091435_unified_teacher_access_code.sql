-- Give the single teacher the same name + 8-digit-code entry as students and guardians,
-- while keeping the resulting teacher session private and independently revocable.

alter table app_private.chem_access_codes
  alter column student_id drop not null,
  add column if not exists principal_name text;

alter table app_private.chem_access_codes
  drop constraint if exists chem_access_codes_role_check;
alter table app_private.chem_access_codes
  add constraint chem_access_codes_role_check
  check (role in ('student','guardian','teacher'));

create unique index if not exists chem_access_codes_teacher_name_unique
  on app_private.chem_access_codes(lower(principal_name))
  where role='teacher' and active;

alter table app_private.chem_app_sessions
  alter column student_id drop not null;

alter table app_private.chem_app_sessions
  drop constraint if exists chem_app_sessions_role_check;
alter table app_private.chem_app_sessions
  add constraint chem_app_sessions_role_check
  check (role in ('student','guardian','teacher'));

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
  if p_code !~ '^[0-9]{8}$' or char_length(normalized_input) not between 1 and 30 then
    insert into app_private.chem_login_attempts(fingerprint_hash,succeeded)
    values(p_fingerprint_hash,false);
    return;
  end if;

  select count(*) into recent_failures
  from app_private.chem_login_attempts
  where fingerprint_hash=p_fingerprint_hash
    and not succeeded
    and attempted_at>now()-interval '15 minutes';
  if recent_failures>=10 then return; end if;

  for candidate in
    select * from app_private.chem_access_codes
    where active
      and code_prefix=left(p_code,2)
      and coalesce(locked_until,'-infinity'::timestamptz)<=now()
  loop
    if candidate.code_hash=extensions.crypt(p_code,candidate.code_hash) then
      if candidate.role='teacher' then
        if lower(regexp_replace(btrim(coalesce(candidate.principal_name,'')), '\s+', '', 'g'))<>normalized_input then
          continue;
        end if;
        session_name := candidate.principal_name;
      elsif candidate.role='student' then
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
      insert into app_private.chem_app_sessions(access_code_id,student_id,role,token_hash,expires_at,principal_name)
      values(candidate.id,candidate.student_id,candidate.role,p_token_hash,p_expires_at,session_name);
      return query select candidate.student_id,candidate.role,session_name;
      return;
    end if;
  end loop;

  insert into app_private.chem_login_attempts(fingerprint_hash,succeeded)
  values(p_fingerprint_hash,false);
end $$;

create or replace function public.chem_rotate_teacher_access_code(p_name text,p_code text)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  normalized_input text;
  teacher_code_id uuid;
begin
  normalized_input := lower(regexp_replace(btrim(coalesce(p_name,'')), '\s+', '', 'g'));
  if p_code !~ '^[0-9]{8}$' or char_length(normalized_input) not between 1 and 30 then
    raise exception 'invalid teacher access code request';
  end if;

  select id into teacher_code_id
  from app_private.chem_access_codes
  where role='teacher'
    and lower(regexp_replace(btrim(coalesce(principal_name,'')), '\s+', '', 'g'))=normalized_input
  order by created_at
  limit 1;

  if teacher_code_id is null then
    insert into app_private.chem_access_codes(student_id,role,principal_name,code_hash,code_prefix,active,failed_count,locked_until,rotated_at)
    values(null,'teacher',btrim(p_name),extensions.crypt(p_code,extensions.gen_salt('bf',12)),left(p_code,2),true,0,null,now())
    returning id into teacher_code_id;
  else
    update app_private.chem_access_codes
    set principal_name=btrim(p_name),
        code_hash=extensions.crypt(p_code,extensions.gen_salt('bf',12)),
        code_prefix=left(p_code,2),
        active=true,
        failed_count=0,
        locked_until=null,
        rotated_at=now()
    where id=teacher_code_id;
  end if;

  update app_private.chem_app_sessions
  set revoked_at=now()
  where access_code_id=teacher_code_id and revoked_at is null;
end $$;

revoke all on function public.chem_exchange_access_code(text,text,text,text,timestamptz) from public,anon,authenticated;
revoke all on function public.chem_rotate_teacher_access_code(text,text) from public,anon,authenticated;
grant execute on function public.chem_exchange_access_code(text,text,text,text,timestamptz) to service_role;
grant execute on function public.chem_rotate_teacher_access_code(text,text) to service_role;
