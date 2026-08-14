import { describe, expect, it } from 'vitest'
import accessFunction from '../../supabase/functions/chemistry-access/index.ts?raw'

describe('five-round review backend contract', () => {
  it('returns the plan and payload limits needed by every client', () => {
    expect(accessFunction).toContain('questionCount, roundLimit, maxQuestionLevel: planMaxQuestionLevel(row)')
    expect(accessFunction).toContain('roundNumber,')
    expect(accessFunction).toContain('attemptSequence: selectionSequence')
    expect(accessFunction).toContain('roundsRemaining: isComplete ? 0')
  })

  it('serves only approved IN-scope questions within the plan difficulty ceiling', () => {
    expect(accessFunction).toMatch(/\.eq\("review_status", "approved"\)[\s\S]*?\.eq\("scope_status", "IN"\)/)
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

  it('allows explicit round inspection only through teacher or demo preview paths', () => {
    expect(accessFunction).toContain('allowCompletedPreview: true, previewRound')
    expect(accessFunction).toContain('previewRound !== undefined && !demo')
    expect(accessFunction).toContain('options.previewRound - 1')
  })

  it('keeps correct-but-uncertain answers unresolved', () => {
    expect(accessFunction).toContain('answer.correct && !answer.uncertain')
    expect(accessFunction).toContain('answer.correct === true && answer.uncertain !== true')
  })
})
