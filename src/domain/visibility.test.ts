import { describe, expect, it } from 'vitest'
import { buildBehaviorSignal, canView, observationForRole } from './visibility'
import type { TeacherObservation } from './types'

const observation: TeacherObservation = { id:'o', studentId:'s', courseDate:'2026-08-12', taughtContent:'氧化物', observedEvidence:'两次漏看二元条件', internalNote:'下节课单独追问', studentMessage:'已经会按组成判断了', guardianMessage:'氧化物边界仍需巩固，已安排新题', visibility:'internal' }

describe('visibility', () => {
  it('never exposes the internal note in student or guardian projections', () => {
    expect(observationForRole(observation,'student')).not.toHaveProperty('internalNote')
    expect(observationForRole(observation,'guardian')).not.toHaveProperty('internalNote')
    expect(observationForRole(observation,'teacher').internalNote).toBeTruthy()
  })
  it('does not let a student view guardian or internal content', () => {
    expect(canView('student','guardian')).toBe(false)
    expect(canView('student','internal')).toBe(false)
  })
  it('requires repeated evidence from at least three sessions for a behavior signal', () => {
    const two = buildBehaviorSignal('pace_fast', [{at:'1',matched:true,sessionId:'a'},{at:'2',matched:true,sessionId:'b'}])
    expect(two).toBeNull()
    const three = buildBehaviorSignal('pace_fast', [{at:'1',matched:true,sessionId:'a'},{at:'2',matched:true,sessionId:'b'},{at:'3',matched:true,sessionId:'c'}])
    expect(three?.guardianCopy).toContain('系统已加入')
    expect(three?.guardianCopy).not.toMatch(/浮躁|冲动|注意力有问题/)
  })
})
