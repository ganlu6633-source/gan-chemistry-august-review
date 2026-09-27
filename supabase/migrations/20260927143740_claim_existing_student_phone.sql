-- A roster student can add a phone/password to their existing profile by
-- proving possession of their student access code. Name alone is not proof.
alter table app_private.chem_registration_attempts
  add column claim_name_hash text;
create index chem_registration_attempts_claim_name_recent
  on app_private.chem_registration_attempts(claim_name_hash, attempted_at desc)
  where claim_name_hash is not null;

create function public.chem_claim_existing_student_phone(
  p_name text,
  p_code text,
  p_phone text,
  p_password text,
  p_fingerprint_hash text,
  p_token_hash text,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
  v_normalized_name text := lower(regexp_replace(btrim(coalesce(p_name, '')), '\s+', '', 'g'));
  v_candidate record;
  v_student_id uuid;
  v_code_id uuid;
  v_display_name text;
  v_verified_phone text;
  v_name_hash text;
begin
  if p_fingerprint_hash is null or p_fingerprint_hash !~ '^[0-9a-f]{64}$'
     or p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$'
     or p_expires_at is null or p_expires_at <= now()
     or p_expires_at > now() + interval '12 hours' then
    return jsonb_build_object('resultCode', 'invalid');
  end if;

  perform pg_advisory_xact_lock(hashtext('claim-fingerprint:' || p_fingerprint_hash));
  if (select count(*) from app_private.chem_registration_attempts a
      where a.fingerprint_hash = p_fingerprint_hash
        and a.attempted_at > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('resultCode', 'rate_limited');
  end if;
  if p_phone is not null and p_phone ~ '^1[3-9][0-9]{9}$' then
    perform pg_advisory_xact_lock(hashtext('registration-phone:' || p_phone));
    if (select count(*) from app_private.chem_registration_attempts a
        where a.phone = p_phone and a.attempted_at > now() - interval '1 hour') >= 10 then
      return jsonb_build_object('resultCode', 'rate_limited');
    end if;
  end if;
  -- A second limit keyed to the canonicalized entered name makes rotating IP
  -- and phone values insufficient for large-scale code guessing. It only
  -- pauses this new binding path for 15 minutes; normal code login remains.
  v_name_hash := encode(extensions.digest(v_normalized_name, 'sha256'), 'hex');
  if char_length(v_normalized_name) between 1 and 30 then
    perform pg_advisory_xact_lock(hashtext('registration-name:' || v_name_hash));
    if (select count(*) from app_private.chem_registration_attempts a
        where a.claim_name_hash = v_name_hash
          and a.attempted_at > now() - interval '15 minutes') >= 100 then
      return jsonb_build_object('resultCode', 'rate_limited');
    end if;
  end if;
  insert into app_private.chem_registration_attempts(fingerprint_hash, phone, claim_name_hash)
  values (p_fingerprint_hash,
    case when p_phone ~ '^1[3-9][0-9]{9}$' then p_phone else null end,
    case when char_length(v_normalized_name) between 1 and 30 then v_name_hash else null end);

  if char_length(v_name) not between 1 and 30
     or p_code is null or p_code !~ '^[0-9]{6,12}$'
     or p_phone is null or p_phone !~ '^1[3-9][0-9]{9}$'
     or p_password is null or char_length(p_password) not between 6 and 12
     or p_password ~ '[[:cntrl:]]' or p_password <> btrim(p_password) then
    return jsonb_build_object('resultCode', 'invalid');
  end if;

  -- Match the existing code-login rules, but accept only an active, real
  -- student's code. A guardian or teacher code can never bind this account.
  for v_candidate in
    select c.id as code_id, c.code_hash, s.id as student_id,
           s.display_name
    from app_private.chem_access_codes c
    join public.chem_students_v2 s on s.id = c.student_id
    where c.role = 'student' and c.active and c.access_scope = 'unified'
      and c.code_prefix = left(p_code, 2)
      and coalesce(c.locked_until, '-infinity'::timestamptz) <= now()
      and s.record_status = 'active'
      and coalesce(s.metadata->>'demo', 'false') <> 'true'
      and (
        lower(regexp_replace(btrim(s.display_name), '\s+', '', 'g')) = v_normalized_name
        or exists (
          select 1 from public.chem_student_aliases a
          where a.student_id = s.id
            and lower(regexp_replace(btrim(a.alias), '\s+', '', 'g')) = v_normalized_name
        )
      )
    for update of c, s
  loop
    if v_candidate.code_hash = extensions.crypt(p_code, v_candidate.code_hash) then
      -- Fail closed if the same credentials happen to match two profiles.
      if v_student_id is not null then
        return jsonb_build_object('resultCode', 'invalid');
      end if;
      v_student_id := v_candidate.student_id;
      v_code_id := v_candidate.code_id;
      v_display_name := v_candidate.display_name;
    end if;
  end loop;
  if v_student_id is null then
    return jsonb_build_object('resultCode', 'invalid');
  end if;

  if exists (
    select 1 from app_private.chem_phone_accounts a
    where a.student_id = v_student_id and a.role = 'student' and a.active
  ) then
    return jsonb_build_object('resultCode', 'already_bound');
  end if;
  if exists (
    select 1 from app_private.chem_phone_accounts a
    where a.role = 'student' and a.phone = p_phone
  ) or exists (
    select 1 from app_private.chem_student_phones sp
    where sp.phone = p_phone and sp.student_id <> v_student_id
  ) then
    return jsonb_build_object('resultCode', 'phone_taken');
  end if;
  select sp.phone into v_verified_phone
  from app_private.chem_student_phones sp where sp.student_id = v_student_id;
  if v_verified_phone is not null and v_verified_phone <> p_phone then
    return jsonb_build_object('resultCode', 'phone_mismatch');
  end if;

  -- Do not insert a self-declared phone into chem_student_phones: that table
  -- specifically represents a number checked by the teacher.
  begin
    insert into app_private.chem_phone_accounts(
      role, phone, display_name, password_hash, student_id
    ) values (
      'student', p_phone, v_display_name,
      extensions.crypt(p_password, extensions.gen_salt('bf', 10)), v_student_id
    );
  exception when unique_violation then
    return jsonb_build_object('resultCode', 'already_bound');
  end;

  -- A prior invite request for the same student/number no longer needs review.
  update app_private.chem_registration_requests r
  set status = 'approved', student_id = v_student_id,
      reviewed_at = now(), reviewed_by = '学生登录码自助绑定'
  where r.role = 'student' and r.phone = p_phone and r.status = 'pending'
    and lower(regexp_replace(btrim(r.display_name), '\s+', '', 'g')) = v_normalized_name;

  update app_private.chem_access_codes c
  set failed_count = 0, locked_until = null, last_used_at = now()
  where c.id = v_code_id;
  insert into app_private.chem_login_attempts(fingerprint_hash, succeeded)
  values (p_fingerprint_hash, true);
  insert into app_private.chem_app_sessions(
    access_code_id, student_id, role, token_hash, expires_at,
    principal_name, access_scope
  ) values (
    v_code_id, v_student_id, 'student', p_token_hash, p_expires_at,
    v_display_name, 'unified'
  );
  return jsonb_build_object(
    'resultCode', 'ok', 'studentId', v_student_id,
    'displayName', v_display_name
  );
end $$;

revoke all on function public.chem_claim_existing_student_phone(
  text, text, text, text, text, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.chem_claim_existing_student_phone(
  text, text, text, text, text, text, timestamptz
) to service_role;
