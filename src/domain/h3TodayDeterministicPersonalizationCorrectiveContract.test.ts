import { describe, expect, it } from 'vitest'

import candidate from '../../supabase/migrations/20260823031500_h3_today_deterministic_personalization_corrective.sql?raw'

describe('2026-08-23 High-3 deterministic personalization corrective contract', () => {
  it('is scoped to the exact formal High-3 REVIEW date and refuses every started-evidence channel', () => {
    expect(candidate).toContain("plan.mode = 'REVIEW'")
    expect(candidate).toContain("plan.plan_date = date '2026-08-23'")
    expect(candidate).toContain("student.grade_band = '高三'")
    expect(candidate).toContain("student.record_status = 'active'")
    expect(candidate).toContain("coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb")
    expect(candidate).toContain('from public.chem_learning_attempts attempt')
    expect(candidate).toContain('join public.chem_attempt_answers answer')
    expect(candidate).toContain('from app_private.chem_question_answer_locks answer_lock')
    expect(candidate).toContain('lock table')
    expect(candidate).toContain('for update of plan')
  })

  it('uses only the active fully verified exact-source pool with both audited images', () => {
    expect(candidate).toContain("release.status = 'active'")
    expect(candidate).toContain("release.verification_status = 'full_visual_verified'")
    expect(candidate).toContain("question.review_status = 'approved'")
    expect(candidate).toContain("question.scope_status = 'IN'")
    expect(candidate).toContain('question.usable_for_review')
    expect(candidate).toContain("question.source_kind = 'licensed_local'")
    expect(candidate).toContain("question.render_mode = 'image_primary'")
    expect(candidate).toContain("asset->>'kind' = 'question_image'")
    expect(candidate).toContain("asset->>'kind' = 'analysis_image'")
    expect(candidate).toContain("asset->>'sha256'")
    expect(candidate).toContain("pg_catalog.jsonb_typeof(question.asset_refs) = 'array'")
  })

  it('excludes all four historical identities and proves four-way uniqueness inside each assignment', () => {
    expect(candidate).toContain('used.question_id = question.id')
    expect(candidate).toContain('used.mother_id = question.mother_id')
    expect(candidate).toContain('used.source_item_key = question.source_item_key')
    expect(candidate).toContain('used.content_fingerprint = question.content_fingerprint')
    expect(candidate).toContain('count(distinct target.question_id)')
    expect(candidate).toContain('count(distinct target.mother_id)')
    expect(candidate).toContain('count(distinct target.source_item_key)')
    expect(candidate).toContain('count(distinct target.content_fingerprint)')
    expect(candidate).toContain("answer.question_snapshot->>'sourceItemKey'")
    expect(candidate).toContain("answer.question_snapshot->>'contentFingerprint'")
  })

  it('keeps unresolved evidence first and never crosses an easy-error priority band', () => {
    expect(candidate).toContain('not latest.correct or latest.uncertain')
    expect(candidate).toContain('evidence_priority')
    expect(candidate).toContain('easy_error_band')
    expect(candidate).toContain("('H3_ION_REDOX',1,1)")
    expect(candidate).toContain("('H3_STOICH',2,1)")
    expect(candidate).toContain("('H3_EXPERIMENT',3,1)")
    expect(candidate).toContain('later.evidence_priority < earlier.evidence_priority')
    expect(candidate).toContain('later.easy_error_band < earlier.easy_error_band')
    expect(candidate).toContain('question.level > latest.question_level')
    expect(candidate).toContain('question.level <= latest.question_level')
  })

  it('personalizes deterministically only after hard priorities and rejects duplicate ordered paths', () => {
    const evidencePosition = candidate.indexOf('proof.evidence_priority,')
    const bandPosition = candidate.indexOf('proof.easy_error_band,')
    const hashPosition = candidate.indexOf('pg_catalog.hashtextextended(', evidencePosition)
    expect(evidencePosition).toBeGreaterThan(-1)
    expect(bandPosition).toBeGreaterThan(evidencePosition)
    expect(hashPosition).toBeGreaterThan(bandPosition)
    expect(candidate).toContain("proof.student_id::text")
    expect(candidate).toContain("':2026-08-23:h3-corrective:'")
    expect(candidate).toContain("array_to_string(assignment.target_concept_keys,'|')")
    expect(candidate).toContain('two eligible High-3 learners still have the same ordered path')
  })

  it('keeps the existing 1..8 daily load and writes only the eligible plan arrays', () => {
    expect(candidate).toContain('plan.question_count between 1 and 8')
    expect(candidate).toContain('where target_order <= question_count')
    expect(candidate).toContain('cardinality(assignment.target_concept_keys) <> assignment.question_count')
    expect(candidate).toContain('cardinality(assignment.knowledge_summaries) <> assignment.question_count')
    expect(candidate).toContain('min(target.target_order) as first_target_order')
    expect(candidate).toContain('update public.chem_learning_plans plan')
    expect(candidate).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.chem_learning_attempts/i)
    expect(candidate).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.chem_attempt_answers/i)
    expect(candidate).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.quiz_sessions/i)
    expect(candidate).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+app_private\.chem_question_answer_locks/i)
  })
})
