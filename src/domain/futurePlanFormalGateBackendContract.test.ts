import { describe, expect, it } from 'vitest'

import accessSource from '../../supabase/functions/chemistry-access/index.ts?raw'

const startPlanFunction = accessSource.slice(
  accessSource.indexOf('async function startPlanPayload'),
  accessSource.indexOf('async function authenticate'),
)

const submitAttemptStart = accessSource.indexOf('if (body.action === "submit_attempt"')
const submitAttemptHandler = accessSource.slice(
  submitAttemptStart,
  accessSource.indexOf('if (body.action === "student_dashboard"', submitAttemptStart),
)

describe('future formal-plan and junior legacy fail-closed gates', () => {
  it('blocks every real-student future plan before the generic question pool is queried', () => {
    const gate = startPlanFunction.indexOf('realStudentOpen && String(plan.plan_date || "") > shanghaiDate()')
    const pool = startPlanFunction.indexOf('.from("chem_questions")')
    expect(startPlanFunction).toContain('const realStudentOpen = options.studentOpen === true && !demoProfile')
    expect(gate).toBeGreaterThan(-1)
    expect(pool).toBeGreaterThan(gate)
    expect(startPlanFunction).toContain('未来计划只能进入只读知识预习')
  })

  it('does not let a real junior student use a legacy-round generic pool', () => {
    const juniorGate = startPlanFunction.indexOf('realStudentOpen && reviewProfile.gradeBand === "初三"')
    const pool = startPlanFunction.indexOf('.from("chem_questions")')
    expect(juniorGate).toBeGreaterThan(-1)
    expect(pool).toBeGreaterThan(juniorGate)
    expect(startPlanFunction).toContain('初三正式学习只能通过专用自适应会话进入')
  })

  it('marks every real-student generic read surface as a student open', () => {
    expect(accessSource).toMatch(/body\.action === "start_plan"[\s\S]{0,900}studentOpen: true/)
    expect(accessSource).toMatch(/expectedPayload = await startPlanPayload\([\s\S]{0,260}studentOpen: true, includeAnswerLocks: true/)
    expect(accessSource).toMatch(/body\.action === "question_feedback"[\s\S]{0,1900}studentOpen: true, includeAnswerLocks: true/)
    expect(submitAttemptHandler).toContain('startPlanPayload(targetId, String(plan.id), { studentOpen: true, includeAnswerLocks: true })')
  })

  it('blocks junior legacy submissions and all future submissions before reading submitted questions', () => {
    const juniorGate = submitAttemptHandler.indexOf('String(targetProfile.data.grade_band) === "初三"')
    const futureGate = submitAttemptHandler.indexOf('String(plan.plan_date || "") > shanghaiDate()')
    const questionQuery = submitAttemptHandler.indexOf('let questionQuery = supabase')
    expect(juniorGate).toBeGreaterThan(-1)
    expect(futureGate).toBeGreaterThan(juniorGate)
    expect(questionQuery).toBeGreaterThan(futureGate)
    expect(submitAttemptHandler).toContain('初三正式作答只能通过专用自适应会话提交')
    expect(submitAttemptHandler).toContain('未来计划只能进入只读知识预习')
  })
})
