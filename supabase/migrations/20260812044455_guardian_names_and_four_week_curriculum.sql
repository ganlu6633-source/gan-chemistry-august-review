create table if not exists app_private.chem_guardian_contacts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 50),
  normalized_name text not null check (char_length(normalized_name) between 1 and 30),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  login_count integer not null default 1 check (login_count > 0),
  unique(student_id, normalized_name)
);

alter table app_private.chem_guardian_contacts enable row level security;
drop policy if exists guardian_contacts_deny_client_access on app_private.chem_guardian_contacts;
create policy guardian_contacts_deny_client_access
  on app_private.chem_guardian_contacts
  for all
  to public
  using (false)
  with check (false);
alter table app_private.chem_app_sessions add column if not exists principal_name text;

drop function if exists public.chem_exchange_access_code(text,text,text,timestamptz);

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
    insert into app_private.chem_login_attempts(fingerprint_hash,succeeded) values(p_fingerprint_hash,false);
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
      if candidate.role='student' then
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

drop function if exists public.chem_resolve_app_session(text);

create function public.chem_resolve_app_session(p_token_hash text)
returns table(student_id uuid, access_role text, expires_at timestamptz, principal_name text)
language sql
security definer
set search_path = ''
as $$
  update app_private.chem_app_sessions
  set last_seen_at=now()
  where token_hash=p_token_hash and revoked_at is null and expires_at>now()
  returning chem_app_sessions.student_id,chem_app_sessions.role,chem_app_sessions.expires_at,chem_app_sessions.principal_name;
$$;

create or replace function public.chem_list_guardian_contacts()
returns table(student_id uuid, display_name text, first_seen_at timestamptz, last_seen_at timestamptz, login_count integer)
language sql
security definer
set search_path = ''
as $$
  select c.student_id,c.display_name,c.first_seen_at,c.last_seen_at,c.login_count
  from app_private.chem_guardian_contacts c
  order by c.student_id,c.first_seen_at;
$$;

revoke all on table app_private.chem_guardian_contacts from public,anon,authenticated;
revoke all on function public.chem_exchange_access_code(text,text,text,text,timestamptz) from public,anon,authenticated;
revoke all on function public.chem_resolve_app_session(text) from public,anon,authenticated;
revoke all on function public.chem_list_guardian_contacts() from public,anon,authenticated;
grant execute on function public.chem_exchange_access_code(text,text,text,text,timestamptz) to service_role;
grant execute on function public.chem_resolve_app_session(text) to service_role;
grant execute on function public.chem_list_guardian_contacts() to service_role;
