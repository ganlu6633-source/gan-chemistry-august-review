import { describe, expect, it } from 'vitest'
import migration from '../../supabase/migrations/20260821190000_repair_future_review_plan_semantics.sql?raw'

const between = (start: string, end: string) => {
  const startIndex = migration.indexOf(start)
  const endIndex = migration.indexOf(end)
  expect(startIndex).toBeGreaterThanOrEqual(0)
  expect(endIndex).toBeGreaterThan(startIndex)
  return migration.slice(startIndex, endIndex)
}

const scheduledSkills = (marker: 'H2' | 'H3') => [
  ...between(`-- ${marker}_FUTURE_SCHEDULE_BEGIN`, `-- ${marker}_FUTURE_SCHEDULE_END`)
    .matchAll(new RegExp(`'(${marker}_[A-Z0-9_]+)'`, 'g')),
].map((match) => match[1])

describe('future REVIEW plan correction migration', () => {
  it('limits today to an honest title/summary repair and preserves attempts and answers', () => {
    expect(migration).toContain("p.plan_date between date '2026-08-21' and date '2026-09-25'")
    expect(migration).toContain("p.plan_date between date '2026-08-22' and date '2026-09-25'")
    expect(migration).toContain('create temporary table _preserved_plan_snapshot')
    expect(migration).toContain('create temporary table _today_plan_snapshot')
    expect(migration).toContain('create temporary table _today_formal_start_contract')
    expect(migration).toContain('create temporary table _attempt_snapshot')
    expect(migration).toContain('create temporary table _answer_snapshot')
    expect(migration).toContain("title = '今日复习｜' || catalog.display_name")
    expect(migration).toContain("to_jsonb(p) - 'title' - 'knowledge_summaries'")
    expect(migration).toContain('today REVIEW start contract changed for a formal student')
    expect(migration).toContain("p.mode = 'REVIEW'")
    expect(migration).not.toMatch(/delete\s+from\s+public\.chem_learning_plans/i)
    expect(migration).not.toMatch(/insert\s+into\s+public\.chem_learning_plans/i)
    expect(migration).not.toMatch(/update\s+public\.chem_learning_attempts/i)
    expect(migration).not.toMatch(/update\s+public\.chem_attempt_answers/i)
    expect(migration).toContain('an attempt row changed')
    expect(migration).toContain('an answer row changed')
  })

  it('contains exactly 35 deterministic High-2 and High-3 future days', () => {
    const high2 = scheduledSkills('H2')
    const high3 = scheduledSkills('H3')

    expect(high2).toHaveLength(35)
    expect(high3).toHaveLength(35)
    expect(new Set(high2)).toEqual(new Set([
      'H2_THERMO', 'H2_RATE', 'H2_EQUIL', 'H2_K',
      'H2_WEAK', 'H2_PH_HYDRO', 'H2_KSP', 'H2_ELECTRO',
    ]))
    expect(new Set(high3)).toEqual(new Set([
      'H3_STOICH', 'H3_ION_REDOX', 'H3_INORGANIC', 'H3_THERMO_RATE',
      'H3_EQUILIBRIUM', 'H3_AQ', 'H3_ELECTRO', 'H3_EXPERIMENT',
      'H3_PROCESS', 'H3_STRUCTURE', 'H3_ORGANIC',
    ]))

    // 2026-08-27 is index 5 from the fixed 2026-08-22 boundary.
    expect(high3[5]).toBe('H3_STOICH')
    expect(migration).toContain("f.plan_date = date '2026-08-27'")
    expect(migration).toContain("'8·27质检当天｜' || catalog.display_name || '轻回看'")
    expect(migration).toContain("p.plan_date between date '2026-08-28' and date '2026-09-25'")
    expect(migration).toContain("p.title not like '质检后%'")
    expect(migration).not.toContain('8·27质检倒排：计量与NA')
  })

  it('derives every title and five-item summary from the final single skill', () => {
    expect(migration).toContain('skill_ids = array[f.selected_skill]')
    expect(migration).toContain('catalog.display_name')
    expect(migration).toContain('knowledge_summaries = summaries.summaries')
    expect(migration).toContain("q.source_info->>'conceptLabel'")
    expect(migration).toContain('cardinality(p.skill_ids) <> 1')
    expect(migration).toContain('cardinality(p.knowledge_summaries) <> 5')
    expect(migration).toContain("p.title not like '%' || c.display_name || '%'")
    expect(migration).toContain('p.knowledge_summaries is distinct from summaries.summaries')
  })

  it('uses unresolved submitted evidence first, then profile evidence, with no random routing', () => {
    expect(migration).toContain('aa.question_snapshot->>\'conceptKey\'')
    expect(migration).toContain('partition by')
    expect(migration).toContain('a.completed_at desc, a.sequence desc, aa.id desc')
    expect(migration).toContain('history.latest_rank = 1')
    expect(migration).toContain('not history.correct or history.uncertain')
    expect(migration).toContain('scores.unresolved_concepts desc')
    expect(migration).toContain("then 'answer_evidence'")
    expect(migration).toContain("then 'profile_evidence'")
    expect(migration).toContain("s.metadata->>'profileNotes'")
    expect(migration).toContain('chem_student_skill_state state')
    expect(migration).toContain('f.plan_date = date \'2026-08-22\'')
    expect(migration).toContain('future REVIEW evidence-priority assertion failed')
    expect(migration).not.toMatch(/\brandom\s*\(/i)
  })

  it('keeps High-1 inside confirmed scope and gives the teacher-marked pair daily honest REDOX', () => {
    expect(migration).toContain("jsonb_typeof(s.metadata->'confirmedLearnedSkillIds') = 'array'")
    expect(migration).toContain("coalesce(s.metadata->>'curriculumCohort', '') = 'high1_current'")
    expect(migration).toContain("? 'H1_REDOX'")
    expect(migration).toContain("when base.redox_every_day then 'H1_REDOX'")
    expect(migration).toContain("when f.redox_every_day then '氧化还原反应｜每日五个知识点复习'")
    expect(migration).toContain('not (f.selected_skill = any(t.allowed_skills))')
    expect(migration).toContain('not (p.skill_ids[1] = any(t.allowed_skills))')
  })

  it('fails closed unless real and demo pools can both supply five non-repeating rounds', () => {
    expect(migration).toContain("q.source_kind = 'licensed_local'")
    expect(migration).toContain('q.usable_for_review')
    expect(migration).toContain("q.source_kind = 'teacher_original'")
    expect(migration).toContain('q.usable_for_demo')
    expect(migration).toContain('pool.question_count <> 25')
    expect(migration).toContain('pool.concept_count <> 5')
    expect(migration).toContain('pool.distinct_mothers <> 25')
    expect(migration).toContain('pool.distinct_source_items <> 25')
    expect(migration).toContain('pool.distinct_fingerprints <> 25')
    expect(migration).toContain('having count(q.id) <> 5')
    expect(migration).toContain('future REVIEW knowledge-card assertion failed')
    expect(migration).toContain('future REVIEW personalization assertion failed')
  })
})
