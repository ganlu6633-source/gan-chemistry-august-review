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

  it('allows junior generic choices only for an owned teacher-managed source plan', () => {
    const context = startPlanFunction.indexOf('const delivery = ownedPlanDeliveryContext(plan, reviewProfile.gradeBand)')
    const juniorGate = startPlanFunction.indexOf('realStudentOpen && reviewProfile.gradeBand === "初三" && !delivery.managed')
    const pool = startPlanFunction.indexOf('.from("chem_questions")')
    expect(juniorGate).toBeGreaterThan(-1)
    expect(juniorGate).toBeGreaterThan(context)
    expect(pool).toBeGreaterThan(juniorGate)
    expect(startPlanFunction).toContain('初三正式学习只能通过专用自适应会话进入')
  })

  it('marks every real-student generic read surface as a student open', () => {
    expect(accessSource).toMatch(/body\.action === "start_plan"[\s\S]{0,900}studentOpen: true/)
    expect(accessSource).toMatch(/const expectedSubmission = formalHighSchoolReview\s*\? await startPlanPayload\([^;]+studentOpen: true, includeAnswerLocks: true/)
    const feedbackHandler = accessSource.slice(accessSource.indexOf('if (body.action === "question_feedback"'), accessSource.indexOf('if (body.action === "junior_open_session"'))
    expect(feedbackHandler).toContain(': { studentOpen: true, includeAnswerLocks: true, onFeedbackPrepared }')
    expect(submitAttemptHandler).toContain('startPlanPayload(targetId, String(plan.id), { studentOpen: true, includeAnswerLocks: true })')
  })

  it('blocks junior legacy submissions and all future submissions before reading submitted questions', () => {
    const juniorGate = submitAttemptHandler.indexOf('String(targetProfile.data.grade_band) === "初三" && !delivery.managed')
    const futureGate = submitAttemptHandler.indexOf('String(plan.plan_date || "") > shanghaiDate()')
    const questionQuery = submitAttemptHandler.indexOf('let questionQuery = supabase')
    expect(juniorGate).toBeGreaterThan(-1)
    expect(futureGate).toBeGreaterThan(juniorGate)
    expect(questionQuery).toBeGreaterThan(futureGate)
    expect(submitAttemptHandler).toContain('const delivery = ownedPlanDeliveryContext(plan, String(targetProfile.data.grade_band))')
    expect(submitAttemptHandler).toContain('初三原自适应课程请从专用会话提交')
    expect(submitAttemptHandler).toContain('if (plan.delivery_mode === "junior_adaptive")')
    expect(submitAttemptHandler).toContain('teachingAssignmentValid(delivery.managed, managedAssignedIds, questionCount)')
    expect(submitAttemptHandler).toContain('未来计划只能进入只读知识预习')
  })
})
