import { describe, expect, it } from 'vitest'
import { juniorDailyPolicy, LEGACY_JUNIOR_POLICY, JUNIOR_THREE_ROUND_POLICY } from '../../supabase/functions/chemistry-access/junior-daily-policy'
import { juniorDailyBudgetReached, juniorReserveAllocationDeferred, nextJuniorOptionBranch, selectJuniorScheduledQuestion, type JuniorOptionBranch, type JuniorOptionState } from '../../supabase/functions/chemistry-access/junior-option-practice'
import type { JuniorAdaptiveCandidate, JuniorAdaptiveHistory } from '../../supabase/functions/chemistry-access/junior-adaptive'

const candidate = (id: string): JuniorAdaptiveCandidate => ({ id, mother_id: `m-${id}`, skill_id: 'oxygen', knowledge_id: 'oxygen',
  same_type_key: 'peroxide-condition', source_item_key: `s-${id}`, parent_source_item_key: `p-${id}`, content_fingerprint: `f-${id}`, level: 1 })
const history = (id: string): JuniorAdaptiveHistory => ({ ...candidate(id), question_id: id, correct: false, answered_at: '2026-09-28T02:00:00Z' })
const branch = (round: number, id: string): JuniorOptionBranch => ({ branchId: id, anchorStepId: `anchor-${id}`, anchorSessionId: 's',
  knowledgeId: 'oxygen', knowledgePoint: '过氧化氢分解的条件', optionIndex: 1, status: 'practicing', reason: '', answered: 0, correct: 0, total: 3,
  candidates: [], nextQuestionId: `next-${id}`, nextRevisionToken: 'r', recoveryRound: round })
const state = (branches: JuniorOptionBranch[], dailyIssuedCount = 8): JuniorOptionState => ({ branches, stepContexts: [], dailyIssuedCount })

describe('junior first-eight and three recovery rounds', () => {
  it('keeps historical sessions on their persisted 12/15 policy and rejects drift', () => {
    expect(juniorDailyPolicy({ question_count: 12, round_limit: 1 }, { initial_question_target: 12, hard_question_cap: 15 })).toEqual(LEGACY_JUNIOR_POLICY)
    expect(juniorDailyPolicy({ question_count: 8, round_limit: 4 }, { initial_question_target: 8, hard_question_cap: 30, recovery_round_limit: 3 })).toEqual(JUNIOR_THREE_ROUND_POLICY)
    expect(() => juniorDailyPolicy({ question_count: 8, round_limit: 4 }, { initial_question_target: 12, hard_question_cap: 15 })).toThrow()
    expect(() => juniorDailyPolicy({ question_count: 8, round_limit: 3 })).toThrow()
  })
  it('finishes eight ordinary originals before starting a recovery branch', () => {
    expect(nextJuniorOptionBranch(state([branch(1, 'b')]), 7, JUNIOR_THREE_ROUND_POLICY)).toBeNull()
    expect(nextJuniorOptionBranch(state([branch(1, 'b')]), 8, JUNIOR_THREE_ROUND_POLICY)?.branchId).toBe('b')
    const issued = Array.from({ length: 8 }, (_, i) => history(`old-${i}`))
    expect(selectJuniorScheduledQuestion({ candidates: [candidate('new')], knowledgeSkillIds: ['oxygen'], history: issued,
      issued, optionState: state([]), policy: JUNIOR_THREE_ROUND_POLICY })).toBeNull()
  })
  it.each(['all wrong', 'all correct', 'mixed'])('balances the first eight across all three oxygen groups even when %s', (answers) => {
    const skills = ['J_KY_OXY_H2O2', 'J_KY_OXY_KMNO4', 'J_KY_OXY_SYMBOLS']
    const candidates = skills.flatMap((skill) => Array.from({ length: 8 }, (_, i) => ({ ...candidate(`${skill}-${i}`),
      skill_id: skill, knowledge_id: skill, level: i < 5 ? 1 : 2 })))
    const issued: JuniorAdaptiveHistory[] = []
    for (let i = 0; i < 8; i += 1) {
      const selected = selectJuniorScheduledQuestion({ candidates, knowledgeSkillIds: skills, history: issued, issued,
        optionState: state([], i), policy: JUNIOR_THREE_ROUND_POLICY })!
      expect(selected).not.toBeNull()
      issued.push({ ...selected.question, question_id: selected.question.id, answered_at: '2026-09-28T10:00:00Z',
        correct: answers === 'all correct' || (answers === 'mixed' && i % 2 === 0) })
    }
    expect(skills.map((skill) => issued.filter((q) => q.knowledge_id === skill).length)).toEqual([3, 3, 2])
    expect(new Set(issued.map((q) => q.parent_source_item_key)).size).toBe(8)
  })
  it('orders child recovery after all available prior-round branches and never opens a fourth round', () => {
    const queue = state([branch(3, 'third'), branch(2, 'second'), branch(1, 'first'), branch(4, 'invalid')])
    expect(nextJuniorOptionBranch(queue, 8, JUNIOR_THREE_ROUND_POLICY)?.branchId).toBe('first')
    queue.branches.find((b) => b.branchId === 'first')!.status = 'consolidated'
    expect(nextJuniorOptionBranch(queue, 11, JUNIOR_THREE_ROUND_POLICY)?.branchId).toBe('second')
    expect(nextJuniorOptionBranch(state([branch(4, 'fourth')]), 29, JUNIOR_THREE_ROUND_POLICY)).toBeNull()
  })
  it('stops at the shared daily budget, including when this session has fewer than eight questions', () => {
    expect(nextJuniorOptionBranch(state([branch(1, 'b')], 30), 8, JUNIOR_THREE_ROUND_POLICY)).toBeNull()
    expect(nextJuniorOptionBranch(state([branch(1, 'b')], 29), 30, JUNIOR_THREE_ROUND_POLICY)).toBeNull()
    expect(selectJuniorScheduledQuestion({ candidates: [candidate('new')], knowledgeSkillIds: ['oxygen'], history: [],
      issued: [], optionState: state([], 30), policy: JUNIOR_THREE_ROUND_POLICY })).toBeNull()
  })
  it('defers freezing repair reserves until the eight ordinary answers are complete, without changing legacy sessions', () => {
    expect(juniorReserveAllocationDeferred(JUNIOR_THREE_ROUND_POLICY, 7)).toBe(true)
    expect(juniorReserveAllocationDeferred(JUNIOR_THREE_ROUND_POLICY, 8)).toBe(false)
    expect(juniorReserveAllocationDeferred(LEGACY_JUNIOR_POLICY, 0)).toBe(false)
  })
  it('keeps an opted-in student under the shared cap even when making up an old 12/15 session', () => {
    const old = { ...state([branch(1, 'old')], 30), dailyBudgetEnabled: true }
    expect(juniorDailyBudgetReached(old, LEGACY_JUNIOR_POLICY)).toBe(true)
    expect(nextJuniorOptionBranch(old, 3, LEGACY_JUNIOR_POLICY)).toBeNull()
    expect(selectJuniorScheduledQuestion({ candidates: [candidate('new')], knowledgeSkillIds: ['oxygen'], history: [],
      issued: [], optionState: old, policy: LEGACY_JUNIOR_POLICY })).toBeNull()
    expect(juniorDailyBudgetReached(state([], 30), LEGACY_JUNIOR_POLICY)).toBe(false)
  })
  it('allows only phase waits to become active during teacher replay, preserving reserve and daily gaps', () => {
    const waits = ['initial_round_in_progress', 'waiting_for_previous_recovery_round']
    for (const reason of waits) expect(nextJuniorOptionBranch(state([{ ...branch(1, 'b'), status: 'pending', reason }]), 8, JUNIOR_THREE_ROUND_POLICY)?.branchId).toBe('b')
    for (const reason of ['daily_limit_carry_forward', 'waiting_for_compatible_curriculum']) {
      expect(nextJuniorOptionBranch(state([{ ...branch(1, 'b'), status: 'pending', reason }]), 8, JUNIOR_THREE_ROUND_POLICY)).toBeNull()
    }
    expect(nextJuniorOptionBranch(state([{ ...branch(1, 'b'), status: 'reserve_gap' }]), 8, JUNIOR_THREE_ROUND_POLICY)).toBeNull()
  })
})
