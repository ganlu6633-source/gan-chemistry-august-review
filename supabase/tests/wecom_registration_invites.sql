-- Run after 20260926130000_wecom_registration_invites.sql. The transaction
-- rolls back all test registrations and invitations.
begin;
set local lock_timeout='5s';

do $verify$
declare
  v_result jsonb;
  v_wecom_id uuid;
  v_guardian_id uuid;
  v_recovery_id uuid;
  v_manual_id uuid;
  v_student_phone text := '19988880001';
  v_other_phone text := '19988880002';
  v_guardian_phone text := '19988880003';
  v_child_phone text := '19988880004';
  v_manual_phone text := '19988880005';
  v_recovery_phone text := '19988880006';
  v_student_data jsonb;
  v_guardian_data jsonb;
  v_manual_data jsonb;
begin
  if has_function_privilege('anon',
      'public.chem_create_wecom_registration_invite(text,text,text)', 'execute')
    or has_function_privilege('authenticated',
      'public.chem_create_wecom_registration_invite(text,text,text)', 'execute')
    or has_function_privilege('anon',
      'public.chem_mark_wecom_welcome_sent(uuid)', 'execute')
    or has_function_privilege('authenticated',
      'public.chem_mark_wecom_welcome_sent(uuid)', 'execute') then
    raise exception 'WeCom invitation RPC must be private to service_role';
  end if;

  v_result := public.chem_create_wecom_registration_invite(
    repeat('a',64),repeat('b',64),repeat('c',64));
  v_wecom_id := (v_result->>'id')::uuid;
  if v_wecom_id is null or (v_result->>'shouldSend')::boolean is not true
    or v_result->>'eventHash' <> repeat('c',64)
    or (v_result->>'expiresAt')::timestamptz not between
      now()+interval '23 hours 59 minutes' and now()+interval '24 hours 1 minute' then
    raise exception 'verified contact event did not create a 24-hour invitation';
  end if;
  v_result := public.chem_create_wecom_registration_invite(
    repeat('a',64),repeat('b',64),repeat('c',64));
  if (v_result->>'id')::uuid <> v_wecom_id
    or (v_result->>'shouldSend')::boolean is not true
    or v_result->>'eventHash' <> repeat('c',64) then
    raise exception 'callback retry must reuse the same invitation';
  end if;

  v_student_data := jsonb_build_object('role','student','displayName','企业微信测试学生',
    'phone',v_student_phone,'password','Secure88','gradeBand','高一');
  if not public.chem_mark_wecom_welcome_sent(v_wecom_id)
    or public.chem_mark_wecom_welcome_sent(v_wecom_id) then
    raise exception 'welcome delivery must be marked exactly once';
  end if;
  v_result := public.chem_create_wecom_registration_invite(
    repeat('a',64),repeat('b',64),repeat('c',64));
  if (v_result->>'shouldSend')::boolean is not false then
    raise exception 'delivered callback retry must not send another welcome';
  end if;
  v_result := public.chem_create_wecom_registration_invite(
    repeat('e',64),repeat('b',64),repeat('e',64));
  if (v_result->>'id')::uuid <> v_wecom_id
    or (v_result->>'shouldSend')::boolean is not false
    or v_result->>'eventHash' <> repeat('c',64)
    or exists(select 1 from app_private.chem_registration_invites
      where id=v_wecom_id and revoked_at is not null) then
    raise exception 'second contact event invalidated an already-sent link';
  end if;
  if not public.chem_submit_registration(v_student_data,repeat('e',64),repeat('a',64)) then
    raise exception 'verified WeCom student invitation was rejected';
  end if;
  if not exists(select 1 from app_private.chem_registration_invites
    where id=v_wecom_id and source='wecom' and role='student'
      and phone=v_student_phone and consumed_at is not null)
    or not exists(select 1 from app_private.chem_registration_requests
      where invite_id=v_wecom_id and role='student' and phone=v_student_phone
        and status='pending') then
    raise exception 'WeCom invitation was not atomically bound and consumed';
  end if;
  if public.chem_submit_registration(
      v_student_data || jsonb_build_object('phone',v_other_phone),
      repeat('f',64),repeat('a',64)) then
    raise exception 'consumed WeCom invitation was accepted a second time';
  end if;

  v_result := public.chem_create_wecom_registration_invite(
    repeat('1',64),repeat('2',64),repeat('3',64));
  v_guardian_id := (v_result->>'id')::uuid;
  if not public.chem_mark_wecom_welcome_sent(v_guardian_id) then
    raise exception 'guardian welcome could not be marked sent';
  end if;
  v_guardian_data := jsonb_build_object('role','guardian','displayName','企业微信测试家长',
    'phone',v_guardian_phone,'password','Secure88','childName','测试孩子',
    'childPhone',v_child_phone);
  if not public.chem_submit_registration(v_guardian_data,repeat('4',64),repeat('1',64)) then
    raise exception 'verified WeCom guardian invitation was rejected';
  end if;
  if not exists(select 1 from app_private.chem_registration_requests
      where invite_id=v_guardian_id and role='guardian' and status='pending')
    or exists(select 1 from app_private.chem_phone_accounts
      where role='guardian' and phone=v_guardian_phone) then
    raise exception 'guardian request must remain pending teacher approval';
  end if;

  -- The welcome API can succeed while the subsequent database mark fails.
  -- The contact already received the code and must still be able to apply.
  v_result := public.chem_create_wecom_registration_invite(
    repeat('b',64),repeat('7',64),repeat('8',64));
  v_recovery_id := (v_result->>'id')::uuid;
  v_result := public.chem_create_wecom_registration_invite(
    repeat('d',64),repeat('7',64),repeat('9',64));
  if (v_result->>'id')::uuid <> v_recovery_id
    or (v_result->>'shouldSend')::boolean is not true
    or v_result->>'eventHash' <> repeat('8',64)
    or exists(select 1 from app_private.chem_registration_invites
      where id=v_recovery_id and revoked_at is not null) then
    raise exception 'undelivered half/full callback must retain first code';
  end if;
  if not public.chem_submit_registration(jsonb_build_object(
      'role','student','displayName','企微送达恢复测试学生',
      'phone',v_recovery_phone,'password','Secure88','gradeBand','高一'),
      repeat('c',64),repeat('b',64)) then
    raise exception 'delivered invitation was rejected after the welcome mark failed';
  end if;
  if not exists(select 1 from app_private.chem_registration_requests
      where invite_id=v_recovery_id and status='pending')
    or public.chem_mark_wecom_welcome_sent(v_recovery_id) then
    raise exception 'delivered invitation failed when welcome mark was unavailable';
  end if;

  insert into app_private.chem_registration_invites
    (code_hash,role,phone,issued_by,issued_by_hash,expires_at)
  values(repeat('5',64),'student',v_manual_phone,'事务测试教师',repeat('6',64),
    now()+interval '7 days') returning id into v_manual_id;
  if (select source from app_private.chem_registration_invites where id=v_manual_id)<>'teacher' then
    raise exception 'existing manual invitation default source changed';
  end if;
  v_manual_data := jsonb_build_object('role','student','displayName','手动邀请测试学生',
    'phone',v_manual_phone,'password','Secure88','gradeBand','高二');
  if public.chem_submit_registration(
      v_manual_data || jsonb_build_object('phone',v_other_phone),
      repeat('7',64),repeat('5',64)) then
    raise exception 'manual invitation lost its phone binding';
  end if;
  if public.chem_submit_registration(
      (v_manual_data || jsonb_build_object('role','guardian','childName','测试孩子',
        'childPhone',v_child_phone)) - 'gradeBand',
      repeat('8',64),repeat('5',64)) then
    raise exception 'manual invitation lost its role binding';
  end if;
  if not public.chem_submit_registration(v_manual_data,repeat('9',64),repeat('5',64)) then
    raise exception 'valid manual invitation stopped working';
  end if;

  begin
    insert into app_private.chem_registration_invites
      (code_hash,source,issued_by,issued_by_hash,expires_at)
    values(repeat('0',64),'teacher','invalid',repeat('0',64),now()+interval '1 day');
    raise exception 'teacher source accepted an unbound invitation';
  exception when check_violation then null;
  end;
  begin
    insert into app_private.chem_registration_invites
      (code_hash,source,role,external_user_hash,event_hash,issued_by,
        issued_by_hash,expires_at)
    values(repeat('0',64),'wecom','student',repeat('0',64),repeat('f',64),
      'invalid',repeat('0',64),now()+interval '1 day');
    raise exception 'WeCom source accepted only a role without a phone';
  exception when check_violation then null;
  end;
end
$verify$;

rollback;
