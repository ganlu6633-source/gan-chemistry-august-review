import { describe, expect, it } from 'vitest'

import candidate from '../../supabase/migrations/20260823023000_restore_today_funded_review_packages.sql?raw'

describe('2026-08-23 funded REVIEW restore contract', () => {
  it('changes only the exact formal REVIEW date and refuses started work', () => {
    expect(candidate).toContain("plan.plan_date=date '2026-08-23'")
    expect(candidate).toContain("plan.mode='REVIEW'")
    expect(candidate).toContain("student.record_status = 'active'")
    expect(candidate).toContain("coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb")
    expect(candidate).toContain('a learner has already started today; do not reshape issued work')
    expect(candidate).toContain('lock table app_private.chem_question_answer_locks in share mode')
    expect(candidate).toContain('for update of plan')
  })

  it('uses only active, fully verified, image-complete source originals', () => {
    expect(candidate).toContain("release.status='active'")
    expect(candidate).toContain("release.verification_status='full_visual_verified'")
    expect(candidate).toContain("question.review_status='approved'")
    expect(candidate).toContain("question.scope_status='IN'")
    expect(candidate).toContain('question.usable_for_review')
    expect(candidate).toContain("question.source_kind='licensed_local'")
    expect(candidate).toContain("question.render_mode='image_primary'")
    expect(candidate).toContain("asset->>'kind'='question_image'")
    expect(candidate).toContain("asset->>'kind'='analysis_image'")
    expect(candidate).toContain("asset->>'sha256'")
  })

  it('excludes all four historical identities and follows difficulty direction', () => {
    expect(candidate).toContain('used.question_id=question.id')
    expect(candidate).toContain('used.mother_id=question.mother_id')
    expect(candidate).toContain('used.source_item_key=question.source_item_key')
    expect(candidate).toContain('used.content_fingerprint=question.content_fingerprint')
    expect(candidate).toContain('question.level > latest.question_level')
    expect(candidate).toContain('question.level <= latest.question_level')
    expect(candidate).toContain('not latest.correct or latest.uncertain')
  })

  it('keeps High-1 in confirmed scope and creates one honest 1..8 package', () => {
    expect(candidate).toContain("student.metadata->'confirmedLearnedSkillIds'")
    expect(candidate).toContain('question.skill_id=any(student.confirmed_h1_skills)')
    expect(candidate).toContain('where target_order <= 8')
    expect(candidate).toContain('assignment.question_count not between 1 and 8')
    expect(candidate).toContain('cardinality(assignment.target_concept_keys) <> assignment.question_count')
    expect(candidate).toContain('cardinality(assignment.knowledge_summaries) <> assignment.question_count')
    expect(candidate).toContain('round_limit=1')
  })

  it('prioritizes unresolved evidence and never writes evidence or quizzes', () => {
    expect(candidate).toContain('not latest.correct or latest.uncertain')
    expect(candidate).toContain('review_priority')
    expect(candidate).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.chem_learning_attempts/i)
    expect(candidate).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.chem_attempt_answers/i)
    expect(candidate).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.quiz_sessions/i)
  })
})
