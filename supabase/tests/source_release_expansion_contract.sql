-- Contract-only test for the High-2/High-3 source-release expansion.
-- It does not activate a release or persist fixtures: every insert is rolled back.
begin;

do $contract$
declare
  activation_rpc regprocedure := to_regprocedure('public.chem_activate_source_original_release(uuid,text)');
  v_constraint_validated boolean;
  v_security_definer boolean;
  v_config text[];
  v_body text;
  v_compact_body text;
  v_failed_as_expected boolean;
  v_marker text;
begin
  select c.convalidated
  into v_constraint_validated
  from pg_constraint c
  where c.conrelid = 'app_private.chem_question_source_releases'::regclass
    and c.conname = 'chem_question_source_releases_expected_question_count_check'
    and c.contype = 'c';

  if v_constraint_validated is distinct from true then
    raise exception 'expected-question-count contract is missing or not validated';
  end if;

  -- The High-1 contract remains exact, while High-2 and High-3 accept the
  -- inclusive expansion endpoints and representative in-range values.
  insert into app_private.chem_question_source_releases (
    id, manifest_sha256, grade_band, status, expected_question_count
  ) values
    (gen_random_uuid(), encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), '高一', 'staged', 125),
    (gen_random_uuid(), encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), '高一', 'staged', 175),
    (gen_random_uuid(), encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), '高二', 'staged', 200),
    (gen_random_uuid(), encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), '高二', 'staged', 201),
    (gen_random_uuid(), encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), '高二', 'staged', 2000),
    (gen_random_uuid(), encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), '高三', 'staged', 275),
    (gen_random_uuid(), encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), '高三', 'staged', 299),
    (gen_random_uuid(), encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), '高三', 'staged', 2000);

  v_failed_as_expected := false;
  begin
    insert into app_private.chem_question_source_releases (
      id, manifest_sha256, grade_band, status, expected_question_count
    ) values (
      gen_random_uuid(), encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'),
      '高一', 'staged', 150
    );
  exception when check_violation then
    v_failed_as_expected := true;
  end;
  if not v_failed_as_expected then
    raise exception 'High-1 unexpectedly accepted a non-contract count';
  end if;

  foreach v_marker in array array['199', '2001']::text[] loop
    v_failed_as_expected := false;
    begin
      insert into app_private.chem_question_source_releases (
        id, manifest_sha256, grade_band, status, expected_question_count
      ) values (
        gen_random_uuid(), encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'),
        '高二', 'staged', v_marker::integer
      );
    exception when check_violation then
      v_failed_as_expected := true;
    end;
    if not v_failed_as_expected then
      raise exception 'High-2 unexpectedly accepted out-of-range count %', v_marker;
    end if;
  end loop;

  foreach v_marker in array array['274', '2001']::text[] loop
    v_failed_as_expected := false;
    begin
      insert into app_private.chem_question_source_releases (
        id, manifest_sha256, grade_band, status, expected_question_count
      ) values (
        gen_random_uuid(), encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'),
        '高三', 'staged', v_marker::integer
      );
    exception when check_violation then
      v_failed_as_expected := true;
    end;
    if not v_failed_as_expected then
      raise exception 'High-3 unexpectedly accepted out-of-range count %', v_marker;
    end if;
  end loop;

  if activation_rpc is null then
    raise exception 'source release activation RPC is missing';
  end if;

  select p.prosecdef, p.proconfig, p.prosrc
  into v_security_definer, v_config, v_body
  from pg_proc p
  where p.oid = activation_rpc;

  if v_security_definer is distinct from true then
    raise exception 'source release activation RPC must remain security definer';
  end if;

  if not exists (
    select 1
    from unnest(coalesce(v_config, array[]::text[])) setting
    where split_part(setting, '=', 1) = 'search_path'
      and split_part(setting, '=', 2) in ('', '""')
  ) then
    raise exception 'source release activation RPC must pin an empty search_path';
  end if;

  if has_function_privilege('anon', activation_rpc, 'execute')
     or has_function_privilege('authenticated', activation_rpc, 'execute') then
    raise exception 'browser roles must not execute source release activation';
  end if;
  if not has_function_privilege('service_role', activation_rpc, 'execute') then
    raise exception 'service_role must execute source release activation';
  end if;

  v_compact_body := regexp_replace(v_body, '[[:space:]]+', '', 'g');

  if position('(v_grade_band=''高一''andv_release_expectednotin(125,175))' in v_compact_body) = 0
     or position('(v_grade_band=''高二''andv_release_expectednotbetween200and2000)' in v_compact_body) = 0
     or position('(v_grade_band=''高三''andv_release_expectednotbetween275and2000)' in v_compact_body) = 0 then
    raise exception 'activation RPC count gates do not match the grade contracts';
  end if;

  if position(
    'when''高二''thenarray[''H2_ELECTRO'',''H2_EQUIL'',''H2_K'',''H2_KSP'',''H2_PH_HYDRO'',''H2_RATE'',''H2_THERMO'',''H2_WEAK'']::text[]'
    in v_compact_body
  ) = 0 then
    raise exception 'High-2 activation must require the exact eight REVIEW skills';
  end if;

  if position(
    'elsearray[''H3_AQ'',''H3_ELECTRO'',''H3_EQUILIBRIUM'',''H3_EXPERIMENT'',''H3_INORGANIC'',''H3_ION_REDOX'',''H3_ORGANIC'',''H3_PROCESS'',''H3_STOICH'',''H3_STRUCTURE'',''H3_THERMO_RATE'']::text[]'
    in v_compact_body
  ) = 0 then
    raise exception 'High-3 activation must require the exact eleven REVIEW skills';
  end if;

  if position('(v_grade_band=''高一''andcount(*)<>25)' in v_compact_body) = 0
     or position('(v_grade_bandin(''高二'',''高三'')andcount(*)<25)' in v_compact_body) = 0
     or position('count(distinctq.concept_key)<>5' in v_compact_body) = 0
     or position('(v_grade_band=''高一''andcount(*)=5)' in v_compact_body) = 0
     or position('(v_grade_bandin(''高二'',''高三'')andcount(*)>=5)' in v_compact_body) = 0 then
    raise exception 'activation RPC skill/concept distribution gates are incomplete';
  end if;

  -- Preserve the four-option single-choice and source-backed integrity gates.
  foreach v_marker in array array[
    'jsonb_array_length(q.options) <> 4',
    'q.correct_option not between 0 and 3',
    'content fingerprint must equal the normalized stem and four options',
    'release ledger must contain exactly',
    'private asset payload does not match its SHA-256 digest',
    'release manifest does not match the staged source items',
    'every source-backed question must have both question and analysis images',
    'postcondition failed: an older same-grade REVIEW question remains enabled'
  ]::text[] loop
    if position(v_marker in v_body) = 0 then
      raise exception 'activation RPC lost required integrity assertion: %', v_marker;
    end if;
  end loop;

  if position('pg_catalog.pg_advisory_xact_lock' in v_body) = 0
     or position('app.chem_release_activation' in v_body) = 0 then
    raise exception 'activation RPC lost its serialized atomic-switch guard';
  end if;
end;
$contract$;

rollback;
