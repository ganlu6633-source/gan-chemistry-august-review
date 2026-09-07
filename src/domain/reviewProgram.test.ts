import { describe, expect, it } from 'vitest'
import { readReviewProgram, programContainsDate, programPlanVisible } from '../../supabase/functions/chemistry-access/review-program'

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
})
