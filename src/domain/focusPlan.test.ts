import { describe, expect, it } from 'vitest'
import { selectFocusPlan } from './focusPlan'
import type { LearningPlanDay } from './types'

const plan = (date: string, isComplete = false) => ({ id: date, date, isComplete } as LearningPlanDay)
describe('primary learning task', () => {
  it('offers the oldest unfinished historical plan for catch-up', () => {
    expect(selectFocusPlan([plan('2026-09-06'), plan('2026-09-05')], '2026-09-07')?.date).toBe('2026-09-05')
    expect(selectFocusPlan([plan('2026-09-06', true)], '2026-09-07')).toBeUndefined()
    expect(selectFocusPlan([], '2026-09-07')).toBeUndefined()
  })
  it('selects the earliest future plan independently of source ordering', () => {
    expect(selectFocusPlan([plan('2026-09-18'), plan('2026-09-12'), plan('2026-08-17', true)], '2026-09-07')?.date).toBe('2026-09-12')
  })
  it('keeps today ahead of the future plan', () => {
    expect(selectFocusPlan([plan('2026-09-13'), plan('2026-09-12')], '2026-09-12')?.date).toBe('2026-09-12')
  })
  it('keeps today ahead of historical catch-up while preserving the backlog', () => {
    expect(selectFocusPlan([plan('2026-09-10'), plan('2026-09-12')], '2026-09-12')?.date).toBe('2026-09-12')
  })
})
