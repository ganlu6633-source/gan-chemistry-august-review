-- Run against a database with 20260927143740_claim_existing_student_phone
-- applied. This whole test rolls back, including the synthetic profiles.
begin;

do $test$
declare
  v_first uuid;
  v_second uuid;
  v_first_name text := '自助绑定回归甲';
  v_second_name text := '自助绑定回归乙';
  v_phone text;
  v_other_phone text;
  v_first_code text := '987654321012';
  v_second_code text := '987654321013';
  v_guardian_code text := '987654321014';
  v_result jsonb;
  v_login_student uuid;
  v_fingerprint text;
begin
  if has_function_privilege('anon', 'public.chem_claim_existing_student_phone(text,text,text,text,text,text,timestamptz)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.chem_claim_existing_student_phone(text,text,text,text,text,text,timestamptz)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.chem_claim_existing_student_phone(text,text,text,text,text,text,timestamptz)', 'EXECUTE') then
    raise exception 'Phone claim RPC privilege boundary is incorrect';
  end if;
  loop
    v_phone := '199' || lpad((floor(random() * 100000000))::integer::text, 8, '0');
    exit when not exists (select 1 from app_private.chem_phone_accounts where phone = v_phone)
      and not exists (select 1 from app_private.chem_student_phones where phone = v_phone);
  end loop;
  loop
    v_other_phone := '199' || lpad((floor(random() * 100000000))::integer::text, 8, '0');
    exit when v_other_phone <> v_phone
      and not exists (select 1 from app_private.chem_phone_accounts where phone = v_other_phone)
      and not exists (select 1 from app_private.chem_student_phones where phone = v_other_phone);
  end loop;

  insert into public.chem_students_v2(display_name, grade_band, record_status)
  values (v_first_name, '高一', 'active') returning id into v_first;
  insert into public.chem_students_v2(display_name, grade_band, record_status)
  values (v_second_name, '高一', 'active') returning id into v_second;
  insert into app_private.chem_access_codes(
    student_id, role, code_hash, code_prefix, access_scope
  ) values
    (v_first, 'student', extensions.crypt(v_first_code, extensions.gen_salt('bf', 10)), left(v_first_code, 2), 'unified'),
    (v_first, 'guardian', extensions.crypt(v_guardian_code, extensions.gen_salt('bf', 10)), left(v_guardian_code, 2), 'unified'),
    (v_second, 'student', extensions.crypt(v_second_code, extensions.gen_salt('bf', 10)), left(v_second_code, 2), 'unified');

  v_fingerprint := encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex');
  v_result := public.chem_claim_existing_student_phone(
    v_first_name, '00000000', v_phone, 'Test1234', v_fingerprint,
    encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), now() + interval '1 hour'
  );
  if v_result->>'resultCode' <> 'invalid' then raise exception 'Unknown code was accepted'; end if;

  v_result := public.chem_claim_existing_student_phone(
    v_first_name, v_guardian_code, v_phone, 'Test1234',
    encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'),
    encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), now() + interval '1 hour'
  );
  if v_result->>'resultCode' <> 'invalid' then raise exception 'Guardian code was accepted'; end if;

  v_result := public.chem_claim_existing_student_phone(
    v_first_name, v_first_code, v_phone, 'Test1234',
    encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'),
    encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), now() + interval '1 hour'
  );
  if v_result->>'resultCode' <> 'ok' or (v_result->>'studentId')::uuid <> v_first then
    raise exception 'Existing student claim failed: %', v_result;
  end if;

  select e.student_id into v_login_student
  from public.chem_exchange_phone_password(
    'student', v_phone, 'Test1234',
    encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'),
    encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), now() + interval '1 hour'
  ) e;
  if v_login_student is distinct from v_first then raise exception 'Phone login did not reach original profile'; end if;

  v_result := public.chem_claim_existing_student_phone(
    v_first_name, v_first_code, v_other_phone, 'Test5678',
    encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'),
    encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), now() + interval '1 hour'
  );
  if v_result->>'resultCode' <> 'already_bound' then raise exception 'Duplicate binding was accepted'; end if;

  v_result := public.chem_claim_existing_student_phone(
    v_second_name, v_second_code, v_phone, 'Test5678',
    encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'),
    encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), now() + interval '1 hour'
  );
  if v_result->>'resultCode' <> 'phone_taken' then raise exception 'Shared phone was accepted'; end if;

  if (select count(*) from app_private.chem_phone_accounts where student_id = v_first and role = 'student') <> 1
     or exists(select 1 from app_private.chem_phone_accounts where student_id = v_second and role = 'student')
     or exists(select 1 from app_private.chem_student_phones where student_id in (v_first, v_second)) then
    raise exception 'Phone ownership or teacher-verification state is incorrect';
  end if;
end;
$test$;

rollback;
