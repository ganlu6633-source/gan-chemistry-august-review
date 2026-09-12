import { describe, expect, it } from 'vitest'
import { teachingPlanContext, teachingAssignmentValid, teachingQuestionSourceMatches } from '../../supabase/functions/chemistry-access/teaching-plan'
import { expandOptionPractice } from '../../supabase/functions/chemistry-access/option-practice'

const plan = { mode: 'REVIEW', delivery_mode: 'legacy_round', question_count: 2, round_limit: 1,
  teaching_managed: true, teaching_source_grade: '高二' }

describe('teacher controlled source grade', () => {
  it('allows a high-one student to use a teacher assigned high-two source without changing enrollment', () => {
    const context = teachingPlanContext(plan, '高一')
    expect(context).toMatchObject({ managed: true, sourceGrade: '高二', sourceKind: 'licensed_local', renderMode: 'image_primary' })
  })
  it('ignores source grade hints on every ordinary plan and requires the owned managed flag to be true', () => {
    expect(teachingPlanContext({ ...plan, teaching_managed: false }, '高一').sourceGrade).toBe('高一')
    expect(teachingPlanContext({ ...plan, teaching_managed: 'true' }, '高一').sourceGrade).toBe('高一')
  })
  it('supports verified native junior originals through the fixed choice workflow', () => {
    const context = teachingPlanContext({ ...plan, teaching_source_grade: '初三' }, '初三')
    expect(context).toMatchObject({ sourceKind: 'user_provided_local', renderMode: 'native', requiresImages: false })
    expect(teachingQuestionSourceMatches({ grade_band: '初三', source_kind: 'user_provided_local', render_mode: 'native', source_release_id: 'active' }, context, 'active')).toBe(true)
    expect(teachingQuestionSourceMatches({ grade_band: '初三', source_kind: 'teacher_created', render_mode: 'native', source_release_id: 'active' }, context, 'active')).toBe(false)
  })
  it('requires the current source grade and release even for an otherwise approved question', () => {
    const context = teachingPlanContext(plan, '高一')
    const row = { grade_band: '高二', source_kind: 'licensed_local', render_mode: 'image_primary', source_release_id: 'active' }
    expect(teachingQuestionSourceMatches(row, context, 'active')).toBe(true)
    expect(teachingQuestionSourceMatches({ ...row, grade_band: '高一' }, context, 'active')).toBe(false)
    expect(teachingQuestionSourceMatches({ ...row, source_release_id: 'retired' }, context, 'active')).toBe(false)
  })
  it('fails closed for missing source grade, non-review/adaptive plans, extra rounds, and more than eight originals', () => {
    for (const changed of [{ teaching_source_grade: null }, { mode: 'CLASS_QUIZ' }, { delivery_mode: 'junior_adaptive' }, { round_limit: 2 }, { question_count: 9 }]) {
      expect(() => teachingPlanContext({ ...plan, ...changed }, '初三')).toThrow()
    }
  })
  it('requires exact fixed assignment length and distinct original identities at the scheduling boundary', () => {
    expect(teachingAssignmentValid(true, null, 2)).toBe(false)
    expect(teachingAssignmentValid(true, [], 2)).toBe(false)
    expect(teachingAssignmentValid(true, ['one', 'one'], 2)).toBe(false)
    expect(teachingAssignmentValid(true, ['one', 'two'], 2)).toBe(true)
    expect(teachingAssignmentValid(false, null, 2)).toBe(true)
  })
  it('keeps legacy junior source identity exclusions in a managed option branch', () => {
    const make = (id: string) => ({ id, mother_id: `m-${id}`, source_item_key: `s-${id}`, parent_source_item_key: `p-${id}`, content_fingerprint: `f-${id}`, question_revision_token: `r-${id}`, correct_option: 1 })
    const candidates = ['a','b','c'].map(make)
    const anchor = { ...make('anchor'), source_info: { optionPractice: { status: 'verified', anchorRevisionToken: 'r-anchor', bindings: [{ optionIndex: 0, knowledgePoint: '污水治理', sameTypeKey: 'sewage', candidates: candidates.map(q => ({ questionId: q.id, revisionToken: q.question_revision_token, reason: '同一处理判断' })) }] } } }
    const result = expandOptionPractice({ baseQuestions: [anchor], candidates, locks: [{ question_id: 'anchor', selected_option: 0 }],
      excludedQuestions: [{ id: 'old-published-id', source_item_key: 's-a' }] })
    expect(result.progress[0].status).toBe('reserve_gap')
    expect(result.questions.map(q => q.id)).toEqual(['anchor'])
  })
})
