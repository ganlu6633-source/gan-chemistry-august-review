#!/usr/bin/env node

/**
 * Destructive-to-ephemeral-data-only live Supabase concurrency acceptance.
 *
 * This is intentionally not part of `supabase test db`: pgTAP uses one
 * database session, while these assertions need independent backend sessions.
 * The harness never activates its temporary source release and never uses a
 * real learner. Every durable row is scoped to deterministic UUIDs derived
 * from the printed run token and is removed in `finally`.
 */

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const CONFIRMATION = 'CREATE_AND_DELETE_EPHEMERAL_JUNIOR_ROWS';
const PG_VERSION = '8.23.0';
const SUITE_LOCK = 'chem-live-junior-concurrency-suite-v1';
const STATEMENT_TIMEOUT_MS = 3_500;
const LOCK_OBSERVATION_TIMEOUT_MS = 1_000;
const DATABASE_WORK_BUDGET_MS = 10_000;

const HELP = `
Live junior Supabase concurrency acceptance

Required environment:
  LIVE_JUNIOR_DATABASE_URL       Direct or Supavisor session-mode Postgres URL.
  LIVE_JUNIOR_TEST_CONFIRMATION  ${CONFIRMATION}

Optional environment:
  LIVE_JUNIOR_DATABASE_CA        PEM CA path (public CA verification is the default).
  LIVE_JUNIOR_ALLOW_LOCAL=yes    Permit localhost for a rehearsal only.

Commands:
  node supabase/tests/live_junior_concurrency.mjs
  node supabase/tests/live_junior_concurrency.mjs --cleanup-run <32-hex-run-token>

The normal run prints a recovery token before creating rows. If the process is
forcibly killed before finally-cleanup, run the cleanup command with that token.
`;

function fail(message) {
  throw new Error(message);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function uuidFrom(seed) {
  const bytes = Buffer.from(createHash('sha256').update(seed).digest().subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function identities(runToken) {
  return {
    releaseId: uuidFrom(`${runToken}:release`),
    studentId: uuidFrom(`${runToken}:student`),
    planId: uuidFrom(`${runToken}:plan`),
    sessionId: uuidFrom(`${runToken}:session`),
  };
}

function parseArguments(argv) {
  if (argv.includes('--help') || argv.includes('-h')) return { help: true };
  const cleanupIndex = argv.indexOf('--cleanup-run');
  if (cleanupIndex >= 0) {
    const runToken = argv[cleanupIndex + 1] || '';
    if (!/^[0-9a-f]{32}$/.test(runToken)) fail('--cleanup-run requires the printed 32-character lowercase hex token');
    return { cleanupOnly: true, runToken };
  }
  if (argv.length > 0) fail(`Unknown argument: ${argv[0]}`);
  return { cleanupOnly: false, runToken: randomBytes(16).toString('hex') };
}

async function loadPgClient() {
  try {
    return (await import('pg')).Client;
  } catch {
    // Keep the production application dependency graph untouched. The pinned
    // test driver is cached in the OS temp directory instead of node_modules.
    const prefix = join(tmpdir(), 'gan-chemistry-live-test-drivers', `pg-${PG_VERSION}`);
    const entry = join(prefix, 'node_modules', 'pg', 'esm', 'index.mjs');
    if (!existsSync(entry)) {
      const npmCommand = process.platform === 'win32' ? 'npm.cmd' : 'npm';
      const result = spawnSync(
        npmCommand,
        ['install', '--prefix', prefix, '--no-save', '--ignore-scripts', '--no-audit', '--no-fund', `pg@${PG_VERSION}`],
        { stdio: 'inherit' },
      );
      if (result.status !== 0 || !existsSync(entry)) fail(`Unable to install pinned pg@${PG_VERSION} test driver`);
    }
    return (await import(pathToFileURL(entry).href)).Client;
  }
}

function connectionSettings(rawUrl) {
  if (!rawUrl) fail('LIVE_JUNIOR_DATABASE_URL is required');
  let parsed;
  try {
    parsed = new URL(rawUrl);
  } catch {
    fail('LIVE_JUNIOR_DATABASE_URL is not a valid URL');
  }
  if (!['postgres:', 'postgresql:'].includes(parsed.protocol)) fail('Only a PostgreSQL connection URL is accepted');
  const port = parsed.port || '5432';
  if (port === '6543') fail('Transaction-pooler port 6543 is not session-safe; use direct or session-mode port 5432');
  const hostname = parsed.hostname.toLowerCase();
  const local = hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '::1';
  const hosted = hostname.endsWith('.supabase.co') || hostname.endsWith('.pooler.supabase.com');
  if (!hosted && !(local && process.env.LIVE_JUNIOR_ALLOW_LOCAL === 'yes')) {
    fail('Target must be a Supabase host; set LIVE_JUNIOR_ALLOW_LOCAL=yes only for a local rehearsal');
  }

  // node-postgres lets sslmode in a URL replace an explicit SSL object. Remove
  // it so hosted runs always verify the server certificate.
  for (const key of ['sslmode', 'sslcert', 'sslkey', 'sslrootcert']) parsed.searchParams.delete(key);
  let ssl = false;
  if (!local) {
    ssl = { rejectUnauthorized: true };
    if (process.env.LIVE_JUNIOR_DATABASE_CA) {
      ssl.ca = readFileSync(process.env.LIVE_JUNIOR_DATABASE_CA, 'utf8');
    }
  }
  return {
    connectionString: parsed.toString(),
    ssl,
    targetLabel: `${hostname}:${port}/${parsed.pathname.replace(/^\//, '') || 'postgres'}`,
  };
}

function clientConfig(base, applicationName) {
  return {
    connectionString: base.connectionString,
    ssl: base.ssl,
    application_name: applicationName,
    connectionTimeoutMillis: STATEMENT_TIMEOUT_MS,
    query_timeout: STATEMENT_TIMEOUT_MS,
  };
}

async function configure(client) {
  await client.query(`set statement_timeout = '${STATEMENT_TIMEOUT_MS}ms'`);
  await client.query(`set lock_timeout = '${STATEMENT_TIMEOUT_MS - 500}ms'`);
  await client.query(`set idle_in_transaction_session_timeout = '${STATEMENT_TIMEOUT_MS}ms'`);
}

async function begin(client) {
  await client.query('begin');
  await client.query(`set local statement_timeout = '${STATEMENT_TIMEOUT_MS}ms'`);
  await client.query(`set local lock_timeout = '${STATEMENT_TIMEOUT_MS - 500}ms'`);
}

async function rollbackQuietly(client) {
  try {
    await client.query('rollback');
  } catch {
    // Connection close and final cleanup are still attempted by the caller.
  }
}

function tracked(queryPromise) {
  const state = { settled: false };
  state.outcome = queryPromise.then(
    (value) => ({ ok: true, value }),
    (error) => ({ ok: false, error }),
  ).finally(() => {
    state.settled = true;
  });
  return state;
}

function assertNotDeadlock(error, label) {
  if (error?.code === '40P01') fail(`${label}: PostgreSQL detected a deadlock (40P01)`);
}

async function assertBlockedOnLock(observer, backendPid, pending, label) {
  const deadline = Date.now() + LOCK_OBSERVATION_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (pending.settled) fail(`${label}: second session settled before it could be observed waiting`);
    const result = await observer.query(
      `select state, wait_event_type, wait_event
       from pg_catalog.pg_stat_activity
       where pid = $1`,
      [backendPid],
    );
    const row = result.rows[0];
    if (row?.state === 'active' && row?.wait_event_type === 'Lock') return row.wait_event;
    await sleep(25);
  }
  fail(`${label}: second session was not observed waiting on a PostgreSQL lock within ${LOCK_OBSERVATION_TIMEOUT_MS}ms`);
}

async function acquireSuiteLock(client) {
  const result = await client.query(
    `select pg_catalog.pg_try_advisory_lock(pg_catalog.hashtextextended($1, 0)) as locked`,
    [SUITE_LOCK],
  );
  if (result.rows[0]?.locked !== true) fail('Another live junior concurrency suite is already running');
}

async function releaseSuiteLock(client) {
  try {
    await client.query(
      `select pg_catalog.pg_advisory_unlock(pg_catalog.hashtextextended($1, 0))`,
      [SUITE_LOCK],
    );
  } catch {
    // Closing the guard connection also releases this session lock.
  }
}

async function cleanup(client, ids) {
  await rollbackQuietly(client);
  await begin(client);
  try {
    await client.query(`select pg_catalog.set_config('app.chem_junior_release_lifecycle', 'on', true)`);
    // Student first: its FK cascades remove only this test plan, session,
    // steps, attempts and mastery state before test questions are considered.
    await client.query(`delete from public.chem_students_v2 where id = $1`, [ids.studentId]);
    await client.query(
      `delete from app_private.chem_question_source_release_items where release_id = $1`,
      [ids.releaseId],
    );
    await client.query(`delete from public.chem_questions where source_release_id = $1`, [ids.releaseId]);
    await client.query(
      `delete from app_private.chem_question_source_releases where id = $1`,
      [ids.releaseId],
    );
    await client.query('commit');
  } catch (error) {
    await rollbackQuietly(client);
    throw error;
  }

  const residue = await client.query(
    `select
       (select count(*)::int from public.chem_students_v2 where id = $1) as students,
       (select count(*)::int from public.chem_learning_plans where id = $2) as plans,
       (select count(*)::int from public.chem_junior_daily_sessions where id = $3) as sessions,
       (select count(*)::int from public.chem_junior_session_steps where session_id = $3) as steps,
       (select count(*)::int from app_private.chem_question_source_release_items where release_id = $4) as items,
       (select count(*)::int from public.chem_questions where source_release_id = $4) as questions,
       (select count(*)::int from app_private.chem_question_source_releases where id = $4) as releases`,
    [ids.studentId, ids.planId, ids.sessionId, ids.releaseId],
  );
  const counts = residue.rows[0];
  assert.equal(Object.values(counts).reduce((sum, value) => sum + Number(value), 0), 0, `cleanup residue: ${JSON.stringify(counts)}`);
}

async function preflight(client) {
  const contract = await client.query(`
    select
      current_user,
      pg_catalog.to_regprocedure('public.chem_prepare_junior_source_release(uuid,text,text,text[],integer)') is not null as has_prepare,
      pg_catalog.to_regprocedure('public.chem_stage_junior_source_release_item(uuid,jsonb)') is not null as has_stage,
      pg_catalog.to_regprocedure('public.chem_seal_junior_source_release_manifest(uuid)') is not null as has_seal,
      pg_catalog.to_regprocedure('public.chem_junior_issue_step(uuid,uuid,text,smallint,text,text,jsonb)') is not null as has_issue,
      pg_catalog.to_regprocedure('public.chem_junior_record_step(uuid,uuid,uuid,smallint,boolean,integer,text)') is not null as has_answer,
      pg_catalog.has_schema_privilege(current_user, 'app_private', 'USAGE') as private_access,
      exists (
        select 1
        from pg_catalog.pg_trigger as trigger_row
        join pg_catalog.pg_class as relation on relation.oid = trigger_row.tgrelid
        join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
          and relation.relname = 'chem_knowledge_cards'
          and trigger_row.tgname = 'chem_lock_junior_knowledge_card_statement'
          and not trigger_row.tgisinternal
          and pg_catalog.pg_get_triggerdef(trigger_row.oid) ~ 'BEFORE INSERT OR UPDATE.*FOR EACH STATEMENT'
      ) as has_statement_card_lock`);
  const row = contract.rows[0];
  for (const key of ['has_prepare', 'has_stage', 'has_seal', 'has_issue', 'has_answer', 'private_access', 'has_statement_card_lock']) {
    if (row[key] !== true) fail(`Live database is missing required deployed contract: ${key}`);
  }
  return row.current_user;
}

async function selectFixture(client) {
  const curriculum = await client.query(`
    select day.id, day.knowledge_skill_ids, day.estimated_minutes
    from public.chem_junior_curriculum_days as day
    where day.textbook_version = '科粤版'
      and day.release_status = 'ready'
      and cardinality(day.knowledge_skill_ids) = 3
      and (
        select count(*)
        from pg_catalog.unnest(day.knowledge_skill_ids) as requested(skill_id)
        where app_private.chem_junior_knowledge_card_is_ready('科粤版', requested.skill_id)
      ) = 3
      and not exists (
        select 1
        from pg_catalog.unnest(day.knowledge_skill_ids) as requested(skill_id)
        where (
          select count(*)
          from public.chem_questions as question
          join app_private.chem_question_source_releases as release on release.id = question.source_release_id
          join app_private.chem_junior_source_release_rights as rights on rights.release_id = release.id
          join app_private.chem_junior_knowledge_provenance as provenance
            on provenance.source_release_id = release.id
           and provenance.textbook_version = '科粤版'
           and provenance.knowledge_id = question.knowledge_id
           and provenance.verification_status = 'verified'
           and provenance.reviewed_at is not null
          where question.knowledge_id = requested.skill_id
            and question.grade_band = '初三'
            and question.textbook_version = '科粤版'
            and question.source_kind = 'user_provided_local'
            and question.review_status = 'approved'
            and question.scope_status = 'IN'
            and question.usable_for_review
            and question.render_mode = 'native'
            and question.image_url is null
            and question.asset_refs = '[]'::jsonb
            and release.status = 'active'
            and release.verification_status = 'full_visual_verified'
            and release.verification_manifest_sha256 = release.manifest_sha256
            and release.revision_contract = 'v3_junior_native_text'
            and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
            and rights.redistribution_allowed = false
            and rights.attested_manifest_sha256 = release.manifest_sha256
        ) < 7
      )
    order by day.day_number
    limit 1`);
  if (curriculum.rowCount !== 1) fail('No ready 科粤版 curriculum day has three ready cards and seven active originals per route');
  const day = curriculum.rows[0];

  const questions = await client.query(`
    with ranked as (
      select
        question.*,
        row_number() over (partition by question.knowledge_id order by question.level, question.id) as route_rank
      from public.chem_questions as question
      join app_private.chem_question_source_releases as release on release.id = question.source_release_id
      join app_private.chem_junior_source_release_rights as rights on rights.release_id = release.id
      join app_private.chem_junior_knowledge_provenance as provenance
        on provenance.source_release_id = release.id
       and provenance.textbook_version = '科粤版'
       and provenance.knowledge_id = question.knowledge_id
       and provenance.verification_status = 'verified'
       and provenance.reviewed_at is not null
      where question.knowledge_id = any($1::text[])
        and question.grade_band = '初三'
        and question.textbook_version = '科粤版'
        and question.source_kind = 'user_provided_local'
        and question.review_status = 'approved'
        and question.scope_status = 'IN'
        and question.usable_for_review
        and question.render_mode = 'native'
        and question.image_url is null
        and question.asset_refs = '[]'::jsonb
        and release.status = 'active'
        and release.verification_status = 'full_visual_verified'
        and release.verification_manifest_sha256 = release.manifest_sha256
        and release.revision_contract = 'v3_junior_native_text'
        and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
        and rights.redistribution_allowed = false
        and rights.attested_manifest_sha256 = release.manifest_sha256
    )
    select
      ranked.*,
      (
        select card.id
        from public.chem_knowledge_cards as card
        where card.skill_id = ranked.knowledge_id and card.review_status = 'approved'
        order by card.id
        limit 1
      ) as card_id
    from ranked
    where route_rank <= 7
    order by knowledge_id, route_rank`, [day.knowledge_skill_ids]);
  assert.equal(questions.rowCount, 21, 'fixture must contain exactly seven originals for each of three routes');
  for (const skillId of day.knowledge_skill_ids) {
    assert.equal(questions.rows.filter((row) => row.knowledge_id === skillId).length, 7, `fixture route ${skillId}`);
  }
  return { day, questions: questions.rows };
}

function stageItems(runToken, sourceQuestions) {
  const prefix = runToken.slice(0, 16);
  return sourceQuestions.map((question, index) => ({
    question_id: `live_jc_q_${prefix}_${index + 1}`,
    mother_id: `live_jc_m_${prefix}_${index + 1}`,
    knowledge_id: question.knowledge_id,
    concept_key: question.concept_key,
    level: Number(question.level),
    stem: question.stem,
    options: question.options,
    correct_option: Number(question.correct_option),
    explanation: question.explanation,
    scaffold: question.scaffold,
    same_type_key: question.same_type_key,
    source_item_key: `live-jc-source-${prefix}-${index + 1}`,
    parent_source_item_key: `live-jc-parent-${prefix}-${index + 1}`,
    canonical_source_id: `live-jc.${prefix}.${index + 1}`,
    source_title: 'live concurrency harness temporary source',
    source_exam: 'ephemeral database acceptance',
    source_question_no: String(index + 1),
    source_locator_label: 'temporary row removed by the live junior concurrency harness',
  }));
}

async function prepareRelease(client, ids, runToken, fixture) {
  const items = stageItems(runToken, fixture.questions);
  const placeholder = createHash('sha256').update(`${runToken}:placeholder`).digest('hex');
  await begin(client);
  try {
    await client.query(
      `select public.chem_prepare_junior_source_release($1, $2, '科粤版', $3::text[], 21)`,
      [ids.releaseId, placeholder, fixture.day.knowledge_skill_ids],
    );
    const staged = await client.query(
      `select public.chem_stage_junior_source_release_item($1, item.value) as staged
       from pg_catalog.jsonb_array_elements($2::jsonb) as item(value)`,
      [ids.releaseId, JSON.stringify(items.slice(0, 20))],
    );
    assert.equal(staged.rowCount, 20);
    await client.query('commit');
  } catch (error) {
    await rollbackQuietly(client);
    throw error;
  }
  return items[20];
}

async function testStageSeal(a, b, observer, bPid, ids, lastItem) {
  await begin(a);
  await a.query(
    `select public.chem_stage_junior_source_release_item($1, $2::jsonb) as staged`,
    [ids.releaseId, JSON.stringify(lastItem)],
  );
  await begin(b);
  const pending = tracked(b.query(
    `select public.chem_seal_junior_source_release_manifest($1) as manifest`,
    [ids.releaseId],
  ));
  const waitEvent = await assertBlockedOnLock(observer, bPid, pending, 'stage/seal serialization');
  await a.query('commit');
  const outcome = await pending.outcome;
  if (!outcome.ok) {
    assertNotDeadlock(outcome.error, 'stage/seal serialization');
    throw outcome.error;
  }
  const manifest = outcome.value.rows[0]?.manifest;
  assert.match(manifest, /^[0-9a-f]{64}$/);
  await b.query('commit');
  const postcondition = await observer.query(
    `select release.manifest_sha256, count(item.question_id)::int as item_count
     from app_private.chem_question_source_releases as release
     join app_private.chem_question_source_release_items as item on item.release_id = release.id
     where release.id = $1
     group by release.manifest_sha256`,
    [ids.releaseId],
  );
  assert.deepEqual(postcondition.rows[0], { manifest_sha256: manifest, item_count: 21 });
  return waitEvent;
}

async function createStudentSession(client, ids, runToken, fixture) {
  await begin(client);
  try {
    await client.query(
      `insert into public.chem_students_v2 (
         id, display_name, grade_band, record_status, enrollment_start_date,
         textbook_version, needs_initial_diagnostic, metadata
       ) values (
         $1, $2, '初三', 'active', (pg_catalog.now() at time zone 'Asia/Shanghai')::date,
         '科粤版', false, pg_catalog.jsonb_build_object('liveJuniorConcurrencyRun', $3)
       )`,
      [ids.studentId, `__live_junior_concurrency__${runToken.slice(0, 12)}`, runToken],
    );
    await client.query(
      `insert into public.chem_learning_plans (
         id, student_id, plan_date, mode, title, skill_ids, estimated_minutes,
         source, is_scheduled, junior_curriculum_day_id, delivery_mode,
         question_count, round_limit
       ) values (
         $1, $2, (pg_catalog.now() at time zone 'Asia/Shanghai')::date,
         'REVIEW', '临时并发验收（自动清理）', $3::text[], pg_catalog.least($4, 60),
         'course', true, $5, 'junior_adaptive', 12, 1
       )`,
      [ids.planId, ids.studentId, fixture.day.knowledge_skill_ids, fixture.day.estimated_minutes, fixture.day.id],
    );
    await client.query(
      `insert into public.chem_junior_daily_sessions (
         id, student_id, plan_day_id, curriculum_day_id, study_date,
         textbook_version, knowledge_skill_ids, initial_question_target,
         hard_question_cap, status
       ) values (
         $1, $2, $3, $4, (pg_catalog.now() at time zone 'Asia/Shanghai')::date,
         '科粤版', $5::text[], 12, 15, 'active'
       )`,
      [ids.sessionId, ids.studentId, ids.planId, fixture.day.id, fixture.day.knowledge_skill_ids],
    );
    await client.query('commit');
  } catch (error) {
    await rollbackQuietly(client);
    throw error;
  }
}

async function questionCapability(client, question, routeReason) {
  const result = await client.query(`
    select
      question.question_revision_token,
      pg_catalog.jsonb_build_object(
        'questionId', question.id,
        'motherId', question.mother_id,
        'skillId', question.skill_id,
        'knowledgeId', question.knowledge_id,
        'conceptKey', question.concept_key,
        'level', question.level,
        'gradeBand', question.grade_band,
        'textbookVersion', question.textbook_version,
        'stem', question.stem,
        'options', question.options,
        'correctOption', question.correct_option,
        'explanation', question.explanation,
        'scaffold', question.scaffold,
        'reviewStatus', question.review_status,
        'scopeStatus', question.scope_status,
        'sourceKind', question.source_kind,
        'renderMode', question.render_mode,
        'imageUrl', question.image_url,
        'assetRefs', question.asset_refs,
        'sourceReleaseId', question.source_release_id,
        'sourceItemKey', question.source_item_key,
        'parentSourceItemKey', question.parent_source_item_key,
        'sameTypeKey', question.same_type_key,
        'contentFingerprint', question.content_fingerprint,
        'revisionToken', question.question_revision_token,
        'routeKind', 'new_learning',
        'routeReason', $2
      ) as snapshot
    from public.chem_questions as question
    where question.id = $1`, [question.id, routeReason]);
  assert.equal(result.rowCount, 1);
  return result.rows[0];
}

function issueSql() {
  return `select * from public.chem_junior_issue_step(
    $1, $2, $3, $4::smallint, 'new_learning', $5, $6::jsonb
  )`;
}

async function testDuplicateIssue(a, b, observer, bPid, ids, question, capability) {
  const reason = 'live concurrency duplicate issue acceptance';
  const params = [ids.sessionId, ids.studentId, question.id, 1, reason, JSON.stringify(capability.snapshot)];
  await begin(a);
  const first = await a.query(issueSql(), params);
  assert.equal(first.rowCount, 1);
  await begin(b);
  const pending = tracked(b.query(issueSql(), params));
  const waitEvent = await assertBlockedOnLock(observer, bPid, pending, 'duplicate issue serialization');
  await a.query('commit');
  const outcome = await pending.outcome;
  if (outcome.ok) fail('duplicate issue unexpectedly inserted a second step');
  assertNotDeadlock(outcome.error, 'duplicate issue serialization');
  assert.equal(outcome.error.code, '40001');
  assert.match(outcome.error.message, /junior issue sequence is stale/);
  await rollbackQuietly(b);
  const count = await observer.query(
    `select count(*)::int as count from public.chem_junior_session_steps where session_id = $1`,
    [ids.sessionId],
  );
  assert.equal(count.rows[0].count, 1);
  return { stepId: first.rows[0].step_id, waitEvent };
}

async function testDuplicateAnswer(a, b, observer, bPid, ids, question, capability, stepId) {
  const params = [ids.sessionId, ids.studentId, stepId, Number(question.correct_option), false, 9, capability.question_revision_token];
  const sql = `select * from public.chem_junior_record_step($1, $2, $3, $4::smallint, $5, $6, $7)`;
  await begin(a);
  const first = await a.query(sql, params);
  assert.equal(first.rowCount, 1);
  await begin(b);
  const pending = tracked(b.query(sql, params));
  const waitEvent = await assertBlockedOnLock(observer, bPid, pending, 'duplicate answer serialization');
  await a.query('commit');
  const outcome = await pending.outcome;
  if (outcome.ok) fail('duplicate answer unexpectedly changed an already answered step');
  assertNotDeadlock(outcome.error, 'duplicate answer serialization');
  assert.match(outcome.error.message, /junior session step is already locked/);
  await rollbackQuietly(b);
  const state = await observer.query(
    `select count(*)::int as rows, count(*) filter (where answered_at is not null)::int as answered
     from public.chem_junior_session_steps where id = $1`,
    [stepId],
  );
  assert.deepEqual(state.rows[0], { rows: 1, answered: 1 });
  return waitEvent;
}

async function testAdvisoryCardOrder(a, b, observer, bPid, ids, question, capability) {
  const reason = 'live concurrency advisory before card acceptance';
  const params = [ids.sessionId, ids.studentId, question.id, 2, reason, JSON.stringify(capability.snapshot)];
  await begin(a);
  const issued = await a.query(issueSql(), params);
  assert.equal(issued.rowCount, 1);
  await begin(b);
  const pending = tracked(b.query(
    `update public.chem_knowledge_cards set updated_at = updated_at where id = $1 returning id`,
    [question.card_id],
  ));
  const waitEvent = await assertBlockedOnLock(observer, bPid, pending, 'advisory/card lock order');
  await a.query('commit');
  const outcome = await pending.outcome;
  if (outcome.ok) fail('bound junior knowledge card update unexpectedly succeeded');
  assertNotDeadlock(outcome.error, 'advisory/card lock order');
  assert.match(outcome.error.message, /knowledge card is immutable/);
  await rollbackQuietly(b);
  return waitEvent;
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  if (args.help) {
    process.stdout.write(HELP);
    return;
  }
  if (process.env.LIVE_JUNIOR_TEST_CONFIRMATION !== CONFIRMATION) {
    fail(`Set LIVE_JUNIOR_TEST_CONFIRMATION=${CONFIRMATION} to acknowledge ephemeral row creation and cleanup`);
  }

  const base = connectionSettings(process.env.LIVE_JUNIOR_DATABASE_URL);
  const ids = identities(args.runToken);
  console.log(`target=${base.targetLabel}`);
  console.log(`run_token=${args.runToken}`);
  console.log(`release_id=${ids.releaseId} student_id=${ids.studentId}`);

  const Client = await loadPgClient();
  const clients = {
    guard: new Client(clientConfig(base, `gan-live-junior-${args.runToken.slice(0, 8)}-guard`)),
    a: new Client(clientConfig(base, `gan-live-junior-${args.runToken.slice(0, 8)}-a`)),
    b: new Client(clientConfig(base, `gan-live-junior-${args.runToken.slice(0, 8)}-b`)),
    observer: new Client(clientConfig(base, `gan-live-junior-${args.runToken.slice(0, 8)}-observer`)),
  };
  let connected = [];
  let exitSignal = null;
  const signalHandler = (signal) => {
    exitSignal = signal;
  };
  process.once('SIGINT', signalHandler);
  process.once('SIGTERM', signalHandler);

  try {
    await Promise.all(Object.values(clients).map(async (client) => {
      await client.connect();
      connected.push(client);
      await configure(client);
    }));
    await acquireSuiteLock(clients.guard);

    if (args.cleanupOnly) {
      await cleanup(clients.guard, ids);
      console.log('cleanup=verified_zero_residue');
      return;
    }

    const dbWorkStarted = Date.now();
    const role = await preflight(clients.guard);
    const fixture = await selectFixture(clients.guard);
    const bPid = Number((await clients.b.query('select pg_catalog.pg_backend_pid() as pid')).rows[0].pid);
    const lastItem = await prepareRelease(clients.guard, ids, args.runToken, fixture);
    if (exitSignal) fail(`Interrupted by ${exitSignal}`);
    const stageSealWait = await testStageSeal(clients.a, clients.b, clients.observer, bPid, ids, lastItem);

    await createStudentSession(clients.guard, ids, args.runToken, fixture);
    const firstQuestion = fixture.questions[0];
    const secondQuestion = fixture.questions.find((row) =>
      row.id !== firstQuestion.id
      && row.mother_id !== firstQuestion.mother_id
      && row.source_item_key !== firstQuestion.source_item_key
      && row.parent_source_item_key !== firstQuestion.parent_source_item_key
      && row.content_fingerprint !== firstQuestion.content_fingerprint);
    if (!secondQuestion) fail('Fixture does not contain two independent question identities');

    const firstReason = 'live concurrency duplicate issue acceptance';
    const firstCapability = await questionCapability(clients.guard, firstQuestion, firstReason);
    const issued = await testDuplicateIssue(clients.a, clients.b, clients.observer, bPid, ids, firstQuestion, firstCapability);
    const answerWait = await testDuplicateAnswer(
      clients.a, clients.b, clients.observer, bPid, ids,
      firstQuestion, firstCapability, issued.stepId,
    );
    const secondReason = 'live concurrency advisory before card acceptance';
    const secondCapability = await questionCapability(clients.guard, secondQuestion, secondReason);
    const cardWait = await testAdvisoryCardOrder(
      clients.a, clients.b, clients.observer, bPid, ids, secondQuestion, secondCapability,
    );
    const elapsedMs = Date.now() - dbWorkStarted;
    assert.ok(elapsedMs < DATABASE_WORK_BUDGET_MS, `database acceptance exceeded ${DATABASE_WORK_BUDGET_MS}ms: ${elapsedMs}ms`);
    console.log(JSON.stringify({
      result: 'pass',
      role,
      databaseWorkMs: elapsedMs,
      observedWaits: {
        stageSeal: stageSealWait,
        duplicateIssue: issued.waitEvent,
        duplicateAnswer: answerWait,
        advisoryCard: cardWait,
      },
      expectedConflictResults: {
        duplicateIssue: '40001 junior issue sequence is stale',
        duplicateAnswer: 'junior session step is already locked',
        boundCardUpdate: 'knowledge card is immutable',
        deadlock: 'never 40P01',
      },
    }, null, 2));
  } finally {
    // Release any transaction-scoped application locks before the independent
    // guard connection performs exact-ID cleanup after a failed assertion.
    await Promise.allSettled(
      [clients.a, clients.b].filter((client) => connected.includes(client)).map(rollbackQuietly),
    );
    if (connected.includes(clients.guard)) {
      try {
        await cleanup(clients.guard, ids);
        console.log('cleanup=verified_zero_residue');
      } catch (cleanupError) {
        console.error(`cleanup_failed=${cleanupError.message}`);
        console.error(`recovery_command=node supabase/tests/live_junior_concurrency.mjs --cleanup-run ${args.runToken}`);
        process.exitCode = 2;
      }
      await releaseSuiteLock(clients.guard);
    }
    await Promise.allSettled(Object.values(clients).map((client) => client.end()));
    process.removeListener('SIGINT', signalHandler);
    process.removeListener('SIGTERM', signalHandler);
  }

  if (exitSignal) fail(`Interrupted by ${exitSignal}`);
}

main().catch((error) => {
  console.error(error?.stack || error);
  process.exitCode ||= 1;
});
