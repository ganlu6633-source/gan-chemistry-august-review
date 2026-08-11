create or replace function public.chem_exchange_access_code(
  p_code text,
  p_fingerprint_hash text,
  p_token_hash text,
  p_expires_at timestamptz
)
returns table(student_id uuid, access_role text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  candidate app_private.chem_access_codes%rowtype;
  recent_failures integer;
begin
  if p_code !~ '^[0-9]{8}$' then
    insert into app_private.chem_login_attempts(fingerprint_hash,succeeded) values(p_fingerprint_hash,false);
    return;
  end if;

  select count(*) into recent_failures
  from app_private.chem_login_attempts
  where fingerprint_hash = p_fingerprint_hash
    and not succeeded
    and attempted_at > now() - interval '15 minutes';
  if recent_failures >= 10 then return; end if;

  for candidate in
    select * from app_private.chem_access_codes
    where active and coalesce(locked_until, '-infinity'::timestamptz) <= now()
  loop
    if candidate.code_hash = extensions.crypt(p_code, candidate.code_hash) then
      update app_private.chem_access_codes
      set failed_count=0, locked_until=null, last_used_at=now()
      where id=candidate.id;
      insert into app_private.chem_login_attempts(fingerprint_hash,succeeded) values(p_fingerprint_hash,true);
      insert into app_private.chem_app_sessions(access_code_id,student_id,role,token_hash,expires_at)
      values(candidate.id,candidate.student_id,candidate.role,p_token_hash,p_expires_at);
      return query select candidate.student_id,candidate.role;
      return;
    end if;
  end loop;

  insert into app_private.chem_login_attempts(fingerprint_hash,succeeded) values(p_fingerprint_hash,false);
end $$;

create or replace function public.chem_resolve_app_session(p_token_hash text)
returns table(student_id uuid, access_role text, expires_at timestamptz)
language sql
security definer
set search_path = ''
as $$
  update app_private.chem_app_sessions
  set last_seen_at=now()
  where token_hash=p_token_hash and revoked_at is null and expires_at>now()
  returning chem_app_sessions.student_id,chem_app_sessions.role,chem_app_sessions.expires_at;
$$;

create or replace function public.chem_rotate_access_code(p_student_id uuid,p_role text,p_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_role not in ('student','guardian') or p_code !~ '^[0-9]{8}$' then
    raise exception 'invalid access code request';
  end if;
  insert into app_private.chem_access_codes(student_id,role,code_hash,active,failed_count,locked_until,rotated_at)
  values(p_student_id,p_role,extensions.crypt(p_code,extensions.gen_salt('bf',12)),true,0,null,now())
  on conflict(student_id,role) do update set
    code_hash=excluded.code_hash,active=true,failed_count=0,locked_until=null,rotated_at=now();
  update app_private.chem_app_sessions set revoked_at=now()
  where student_id=p_student_id and role=p_role and revoked_at is null;
end $$;

create or replace function public.chem_teacher_is_allowed(p_email text)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists(select 1 from app_private.chem_teacher_allowlist where lower(email)=lower(p_email) and active);
$$;

revoke all on function public.chem_exchange_access_code(text,text,text,timestamptz) from public,anon,authenticated;
revoke all on function public.chem_resolve_app_session(text) from public,anon,authenticated;
revoke all on function public.chem_rotate_access_code(uuid,text,text) from public,anon,authenticated;
revoke all on function public.chem_teacher_is_allowed(text) from public,anon,authenticated;
grant execute on function public.chem_exchange_access_code(text,text,text,timestamptz) to service_role;
grant execute on function public.chem_resolve_app_session(text) to service_role;
grant execute on function public.chem_rotate_access_code(uuid,text,text) to service_role;
grant execute on function public.chem_teacher_is_allowed(text) to service_role;
