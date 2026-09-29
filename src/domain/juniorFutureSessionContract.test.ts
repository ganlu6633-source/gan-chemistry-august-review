import { describe, expect, it } from 'vitest'
import ts from 'typescript'
import source from '../../supabase/functions/chemistry-access/index.ts?raw'

type Row = Record<string, unknown>
type Contract = (plan: Row, session: Row, curriculum: Row, studentId: string, textbook: string, allowAdvance?: boolean) => boolean

// Run the production contract function. Only the clock is fixed for the test.
const functions = source.slice(source.indexOf('function juniorExactStringArray('), source.indexOf('function juniorSourceQuestionIsSafe('))
const contract = new Function('shanghaiDate', 'JUNIOR_TEXTBOOK_VERSION', ts.transpileModule(
  `${functions}\nreturn juniorPlanMatchesSessionContract;`,
  { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None } },
).outputText)(() => '2026-09-29', '科粤版') as Contract

function fixture(date = '2026-09-30') {
  const skills = ['J_KY_OXY_H2O2', 'J_KY_OXY_KMNO4', 'J_KY_OXY_SYMBOLS']
  return {
    plan: { id: 'plan-1', student_id: 'student-1', plan_date: date, delivery_mode: 'junior_adaptive', junior_curriculum_day_id: 'day-1', skill_ids: [...skills], mode: 'REVIEW', question_count: 8, round_limit: 4 },
    session: { plan_day_id: 'plan-1', student_id: 'student-1', study_date: date, curriculum_day_id: 'day-1', knowledge_skill_ids: [...skills], initial_question_target: 8, hard_question_cap: 30, recovery_round_limit: 3, textbook_version: '科粤版' },
    curriculum: { id: 'day-1', knowledge_skill_ids: [...skills], textbook_version: '科粤版', release_status: 'ready' },
  }
}

describe('junior future session immutable contract', () => {
  it('accepts the explicit authorized future date without treating it as drift', () => {
    const { plan, session, curriculum } = fixture()
    expect(contract(plan, session, curriculum, 'student-1', '科粤版', true)).toBe(true)
  })

  it('keeps future dates closed when authorization is absent or false', () => {
    const { plan, session, curriculum } = fixture()
    expect(contract(plan, session, curriculum, 'student-1', '科粤版')).toBe(false)
    expect(contract(plan, session, curriculum, 'student-1', '科粤版', false)).toBe(false)
  })

  it.each(['2026-09-21', '2026-09-29'])('keeps %s available without advance permission', (date) => {
    const { plan, session, curriculum } = fixture(date)
    expect(contract(plan, session, curriculum, 'student-1', '科粤版')).toBe(true)
  })

  it.each([
    ['plan', 'student_id', 'other-student'], ['session', 'student_id', 'other-student'],
    ['session', 'plan_day_id', 'another-plan'], ['session', 'study_date', '2026-10-01'],
    ['plan', 'plan_date', ''], ['curriculum', 'id', 'another-day'],
    ['session', 'textbook_version', '人教版'], ['curriculum', 'textbook_version', '人教版'],
    ['plan', 'skill_ids', ['J_KY_OXY_KMNO4', 'J_KY_OXY_H2O2', 'J_KY_OXY_SYMBOLS']],
    ['curriculum', 'knowledge_skill_ids', ['different', 'J_KY_OXY_KMNO4', 'J_KY_OXY_SYMBOLS']],
    ['plan', 'question_count', 12], ['session', 'hard_question_cap', 31],
    ['plan', 'round_limit', 5], ['curriculum', 'release_status', 'draft'],
  ])('still rejects authorized future contract mismatch %s.%s', (target, key, value) => {
    const data = fixture() as Record<string, Row>
    data[String(target)][String(key)] = value
    expect(contract(data.plan, data.session, data.curriculum, 'student-1', '科粤版', true)).toBe(false)
  })

  it('requires the caller identity and exact textbook even when advance is enabled', () => {
    const { plan, session, curriculum } = fixture()
    expect(contract(plan, session, curriculum, 'other-student', '科粤版', true)).toBe(false)
    expect(contract(plan, session, curriculum, 'student-1', '人教版', true)).toBe(false)
  })

  it('supplies the same profile authorization in student and preview contract calls', () => {
    expect(source).toContain('juniorPlanMatchesSessionContract(plan, session, curriculum, studentId, textbookVersion,\n    juniorPlanAllowsAdvanceStudy(profileResult.data, plan))')
    expect(source).toContain('juniorPlanMatchesSessionContract(plan, session, curriculum, studentId, JUNIOR_TEXTBOOK_VERSION,\n    juniorPlanAllowsAdvanceStudy(profile, plan))')
  })
})
