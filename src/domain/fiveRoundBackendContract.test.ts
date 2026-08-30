import { describe, expect, it } from 'vitest'
import accessFunction from '../../supabase/functions/chemistry-access/index.ts?raw'

describe('five-round review backend contract', () => {
  it('returns the plan and payload limits needed by every client', () => {
    expect(accessFunction).toContain('questionCount, roundLimit, maxQuestionLevel: maximumLevel')
    expect(accessFunction).toContain('roundNumber,')
    expect(accessFunction).toContain('attemptSequence: selectionSequence')
    expect(accessFunction).toContain('roundsRemaining: isComplete ? 0')
  })

  it('serves only approved IN-scope questions within the plan difficulty ceiling', () => {
    expect(accessFunction).toMatch(/\.eq\("review_status", "approved"\)[\s\S]*?\.eq\("scope_status", "IN"\)/)
    expect(accessFunction).toContain('.not("mother_id", "is", null)')
    expect(accessFunction).toContain('eligibleQuestions = eligibleQuestions.lte("level", maxQuestionLevel)')
    expect(accessFunction).toContain('questionQuery = questionQuery.lte("level", maxQuestionLevel)')
  })

  it('requires a complete round and refuses writes after the configured limit', () => {
    expect(accessFunction).toContain('adaptiveQuestions.length !== questionCount')
    expect(accessFunction).toContain('submittedAnswers.length !== questionCount')
    expect(accessFunction).toContain('attemptSequence >= roundLimit')
    expect(accessFunction).toContain('Number(attempt.sequence) !== attemptSequence')
    expect(accessFunction).toContain('sequence: attemptSequence')
  })

  it('enforces zero repeated questions and mother questions for the whole plan day', () => {
    expect(accessFunction).toContain('const attemptIds = attempts.map')
    expect(accessFunction).toContain('usedQuestionIds.has(String(question.id))')
    expect(accessFunction).toContain('usedMotherIds.has(String(question.mother_id))')
    expect(accessFunction).toContain('同一天的后续轮次不能重复题目或同一母题')
    expect(accessFunction).toContain('题库变式不足，本轮已停止并通知甘老师')
  })

  it('allows explicit round inspection only through teacher or demo preview paths', () => {
    expect(accessFunction).toContain('allowCompletedPreview: true, previewRound')
    expect(accessFunction).toMatch(/if \(options\.studentOpen && !demoProfile && options\.previewRound !== undefined\) \{[\s\S]*?throw new RequestError\(403, "真实学习记录不能指定练习轮次。"\);[\s\S]*?\}/)
    expect(accessFunction).toContain('payload: await startPlanPayload(targetId, planId, { studentOpen: true, previewRound })')
    expect(accessFunction).toContain('effectiveOptions.previewRound - 1')
    expect(accessFunction).toContain('for (let previewIndex = 0; previewIndex <= selectionSequence; previewIndex += 1)')
  })

  it('keeps correct-but-uncertain answers unresolved', () => {
    expect(accessFunction).toContain('answer.correct && !answer.uncertain')
    expect(accessFunction).toContain('answer.correct === true && answer.uncertain !== true')
  })

  it('rebuilds and verifies the exact adaptive five-question set on submit', () => {
    expect(accessFunction).toContain('eligibleQuestions = eligibleQuestions.order("id")')
    expect(accessFunction).toContain('const expectedPayload = await startPlanPayload(targetId, String(plan.id), { studentOpen: true, includeAnswerLocks: true })')
    expect(accessFunction).toContain('expectedQuestionIdSet.has(questionId)')
    expect(accessFunction).toContain('不属于系统刚刚生成的自适应题组')
  })
})
