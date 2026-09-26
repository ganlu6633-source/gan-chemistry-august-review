create or replace function public.chem_exchange_phone_password(p_role text,p_phone text,p_password text,p_fingerprint_hash text,p_token_hash text,p_expires_at timestamptz)
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
  select c.id into v_code from app_private.chem_access_codes c where c.student_id=v_account.student_id and c.role=v_account.role and c.active;
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
