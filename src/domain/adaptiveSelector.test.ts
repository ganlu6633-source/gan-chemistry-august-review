import { describe, expect, it } from 'vitest'
import { selectAdaptiveQuestions } from '../../supabase/functions/chemistry-access/adaptive'

const questions = [
  { id: 'a1', mother_id: 'ma1', skill_id: 'A', level: 1 },
  { id: 'a2', mother_id: 'ma2', skill_id: 'A', level: 2 },
  { id: 'a3', mother_id: 'ma3', skill_id: 'A', level: 3 },
  { id: 'b1', mother_id: 'mb1', skill_id: 'B', level: 1 },
  { id: 'b2', mother_id: 'mb2', skill_id: 'B', level: 2 },
]

describe('adaptive question selector', () => {
  it('covers every skill in a multi-skill plan', () => {
    const selected = selectAdaptiveQuestions(questions, [], [], 0, 3, new Date('2026-08-12'))
    expect(new Set(selected.map((item) => item.skill_id))).toEqual(new Set(['A', 'B']))
  })

  it('uses a different mother question for an unresolved skill in rounds two to four', () => {
    const selected = selectAdaptiveQuestions(
      questions,
      [{ skill_id: 'A', verified_level: 1, consecutive_errors: 1, next_review_at: '2026-08-11' }],
      [{ question_id: 'a1', mother_id: 'ma1', skill_id: 'A', correct: true }, { question_id: 'a2', mother_id: 'ma2', skill_id: 'A', correct: false }],
      1,
      2,
      new Date('2026-08-12'),
    )
    expect(selected[0].skill_id).toBe('A')
    expect(selected[0].mother_id).not.toBe('ma2')
  })

  it('can return to the unresolved original mother in the fifth round', () => {
    const selected = selectAdaptiveQuestions(
      questions,
      [{ skill_id: 'A', verified_level: 1, consecutive_errors: 1, next_review_at: '2026-08-11' }],
      [{ question_id: 'a2', mother_id: 'ma2', skill_id: 'A', correct: true, uncertain: true }],
      4,
      1,
      new Date('2026-08-12'),
    )
    expect(selected[0].id).toBe('a2')
  })

  it('keeps a correct-but-uncertain answer unresolved and changes its mother next round', () => {
    const selected = selectAdaptiveQuestions(
      questions.filter((question) => question.skill_id === 'A'),
      [],
      [{ question_id: 'a1', mother_id: 'ma1', skill_id: 'A', correct: true, uncertain: true }],
      1,
      1,
    )
    expect(selected[0].mother_id).not.toBe('ma1')
  })

  it('rotates equally ranked unseen items on a later attempt', () => {
    const equal = ['x1', 'x2', 'x3'].map((id) => ({ id, skill_id: 'X', level: 1 }))
    const first = selectAdaptiveQuestions(equal, [], [], 0, 1)
    const next = selectAdaptiveQuestions(equal, [], [], 1, 1)
    expect(next[0].id).not.toBe(first[0].id)
  })
})
