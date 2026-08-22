import { describe, expect, it } from 'vitest'
import { selectAdaptiveQuestions } from '../../supabase/functions/chemistry-access/adaptive'

const fiveConceptPool = Array.from({ length: 5 }, (_, conceptIndex) =>
  [1, 1, 2, 3, 3].map((level, variantIndex) => ({
    id: `q-${conceptIndex}-${variantIndex}`,
    mother_id: `m-${conceptIndex}-${variantIndex}`,
    skill_id: 'A',
    concept_key: `A__C0${conceptIndex + 1}`,
    level,
  }))).flat()

describe('adaptive original-question selector', () => {
  it('covers all five fine-grained concepts once in round one', () => {
    const selected = selectAdaptiveQuestions(fiveConceptPool, [], [], 0, 5)
    expect(selected).toHaveLength(5)
    expect(new Set(selected.map((item) => item.concept_key)).size).toBe(5)
    expect(selected.every((item) => item.level === 1)).toBe(true)
  })

  it('covers an exact five-concept day even when one target comes from a second skill', () => {
    const mixedPool = fiveConceptPool
      .filter((question) => question.concept_key !== 'A__C05')
      .concat([1, 1, 2, 3, 3].map((level, variantIndex) => ({
        id: `redox-${variantIndex}`,
        mother_id: `redox-mother-${variantIndex}`,
        skill_id: 'H1_REDOX',
        concept_key: 'H1_REDOX__C01',
        level,
      })))
    const selected = selectAdaptiveQuestions(mixedPool, [], [], 0, 5)

    expect(selected).toHaveLength(5)
    expect(new Set(selected.map((item) => item.concept_key))).toEqual(new Set([
      'A__C01', 'A__C02', 'A__C03', 'A__C04', 'H1_REDOX__C01',
    ]))
    expect(selected.every((item) => item.level === 1)).toBe(true)
  })

  it('raises difficulty after a correct and confident answer', () => {
    const selected = selectAdaptiveQuestions(fiveConceptPool, [], [{
      question_id: 'q-0-0', mother_id: 'm-0-0', skill_id: 'A', concept_key: 'A__C01',
      question_level: 1, attempt_sequence: 0, correct: true, uncertain: false,
    }], 1, 5)
    expect(selected.find((item) => item.concept_key === 'A__C01')?.level).toBe(2)
  })

  it('uses the next unseen original from the same concept after an error or uncertainty', () => {
    const selected = selectAdaptiveQuestions(fiveConceptPool, [], [{
      question_id: 'q-0-0', mother_id: 'm-0-0', skill_id: 'A', concept_key: 'A__C01',
      question_level: 1, attempt_sequence: 0, correct: false, uncertain: true,
    }], 1, 5)
    const followUp = selected.find((item) => item.concept_key === 'A__C01')
    expect(followUp?.level).toBe(1)
    expect(followUp?.mother_id).not.toBe('m-0-0')
  })

  it('keeps the latest evidence for each concept across different review dates', () => {
    const selected = selectAdaptiveQuestions(fiveConceptPool, [], [
      {
        question_id: 'q-0-0', mother_id: 'm-0-0', skill_id: 'A', concept_key: 'A__C01',
        question_level: 1, attempt_sequence: 3, correct: true, uncertain: false,
      },
      {
        question_id: 'q-1-0', mother_id: 'm-1-0', skill_id: 'A', concept_key: 'A__C02',
        question_level: 1, attempt_sequence: 4, correct: false, uncertain: true,
      },
    ], 5, 5)

    expect(selected.find((item) => item.concept_key === 'A__C01')?.level).toBe(2)
    expect(selected.some((item) => item.id === 'q-0-0')).toBe(false)
    expect(selected.some((item) => item.id === 'q-1-0')).toBe(false)
  })

  it('never repeats a question or mother across five unresolved rounds', () => {
    let history: Array<{
      question_id: string; mother_id: string; skill_id: string; concept_key: string
      question_level: number; attempt_sequence: number; correct: boolean; uncertain: boolean
    }> = []
    const allSelected = []
    for (let round = 0; round < 5; round += 1) {
      const selected = selectAdaptiveQuestions(fiveConceptPool, [], history, round, 5)
      expect(selected).toHaveLength(5)
      allSelected.push(...selected)
      history = history.concat(selected.map((question) => ({
        question_id: question.id, mother_id: question.mother_id, skill_id: question.skill_id,
        concept_key: question.concept_key, question_level: question.level, attempt_sequence: round,
        correct: false, uncertain: true,
      })))
    }
    expect(new Set(allSelected.map((item) => item.id)).size).toBe(25)
    expect(new Set(allSelected.map((item) => item.mother_id)).size).toBe(25)
  })

  it('stops instead of repeating when a concept runs out of unseen originals', () => {
    const oneConcept = fiveConceptPool.filter((item) => item.concept_key === 'A__C01').slice(0, 2)
    const selected = selectAdaptiveQuestions(oneConcept, [], oneConcept.map((question) => ({
      question_id: question.id, mother_id: question.mother_id, skill_id: question.skill_id,
      concept_key: question.concept_key, question_level: question.level, attempt_sequence: 0,
      correct: false, uncertain: true,
    })), 1, 1)
    expect(selected).toHaveLength(0)
  })

  it('fails closed instead of filling an exhausted REVIEW concept from another concept', () => {
    const exhaustedConcept = fiveConceptPool.filter((item) => item.concept_key === 'A__C01')
    const history = exhaustedConcept.map((question, attemptSequence) => ({
      question_id: question.id,
      mother_id: question.mother_id,
      skill_id: question.skill_id,
      concept_key: question.concept_key,
      question_level: question.level,
      attempt_sequence: attemptSequence,
      correct: false,
      uncertain: true,
    }))

    const selected = selectAdaptiveQuestions(fiveConceptPool, [], history, 5, 5, new Date(), true)

    expect(selected).toHaveLength(4)
    expect(new Set(selected.map((item) => item.concept_key))).toEqual(new Set([
      'A__C02', 'A__C03', 'A__C04', 'A__C05',
    ]))
  })
})
