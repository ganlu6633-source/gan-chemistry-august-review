import { describe, expect, it } from 'vitest'
import { selectJuniorScheduledQuestion, type JuniorPracticeAvailability } from '../../supabase/functions/chemistry-access/junior-option-practice'
import type { JuniorAdaptiveCandidate, JuniorAdaptiveHistory } from '../../supabase/functions/chemistry-access/junior-adaptive'

const q = (id: string): JuniorAdaptiveCandidate => ({ id, mother_id:`M-${id}`, skill_id:'K', knowledge_id:'K', same_type_key:'micro', source_item_key:`S-${id}`, parent_source_item_key:`P-${id}`, content_fingerprint:`F-${id}`, level:1 })
const answer = (v:JuniorAdaptiveCandidate): JuniorAdaptiveHistory => ({ ...v, question_id:v.id, correct:true, uncertain:false, answered_at:'2026-09-01T01:00:00Z' })
const base = { knowledgeSkillIds:['K'], issued:[] as JuniorAdaptiveHistory[], optionState:{ branches:[],stepContexts:[] }, policy:{initialTarget:8,hardCap:30,recoveryRoundLimit:3} as const }
const availability = (questions:JuniorPracticeAvailability['questions']):JuniorPracticeAvailability => ({policy:'spaced_review',questions})

describe('explicit spaced review selector', () => {
  it('labels an actually due source as review and prefers it to a fresh source', () => {
    const old=q('old'),fresh=q('fresh')
    const result=selectJuniorScheduledQuestion({...base,candidates:[fresh,old],history:[answer(old)],availability:availability({old:{eligible:true,kind:'due_review',lastAnsweredDate:'2026-09-01'},fresh:{eligible:true,kind:'fresh'}})})
    expect(result?.question.id).toBe('old')
    expect(result?.routeKind).toBe('spaced_review')
    expect(result?.routeReason).toContain('2026-09-01')
  })
  it('retains lifetime exclusion for old sessions and fails closed on absent eligibility', () => {
    const old=q('old')
    expect(selectJuniorScheduledQuestion({...base,candidates:[old],history:[answer(old)]})).toBeNull()
    expect(selectJuniorScheduledQuestion({...base,candidates:[old],history:[],availability:availability({})})).toBeNull()
  })
  it('does not let an old plan date bypass not-yet-due or same-day evidence', () => {
    const old=q('old')
    expect(selectJuniorScheduledQuestion({...base,candidates:[old],history:[],availability:availability({old:{eligible:false,kind:'not_due',reviewDueDate:'2026-09-30'}})})).toBeNull()
  })
  it('never repeats a parent in the current first round, even with a different child ID', () => {
    const old=q('old'),clone={...q('clone'),parent_source_item_key:old.parent_source_item_key}
    expect(selectJuniorScheduledQuestion({...base,candidates:[clone],history:[],issued:[answer(old)],availability:availability({clone:{eligible:true,kind:'due_review'}})})).toBeNull()
  })
  it('respects the first-eight and all-entry actual-day thirty caps', () => {
    const fresh=q('fresh'),a=availability({fresh:{eligible:true,kind:'fresh'}})
    expect(selectJuniorScheduledQuestion({...base,candidates:[fresh],history:[],issued:Array.from({length:8},(_,i)=>answer(q(String(i)))),availability:a})).toBeNull()
    expect(selectJuniorScheduledQuestion({...base,candidates:[fresh],history:[],optionState:{branches:[],stepContexts:[],dailyIssuedCount:30},availability:a})).toBeNull()
  })
})
