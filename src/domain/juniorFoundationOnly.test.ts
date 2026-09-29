import { describe, expect, it } from 'vitest'
import { juniorRouteFoundationOnly, juniorRouteInventoryReadiness, selectJuniorScheduledQuestion, type JuniorPracticeAvailability } from '../../supabase/functions/chemistry-access/junior-option-practice'
import type { JuniorAdaptiveCandidate, JuniorAdaptiveHistory } from '../../supabase/functions/chemistry-access/junior-adaptive'

const skills = ['J_KY_1_1_K01', 'J_KY_1_1_K02', 'J_KY_1_1_K03']
const make = (id: string, skill: string, level = 1): JuniorAdaptiveCandidate => ({ id, skill_id: skill, knowledge_id: skill, level, mother_id: `M${id}`, source_item_key: `S${id}`, parent_source_item_key: `P${id}`, content_fingerprint: `F${id}`, same_type_key: 'micro' })
const answer = (q: JuniorAdaptiveCandidate): JuniorAdaptiveHistory => ({ ...q, question_id: q.id, correct: true, uncertain: false, answered_at: '2026-09-29T01:00:00Z' })
const base = { knowledgeSkillIds: skills, history: [], issued: [] as JuniorAdaptiveHistory[], optionState: { branches: [], stepContexts: [] }, policy: { initialTarget: 8, hardCap: 30, recoveryRoundLimit: 3 } as const }
const availability = (qs: JuniorAdaptiveCandidate[], policy: JuniorPracticeAvailability['policy'] = 'spaced_review'): JuniorPracticeAvailability => ({ policy, questions: Object.fromEntries(qs.map(q => [q.id, { eligible: true, kind: 'fresh' }])) })

describe('reviewed introductory foundation-only routes', () => {
  it('uses the release inventory boundary: seven independent L1 parents, never seven subquestions of six parents', () => {
    for (const skill of skills) {
      const qs = Array.from({ length: 7 }, (_, i) => make(`inventory-${i}`, skill));
      expect(juniorRouteInventoryReadiness(qs, skill, '科粤版').ready).toBe(true);
      expect(juniorRouteInventoryReadiness(qs.slice(0, 6), skill, '科粤版').ready).toBe(false);
      qs[6].parent_source_item_key = qs[5].parent_source_item_key;
      expect(juniorRouteInventoryReadiness(qs, skill, '科粤版').ready).toBe(false);
    }
  });
  it('keeps all other calendar routes at five foundation plus two higher independent parents', () => {
    const other = ['J_KY_LAB_BASICS', 'J_KY_CHANGE_PROPERTY', 'J_KY_PARTICLES', 'J_KY_ELEMENTS',
      'J_KY_AIR', 'J_KY_OXY_PROPERTIES', 'J_KY_OXY_H2O2', 'J_KY_OXY_KMNO4', 'J_KY_OXY_SYMBOLS',
      'J_KY_WATER', 'J_KY_FORMULA', 'J_KY_COMBUSTION', 'J_KY_CONSERVATION', 'J_KY_EQUATIONS'];
    for (const skill of other) {
      const qs = Array.from({ length: 7 }, (_, i) => make(`inventory-${i}`, skill, i < 5 ? 1 : 2));
      expect(juniorRouteInventoryReadiness(qs, skill, '科粤版').ready).toBe(true);
      expect(juniorRouteInventoryReadiness(qs.map(q => ({ ...q, level: 1 })), skill, '科粤版').ready).toBe(false);
      expect(juniorRouteInventoryReadiness(qs.slice(0, 6), skill, '科粤版').ready).toBe(false);
    }
    expect(juniorRouteInventoryReadiness(Array.from({ length: 7 }, (_, i) => make(`wrong-book-${i}`, skills[0])), skills[0], 'other').ready).toBe(false);
  });
  it('restricts the exception to exactly the three opted-in introductory routes', () => {
    for (const s of skills) expect(juniorRouteFoundationOnly(s, 'spaced_review')).toBe(true)
    expect(juniorRouteFoundationOnly('J_KY_LAB_BASICS', 'spaced_review')).toBe(false)
    expect(juniorRouteFoundationOnly('J_KY_1_1_K04', 'spaced_review')).toBe(false)
    expect(juniorRouteFoundationOnly(skills[0], 'fresh_only')).toBe(false)
    expect(juniorRouteFoundationOnly(skills[0], undefined)).toBe(false)
  })
  it('delivers exactly eight independent L1 originals, even if a caller accidentally supplies L2', () => {
    const candidates = skills.flatMap((s, i) => [...Array.from({ length: 7 }, (_, j) => make(`${i}-${j}`, s)), make(`${i}-L2`, s, 2)])
    const issued: JuniorAdaptiveHistory[] = []
    for (let i = 0; i < 8; i++) {
      const result = selectJuniorScheduledQuestion({ ...base, candidates, issued, availability: availability(candidates) })
      expect(result?.question.level).toBe(1)
      expect(issued.some(r => r.parent_source_item_key === result?.question.parent_source_item_key)).toBe(false)
      issued.push(answer(result!.question))
    }
    expect(selectJuniorScheduledQuestion({ ...base, candidates, issued, availability: availability(candidates) })).toBeNull()
    expect(new Set(issued.map(r => r.knowledge_id)).size).toBe(3)
  })
  it('does not fill an exhausted foundation pool with a mislabelled higher-level question', () => {
    const higher = make('only-higher', skills[0], 2)
    expect(selectJuniorScheduledQuestion({ ...base, candidates: [higher], availability: availability([higher]) })).toBeNull()
  })
  it('keeps old fresh-only sessions and other routes at their existing 2-foundation-then-higher policy', () => {
    for (const [skill, policy] of [[skills[0], 'fresh_only'], ['J_KY_LAB_BASICS', 'spaced_review']] as const) {
      const old = [make('used1', skill), make('used2', skill)], candidates = [make('new1', skill), make('new2', skill, 2)]
      const result = selectJuniorScheduledQuestion({ ...base, knowledgeSkillIds: [skill], issued: old.map(answer), candidates, availability: availability(candidates, policy) })
      expect(result?.question.level).toBe(2)
    }
  })
})
