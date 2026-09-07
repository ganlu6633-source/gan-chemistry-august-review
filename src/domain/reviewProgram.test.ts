import { describe, expect, it } from 'vitest'
import { readReviewProgram, programContainsDate, programPlanVisible, programAllowsJuniorUnit, programQuestionIds, programReviewSkillIds } from '../../supabase/functions/chemistry-access/review-program'

const program = readReviewProgram({ reviewProgram: { startDate: '2026-09-12', endDate: '2026-09-18', participating: true } })
describe('bounded review program', () => {
  it('includes exactly the selected date boundaries', () => {
    expect(programContainsDate(program, '2026-09-11')).toBe(false)
    expect(programContainsDate(program, '2026-09-12')).toBe(true)
    expect(programContainsDate(program, '2026-09-18')).toBe(true)
    expect(programContainsDate(program, '2026-09-19')).toBe(false)
  })
  it('excludes paused students and unscheduled plans', () => {
    expect(programContainsDate({ ...program!, participating: false }, '2026-09-12')).toBe(false)
    expect(programPlanVisible(program, { mode: 'REVIEW', plan_date: '2026-09-12', is_scheduled: false })).toBe(false)
  })
  it('preserves unrelated classroom quizzes and unconfigured profiles', () => {
    expect(programPlanVisible(program, { mode: 'CLASS_QUIZ', plan_date: '2026-09-10' })).toBe(true)
    expect(programPlanVisible(null, { mode: 'REVIEW', plan_date: '2026-09-10' })).toBe(true)
  })
  it('fails closed on malformed configuration', () => {
    expect(programContainsDate(readReviewProgram({ reviewProgram: {} }), '2026-09-12')).toBe(false)
  })
  it('keeps junior learners inside the teacher-confirmed unit', () => {
    const metadata = { reviewProgram: { juniorUnitIds: ['J-KY-9UP-U01'] } }
    expect(programAllowsJuniorUnit(metadata, 'J-KY-9UP-U01')).toBe(true)
    expect(programAllowsJuniorUnit(metadata, 'J-KY-9UP-U02')).toBe(false)
    expect(programAllowsJuniorUnit(metadata, undefined)).toBe(false)
    expect(programAllowsJuniorUnit({}, 'J-KY-9UP-U02')).toBe(true)
  })
  it('does not widen scope when the unit configuration is invalid', () => {
    for (const juniorUnitIds of [[], null, 'J-KY-9UP-U01', ['J-KY-9UP-U01', 2]]) {
      expect(programAllowsJuniorUnit({ reviewProgram: { juniorUnitIds } }, 'J-KY-9UP-U01')).toBe(false)
    }
  })
  it('uses only the teacher assignment for the selected date', () => {
    const metadata = { reviewProgram: { ...program, questionAssignments: { '2026-09-12': ['Q1', 'Q2'] } } }
    expect(programQuestionIds(metadata, '2026-09-12')).toEqual(['Q1', 'Q2'])
    expect(programQuestionIds(metadata, '2026-09-13')).toEqual([])
    expect(programQuestionIds(metadata, '2026-09-19')).toEqual([])
    expect(programQuestionIds({}, '2026-09-12')).toBeNull()
    expect(programQuestionIds({ reviewProgram: { ...metadata.reviewProgram, participating: false } }, '2026-09-12')).toEqual([])
  })
  it('rejects malformed, duplicate and oversized assignments', () => {
    for (const ids of [null, 'Q1', [], ['Q1', 'Q1'], ['Q1', 7], ['bad id'], Array.from({ length: 9 }, (_, n) => `Q${n}`)]) {
      expect(programQuestionIds({ reviewProgram: { ...program, questionAssignments: { '2026-09-12': ids } } }, '2026-09-12')).toEqual([])
    }
  })
  it('keeps practice scope separate from recorded learned skills', () => {
    const metadata = { confirmedLearnedSkillIds: ['H1_MOLE_INTRO'], reviewProgram: { allowedSkillIds: ['H1_CLASSIFY'] } }
    expect(programReviewSkillIds(metadata)).toEqual(['H1_CLASSIFY'])
    expect(metadata.confirmedLearnedSkillIds).toEqual(['H1_MOLE_INTRO'])
    expect(programReviewSkillIds({})).toBeNull()
    expect(programReviewSkillIds({ reviewProgram: { allowedSkillIds: ['H1_CLASSIFY', 'H1_CLASSIFY'] } })).toEqual([])
  })
})
