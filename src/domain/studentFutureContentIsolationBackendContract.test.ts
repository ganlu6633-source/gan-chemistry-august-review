import { describe, expect, it } from 'vitest'

import accessSource from '../../supabase/functions/chemistry-access/index.ts?raw'

const learningRecord = accessSource.slice(
  accessSource.indexOf('async function studentLearningRecord'),
  accessSource.indexOf('function isJuniorAdaptivePlan'),
)
const dashboardPlanShape = accessSource.slice(
  accessSource.indexOf('function studentDashboardPlanShape'),
  accessSource.indexOf('async function studentDashboard'),
)
const dashboard = accessSource.slice(
  accessSource.indexOf('async function studentDashboard'),
  accessSource.indexOf('async function guardianDashboard'),
)
const juniorPlanShape = accessSource.slice(
  accessSource.indexOf('function juniorStudentPlanShape'),
  accessSource.indexOf('function planTargetConceptKeys'),
)

describe('student future-content isolation', () => {
  it('does not treat the whole junior catalogue or an untouched L0 state as learned', () => {
    expect(accessSource).not.toContain('gradeBand === "初三" || gradeBand === "高二"')
    expect(accessSource).toContain('gradeBand !== "初三" || Number(state.verified_level) > 0 || state.last_reviewed_at')
  })

  it('unlocks junior record cards only after a reached formal route and current provenance', () => {
    expect(learningRecord).toContain('const juniorContentReachedIds = gradeBand === "初三"')
    expect(learningRecord).toContain('String(plan.plan_date || "") <= today')
    expect(learningRecord).toContain('plan.delivery_mode === "junior_adaptive"')
    expect(learningRecord).toContain('Boolean(plan.junior_curriculum_day_id)')
    expect(learningRecord).toContain('juniorIndividuallyVerifiedProvenanceIds(')
    expect(accessSource).toContain('for (const batch of juniorProvenanceBatches(skillIds))')
    expect(accessSource).toContain('for (const skillId of releaseByKnowledge.keys()) readyIds.add(skillId)')
    expect(learningRecord).toContain('const contentReached = gradeBand === "初三" ? juniorContentReadyIds.has(skillId) : isLearned')
    expect(learningRecord).toContain('knowledgeSections: contentReached ? studentLearningRecordKnowledgeSections(cards) : []')
  })

  it('applies the provenance-free allowlist and scanner to every returned record card', () => {
    expect(accessSource).toContain('if (!validOptionalStructuredKnowledgeContent(structured)) return []')
    expect(accessSource).toContain('if (!isPlainRecord(value)) return false')
    expect(accessSource).toContain('const shaped = studentProvenanceFreeCardShape(card)')
    expect(accessSource).toContain('studentInstructionalCardTextIsSafe(shaped) ? [shaped] : []')
    expect(learningRecord).toContain('futurePreviewInstructionalTextIsSafe([topic])')
    expect(learningRecord).toContain('futurePreviewInstructionalTextIsSafe([nextPlanRow.title])')
    expect(learningRecord).toContain('gradeBand === "初三" && !juniorStudentVisibleSourceTextIsSafe')
  })

  it('removes source from every junior dashboard row and replaces unsafe copy before rendering', () => {
    expect(dashboardPlanShape).toContain('profile.gradeBand === "初三" || row.delivery_mode === "junior_adaptive"')
    expect(dashboardPlanShape).toContain('return juniorStudentPlanShape(row, attemptRows, juniorSession, profile)')
    expect(dashboardPlanShape).toContain('String(row.plan_date || "") <= shanghaiDate()')
    expect(juniorPlanShape).toContain('filter(([key]) => key !== "source")')
    expect(juniorPlanShape).toContain('futurePreviewInstructionalTextIsSafe([withoutSource.title, withoutSource.knowledgeSummaries])')
    expect(juniorPlanShape).toContain('title: "初三学习计划（内容清理中）", knowledgeSummaries: []')
    expect(dashboard).toContain('plans.map((plan) => studentDashboardPlanShape(')
  })
})
