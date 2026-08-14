-- Run after 20260814102737_flexible_access_recovery_demo_preview.sql.
-- Every mutation is rolled back so the shared demo account remains unchanged.
begin;
set local lock_timeout='5s';

do $verify$
declare
  teacher_role text;
  teacher_name text;
  demo_role text;
  demo_id uuid;
  test_id uuid := '00000000-0000-4000-8000-0000000000ff'::uuid;
  test_role text;
  secret_hash text;
begin
  perform public.chem_rotate_teacher_access_code('事务测试教师','904422771155');
  select access_role,principal_name into teacher_role,teacher_name
  from public.chem_exchange_access_code(
    '任意教师姓名','904422771155','test-teacher-fingerprint','test-teacher-token',now()+interval '1 hour'
  );
  if teacher_role<>'teacher' or teacher_name<>'任意教师姓名' then
    raise exception 'teacher arbitrary-name login failed';
  end if;

  select access_role,student_id into demo_role,demo_id
  from public.chem_exchange_access_code(
    '演示学生','11111111','test-demo-fingerprint','test-demo-token',now()+interval '1 hour'
  );
  if demo_role<>'student' or demo_id<>'00000000-0000-4000-8000-000000000001'::uuid then
    raise exception 'demo student login failed';
  end if;

  insert into public.chem_students_v2(
    id,display_name,grade_band,record_status,enrollment_start_date,textbook_version,
    needs_initial_diagnostic,missing_fields,metadata
  ) values(
    test_id,'后端事务测试学生','高一','active',current_date,'苏教版',false,'{}','{"backendTest":true}'::jsonb
  );
  perform public.chem_rotate_access_code(test_id,'student','112233');
  select access_role into test_role
  from public.chem_exchange_access_code(
    '后端事务测试学生','112233','test-account-fingerprint','test-account-token',now()+interval '1 hour'
  );
  if test_role<>'student' then
    raise exception 'test student login failed';
  end if;

  if not public.chem_set_recovery_secret('test-account-token','112233','我的化学找回短语') then
    raise exception 'set recovery secret failed';
  end if;
  select recovery_secret_hash into secret_hash
  from app_private.chem_access_codes
  where student_id=test_id and role='student';
  if secret_hash is null or secret_hash='我的化学找回短语' then
    raise exception 'recovery secret was not safely hashed';
  end if;

  if not public.chem_change_own_access_code('test-account-token','112233','654321') then
    raise exception 'change own code failed';
  end if;
  if not public.chem_recover_access_code('后端事务测试学生','我的化学找回短语','654322','test-recovery-fingerprint') then
    raise exception 'recovery reset failed';
  end if;
  if not exists (
    select 1 from app_private.chem_access_codes c
    where c.student_id=test_id and c.role='student'
      and c.code_hash=extensions.crypt('654322',c.code_hash)
  ) then
    raise exception 'recovered code verification failed';
  end if;

  if exists (
    select 1
    from (values
      ('00000000-0000-4000-8000-000000000002'::uuid),
      ('00000000-0000-4000-8000-000000000003'::uuid)
    ) d(id)
    where (select count(*) from public.chem_learning_plans p where p.student_id=d.id)<>40
  ) then
    raise exception 'demo grade plan count failed';
  end if;
end
$verify$;

rollback;
