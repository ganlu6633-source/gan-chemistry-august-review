import { describe, expect, it } from 'vitest'
import { choiceAnswersMatch, choiceBranches, choiceProgress, parseChoiceContext, type ChoiceTrainingContext } from '../../supabase/functions/chemistry-access/choice-training'

function context(): ChoiceTrainingContext {
  return { policyVersion: 'choice_8_3_30_v1', planId: 'plan', baseQuestionIds: Array.from({ length: 8 }, (_, i) => `q${i}`),
    questions: Array.from({ length: 8 }, (_, i) => ({ id: `q${i}`, question_revision_token: `r${i}`, correct_option: 0 })),
    lockedAnswers: Array.from({ length: 8 }, (_, i) => ({ question_id: `q${i}`, revision_token: `r${i}`, selected_option: 0 })),
    branches: [], dailyUsed: 8, dailyRemaining: 22, complete: true }
}
const submitted = () => context().questions.map(q => ({ questionId: q.id, selectedOption: 0, revisionToken: q.question_revision_token }))

describe('choice training private context boundary', () => {
  it('accepts only complete ordered immutable answers, never client scores', () => {
    expect(choiceAnswersMatch(context(), submitted().map(a => ({ ...a, correct: false })))).toBe(true)
    expect(choiceAnswersMatch(context(), submitted().reverse())).toBe(false)
    expect(choiceAnswersMatch(context(), submitted().slice(1))).toBe(false)
    expect(choiceAnswersMatch({ ...context(), complete: false }, submitted())).toBe(false)
    expect(choiceAnswersMatch(context(), submitted().map((a, i) => i ? a : { ...a, selectedOption: 1 }))).toBe(false)
    expect(choiceAnswersMatch(context(), submitted().map((a, i) => i ? a : { ...a, revisionToken: 'forged' }))).toBe(false)
  })
  it('does not publish private candidate, binding, or answer rows in progress', () => {
    const c = context()
    c.branches = [{ anchorQuestionId: 'q0', anchorOptionIndex: 2, knowledgePoint: '离子半径',
      questionIds: ['q8', 'q9', 'q10'], answered: 1, correct: 1, status: 'practicing', recoveryRound: 1,
      _binding: { secret: 'source-locator' }, _candidates: [{ questionId: 'unissued' }] }]
    expect(choiceBranches(c)[0]).toMatchObject({ optionIndex: 2, questionIds: ['q8', 'q9', 'q10'] })
    expect(JSON.stringify(choiceBranches(c))).not.toMatch(/source-locator|unissued|_binding|_candidates/)
    expect(choiceProgress(c)).not.toHaveProperty('questions')
    expect(choiceProgress(c)).not.toHaveProperty('lockedAnswers')
  })
  it('rejects missing, duplicate or over-budget question groups', () => {
    expect(() => parseChoiceContext(null)).toThrow()
    expect(() => parseChoiceContext({ ...context(), questions: [...context().questions, context().questions[0]] })).toThrow()
    expect(() => parseChoiceContext({ ...context(), questions: Array.from({ length: 31 }, (_, i) => ({ id: `q${i}` })) })).toThrow()
    expect(parseChoiceContext(context()).questions).toHaveLength(8)
  })
  it('keeps older same-day history above the new cap without granting new questions', () => {
    const blocked = { ...context(), baseQuestionIds: [], questions: [], lockedAnswers: [],
      dailyUsed: 35, dailyRemaining: 0, complete: false, pendingReason: 'daily_limit' }
    expect(parseChoiceContext(blocked).pendingReason).toBe('daily_limit')
    expect(() => parseChoiceContext({ ...blocked, dailyRemaining: 1 })).toThrow()
    expect(() => parseChoiceContext({ ...blocked, dailyUsed: -1 })).toThrow()
  })
})
