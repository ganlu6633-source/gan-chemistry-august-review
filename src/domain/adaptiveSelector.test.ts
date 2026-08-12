import { describe, expect, it } from 'vitest'
import { selectAdaptiveQuestions } from '../../supabase/functions/chemistry-access/adaptive'

const questions = [
  { id: 'a1', skill_id: 'A', level: 1 },
  { id: 'a2', skill_id: 'A', level: 2 },
  { id: 'a3', skill_id: 'A', level: 3 },
  { id: 'b1', skill_id: 'B', level: 1 },
  { id: 'b2', skill_id: 'B', level: 2 },
]

describe('adaptive question selector', () => {
  it('covers every skill in a multi-skill plan', () => {
    const selected = selectAdaptiveQuestions(questions, [], [], 0, 3, new Date('2026-08-12'))
    expect(new Set(selected.map((item) => item.skill_id))).toEqual(new Set(['A', 'B']))
  })

  it('prioritizes a previously missed item and moves toward the next verified level', () => {
    const selected = selectAdaptiveQuestions(
      questions,
      [{ skill_id: 'A', verified_level: 1, consecutive_errors: 1, next_review_at: '2026-08-11' }],
      [{ question_id: 'a1', correct: true }, { question_id: 'a2', correct: false }],
      1,
      2,
      new Date('2026-08-12'),
    )
    expect(selected[0].id).toBe('a2')
  })

  it('rotates equally ranked unseen items on a later attempt', () => {
    const equal = ['x1', 'x2', 'x3'].map((id) => ({ id, skill_id: 'X', level: 1 }))
    const first = selectAdaptiveQuestions(equal, [], [], 0, 1)
    const next = selectAdaptiveQuestions(equal, [], [], 1, 1)
    expect(next[0].id).not.toBe(first[0].id)
  })
})
