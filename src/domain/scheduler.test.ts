import { describe, expect, it } from 'vitest'
import { enforceDailyBudget, selectFirstRound, selectOptionalSecondRound } from './scheduler'
import type { QuestionCandidate } from './types'

const candidate = (id: string, motherId: string, score: number, approved = true): QuestionCandidate => ({
  score,
  reason: 'memory_due',
  question: { id, motherId, skillId: 's', level: 1, gradeBand: '高一', stem: id, options: ['a','b','c','d'], correctOption: 0, explanation: '', reviewStatus: approved ? 'approved' : 'draft', scopeStatus: 'IN', sourceKind: 'original_variant' },
})

describe('scheduler', () => {
  it('keeps the first round small and never reuses a mother question', () => {
    const items = [candidate('q1','m1',10), candidate('q2','m1',20), candidate('q3','m2',30), candidate('q4','m3',40), candidate('q5','m4',50), candidate('q6','m5',60), candidate('q7','m6',70), candidate('q8','m7',80)]
    const selected = selectFirstRound(items, { mode: 'REVIEW', alreadyUsedMotherIds: [], firstRoundTarget: 6 })
    expect(selected).toHaveLength(6)
    expect(new Set(selected.map((item) => item.question.motherId)).size).toBe(6)
  })

  it('never exposes draft questions', () => {
    const selected = selectFirstRound([candidate('q1','m1',100,false), candidate('q2','m2',1)], { mode: 'REVIEW', alreadyUsedMotherIds: [] })
    expect(selected.map((item) => item.question.id)).toEqual(['q2'])
  })

  it('keeps default daily work at eight and hard special limit at ten', () => {
    expect(enforceDailyBudget(6, 4, false)).toBe(8)
    expect(enforceDailyBudget(7, 7, true)).toBe(10)
  })

  it('uses new mother questions in an optional second round', () => {
    const first = [candidate('q1','m1',10)]
    const second = selectOptionalSecondRound([candidate('q2','m1',99), candidate('q3','m2',5)], first)
    expect(second.map((item) => item.question.id)).toEqual(['q3'])
  })
})
