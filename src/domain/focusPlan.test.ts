import { describe, expect, it } from 'vitest'
import { selectFocusPlan } from './focusPlan'
import type { LearningPlanDay } from './types'

const plan = (date: string) => ({ id: date, date } as LearningPlanDay)
describe('primary learning task', () => {
  it('never relabels a historical plan as today', () => {
    expect(selectFocusPlan([plan('2026-09-06')], '2026-09-07')).toBeUndefined()
    expect(selectFocusPlan([], '2026-09-07')).toBeUndefined()
  })
  it('selects the earliest future plan independently of source ordering', () => {
    expect(selectFocusPlan([plan('2026-09-18'), plan('2026-09-12'), plan('2026-08-17')], '2026-09-07')?.date).toBe('2026-09-12')
  })
  it('keeps today ahead of the future plan', () => {
    expect(selectFocusPlan([plan('2026-09-13'), plan('2026-09-12')], '2026-09-12')?.date).toBe('2026-09-12')
  })
})
