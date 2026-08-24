import { describe, expect, it } from 'vitest'

import migration from '../../supabase/migrations/20260823002000_review_daily_cap_and_next_day_personalization.sql?raw'
import suffixRebudget from '../../supabase/migrations/20260823014500_rebudget_unstarted_review_suffix.sql?raw'

function section(start: string, end: string) {
  const startIndex = migration.indexOf(start)
  const endIndex = migration.indexOf(end, startIndex)
  expect(startIndex).toBeGreaterThanOrEqual(0)
  expect(endIndex).toBeGreaterThan(startIndex)
  return migration.slice(startIndex, endIndex)
}

describe('formal REVIEW daily personalization database contract', () => {
  it('ships the exact 130-row reviewed human concept catalog', () => {
    const catalogInsert = section(
      'insert into app_private.chem_review_concept_catalog',
      'on conflict (concept_key)',
    )
    const rows = [...catalogInsert.matchAll(
      /\('(高一|高二|高三)','(H[123]_[A-Z0-9_]+)','(H[123]_[A-Z0-9_]+__C0[1-5])',([1-5]),'([^']+)'\)/g,
    )].map((match) => ({
      grade: match[1], skill: match[2], concept: match[3],
      order: Number(match[4]), title: match[5],
    }))

    expect(rows).toHaveLength(130)
    expect(rows.filter((row) => row.grade === '高一')).toHaveLength(35)
    expect(rows.filter((row) => row.grade === '高二')).toHaveLength(40)
    expect(rows.filter((row) => row.grade === '高三')).toHaveLength(55)
    expect(new Set(rows.map((row) => row.concept)).size).toBe(130)
    expect(new Set(rows.map((row) => `${row.grade}:${row.skill}:${row.order}`)).size).toBe(130)
    expect(rows.every((row) => row.concept === `${row.skill}__C0${row.order}`)).toBe(true)
    expect(rows.every((row) => row.title !== row.concept && !/^H[123]_/.test(row.title))).toBe(true)

    expect(catalogInsert).toContain("'H2_THERMO__C01',1,'焓变正负'")
    expect(catalogInsert).toContain("'H2_RATE__C01',1,'速率表示'")
    expect(catalogInsert).toContain("'H3_AQ__C01',1,'弱酸电离与微粒分布'")
    expect(catalogInsert).toContain("'H3_ELECTRO__C04',4,'离子交换膜与离子迁移'")
  })

  it('never derives a student-facing title from source_info', () => {
    const personalizer = section(
      'create or replace function public.chem_personalize_next_review_plan',
      'revoke all on function public.chem_personalize_next_review_plan',
    )
    expect(personalizer).toContain('join app_private.chem_review_concept_catalog catalog')
    expect(personalizer).toContain('catalog.concept_label')
    expect(personalizer).not.toContain("source_info->>'conceptLabel'")
    expect(migration).toContain('authoritative 130-concept REVIEW catalog failed closed')
    expect(migration).toContain('catalog.concept_label <> plan.knowledge_summaries[target.position]')
  })

  it('uses one 1..8-question package and cannot silently drop unresolved concepts 6..8', () => {
    expect(migration).toContain('chem_learning_plans_review_daily_question_cap_check')
    expect(migration).toContain('chem_learning_plans_one_review_per_student_day_uidx')
    expect(migration).toContain('v_question_count := greatest(v_question_count, v_raw_unresolved_count)')
    expect(migration).toContain('v_raw_unresolved_count > 8')
    expect(migration).toContain('cardinality(plan.target_concept_keys) <> plan.question_count')
    expect(migration).toContain('cardinality(plan.skill_ids) not between 1 and plan.question_count')
    expect(migration).toContain('count(distinct listed.skill_id)')
    expect(migration).toContain('round_limit = 1')
  })

  it('uses persisted completion evidence and mutates only the immediate unstarted suffix', () => {
    const personalizer = section(
      'create or replace function public.chem_personalize_next_review_plan',
      'revoke all on function public.chem_personalize_next_review_plan',
    )
    expect(personalizer).toContain('select plan.plan_date, plan.skill_ids, evidence.completed_at')
    expect(personalizer).toContain('v_next_date := v_completed_plan_date + 1')
    expect(personalizer.match(/p_completed_at/g)).toHaveLength(1)
    expect(personalizer).toContain("attempt.plan_day_id = v_next_plan.id")
    expect(personalizer).toContain('from app_private.chem_question_answer_locks answer_lock')
    expect(personalizer).toContain('answer_lock.plan_day_id = v_next_plan.id')
    expect(personalizer).toContain("set status = 'not_needed'")
    expect(personalizer).toContain("to_regprocedure(\n    'app_private.chem_rebudget_unstarted_review_suffix(uuid,uuid,text[])'")
    expect(personalizer).toContain('select app_private.chem_rebudget_unstarted_review_suffix($1,$2,$3)')
    expect(personalizer).toContain('v_rebudget_result jsonb')
    expect(personalizer).toContain("(v_rebudget_result->>'ok')::boolean")
    expect(personalizer).toContain("v_rebudget_result->>'reasonCode'")
    expect(personalizer).toContain("v_rebudget_result->>'detail'")
    expect(personalizer).toContain("v_rebudget_result->>'conflictPlanDate'")
    expect(personalizer).toContain("set status = 'blocked'")
    expect(personalizer).toContain("'chem-review-suffix:' || p_student_id::text")
    expect(personalizer).not.toMatch(/update\s+public\.chem_learning_plans/i)
    expect(suffixRebudget).toContain('app_private.chem_rebudget_unstarted_review_suffix(')
    expect(suffixRebudget).toContain('returns jsonb')
    expect(suffixRebudget).toContain("'ok', true")
    expect(suffixRebudget).toContain("'ok', false")
  })

  it('excludes every historical source identity and stays in learner curriculum scope', () => {
    const personalizer = section(
      'create or replace function public.chem_personalize_next_review_plan',
      'revoke all on function public.chem_personalize_next_review_plan',
    )
    expect(personalizer).toContain('used.question_id = question.id')
    expect(personalizer).toContain('used.mother_id = question.mother_id')
    expect(personalizer).toContain('used.source_item_key = question.source_item_key')
    expect(personalizer).toContain('used.content_fingerprint = question.content_fingerprint')
    expect(personalizer).toContain('from app_private.chem_question_answer_locks answer_lock')
    expect(personalizer).toContain('locked_question.content_fingerprint')
    expect(personalizer).toContain("release.status = 'active'")
    expect(personalizer).toContain("release.verification_status = 'full_visual_verified'")
    expect(personalizer).toContain("v_student_metadata->'confirmedLearnedSkillIds'")
    expect(personalizer).toContain("v_grade_band = '高二'")
    expect(personalizer).toContain("v_grade_band = '高三'")
    expect(personalizer).toContain('question.skill_id = any(v_allowed_skills)')
    expect(personalizer).toContain('next REVIEW plan leaves the learner confirmed curriculum scope')
  })

  it('funds only difficulty-compatible fresh originals', () => {
    const personalizer = section(
      'create or replace function public.chem_personalize_next_review_plan',
      'revoke all on function public.chem_personalize_next_review_plan',
    )
    expect(personalizer).toContain('latest_concept_evidence as')
    expect(personalizer).toContain('and question.level > evidence.question_level')
    expect(personalizer).toContain('and question.level <= evidence.question_level')
    expect(personalizer).toContain('evidence.correct')
    expect(personalizer).toContain('not evidence.uncertain')
    expect(personalizer).toContain('not evidence.correct or evidence.uncertain')
    expect(migration).toContain('create temporary table _latest_review_concept_state')
    expect(migration).toContain("answer.question_snapshot->>'level'")
  })

  it('records retryable failures and exposes only server-only queue RPCs', () => {
    expect(migration).toContain('app_private.review_plan_personalization_jobs')
    expect(migration).toContain("status in ('pending','blocked','succeeded','not_needed')")
    expect(migration).toContain('create or replace function public.chem_enqueue_review_personalization')
    expect(migration).toContain('create or replace function public.chem_retry_pending_review_personalization')
    expect(migration).toContain('create or replace function public.chem_reconcile_missing_review_personalization_jobs')
    expect(migration).toContain('create or replace function public.chem_review_personalization_job_rows')
    expect(migration).toContain('for update skip locked')
    expect(migration).toContain("job.updated_at <= pg_catalog.now() - interval '5 minutes'")
    expect(migration).toContain('job.attempt_count < 5')
    expect(migration).toContain('having count(distinct attempt.sequence) >= completed_plan.round_limit')
    expect(migration).toContain('on conflict (completed_plan_id) do nothing')
    expect(migration).toContain("completed_plan.plan_date >= date '2026-08-23'")
    expect(migration).toContain("completed_plan.plan_date < date '2026-09-29'")
    expect(migration).toContain('next_attempt.plan_day_id = next_plan.id')
    expect(migration).toContain('next_lock.plan_day_id = next_plan.id')
    expect(migration).toContain('grant execute on function public.chem_retry_pending_review_personalization(integer)')
    expect(migration).toContain('grant execute on function public.chem_reconcile_missing_review_personalization_jobs()')
    expect(migration).toContain('to service_role')
    expect(migration).toContain('from public, anon, authenticated')
  })

  it('does not write attempts, answers, or independent quiz sessions', () => {
    expect(migration).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.chem_learning_attempts/i)
    expect(migration).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.chem_attempt_answers/i)
    expect(migration).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.quiz_sessions/i)
  })

  it('treats an answer lock as started throughout migration and suffix rebudget', () => {
    expect(migration).toContain('lock table app_private.chem_question_answer_locks in share mode')
    expect(migration).toContain('where answer_lock.plan_day_id = plan.id')
    expect(suffixRebudget).not.toContain('lock table app_private.chem_question_answer_locks in share mode')
    expect(suffixRebudget).toContain("'conflictPlanDate', v_conflict_date")
    expect(suffixRebudget).toContain("'reasonCode', 'suffix_contains_answer_lock'")
    expect(migration).toContain("'suffix_contains_answer_lock'")
  })

  it('closes the funded calendar cleanly after the 2026-09-29 package', () => {
    expect(migration).toContain("if v_next_date > date '2026-09-29' then")
    expect(migration).toContain("'not_needed', 0, null, pg_catalog.now()")
    expect(migration).toContain("when v_plan_date + 1 > date '2026-09-29' then 'not_needed'")
  })

  it('provides the teacher server-only catalog row shape', () => {
    const rpc = section(
      'create or replace function public.chem_review_concept_catalog_rows()',
      'revoke all on function public.chem_review_concept_catalog_rows()',
    )
    expect(rpc).toContain('concept_title text')
    expect(rpc).toContain('sequence_no integer')
    expect(rpc).toContain('catalog.concept_label as concept_title')
    expect(migration).toContain('grant execute on function public.chem_review_concept_catalog_rows()')
  })

  it('counts teacher capacity usage only against the current verified source pool', () => {
    const rpc = section(
      'create or replace function public.chem_review_active_source_usage_counts(',
      'revoke all on function public.chem_review_active_source_usage_counts(uuid[])',
    )
    expect(rpc).toContain('student_id uuid')
    expect(rpc).toContain('concept_key text')
    expect(rpc).toContain('used_count integer')
    expect(rpc).toContain("release.status = 'active'")
    expect(rpc).toContain("release.verification_status = 'full_visual_verified'")
    expect(rpc).toContain("question.review_status = 'approved'")
    expect(rpc).toContain("question.scope_status = 'IN'")
    expect(rpc).toContain('question.usable_for_review')
    expect(rpc).toContain("question.source_kind = 'licensed_local'")
    expect(rpc).toContain("question.render_mode = 'image_primary'")
    expect(rpc).toContain('used.question_id = pool.question_id')
    expect(rpc).toContain('used.mother_id = pool.mother_id')
    expect(rpc).toContain('used.source_item_key = pool.source_item_key')
    expect(rpc).toContain('used.content_fingerprint = pool.content_fingerprint')
    expect(rpc).toContain('count(distinct pool.question_id)::integer as used_count')
    expect(rpc).toContain('security definer')
    expect(migration).toContain('grant execute on function public.chem_review_active_source_usage_counts(uuid[])')
    expect(migration).toContain('from public, anon, authenticated')
  })
})
