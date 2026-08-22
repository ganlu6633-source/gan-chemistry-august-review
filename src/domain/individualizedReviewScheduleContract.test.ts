import { describe, expect, it } from 'vitest'

import builder from '../../scripts/build-individualized-review-plan-migration.mjs?raw'
import scheduleSpec from '../../scripts/review-schedule-20260822-20260929.mjs?raw'
import migration from '../../supabase/candidates/20260821235500_individualize_review_plans_through_september.sql?raw'

function between(start: string, end: string) {
  const startIndex = migration.indexOf(start)
  const endIndex = migration.indexOf(end)
  expect(startIndex).toBeGreaterThanOrEqual(0)
  expect(endIndex).toBeGreaterThan(startIndex)
  return migration.slice(startIndex, endIndex)
}

function gradeSkills(gradeBand: '高一' | '高二' | '高三') {
  const generated = between(
    '-- GENERATED_GRADE_SCHEDULE_BEGIN',
    '-- GENERATED_GRADE_SCHEDULE_END',
  )
  const gradeStart = generated.indexOf(`select '${gradeBand}'`)
  expect(gradeStart).toBeGreaterThanOrEqual(0)
  const remaining = generated.slice(gradeStart)
  const arrayStart = remaining.indexOf('from unnest(array[')
  const arrayEnd = remaining.indexOf(']::text[])')
  expect(arrayStart).toBeGreaterThanOrEqual(0)
  expect(arrayEnd).toBeGreaterThan(arrayStart)
  return [...remaining.slice(arrayStart, arrayEnd).matchAll(/'(H[123]_[A-Z0-9_]+)'/g)]
    .map((match) => match[1])
}

describe('individualized REVIEW schedule through 2026-09-29', () => {
  it('is generated from the 39-day curriculum spine and keeps the opening order', () => {
    const high1 = gradeSkills('高一')
    const high2 = gradeSkills('高二')
    const high3 = gradeSkills('高三')

    expect(high1).toHaveLength(39)
    expect(high2).toHaveLength(39)
    expect(high3).toHaveLength(39)
    expect(migration).toContain("date '2026-08-22'")
    expect(migration).toContain("date '2026-09-29'")
    expect(migration).toContain('array[0,4,9,14,20,27,34]::integer[]')

    // 9/1 is day index 10. High-1 starts Compulsory 1 Unit 1 and High-2
    // enters thermal effects before electrochemistry/corrosion.
    expect(high1.slice(10, 24)).toEqual([
      'H1_CLASSIFY', 'H1_REACTION_CLASSIFICATION', 'H1_CLASSIFY',
      'H1_REACTION_CLASSIFICATION', 'H1_MOLE_INTRO', 'H1_MOLE_INTRO',
      'H1_SOLUTION_CONCENTRATION', 'H1_SOLUTION_CONCENTRATION',
      'H1_MOLE_INTRO', 'H1_SOLUTION_CONCENTRATION',
      'H1_GAS_MOLAR_VOLUME', 'H1_GAS_MOLAR_VOLUME',
      'H1_CLASSIFY', 'H1_REACTION_CLASSIFICATION',
    ])
    expect(new Set(high2.slice(10, 24))).toEqual(new Set(['H2_THERMO', 'H2_ELECTRO']))
    expect(high3.slice(0, 5)).toEqual([
      'H3_ION_REDOX', 'H3_STOICH', 'H3_EXPERIMENT', 'H3_AQ', 'H3_ION_REDOX',
    ])

    expect(builder).toContain("from './review-schedule-20260822-20260929.mjs'")
    expect(builder).toContain('renderGeneratedScheduleBlock')
    expect(builder).toContain('generated grade schedule block is stale')
    expect(scheduleSpec).toContain("export const START_DATE = '2026-08-22'")
    expect(scheduleSpec).toContain("export const END_DATE = '2026-09-29'")
  })

  it('builds exact 5-concept days and uses only submitted unresolved evidence for recovery', () => {
    expect(migration).toContain('create temporary table _unresolved_evidence')
    expect(migration).toContain('attempt.completed_at is not null')
    expect(migration).toContain('attempt.completed_at desc, attempt.sequence desc, answer.id desc')
    expect(migration).toContain('history.latest_rank = 1')
    expect(migration).toContain('not history.correct or history.uncertain')
    expect(migration).toContain("then 'answer_evidence'")
    expect(migration).toContain("then 'classroom_diagnostic'")
    expect(migration).toContain("then '课堂诊断｜' || catalog.display_name")
    expect(migration).not.toContain('profileNotes')
    expect(migration).not.toContain('profile_evidence')
    expect(migration).toContain("assignment.title like '%薄弱%'")
    expect(migration).not.toContain("then '薄弱")

    expect(migration).toContain('create temporary table _personal_target')
    expect(migration).toContain('four classroom concepts plus the exact')
    expect(migration).toContain('personal.skill_id = context.classroom_skill')
    expect(migration).toContain('personal.skill_id <> context.classroom_skill')
    expect(migration).toContain('personal recovery target lacks submitted evidence')
    expect(migration).toContain('cardinality(assignment.target_concept_keys) <> 5')
    expect(migration).toContain('count(distinct target.concept_key) <> 5')
  })

  it('enforces confirmed High-1 summer scope and daily REDOX as one rotating concept', () => {
    expect(migration).toContain("jsonb_typeof(s.metadata->'confirmedLearnedSkillIds') = 'array'")
    expect(migration).toContain("coalesce(active.metadata->>'curriculumCohort', '') = 'high1_current'")
    expect(migration).toContain("? 'H1_REDOX'")
    expect(migration).toContain("schedule.skill_id = 'H1_REDOX'")
    expect(migration).toContain("then 'H1_GAS_MOLAR_VOLUME'")
    expect(migration).toContain('not (target.skill_id = any(student.confirmed_h1_skills))')
    expect(migration).toContain('High-1 confirmed summer scope was violated')

    expect(migration).toContain('create temporary table _daily_redox_target')
    expect(migration).toContain("redox.skill_id = 'H1_REDOX'")
    expect(migration).toContain('redox.concept_order = 1 + mod(context.day_index, 5)')
    expect(migration).toContain("count(*) filter (where target.skill_id = 'H1_REDOX') <> 1")
    expect(migration).toContain("count(*) filter (where target.skill_id <> 'H1_REDOX') <> 4")
    expect(migration).toContain('daily-redox 4+1 contract failed')
    expect(migration).not.toContain('REDOX-only plan every day')
  })

  it('funds complete cross-date no-repeat capacity and real difficulty progression', () => {
    expect(migration).toContain('create temporary table _historical_identity')
    expect(migration).toContain("answer.question_snapshot->>'sourceItemKey'")
    expect(migration).toContain("answer.question_snapshot->>'contentFingerprint'")
    expect(migration).toContain('history.question_id = candidate.id')
    expect(migration).toContain('history.mother_id = candidate.mother_id')
    expect(migration).toContain('history.source_item_key = candidate.source_item_key')
    expect(migration).toContain('history.content_fingerprint = candidate.content_fingerprint')
    expect(migration).toContain('(count(*) * 5)::integer as required_fresh_originals')
    expect(migration).toContain('remaining.remaining_originals, 0) < need.required_fresh_originals')
    expect(migration).toContain('fresh-source capacity is insufficient')

    expect(migration).toContain("q.review_status = 'approved'")
    expect(migration).toContain("q.scope_status = 'IN'")
    expect(migration).toContain('q.usable_for_review')
    expect(migration).toContain("q.source_kind = 'licensed_local'")
    expect(migration).toContain("q.render_mode = 'image_primary'")
    expect(migration).toContain("asset->>'kind' = 'question_image'")
    expect(migration).toContain("asset->>'kind' = 'analysis_image'")
    expect(migration).toContain('count(distinct candidate.mother_id)')
    expect(migration).toContain('count(distinct candidate.source_item_key)')
    expect(migration).toContain('count(distinct candidate.content_fingerprint)')
    expect(migration).toContain('remaining.remaining_levels @> array[1,2,3]::smallint[]')
    expect(migration).toContain('remaining.remaining_level_count < 2')
  })

  it('preserves plan ids and every attempt/answer/independent quiz row', () => {
    expect(migration).toContain('create temporary table _existing_window_identity')
    expect(migration).toContain('Update the existing 35 days in place')
    expect(migration).toContain("assignment.plan_date <= date '2026-09-25'")
    expect(migration).toContain("between date '2026-09-26' and date '2026-09-29'")
    expect(migration).toContain('an existing future REVIEW plan id or identity changed')

    expect(migration).toContain('create temporary table _attempt_snapshot')
    expect(migration).toContain('create temporary table _answer_snapshot')
    expect(migration).toContain('create temporary table _quiz_session_snapshot')
    expect(migration).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.chem_learning_attempts/i)
    expect(migration).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.chem_attempt_answers/i)
    expect(migration).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.quiz_sessions/i)
    expect(migration).toContain('independent quiz_sessions changed unexpectedly')
  })

  it('keeps demo on teacher originals and embeds no student identity or login secret', () => {
    expect(migration).toContain("question.source_kind = 'teacher_original'")
    expect(migration).toContain('question.usable_for_demo')
    expect(migration).toContain('create temporary table _demo_assignment')
    expect(migration).toContain('array[]::text[] as target_concept_keys')
    expect(migration).toContain('create temporary table _all_plan_assignment')
    expect(migration).toContain('create temporary table _mutation_assignment')
    expect(migration).toContain('Existing demo')
    expect(migration).toContain('cardinality(assignment.target_concept_keys) <> 0')
    expect(migration).toContain('safe legacy demo plan shape failed')
    expect(migration).toContain("schedule.skill_id = 'H1_REACTION_CLASSIFICATION'")
    expect(migration).toContain("then 'H1_CLASSIFY'")
    expect(migration).toContain("schedule.skill_id = 'H1_SOLUTION_CONCENTRATION'")
    expect(migration).toContain("then 'H1_MOLE_INTRO'")
    expect(migration).toContain('teacher-original demo pool is short')

    expect(migration).not.toMatch(/\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/i)
    expect(migration).not.toMatch(/access[_ ]?code|phone|手机号|登录码|设备令牌/i)
    expect(migration).not.toMatch(/display_name\s*=|display_name\s+in\s*\(/i)
  })
})
