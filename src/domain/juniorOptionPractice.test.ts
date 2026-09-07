import { describe, expect, it } from 'vitest'
import { juniorOptionContext, juniorPublicOptionProgress, nextJuniorOptionBranch, selectJuniorScheduledQuestion, type JuniorOptionBranch, type JuniorOptionState } from '../../supabase/functions/chemistry-access/junior-option-practice'
import type { JuniorAdaptiveCandidate, JuniorAdaptiveHistory } from '../../supabase/functions/chemistry-access/junior-adaptive'
import queueSql from '../../supabase/migrations/20260907174213_junior_strict_option_practice_queue.sql?raw'

const make = (id: string, skill = 'K03', level = 1): JuniorAdaptiveCandidate => ({ id, mother_id: `M${id}`, skill_id: skill, knowledge_id: skill, source_item_key: `S${id}`, parent_source_item_key: `P${id}`, content_fingerprint: `F${id}`, same_type_key: 'coarse-route', level })
const branch: JuniorOptionBranch = { branchId: 'private-branch', anchorStepId: 'opaque-step', anchorSessionId: 'private-session', knowledgeId: 'K03', knowledgePoint: '源头减污', optionIndex: 1, status: 'practicing', reason: '', answered: 0, correct: 0, total: 3,
  candidates: [{ questionId: 'reserve1', revisionToken: 'r1' },{ questionId: 'reserve2', revisionToken: 'r2' },{ questionId: 'reserve3', revisionToken: 'r3' }], nextQuestionId: 'reserve1', nextRevisionToken: 'r1' }
const state: JuniorOptionState = { branches: [branch], stepContexts: [{ stepId: 'opaque-reserve-step', branchId: branch.branchId, position: 1 }] }
const history = (q: JuniorAdaptiveCandidate): JuniorAdaptiveHistory => ({ ...q, question_id: q.id, correct: false, uncertain: false, answered_at: '2026-09-12T01:00:00Z' })

describe('strict junior option practice integration', () => {
  it('exposes only opaque step context and instructional progress, with no source or library identities', () => {
    const publicResult = { progress: juniorPublicOptionProgress(state), context: juniorOptionContext(state, 'opaque-reserve-step') }
    expect(publicResult.context).toEqual({ anchorStepId: 'opaque-step', knowledgePoint: '源头减污', optionIndex: 1, position: 1, total: 3 })
    expect(JSON.stringify(publicResult)).not.toMatch(/private-|reserve[123]|revisionToken|candidates|nextQuestionId/)
  })
  it('keeps the ordered frozen branch at 14 questions and stops at 15 without changing its state', () => {
    expect(nextJuniorOptionBranch(state,14)).toBe(branch)
    expect(nextJuniorOptionBranch(state,15)).toBeNull()
    expect(branch.answered).toBe(0)
    expect(branch.candidates).toHaveLength(3)
    expect(nextJuniorOptionBranch({ ...state, branches: [{ ...branch, status: 'pending', reason: 'daily_limit_carry_forward' }] },0)).toBeNull()
  })
  it('excludes reserved originals and identity clones from ordinary practice without broad error repair', () => {
    const reserve = make('reserve1')
    const clone = { ...make('clone'), parent_source_item_key: reserve.parent_source_item_key }
    const question = make('ordinary')
    const result = selectJuniorScheduledQuestion({ candidates: [reserve,clone,question], knowledgeSkillIds: ['K03'], history: [], issued: [], optionState: state })
    expect(result?.question.id).toBe('ordinary')
    expect(result?.routeKind).toBe('new_learning')
  })
  it('does not turn an unbound wrong option into another broad K03 repair or routine extra question', () => {
    const issued = Array.from({length:12},(_,i)=>history(make(`old${i}`)))
    expect(selectJuniorScheduledQuestion({ candidates:[make('unused')],knowledgeSkillIds:['K03'],history:issued,issued,optionState:{...state,branches:[{...branch,status:'reserve_gap',candidates:[]}]}})).toBeNull()
  })
  it('retains all five history exclusions, even when a new question id is assigned', () => {
    const old = make('old')
    const variants = ['mother_id','source_item_key','parent_source_item_key','content_fingerprint'].map((key,i)=>({...make(`clone${i}`),[key]:old[key as keyof JuniorAdaptiveCandidate]})) as JuniorAdaptiveCandidate[]
    expect(selectJuniorScheduledQuestion({candidates:[old,...variants],knowledgeSkillIds:['K03'],history:[history(old)],issued:[],optionState:{branches:[],stepContexts:[]}})).toBeNull()
  })
  it('leaves strict snapshot and 12/15 completion checks in the transactional finalizer and gates mastery by branches', () => {
    expect(queueSql).toContain("v_total not between v_session.initial_question_target and v_session.hard_question_cap")
    expect(queueSql).toContain("b.status <> 'consolidated'")
    expect(queueSql).toContain('public.chem_junior_issue_step(p_session_id,p_student_id,p_question_id,p_sequence,p_route_kind,p_route_reason,p_question_snapshot)')
    expect(queueSql).toContain("st.correct=false and os.position<=3")
    expect(queueSql).toContain("greatest(3,least(5,jsonb_array_length(branch.candidates)))")
    expect(queueSql).toContain("daily_limit_carry_forward")
    expect(queueSql).toContain("not exists(select 1 from app_private.chem_junior_option_steps os where os.step_id=st.id)")
  })
})
