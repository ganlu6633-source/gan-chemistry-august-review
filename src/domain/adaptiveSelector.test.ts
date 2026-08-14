import { describe, expect, it } from 'vitest'
import { selectAdaptiveQuestions } from '../../supabase/functions/chemistry-access/adaptive'

const questions = [
  { id: 'a1', mother_id: 'ma1', skill_id: 'A', concept_key: 'A::alpha', level: 1 },
  { id: 'a2', mother_id: 'ma2', skill_id: 'A', concept_key: 'A::alpha', level: 2 },
  { id: 'a4', mother_id: 'ma4', skill_id: 'A', concept_key: 'A::alpha', level: 2 },
  { id: 'a3', mother_id: 'ma3', skill_id: 'A', concept_key: 'A::beta', level: 3 },
  { id: 'b1', mother_id: 'mb1', skill_id: 'B', concept_key: 'B::alpha', level: 1 },
  { id: 'b2', mother_id: 'mb2', skill_id: 'B', concept_key: 'B::beta', level: 2 },
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
      [{ question_id: 'a1', mother_id: 'ma1', skill_id: 'A', concept_key: 'A::alpha', attempt_sequence: 0, correct: true }, { question_id: 'a2', mother_id: 'ma2', skill_id: 'A', concept_key: 'A::alpha', attempt_sequence: 0, correct: false }],
      1,
      2,
      new Date('2026-08-12'),
    )
    expect(selected[0].skill_id).toBe('A')
    expect(selected[0].concept_key).toBe('A::alpha')
    expect(selected[0].mother_id).not.toBe('ma2')
  })

  it('targets only concepts unresolved in the latest round', () => {
    const pool = [
      { id: 'alpha-3', mother_id: 'm-alpha-3', skill_id: 'A', concept_key: 'A::alpha', level: 2 },
      { id: 'beta-3', mother_id: 'm-beta-3', skill_id: 'A', concept_key: 'A::beta', level: 2 },
    ]
    const selected = selectAdaptiveQuestions(pool, [], [
      { question_id: 'alpha-1', mother_id: 'm-alpha-1', skill_id: 'A', concept_key: 'A::alpha', attempt_sequence: 0, correct: false },
      { question_id: 'alpha-2', mother_id: 'm-alpha-2', skill_id: 'A', concept_key: 'A::alpha', attempt_sequence: 1, correct: true },
      { question_id: 'beta-2', mother_id: 'm-beta-2', skill_id: 'A', concept_key: 'A::beta', attempt_sequence: 1, correct: true, uncertain: true },
    ], 2, 1)
    expect(selected[0].concept_key).toBe('A::beta')
  })

  it('never returns to an unresolved original mother in the fifth round', () => {
    const selected = selectAdaptiveQuestions(
      questions,
      [{ skill_id: 'A', verified_level: 1, consecutive_errors: 1, next_review_at: '2026-08-11' }],
      [{ question_id: 'a2', mother_id: 'ma2', skill_id: 'A', correct: true, uncertain: true }],
      4,
      1,
      new Date('2026-08-12'),
    )
    expect(selected[0].mother_id).not.toBe('ma2')
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
    const equal = ['x1', 'x2', 'x3'].map((id) => ({ id, mother_id: `m-${id}`, skill_id: 'X', level: 1 }))
    const first = selectAdaptiveQuestions(equal, [], [], 0, 1)
    const next = selectAdaptiveQuestions(equal, [], [], 1, 1)
    expect(next[0].id).not.toBe(first[0].id)
  })

  it('serves 25 different questions and mother questions across five rounds', () => {
    const pool = Array.from({ length: 30 }, (_, index) => ({
      id: `q${index + 1}`,
      mother_id: `m${index + 1}`,
      skill_id: 'A',
      concept_key: `A::concept-${index % 5}`,
      level: (index % 3) + 1,
    }))
    let history: Array<{ question_id: string; mother_id: string; skill_id: string; concept_key: string; attempt_sequence: number; correct: boolean; uncertain: boolean }> = []
    const allSelected = []

    for (let round = 0; round < 5; round += 1) {
      const selected = selectAdaptiveQuestions(pool, [], history, round, 5)
      expect(selected).toHaveLength(5)
      allSelected.push(...selected)
      history = [
        ...history,
        ...selected.map((question) => ({
          question_id: question.id,
          mother_id: question.mother_id,
          skill_id: question.skill_id,
          concept_key: question.concept_key,
          attempt_sequence: round,
          correct: round % 2 === 0,
          uncertain: round % 3 === 0,
        })),
      ]
    }

    expect(new Set(allSelected.map((question) => question.id)).size).toBe(25)
    expect(new Set(allSelected.map((question) => question.mother_id)).size).toBe(25)
  })

  it('stops short rather than repeating when unseen mother questions run out', () => {
    const history = questions
      .filter((question) => question.skill_id === 'A')
      .slice(0, 3)
      .map((question) => ({
        question_id: question.id,
        mother_id: question.mother_id,
        skill_id: question.skill_id,
        correct: true,
        uncertain: false,
      }))

    const selected = selectAdaptiveQuestions(
      questions.filter((question) => question.skill_id === 'A'),
      [],
      history,
      2,
      2,
    )
    expect(selected).toHaveLength(1)
    expect(selected[0].mother_id).toBe('ma3')
  })
})
