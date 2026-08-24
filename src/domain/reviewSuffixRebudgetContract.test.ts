import { describe, expect, it } from 'vitest'

import candidate from '../../supabase/migrations/20260823014500_rebudget_unstarted_review_suffix.sql?raw'

describe('runtime REVIEW suffix re-budget contract', () => {
  it('uses a private, non-conflicting function and documents the caller transaction contract', () => {
    expect(candidate).toContain('app_private.chem_rebudget_unstarted_review_suffix')
    expect(candidate).not.toContain('create or replace function public.chem_personalize_next_review_plan')
    expect(candidate).toContain('Do NOT update tomorrow\'s plan directly')
    expect(candidate).toContain('On {ok:false}, return false without raising')
    expect(candidate).toContain('must not replace the')
    expect(candidate).toContain('three funded arrays')
  })

  it('is safe for multiple pooled RPC calls or retries in one transaction', () => {
    expect(candidate).toContain('same pooled connection')
    expect(candidate).toContain('drop table if exists')
    for (const table of [
      '_suffix_plan_arrays',
      '_suffix_assignment',
      '_suffix_capacity',
      '_suffix_fresh_original',
      '_suffix_raw_fresh_original',
      '_suffix_latest_concept_state',
      '_suffix_required_first_pass',
      '_suffix_used_identity',
      '_suffix_course_order',
      '_suffix_plans',
    ]) expect(candidate).toContain(`pg_temp.${table}`)
  })

  it('locks and rejects any started or incomplete suffix before mutating plans', () => {
    expect(candidate).toContain('pg_advisory_xact_lock')
    expect(candidate).toContain('order by plan.plan_date, plan.id')
    expect(candidate).toContain('for update')
    expect(candidate).toContain('suffix_contains_started_plan')
    expect(candidate).toContain('suffix_plan_calendar_incomplete')
    expect(candidate).toContain("between v_anchor_date and date '2026-09-29'")
    expect(candidate).toContain('not exists (')
    expect(candidate).toContain('where attempt.plan_day_id = plan.id')
  })

  it('treats answer locks as issued evidence without blocking unrelated learners', () => {
    expect(candidate).not.toContain('lock table app_private.chem_question_answer_locks in share mode')
    expect(candidate).toContain("'chem-review-suffix:' || p_student_id::text")
    expect(candidate).toContain('from app_private.chem_question_answer_locks answer_lock')
    expect(candidate).toContain('answer_lock.question_id')
    expect(candidate).toContain('question.mother_id')
    expect(candidate).toContain('question.source_item_key')
    expect(candidate).toContain('question.content_fingerprint')
    expect(candidate).toContain('suffix_contains_answer_lock')
    expect(candidate).toContain("'conflictPlanDate', v_conflict_date")
    expect(candidate).toContain('for share')
    expect(candidate).toContain('Re-check immediately before the write')
    expect(candidate).toContain('answer_lock.plan_day_id = plan.id')
    expect(candidate).toContain('suffix_update_row_count_mismatch')
    expect(candidate).toContain('chem_lock_question_answer takes the same per-student advisory')
  })

  it('takes the learner advisory before any plan row FOR UPDATE', () => {
    const advisory = candidate.indexOf('pg_advisory_xact_lock')
    const firstPlanLock = candidate.indexOf('for update')
    expect(advisory).toBeGreaterThanOrEqual(0)
    expect(firstPlanLock).toBeGreaterThan(advisory)
  })

  it('hard-filters scope by reviewed grade spines and never learns scope from history', () => {
    expect(candidate).toContain("student.metadata->'confirmedLearnedSkillIds'")
    expect(candidate).toContain("or question.skill_id = any(v_confirmed_h1_skills)")
    expect(candidate).toContain('anchor_concept_outside_learned_scope')
    expect(candidate).toContain('not (catalog.skill_id = any(v_confirmed_h1_skills))')
    expect(candidate).toContain("('高二','H2_THERMO',1)")
    expect(candidate).toContain("('高二','H2_ELECTRO',8)")
    expect(candidate).toContain('Jiangsu Selective Compulsory 1')
    expect(candidate).toContain("('高三','H3_ION_REDOX',1)")
    expect(candidate).toContain("('高三','H3_STOICH',2)")
    expect(candidate).toContain('high-frequency, error-prone foundations')
    expect(candidate).not.toContain('chem_student_skill_state')
    expect(candidate).not.toContain('prior_unresolved')
    expect(candidate).not.toContain('learned_alternative')
  })

  it('excludes four used identities and debits each retained/future concept visit', () => {
    expect(candidate).toContain("answer.question_snapshot->>'sourceItemKey'")
    expect(candidate).toContain("answer.question_snapshot->>'contentFingerprint'")
    expect(candidate).toContain('used.question_id = question.id')
    expect(candidate).toContain('used.mother_id = question.mother_id')
    expect(candidate).toContain('used.source_item_key = question.source_item_key')
    expect(candidate).toContain('used.content_fingerprint = question.content_fingerprint')
    expect(candidate).toContain('remaining_questions = capacity.remaining_questions - 1')
    expect(candidate).toContain('reserved_questions = capacity.reserved_questions + 1')
    expect(candidate).toContain('v_required_questions > v_fresh_questions')
  })

  it('re-funds later daily counts from current compatible capacity instead of stale baseline counts', () => {
    expect(candidate).toContain('v_remaining_plan_count := v_expected_plan_count - 1')
    expect(candidate).toContain('v_fresh_questions < v_anchor_question_count + v_remaining_plan_count')
    expect(candidate).toContain('suffix_minimum_daily_capacity_shortage')
    expect(candidate).toContain('v_fresh_questions - v_anchor_question_count')
    expect(candidate).toContain('v_remaining_plan_count * 8')
    expect(candidate).toContain('v_base_daily_count := v_remaining_question_budget / v_remaining_plan_count')
    expect(candidate).toContain('v_extra_daily_days := v_remaining_question_budget % v_remaining_plan_count')
    expect(candidate).toContain("p_student_id::text || ':' || v_anchor_date::text")
    expect(candidate).toContain('where plan.plan_date > v_anchor_date')
    expect(candidate).toContain('counts differ')
    expect(candidate).toContain('anchor grows from 7 to 8')
  })

  it('hard-covers every still-unseen in-scope concept in the remaining suffix', () => {
    expect(candidate).toContain('create temporary table _suffix_required_first_pass')
    expect(candidate).toContain("attempt.mode = 'REVIEW'")
    expect(candidate).toContain("answer.question_snapshot->>'conceptKey'")
    expect(candidate).toContain('Locks alone do not count as first-pass mastery')
    expect(candidate).toContain("v_grade_band <> '高一'")
    expect(candidate).toContain('catalog.skill_id = any(v_confirmed_h1_skills)')
    expect(candidate).toContain('v_unfunded_first_pass_concepts > 0')
    expect(candidate).toContain('v_required_questions - v_anchor_question_count')
    expect(candidate).toContain('v_uncovered_first_pass_concepts')
    expect(candidate).toContain("v_reason := 'first_pass_concept_coverage_shortage'")
    expect(candidate).toContain('from _suffix_assignment covered')
    expect(candidate).toContain('where assignment.concept_key = required.concept_key')
  })

  it('treats difficulty direction as capacity and distinguishes exhausted from no-upgrade', () => {
    expect(candidate).toContain('create temporary table _suffix_latest_concept_state')
    expect(candidate).toContain('create temporary table _suffix_raw_fresh_original')
    expect(candidate).toContain('latest.correct and not latest.uncertain')
    expect(candidate).toContain('raw.level > latest.question_level')
    expect(candidate).toContain('(not latest.correct or latest.uncertain)')
    expect(candidate).toContain('raw.level <= latest.question_level')
    expect(candidate).toContain("then 'source_original_exhausted'")
    expect(candidate).toContain("then 'no_upgrade_original'")
    expect(candidate).toContain("else 'no_non_escalating_original'")
  })

  it('funds only fully visual-verified originals with both required images', () => {
    expect(candidate).toContain("release.status = 'active'")
    expect(candidate).toContain("release.verification_status = 'full_visual_verified'")
    expect(candidate).toContain("asset->>'kind' = 'question_image'")
    expect(candidate).toContain("asset->>'kind' = 'analysis_image'")
  })

  it('keeps course-spine targets when funded and makes all plan arrays exact', () => {
    expect(candidate).toContain('capacity.concept_key = v_desired_concept then 0')
    expect(candidate).toContain('capacity.skill_id = v_desired_skill then 1')
    expect(candidate).toContain('stable grade-specific spine')
    expect(candidate).toContain('min(owned.target_order) as first_target_order')
    expect(candidate).toContain('array_agg(assignment.concept_key order by assignment.target_order)')
    expect(candidate).toContain('array_agg(assignment.concept_label order by assignment.target_order)')
    expect(candidate).toContain('cardinality(arrays.target_concept_keys) <> plan.question_count')
    expect(candidate).toContain('cardinality(arrays.knowledge_summaries) <> plan.question_count')
    expect(candidate).toContain('plan.question_count not between 1 and 8')
    expect(candidate).toContain('plan.round_limit <> 1')
    expect(candidate).toContain('min(owned.target_order) as first_target_order')
    expect(candidate).toContain('group by owned.skill_id')
    expect(candidate).toContain('cardinality(arrays.skill_ids) not between 1 and plan.question_count')
  })

  it('can expand a smaller stored anchor to 6..8 unresolved concepts atomically', () => {
    expect(candidate).toContain('discover 6..8 unresolved concepts')
    expect(candidate).toContain('v_anchor_question_count := pg_catalog.cardinality(p_anchor_concept_keys)')
    expect(candidate).toContain('when plan.id = p_anchor_plan_id then v_anchor_question_count')
    expect(candidate).toContain('count(*)::smallint as question_count')
    expect(candidate).toContain('question_count = arrays.question_count')
    expect(candidate).toContain('estimated_minutes = least(30, greatest(8, arrays.question_count * 4))::smallint')
    expect(candidate).toContain('plan.question_count is distinct from arrays.question_count')
  })

  it('records a teacher-visible shortage while changing no learning evidence or quiz session', () => {
    expect(candidate).toContain('app_private.chem_review_capacity_shortages')
    expect(candidate).toContain('A row means suffix personalization was refused')
    expect(candidate).toContain('on conflict (student_id, anchor_date, reason_code)')
    expect(candidate).toContain("'ok', false")
    expect(candidate).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.chem_learning_attempts/i)
    expect(candidate).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.chem_attempt_answers/i)
    expect(candidate).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.quiz_sessions/i)
  })

  it('verifies catalog/spine coverage and exact persisted update count', () => {
    expect(candidate).toContain('grade_catalog_skill_outside_spine')
    expect(candidate).toContain('get diagnostics v_updated_plans = row_count')
    expect(candidate).toContain('v_updated_plans <> v_expected_plan_count')
    expect(candidate).toContain('suffix_update_row_count_mismatch')
  })

  it('provides a service-only teacher shortage feed without question or answer fields', () => {
    expect(candidate).toContain('public.chem_review_capacity_shortage_rows()')
    expect(candidate).toContain('security invoker')
    expect(candidate).toContain('where shortage.resolved_at is null')
    expect(candidate).toContain('to service_role')
    const feed = candidate.slice(candidate.indexOf('create or replace function public.chem_review_capacity_shortage_rows()'))
    expect(feed).not.toMatch(/question_(?:id|content)|correct_option|selected_option|access_code|phone/i)
  })

  it('audits the deployed migration and grants execution only to the server role', () => {
    expect(candidate).toContain('Applied server-side suffix re-budgeter')
    expect(candidate).toContain('security definer')
    expect(candidate).toContain("set search_path = ''")
    expect(candidate).toContain('from public, anon, authenticated')
    expect(candidate).toContain('to service_role')
  })
})
