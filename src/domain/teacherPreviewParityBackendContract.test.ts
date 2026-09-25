import { describe, expect, it } from 'vitest'
import source from '../../supabase/functions/chemistry-access/index.ts?raw'


describe('teacher student simulation backend contract', () => {
  it('replays junior answers without issuing, recording or finalizing student steps', () => {
    const preview = source.slice(source.indexOf('async function juniorPreviewPayload'), source.indexOf('async function authenticate'))
    expect(preview).toContain('selectJuniorScheduledQuestion(')
    expect(preview).toContain('juniorQuestionFeedbackShape(')
    expect(preview).not.toMatch(/\.insert\(|\.update\(|\.upsert\(|chem_junior_record_step|chem_junior_issue_option_step|chem_junior_finalize_session/)
    expect(source).toMatch(/body\.action === "preview_junior_submit_step" && identity\.role === "teacher"/)
  })

  it('reconstructs self-study from the same verified source pool without creating a plan for teachers', () => {
    const open = source.slice(source.indexOf('async function openSelfStudy'), source.indexOf('async function guardianDashboard'))
    expect(open).toContain('if (readOnlyPreview)')
    expect(open.indexOf('if (readOnlyPreview)')).toBeLessThan(open.indexOf('.insert({'))
    expect(open).toContain('planOverride: { id, ...planFields }')
    expect(source).toContain('payload: await openSelfStudy(targetId, skillId, conceptKey, releaseId, true')
  })

  it('uses student future-date gates and never locks a teacher answer', () => {
    expect(source).toContain('futurePlanPreviewPayload(targetId, planId)')
    expect(source).toContain('studentOpen: true, teacherSimulation: true, includeAnswerLocks: true, previewRound')
    const feedback = source.slice(source.indexOf('if (body.action === "question_feedback")'), source.indexOf('if (body.action === "junior_open_session")'))
    expect(feedback).toContain('if (!readOnlyPreview) {')
    expect(feedback).toContain('simulated: readOnlyPreview')
  })
})
