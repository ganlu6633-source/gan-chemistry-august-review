import { describe, expect, it } from 'vitest'

import accessFunction from '../../supabase/functions/chemistry-access/index.ts?raw'
import juniorBaseMigration from '../../supabase/migrations/20260823102000_add_junior_adaptive_daily_learning.sql?raw'

const migrationModules = import.meta.glob('../../supabase/migrations/20260829*junior*.sql', {
  eager: true,
  query: '?raw',
  import: 'default',
}) as Record<string, string>

const migrationEntries = Object.entries(migrationModules).sort(([left], [right]) => left.localeCompare(right))
const juniorEvidenceMigration = migrationEntries.map(([, source]) => source).join('\n')
const effectiveJuniorSql = `${juniorBaseMigration}\n${juniorEvidenceMigration}`

function sqlFunction(source: string, name: string, nextName?: string) {
  const normalized = source.toLowerCase()
  const marker = `create or replace function public.${name.toLowerCase()}`
  const start = normalized.lastIndexOf(marker)
  if (start < 0) return ''
  if (!nextName) return source.slice(start)
  const end = normalized.indexOf(`create or replace function public.${nextName.toLowerCase()}`, start + marker.length)
  return source.slice(start, end < 0 ? undefined : end)
}

function accessSection(startMarker: string, endMarker: string) {
  const start = accessFunction.indexOf(startMarker)
  const end = accessFunction.indexOf(endMarker, start + startMarker.length)
  return start < 0 ? '' : accessFunction.slice(start, end < 0 ? undefined : end)
}

const juniorAccess = accessSection('function juniorSourceQuestionIsSafe', 'async function studentDashboard')

describe('2026-08-29 junior evidence backend contract', () => {
  it('admits a bounded junior source release without weakening any high-school count contract', () => {
    expect(juniorEvidenceMigration).toMatch(
      /chem_question_source_releases_grade_band_check[\s\S]*?grade_band\s+in\s*\(\s*'初三'\s*,\s*'高一'\s*,\s*'高二'\s*,\s*'高三'\s*\)/i,
    )
    expect(juniorEvidenceMigration).toMatch(
      /grade_band\s*=\s*'初三'[\s\S]{0,120}expected_question_count\s+between\s+21\s+and\s+2000/i,
    )
    expect(juniorEvidenceMigration).toMatch(
      /grade_band\s*=\s*'高一'[\s\S]{0,180}expected_question_count\s+in\s*\(\s*125\s*,\s*175\s*\)[\s\S]{0,160}between\s+211\s+and\s+275/i,
    )
    expect(juniorEvidenceMigration).toMatch(/grade_band\s*=\s*'高二'[\s\S]{0,120}between\s+200\s+and\s+2000/i)
    expect(juniorEvidenceMigration).toMatch(/grade_band\s*=\s*'高三'[\s\S]{0,120}between\s+275\s+and\s+2000/i)
  })

  it('fails closed when a junior plan is sent through legacy start or submit routes', () => {
    const legacyStart = accessSection('async function startPlanPayload', 'async function authenticate')
    expect(legacyStart).toMatch(/plan\.delivery_mode\s*===\s*["']junior_adaptive["'][\s\S]*?throw\s+new\s+RequestError\(409/i)
    expect(accessFunction).toMatch(/body\.action\s*===\s*["']submit_attempt["'][\s\S]*?select\(["'][^"']*delivery_mode[^"']*["']\)[\s\S]*?plan\.delivery_mode\s*===\s*["']junior_adaptive["'][\s\S]*?reply\(req,[\s\S]*?,\s*409\)/i)
  })

  it('lets finalization win over a stale concurrent blocker without creating a false alert', () => {
    const blocker = accessSection('async function blockJuniorSession', 'async function juniorVerifiedProvenance')
    expect(blocker).toMatch(/update\(\{[\s\S]*?status:\s*["']blocked["'][\s\S]*?\.eq\(["']status["']\s*,\s*["']active["']\)[\s\S]*?\.select\(["']id["']\)[\s\S]*?\.maybeSingle\(\)/i)
    expect(blocker).toMatch(/if\s*\(\s*!blocked\.data\s*\)[\s\S]*?select\(["']status["']\)[\s\S]*?status\s*===\s*["']completed["']/i)
    expect(blocker.indexOf('if (!blocked.data)')).toBeLessThan(blocker.indexOf('await ensureJuniorTeacherAlert'))
  })

  it('reads private junior provenance only through a least-privilege service RPC', () => {
    expect(juniorEvidenceMigration).toMatch(/create\s+or\s+replace\s+function\s+public\.chem_junior_verified_provenance_rows[\s\S]*?security\s+definer[\s\S]*?set\s+search_path\s*=\s*''/i)
    expect(juniorEvidenceMigration).toMatch(/revoke\s+all\s+on\s+function\s+public\.chem_junior_verified_provenance_rows[\s\S]*?from\s+public\s*,\s*anon\s*,\s*authenticated\s*,\s*service_role[\s\S]*?grant\s+execute[\s\S]*?to\s+service_role/i)
    expect(juniorAccess).toContain('supabase.rpc("chem_junior_verified_provenance_rows"')
    expect(juniorAccess).not.toContain('supabase.schema("app_private")')
  })

  it('rechecks future dates, immutable issued snapshots, and current source eligibility on open and submit', () => {
    expect(juniorAccess).toMatch(/plan\.plan_date[\s\S]{0,100}>\s*shanghaiDate\(\)[\s\S]{0,160}RequestError\(409/i)
    expect(juniorAccess).toContain('function juniorIssuedQuestionMatchesContract')
    for (const gate of [
      'textbook_version',
      'source_release_id',
      'usable_for_review',
      'review_status',
      'scope_status',
      'question_revision_token',
      'content_fingerprint',
    ]) {
      expect(juniorAccess, `missing issued-question recheck for ${gate}`).toContain(gate)
    }
    expect(accessFunction).toMatch(/body\.action\s*===\s*["']junior_submit_step["'][\s\S]*?\.eq\(["']usable_for_review["']\s*,\s*true\)[\s\S]*?\.eq\(["']render_mode["']\s*,\s*["']native["']\)/i)
  })

  it('issues and resumes junior steps only through atomic service-role database gates', () => {
    const issueStep = sqlFunction(juniorEvidenceMigration, 'chem_junior_issue_step', 'chem_junior_validate_issued_step')
    const validateStep = sqlFunction(juniorEvidenceMigration, 'chem_junior_validate_issued_step')

    for (const [name, contract] of [['issue', issueStep], ['resume', validateStep]] as const) {
      expect(contract, `missing ${name} RPC`).not.toBe('')
      expect(contract).toMatch(/security\s+definer[\s\S]*?set\s+search_path\s*=\s*''/i)
      expect(contract).toMatch(/pg_advisory_xact_lock[\s\S]*?chem-source-original-release[\s\S]*?pg_advisory_xact_lock[\s\S]*?chem-h3-original-release/i)
      expect(contract.indexOf("'chem-source-original-release'")).toBeLessThan(contract.indexOf('from public.chem_junior_daily_sessions'))
      expect(contract).toMatch(/chem_junior_daily_sessions[\s\S]*?status\s*=\s*'active'[\s\S]*?for\s+update/i)
      expect(contract).toMatch(/chem_junior_curriculum_days[\s\S]*?release_status\s*=\s*'ready'[\s\S]*?knowledge_skill_ids\s*=\s*v_session\.knowledge_skill_ids[\s\S]*?for\s+share/i)
      expect(contract).toMatch(/chem_questions[\s\S]*?for\s+share/i)
      expect(contract).toMatch(/chem_junior_knowledge_provenance[\s\S]*?verification_status\s*=\s*'verified'[\s\S]*?for\s+share/i)
      expect(contract).toMatch(/chem_question_source_releases[\s\S]*?status\s*=\s*'active'[\s\S]*?verification_status\s*=\s*'full_visual_verified'[\s\S]*?for\s+share/i)
      expect(contract).toContain("release.revision_contract = 'v3_junior_native_text'")
      expect(contract).toContain('release.verified_at is not null')
      expect(contract).toContain('release.verification_actor')
      expect(contract).toMatch(/chem_knowledge_cards[\s\S]*?review_status\s*=\s*'approved'[\s\S]*?for\s+share/i)
      expect(contract).toMatch(/having\s+count\(card\.id\)\s*=\s*1/i)
      expect(contract).toContain("grade_band <> '初三'")
      expect(contract).toContain("source_kind <> 'licensed_local'")
      expect(contract).toContain("review_status <> 'approved'")
      expect(contract).toContain("scope_status <> 'IN'")
      expect(contract).toContain('not v_question.usable_for_review')
      expect(contract).toContain("render_mode <> 'native'")
      expect(contract).toContain('v_question.image_url is not null')
      expect(contract).toContain("v_question.asset_refs <> '[]'::jsonb")
      expect(contract).toContain('v_question.skill_id <> v_question.knowledge_id')
      expect(contract).toMatch(/jsonb_array_length\(v_question\.options\)\s*<>\s*4/i)
      expect(contract).toMatch(/v_question\.correct_option\s*>\s*3/i)
      expect(contract).toMatch(/count\(distinct\s+pg_catalog\.btrim\(option_value\.value\s*#>>\s*'\{\}'\)\)[\s\S]{0,120}<>\s*4/i)
      expect(contract).toMatch(/question_snapshot\s+is\s+distinct\s+from\s+v_snapshot/i)
    }

    const nativeQuestionGate = accessSection('function juniorNativeQuestionIsSafe', 'function juniorIssuedQuestionMatchesContract')
    expect(nativeQuestionGate).toMatch(/options\.length\s*===\s*4/i)
    expect(nativeQuestionGate).toMatch(/typeof\s+option\s*===\s*["']string["']/i)
    expect(nativeQuestionGate).toMatch(/new\s+Set\(normalizedOptions\)\.size\s*===\s*4/i)
    expect(nativeQuestionGate).toMatch(/correctOption\s*<=\s*3/i)

    for (const identity of ['question_id', 'mother_id', 'source_item_key', 'parent_source_item_key', 'content_fingerprint']) {
      expect(issueStep, `issue RPC does not atomically exclude ${identity}`).toContain(identity)
      expect(validateStep, `resume RPC does not revalidate ${identity}`).toContain(identity)
    }
    for (const contentField of ['stem', 'options', 'correct_option', 'explanation', 'scaffold', 'question_revision_token']) {
      expect(issueStep, `issue RPC does not bind ${contentField}`).toContain(contentField)
      expect(validateStep, `resume RPC does not revalidate ${contentField}`).toContain(contentField)
    }
    for (const contract of [issueStep, validateStep]) {
      expect(contract).toMatch(/route_kind\s*=\s*'prior_error_recovery'[\s\S]*?prior_session\.status\s*=\s*'completed'/i)
      expect(contract).toMatch(/not\s+prior_step\.correct\s+or\s+prior_step\.uncertain/i)
      expect(contract).toMatch(/prior_step\.same_type_key\s*=\s*v_question\.same_type_key/i)
      expect(contract).toMatch(/elsif\s+not\s*\(v_question\.knowledge_id\s*=\s*any\(v_session\.knowledge_skill_ids\)\)/i)
      for (const identity of ['question_id', 'mother_id', 'source_item_key', 'parent_source_item_key', 'content_fingerprint']) {
        expect(contract, `recovery gate does not exclude prior ${identity}`).toMatch(
          new RegExp(`prior_step\\.${identity}\\s+is\\s+distinct\\s+from\\s+v_question\\.${identity === 'question_id' ? 'id' : identity}`, 'i'),
        )
      }
    }
    expect(issueStep).toMatch(/insert\s+into\s+public\.chem_junior_session_steps[\s\S]*?returning[\s\S]*?into\s+v_step_id/i)
    expect(validateStep).not.toMatch(/return[\s\S]{0,160}(?:stem|options|correct_option|explanation|question_snapshot)/i)
    expect(juniorEvidenceMigration).toMatch(/revoke\s+all\s+on\s+function\s+public\.chem_junior_issue_step[\s\S]*?from\s+public\s*,\s*anon\s*,\s*authenticated\s*,\s*service_role[\s\S]*?grant\s+execute[\s\S]*?to\s+service_role/i)
    expect(juniorEvidenceMigration).toMatch(/revoke\s+all\s+on\s+function\s+public\.chem_junior_validate_issued_step[\s\S]*?from\s+public\s*,\s*anon\s*,\s*authenticated\s*,\s*service_role[\s\S]*?grant\s+execute[\s\S]*?to\s+service_role/i)

    expect(juniorAccess).not.toMatch(/from\(["']chem_junior_session_steps["']\)\.insert\(/i)
    expect(juniorAccess).toContain('supabase.rpc("chem_junior_issue_step"')
    expect(juniorAccess).toContain('supabase.rpc("chem_junior_validate_issued_step"')
    expect(juniorAccess.indexOf('supabase.rpc("chem_junior_issue_step"')).toBeLessThan(
      juniorAccess.indexOf('currentQuestion: juniorQuestionShape(selected)'),
    )
    expect(juniorAccess.indexOf('supabase.rpc("chem_junior_validate_issued_step"')).toBeLessThan(
      juniorAccess.indexOf('currentQuestion: juniorQuestionShape(currentQuestion.data)'),
    )
  })

  it('locks the exact parent plan before junior issue or resume and rejects completed-session drift before display', () => {
    const issueStep = sqlFunction(juniorEvidenceMigration, 'chem_junior_issue_step', 'chem_junior_validate_issued_step')
    const validateStep = sqlFunction(juniorEvidenceMigration, 'chem_junior_validate_issued_step')

    for (const [name, contract] of [['issue', issueStep], ['resume', validateStep]] as const) {
      const sessionLock = contract.indexOf('from public.chem_junior_daily_sessions as session')
      const planLock = contract.indexOf('from public.chem_learning_plans as plan')
      const profileLock = contract.indexOf('from public.chem_students_v2 as student')
      const curriculumLock = contract.indexOf('from public.chem_junior_curriculum_days as curriculum')
      expect(sessionLock, `${name} is missing its session lock`).toBeGreaterThanOrEqual(0)
      expect(planLock, `${name} is missing its parent-plan lock`).toBeGreaterThan(sessionLock)
      expect(profileLock, `${name} locks the profile before the plan`).toBeGreaterThan(planLock)
      expect(curriculumLock, `${name} locks the curriculum before the plan`).toBeGreaterThan(planLock)
      expect(contract.slice(planLock, profileLock)).toMatch(/for\s+share/i)

      for (const exactPlanGate of [
        'plan.id = v_session.plan_day_id',
        'plan.student_id = v_session.student_id',
        'plan.student_id = p_student_id',
        "plan.delivery_mode = 'junior_adaptive'",
        'plan.plan_date = v_session.study_date',
        "plan.plan_date <= (pg_catalog.now() at time zone 'Asia/Shanghai')::date",
        'plan.junior_curriculum_day_id = v_session.curriculum_day_id',
        'plan.skill_ids = v_session.knowledge_skill_ids',
        "plan.mode = 'REVIEW'",
        'plan.question_count = v_session.initial_question_target',
        'plan.round_limit = 1',
      ]) {
        expect(contract, `${name} omits exact plan gate: ${exactPlanGate}`).toContain(exactPlanGate)
      }
    }

    const planSessionGuard = accessSection('function juniorPlanMatchesSessionContract', 'function juniorSourceQuestionIsSafe')
    for (const edgeGate of [
      'plan.id',
      'session.plan_day_id',
      'plan.student_id',
      'session.student_id',
      'plan.plan_date',
      'session.study_date',
      'plan.junior_curriculum_day_id',
      'session.curriculum_day_id',
      'plan.skill_ids',
      'session.knowledge_skill_ids',
      'curriculum.knowledge_skill_ids',
      'plan.question_count',
      'session.initial_question_target',
      'plan.round_limit',
      'session.textbook_version',
      'curriculum.textbook_version',
      'curriculum.release_status',
    ]) {
      expect(planSessionGuard, `Edge plan/session guard omits ${edgeGate}`).toContain(edgeGate)
    }
    expect(planSessionGuard).toContain('plan.delivery_mode === "junior_adaptive"')
    expect(planSessionGuard).toContain('String(plan.mode || "") === "REVIEW"')
    expect(planSessionGuard).toContain('planDate <= shanghaiDate()')
    expect(planSessionGuard).toContain('juniorExactStringArray(plan.skill_ids, session.knowledge_skill_ids)')

    const sessionPayload = accessSection('async function juniorSessionPayload', 'async function studentDashboard')
    const driftGate = sessionPayload.indexOf('if (!juniorPlanMatchesSessionContract')
    const completedReturn = sessionPayload.indexOf('if (session.status === "completed") return')
    expect(driftGate).toBeGreaterThanOrEqual(0)
    expect(completedReturn).toBeGreaterThan(driftGate)
    expect(sessionPayload.slice(driftGate, completedReturn)).toContain('await ensureJuniorTeacherAlert')
    expect(sessionPayload.slice(driftGate, completedReturn)).toContain('throw new RequestError(409')
    expect(sessionPayload).toContain('grade_band,textbook_version,metadata,record_status')
    expect(sessionPayload).toContain('String(profileResult.data.record_status) !== "active"')
  })

  it('enforces the atomic issue RPC as the only database insert path and freezes issued identity fields', () => {
    const guardStart = juniorEvidenceMigration.indexOf('create or replace function app_private.chem_guard_junior_session_step_mutation')
    const guardEnd = juniorEvidenceMigration.indexOf('create or replace function public.chem_junior_issue_step', guardStart)
    const guard = juniorEvidenceMigration.slice(guardStart, guardEnd)
    const issueStep = sqlFunction(juniorEvidenceMigration, 'chem_junior_issue_step', 'chem_junior_validate_issued_step')
    const recordStep = sqlFunction(juniorEvidenceMigration, 'chem_junior_record_step', 'chem_junior_finalize_session')

    expect(guardStart).toBeGreaterThanOrEqual(0)
    expect(guard).toContain("current_setting('app.chem_junior_step_issue', true)")
    expect(guard).toContain("current_setting('app.chem_junior_step_answer', true)")
    expect(guard).toMatch(/tg_op\s*=\s*'INSERT'[\s\S]*?is\s+distinct\s+from\s+'on'[\s\S]*?raise\s+exception/i)
    expect(guard).toMatch(/tg_op\s*=\s*'UPDATE'[\s\S]*?chem_junior_step_answer[\s\S]*?is\s+distinct\s+from\s+'on'[\s\S]*?new\.question_id\s+is\s+distinct\s+from\s+old\.question_id/i)
    for (const immutable of ['mother_id', 'skill_id', 'knowledge_id', 'source_item_key', 'parent_source_item_key', 'content_fingerprint', 'route_kind', 'route_reason', 'question_snapshot']) {
      expect(guard, `guard omits immutable ${immutable}`).toContain(`new.${immutable} is distinct from old.${immutable}`)
    }
    expect(guard).toMatch(/create\s+trigger\s+chem_junior_session_steps_guard_mutation[\s\S]*?before\s+insert\s+or\s+update/i)
    expect(guard).toMatch(/revoke\s+all\s+on\s+function\s+app_private\.chem_guard_junior_session_step_mutation\(\)[\s\S]*?service_role/i)
    expect(issueStep.indexOf("set_config('app.chem_junior_step_issue', 'on', true)")).toBeLessThan(
      issueStep.indexOf('insert into public.chem_junior_session_steps'),
    )
    expect(issueStep.indexOf('insert into public.chem_junior_session_steps')).toBeLessThan(
      issueStep.indexOf("set_config('app.chem_junior_step_issue', 'off', true)"),
    )
    expect(recordStep.indexOf("set_config('app.chem_junior_step_answer', 'on', true)")).toBeLessThan(
      recordStep.indexOf('update public.chem_junior_session_steps as updated'),
    )
    expect(recordStep.indexOf('update public.chem_junior_session_steps as updated')).toBeLessThan(
      recordStep.indexOf("set_config('app.chem_junior_step_answer', 'off', true)"),
    )
  })

  it('treats uncertain prior answers as recoveries and requires at least two recovery originals', () => {
    expect(juniorAccess).toMatch(/step\.correct\s*!==\s*true\s*\|\|\s*step\.uncertain\s*===\s*true/i)
    expect(juniorAccess).toMatch(/route_kind\s*===\s*["']prior_error_recovery["'][\s\S]{0,100}length\s*>=\s*2/i)
    expect(juniorAccess).toContain('juniorInitialPathHasCapacity')
  })

  it('loads the versioned junior evidence migration without coupling to its timestamp suffix', () => {
    expect(migrationEntries.length).toBeGreaterThan(0)
    for (const [path, source] of migrationEntries) {
      expect(path.replaceAll('\\', '/')).toMatch(/\/20260829[^/]*junior[^/]*\.sql$/i)
      expect(source.trim().length).toBeGreaterThan(0)
    }
  })

  it('finalizes each junior session into the unified attempt and answer history with a durable snapshot', () => {
    expect(juniorEvidenceMigration).toMatch(/alter\s+table\s+public\.chem_learning_attempts[\s\S]*?junior_session_id/i)
    expect(juniorEvidenceMigration).toMatch(/unique\s*\(\s*junior_session_id\s*\)|unique\s+index[\s\S]*?junior_session_id/i)

    const finalize = sqlFunction(juniorEvidenceMigration, 'chem_junior_finalize_session', 'chem_junior_issue_step')
    expect(finalize).toMatch(/insert\s+into\s+public\.chem_learning_attempts/i)
    expect(finalize).toMatch(/insert\s+into\s+public\.chem_attempt_answers/i)
    expect(finalize).toMatch(/get\s+diagnostics\s+v_verified_provenance_count\s*=\s*row_count[\s\S]*?into\s+v_current_contract_count/i)
    expect(finalize).toMatch(/chem_junior_session_steps\s+as\s+step[\s\S]*?for\s+update[\s\S]*?chem_questions\s+as\s+question[\s\S]*?for\s+share\s+of\s+question/i)
    expect(finalize.indexOf('v_current_contract_count <> v_total')).toBeLessThan(finalize.indexOf('insert into public.chem_learning_attempts'))
    expect(finalize).toContain('question_snapshot')
    for (const snapshotKey of [
      'questionId',
      'motherId',
      'skillId',
      'knowledgeId',
      'level',
      'stem',
      'options',
      'correctOption',
      'explanation',
      'sameTypeKey',
      'sourceItemKey',
      'parentSourceItemKey',
      'contentFingerprint',
      'routeKind',
    ]) {
      expect(finalize, `missing ${snapshotKey} from the unified answer snapshot`).toContain(`'${snapshotKey}'`)
    }
  })

  it('reauthorizes record and finalize through the exact plan, profile, curriculum, card, and source lock chain', () => {
    const recordStep = sqlFunction(juniorEvidenceMigration, 'chem_junior_record_step', 'chem_junior_finalize_session')
    const finalize = sqlFunction(juniorEvidenceMigration, 'chem_junior_finalize_session', 'chem_junior_issue_step')

    for (const [name, contract, firstWrite] of [
      ['record', recordStep, 'update public.chem_junior_session_steps as updated'],
      ['finalize', finalize, 'insert into public.chem_learning_attempts'],
    ] as const) {
      expect(contract, `missing ${name} RPC`).not.toBe('')
      expect(contract).toMatch(/security\s+definer[\s\S]*?set\s+search_path\s*=\s*''/i)

      const sourceLifecycleLock = contract.indexOf("'chem-source-original-release'")
      const h3LifecycleLock = contract.indexOf("'chem-h3-original-release'")
      const sessionLock = contract.indexOf('from public.chem_junior_daily_sessions as session')
      const planLock = contract.indexOf('from public.chem_learning_plans as plan')
      const profileLock = contract.indexOf('from public.chem_students_v2 as student')
      const curriculumLock = contract.indexOf('from public.chem_junior_curriculum_days as curriculum')
      const cardLock = contract.indexOf('from public.chem_knowledge_cards as card')
      const stepLock = contract.indexOf('from public.chem_junior_session_steps as step', cardLock)
      const questionLock = name === 'record'
        ? contract.indexOf('from public.chem_questions as question', stepLock)
        : contract.indexOf('join public.chem_questions as question', stepLock)
      const provenanceLock = contract.indexOf('from app_private.chem_junior_knowledge_provenance as provenance', questionLock)
      const releaseLock = contract.indexOf('from app_private.chem_question_source_releases as release', provenanceLock)
      const write = contract.indexOf(firstWrite)

      expect(sourceLifecycleLock, `${name} omits the source lifecycle lock`).toBeGreaterThanOrEqual(0)
      expect(h3LifecycleLock, `${name} locks h3 before the source lifecycle`).toBeGreaterThan(sourceLifecycleLock)
      expect(sessionLock, `${name} locks a session before the lifecycle`).toBeGreaterThan(h3LifecycleLock)
      expect(planLock, `${name} locks a plan before its session`).toBeGreaterThan(sessionLock)
      expect(profileLock, `${name} locks a profile before its plan`).toBeGreaterThan(planLock)
      expect(curriculumLock, `${name} locks curriculum before profile`).toBeGreaterThan(profileLock)
      expect(cardLock, `${name} locks cards before curriculum`).toBeGreaterThan(curriculumLock)
      expect(stepLock, `${name} locks steps before cards`).toBeGreaterThan(cardLock)
      expect(questionLock, `${name} locks questions before steps`).toBeGreaterThan(stepLock)
      expect(provenanceLock, `${name} locks provenance before questions`).toBeGreaterThan(questionLock)
      expect(releaseLock, `${name} locks releases before provenance`).toBeGreaterThan(provenanceLock)
      expect(write, `${name} writes before the complete authorization chain`).toBeGreaterThan(releaseLock)

      for (const exactPlanGate of [
        'plan.id = v_session.plan_day_id',
        'plan.student_id = v_session.student_id',
        'plan.student_id = p_student_id',
        "plan.delivery_mode = 'junior_adaptive'",
        'plan.plan_date = v_session.study_date',
        "plan.plan_date <= (pg_catalog.now() at time zone 'Asia/Shanghai')::date",
        'plan.junior_curriculum_day_id = v_session.curriculum_day_id',
        'plan.skill_ids = v_session.knowledge_skill_ids',
        "plan.mode = 'REVIEW'",
        'plan.question_count = v_session.initial_question_target',
        'plan.round_limit = 1',
      ]) {
        expect(contract, `${name} omits exact plan gate: ${exactPlanGate}`).toContain(exactPlanGate)
      }

      expect(contract.slice(profileLock, curriculumLock)).toMatch(/student\.grade_band\s*=\s*'初三'[\s\S]*?student\.record_status\s*=\s*'active'[\s\S]*?student\.textbook_version\s*=\s*v_session\.textbook_version[\s\S]*?for\s+share/i)
      expect(contract.slice(curriculumLock, cardLock)).toMatch(/curriculum\.id\s*=\s*v_session\.curriculum_day_id[\s\S]*?curriculum\.textbook_version\s*=\s*v_session\.textbook_version[\s\S]*?curriculum\.release_status\s*=\s*'ready'[\s\S]*?curriculum\.knowledge_skill_ids\s*=\s*v_session\.knowledge_skill_ids[\s\S]*?for\s+share/i)
      expect(contract).toMatch(/unnest\(v_session\.knowledge_skill_ids\)[\s\S]*?union\s+all[\s\S]*?select\s+existing\.knowledge_id[\s\S]*?chem_junior_session_steps/i)
      expect(contract).toMatch(/chem_knowledge_cards[\s\S]*?review_status\s*=\s*'approved'[\s\S]*?for\s+share\s+of\s+card/i)
      expect(contract).toMatch(/having\s+count\(card\.id\)\s*=\s*1/i)
      expect(contract).toMatch(/question\.content_fingerprint[\s\S]*?chem_h3_content_fingerprint/i)
      expect(contract).toMatch(/question\.question_revision_token[\s\S]*?chem_junior_native_revision_sha256/i)
      if (name === 'record') {
        expect(contract).toMatch(/v_snapshot\s*:=\s*pg_catalog\.jsonb_build_object[\s\S]*?v_step\.question_snapshot\s+is\s+distinct\s+from\s+v_snapshot/i)
      } else {
        expect(contract).toMatch(/step\.question_snapshot\s*=\s*pg_catalog\.jsonb_build_object/i)
      }
      expect(contract).toContain("release.revision_contract = 'v3_junior_native_text'")
      expect(contract).toContain('release.verification_manifest_sha256 = release.manifest_sha256')
    }

    const currentContractGate = finalize.indexOf('v_current_contract_count <> v_total')
    const attemptLookup = finalize.indexOf('from public.chem_learning_attempts as attempt')
    const idempotentReturn = finalize.indexOf('return query select true, v_total, v_correct;')
    const firstAttemptWrite = finalize.indexOf('insert into public.chem_learning_attempts')
    expect(attemptLookup).toBeGreaterThan(currentContractGate)
    expect(idempotentReturn).toBeGreaterThan(attemptLookup)
    expect(firstAttemptWrite).toBeGreaterThan(idempotentReturn)
  })

  it('binds verified knowledge provenance to both textbook version and a source release', () => {
    expect(effectiveJuniorSql).toMatch(/primary\s+key\s*\(\s*textbook_version\s*,\s*knowledge_id\s*\)/i)
    expect(juniorEvidenceMigration).toMatch(/source_release_id[\s\S]{0,160}(?:set\s+not\s+null|not\s+null)/i)

    const provenanceRpc = sqlFunction(juniorEvidenceMigration, 'chem_junior_verified_provenance_rows', 'chem_junior_record_step')
    for (const field of ['knowledge_id', 'textbook_version', 'source_release_id', 'verification_status', 'source_release_ready']) {
      expect(provenanceRpc).toContain(field)
    }
    expect((juniorAccess.match(/textbook_version/g) || []).length).toBeGreaterThanOrEqual(2)
    expect((juniorAccess.match(/source_release_id/g) || []).length).toBeGreaterThanOrEqual(2)
  })

  it('does not promote verified skill state from a single recorded step', () => {
    const recordStep = sqlFunction(juniorEvidenceMigration, 'chem_junior_record_step', 'chem_junior_finalize_session')
    expect(recordStep).not.toBe('')
    expect(recordStep).not.toMatch(/\bverified_level\b[\s\S]{0,240}\bv_step\.level\b/i)
    expect(recordStep).not.toMatch(/\bstability\b[\s\S]{0,180}'verified'/i)
    expect(recordStep).toMatch(/update\s+public\.chem_junior_session_steps\s+as\s+updated[\s\S]*?returning\s+updated\.id\s*,\s*updated\.question_id\s*,\s*updated\.selected_option/i)
    expect(recordStep).toMatch(/from\s+app_private\.chem_junior_knowledge_provenance[\s\S]*?from\s+app_private\.chem_question_source_releases/i)
    for (const currentGate of [
      /v_question\.review_status\s+is\s+distinct\s+from\s+'approved'/i,
      /v_question\.scope_status\s+is\s+distinct\s+from\s+'IN'/i,
      /v_question\.usable_for_review\s+is\s+distinct\s+from\s+true/i,
      /v_question\.render_mode\s+is\s+distinct\s+from\s+'native'/i,
      /provenance\.source_release_id\s*=\s*v_question\.source_release_id/i,
      /v_step\.question_snapshot\s*->>\s*'revisionToken'/i,
    ]) {
      expect(recordStep).toMatch(currentGate)
    }
  })

  it('backs selector uniqueness with one junior plan per day and five session identity constraints', () => {
    expect(juniorEvidenceMigration).toMatch(/create\s+unique\s+index[\s\S]{0,240}on\s+public\.chem_learning_plans\s*\(\s*student_id\s*,\s*plan_date\s*\)[\s\S]{0,160}delivery_mode\s*=\s*'junior_adaptive'/i)
    expect(juniorEvidenceMigration).toMatch(/create\s+unique\s+index[\s\S]{0,240}on\s+public\.chem_junior_daily_sessions\s*\(\s*student_id\s*\)[\s\S]{0,160}status\s*=\s*'active'/i)
    expect(juniorAccess).toMatch(/existingActive[\s\S]*?status["']\s*,\s*["']active[\s\S]*?RequestError\(409/i)

    for (const identity of ['question_id', 'mother_id', 'source_item_key', 'parent_source_item_key', 'content_fingerprint']) {
      expect(effectiveJuniorSql, `missing session-level uniqueness for ${identity}`).toMatch(
        new RegExp(`(?:unique\\s*\\(\\s*session_id\\s*,\\s*${identity}\\s*\\)|create\\s+unique\\s+index[^;]*?\\(\\s*session_id\\s*,\\s*${identity}\\s*\\))`, 'i'),
      )
    }
  })

  it('persists actionable blocked metadata and refuses non-native junior questions', () => {
    expect(effectiveJuniorSql).toContain('blocked_reason_code')
    expect(effectiveJuniorSql).toContain('blocked_reason_detail')
    expect(effectiveJuniorSql).toContain('blocked_at')
    expect(effectiveJuniorSql).toContain('chem_junior_daily_sessions_blocked_metadata_check')

    expect(juniorAccess).toContain('blocked_reason_code')
    expect(juniorAccess).toContain('blocked_reason_detail')
    expect(juniorAccess).toContain('blocked_at')
    const runtimeNativeGate = /String\(row\.render_mode\s*\|\|\s*""\)\s*(?:===|!==)\s*"native"/i.test(juniorAccess)
    const queryNativeGate = /\.eq\("render_mode",\s*"native"\)/i.test(juniorAccess)
    expect(runtimeNativeGate || queryNativeGate).toBe(true)
    const sourceSafety = accessSection('function juniorSourceQuestionIsSafe', 'function juniorNativeQuestionIsSafe')
    expect(sourceSafety).toContain('row.explanation')
    expect(sourceSafety).toContain('row.scaffold')
    for (const label of ['来源', '出处', '选自', '题源', '中考', '模拟', '真题']) {
      expect(sourceSafety).toContain(label)
    }
  })

  it('owns a service-only junior release lifecycle without opening the private ledgers', () => {
    const lifecycleFunctions = [
      ['chem_prepare_junior_source_release', 'chem_stage_junior_source_release_item'],
      ['chem_stage_junior_source_release_item', 'chem_stage_junior_source_release_provenance'],
      ['chem_stage_junior_source_release_provenance', 'chem_verify_junior_source_release_provenance'],
      ['chem_verify_junior_source_release_provenance', 'chem_preflight_junior_source_release'],
      ['chem_preflight_junior_source_release', 'chem_mark_junior_source_release_full_visual_verified'],
      ['chem_mark_junior_source_release_full_visual_verified', 'chem_activate_junior_source_release'],
      ['chem_activate_junior_source_release', 'chem_junior_record_step'],
    ] as const

    for (const [name, nextName] of lifecycleFunctions) {
      const contract = sqlFunction(juniorEvidenceMigration, name, nextName)
      expect(contract, `missing lifecycle RPC ${name}`).not.toBe('')
      expect(contract).toMatch(/security\s+definer[\s\S]*?set\s+search_path\s*=\s*''/i)
      expect(juniorEvidenceMigration).toMatch(
        new RegExp(`revoke\\s+all\\s+on\\s+function\\s+public\\.${name}[\\s\\S]*?from\\s+public\\s*,\\s*anon\\s*,\\s*authenticated\\s*,\\s*service_role[\\s\\S]*?grant\\s+execute\\s+on\\s+function\\s+public\\.${name}[\\s\\S]*?to\\s+service_role`, 'i'),
      )
    }

    expect(juniorEvidenceMigration).toMatch(/alter\s+table\s+app_private\.chem_junior_source_release_specs\s+enable\s+row\s+level\s+security/i)
    expect(juniorEvidenceMigration).toMatch(/alter\s+table\s+app_private\.chem_junior_source_release_provenance\s+enable\s+row\s+level\s+security/i)
    expect(juniorEvidenceMigration).toMatch(/revoke\s+all\s+on\s+table\s+app_private\.chem_junior_source_release_(?:specs|provenance)[\s\S]*?service_role/i)
    expect(juniorEvidenceMigration).toContain('app.chem_junior_release_lifecycle')
    expect(juniorEvidenceMigration).toContain('junior source releases may change only through the dedicated server lifecycle')

    const prepare = sqlFunction(
      juniorEvidenceMigration,
      'chem_prepare_junior_source_release',
      'chem_stage_junior_source_release_item',
    )
    expect(prepare).toMatch(/cardinality\(p_knowledge_ids\)[\s\S]{0,80}between\s+3\s+and\s+200/i)
    expect(prepare).toMatch(/array_agg\(route\.knowledge_id\s+order\s+by\s+route\.knowledge_id\)[\s\S]*?select\s+distinct\s+btrim\(knowledge_id\)/i)
    expect(prepare).toMatch(/coalesce\(cardinality\(v_knowledge_ids\),\s*0\)\s*<>\s*cardinality\(p_knowledge_ids\)/i)
    expect(prepare).toContain('p_expected_question_count < 7 * cardinality(v_knowledge_ids)')
  })

  it('stages only immutable native-text originals with server-computed zero-asset digests', () => {
    const stage = sqlFunction(
      juniorEvidenceMigration,
      'chem_stage_junior_source_release_item',
      'chem_stage_junior_source_release_provenance',
    )
    for (const forcedValue of [
      "'初三'",
      "'approved'",
      "'IN'",
      "'licensed_local'",
      "'[]'::jsonb",
      "'native'",
    ]) {
      expect(stage).toContain(forcedValue)
    }
    expect(stage).toMatch(/usable_for_class_quiz,[\s\S]*?usable_for_review,[\s\S]*?usable_for_exam_sprint,[\s\S]*?usable_for_demo[\s\S]*?false,[\s\S]*?false,[\s\S]*?false,[\s\S]*?false/i)
    expect(stage).toContain('app_private.chem_h3_content_fingerprint')
    expect(stage).toContain('app_private.chem_junior_native_revision_sha256')
    expect(stage).toContain('app_private.chem_junior_native_release_item_sha256')
    expect(stage).toContain('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
    expect(stage).not.toContain('insert into app_private.chem_question_assets')

    const digestStart = juniorEvidenceMigration.indexOf('create or replace function app_private.chem_junior_native_revision_sha256')
    const digestEnd = juniorEvidenceMigration.indexOf('create or replace function app_private.chem_guard_junior_release_lifecycle', digestStart)
    const digests = juniorEvidenceMigration.slice(digestStart, digestEnd)
    for (const boundField of [
      'textbook_version',
      'knowledge_id',
      'skill_id',
      'same_type_key',
      'parent_source_item_key',
      'source_item_key',
      'content_fingerprint',
      'explanation',
      'scaffold',
    ]) {
      expect(digests, `native digest omits ${boundField}`).toContain(`p_question.${boundField}`)
    }
  })

  it('preflights the exact manifest, complete textbook routes, and 5+2 level capacity before marking', () => {
    const assertionStart = juniorEvidenceMigration.indexOf('create or replace function app_private.chem_assert_junior_source_release')
    const assertionEnd = juniorEvidenceMigration.indexOf('create or replace function public.chem_preflight_junior_source_release', assertionStart)
    const assertion = juniorEvidenceMigration.slice(assertionStart, assertionEnd)
    expect(assertion).toMatch(/for\s+update\s+of\s+release_row\s*,\s*spec/i)
    expect(assertion).toMatch(/for\s+update[\s\S]*?chem_question_source_release_items[\s\S]*?for\s+update[\s\S]*?chem_junior_source_release_provenance[\s\S]*?for\s+update/i)
    expect(assertion).toContain('junior native-text release must contain zero private assets')
    expect(assertion).toContain('foundation_count < 5 or higher_count < 2')
    expect(assertion).toMatch(/count\(distinct\s+question\.knowledge_id\)[\s\S]{0,180}<>\s*cardinality\(v_knowledge_ids\)/i)
    expect(assertion).toMatch(/string_agg\(item\.item_sha256,\s*E'\\n'\s+order\s+by\s+item\.question_id\)/i)
    expect(assertion).toContain('v_computed_manifest is distinct from p_manifest_sha256')
    expect(assertion).toContain('provenance.verification_status <> \'verified\'')
    expect(assertion).toContain("provenance.verification_actor is distinct from 'codex-source-provenance-qa'")
    expect(assertion).toContain('cardinality(v_knowledge_ids)')
    expect(assertion).toContain('foundation_count < 5 or higher_count < 2')
    expect(assertion).toContain('every junior original requires a five-identity-distinct same-type recovery partner')
    expect(assertion).toMatch(/chem_junior_curriculum_days[\s\S]*?release_status\s*=\s*'ready'[\s\S]*?requested\.knowledge_id\s*=\s*any\(v_knowledge_ids\)/i)
    expect(assertion).toContain('lock table public.chem_junior_curriculum_days in share mode')

    const mark = sqlFunction(
      juniorEvidenceMigration,
      'chem_mark_junior_source_release_full_visual_verified',
      'chem_activate_junior_source_release',
    )
    expect(mark.indexOf('app_private.chem_assert_junior_source_release')).toBeLessThan(mark.indexOf("verification_status = 'full_visual_verified'"))
    expect(mark).toContain("p_verification_actor is distinct from 'codex-full-visual-qa'")
  })

  it('atomically swaps only the matching junior textbook and preserves high-school activation contracts', () => {
    const activate = sqlFunction(juniorEvidenceMigration, 'chem_activate_junior_source_release', 'chem_junior_record_step')
    expect(activate).toMatch(/chem_assert_junior_source_release\([\s\S]*?true[\s\S]*?for\s+update\s+of\s+release_row\s*,\s*spec/i)
    expect(activate).toContain("old_release.grade_band = '初三'")
    expect(activate).toContain('old_release.textbook_version = v_textbook_version')
    expect(activate).toContain("old_release.status = 'active'")
    expect(activate).toContain("status = 'retired'")
    expect(activate).toContain('insert into app_private.chem_junior_knowledge_provenance')
    expect(activate).toContain('on conflict (textbook_version, knowledge_id) do update')
    expect(activate).toContain('question.source_release_id is distinct from p_release_id')
    expect(activate).toContain('app.chem_release_activation')
    expect(activate).toMatch(/chem_junior_daily_sessions[\s\S]*?status\s*=\s*'active'[\s\S]*?for\s+update[\s\S]*?chem_question_source_releases[\s\S]*?status\s*=\s*'active'[\s\S]*?for\s+update/i)
    expect(activate).not.toMatch(/old_release\.grade_band\s+in\s*\(\s*'高一'/i)

    expect(juniorEvidenceMigration).toMatch(/chem_question_source_releases_one_active_grade_uidx[\s\S]{0,180}grade_band\s+in\s*\(\s*'高一'\s*,\s*'高二'\s*,\s*'高三'\s*\)/i)
    expect(juniorEvidenceMigration).toMatch(/chem_question_source_releases_one_active_junior_textbook_uidx[\s\S]{0,180}textbook_version[\s\S]{0,180}grade_band\s*=\s*'初三'/i)
  })

  it('freezes every late-added junior identity after activation or student use', () => {
    const triggerStart = juniorEvidenceMigration.indexOf('create trigger chem_questions_guard_source_content_update')
    const triggerEnd = juniorEvidenceMigration.indexOf('create or replace function app_private.chem_junior_native_revision_sha256', triggerStart)
    const trigger = juniorEvidenceMigration.slice(triggerStart, triggerEnd)
    for (const identity of ['textbook_version', 'knowledge_id', 'same_type_key', 'parent_source_item_key']) {
      expect(trigger, `source content trigger omits ${identity}`).toContain(identity)
    }
    expect(trigger).toContain('app_private.chem_guard_source_question_content_mutation()')
  })
})
