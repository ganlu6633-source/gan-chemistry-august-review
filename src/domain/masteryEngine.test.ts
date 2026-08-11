import { describe, expect, it } from 'vitest'
import { achievementCopy, applyEvidence, initialSkillState, REVIEW_INTERVALS } from './masteryEngine'
import type { SkillEvidence } from './types'

const evidence = (id: string, motherId: string, correct: boolean, level = 1): SkillEvidence => ({ id, questionId: id, motherId, level, correct, uncertain: false, durationSec: 20, observedAt: '2026-08-12T08:00:00.000Z', mode: 'REVIEW' })

describe('MasteryEngine', () => {
  it('requires two different mother questions to verify a level', () => {
    const start = initialSkillState('s1', 'skill', 3)
    const once = applyEvidence(start, evidence('q1', 'm1', true))
    const duplicateMother = applyEvidence(once, evidence('q2', 'm1', true))
    expect(duplicateMother.verifiedLevel).toBe(0)
    const verified = applyEvidence(duplicateMother, evidence('q3', 'm2', true))
    expect(verified.verifiedLevel).toBe(1)
    expect(achievementCopy(duplicateMother, verified, '氧化物分类')).toContain('通过了 L1')
  })

  it('does not drop a verified level when a new candidate level fails', () => {
    const start = { ...initialSkillState('s1', 'skill', 4), verifiedLevel: 2, candidateLevel: 3, stability: 'verified' as const }
    const next = applyEvidence(start, evidence('q3', 'm3', false, 3))
    expect(next.verifiedLevel).toBe(2)
    expect(next.candidateLevel).toBeNull()
  })

  it('requires repeated errors before declaring forgetting', () => {
    const start = { ...initialSkillState('s1', 'skill', 3), verifiedLevel: 2, candidateLevel: null, stability: 'stable' as const }
    const once = applyEvidence(start, evidence('q1', 'm1', false, 2))
    expect(once.stability).toBe('stable')
    const twice = applyEvidence(once, evidence('q2', 'm2', false, 2))
    expect(twice.stability).toBe('forgotten')
  })

  it('uses the confirmed 3/5/7/14/30 review skeleton', () => {
    expect(REVIEW_INTERVALS).toEqual([3, 5, 7, 14, 30])
  })
})
