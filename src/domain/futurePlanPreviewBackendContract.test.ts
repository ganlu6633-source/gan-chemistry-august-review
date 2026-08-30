import { describe, expect, it } from 'vitest'
import accessSource from '../../supabase/functions/chemistry-access/index.ts?raw'

const previewFunction = accessSource.slice(
  accessSource.indexOf('async function futurePlanPreviewPayload'),
  accessSource.indexOf('async function studentDashboard'),
)
const juniorPlanShape = accessSource.slice(
  accessSource.indexOf('function juniorStudentPlanShape'),
  accessSource.indexOf('function planTargetConceptKeys'),
)

describe('future plan preview backend contract', () => {
  it('requires plan ownership, a future date, an active profile and approved knowledge cards', () => {
    expect(previewFunction).toContain('.eq("id", planId).eq("student_id", studentId)')
    expect(previewFunction).toContain('String(profile.record_status) !== "active"')
    expect(previewFunction).toContain('planDate <= shanghaiDate()')
    expect(previewFunction).toContain('.eq("review_status", "approved")')
    expect(previewFunction).toContain('length !== 1')
  })

  it('validates the junior textbook/curriculum match before showing cards', () => {
    expect(previewFunction).toContain('String(profile.grade_band) === "初三"')
    expect(previewFunction).toContain('!isJuniorAdaptivePlan(plan)')
    expect(previewFunction).toContain('textbookVersion !== JUNIOR_TEXTBOOK_VERSION')
    expect(previewFunction).toContain('.eq("textbook_version", JUNIOR_TEXTBOOK_VERSION).eq("release_status", "ready")')
    expect(previewFunction).toContain('juniorExactStringArray(curriculum.knowledge_skill_ids, skillIds)')
    expect(previewFunction).toContain('juniorVerifiedProvenance(skillIds, JUNIOR_TEXTBOOK_VERSION)')
    expect(previewFunction).toContain('if (!provenance.ready)')
  })

  it('returns only a knowledge preview and performs no question, session or evidence writes', () => {
    expect(previewFunction).toContain('previewMode: "future_knowledge_only"')
    expect(previewFunction).toContain('recordsLearningEvidence: false')
    expect(previewFunction).toContain('includesQuestions: false')
    expect(previewFunction).not.toContain('chem_questions')
    expect(previewFunction).not.toContain('chem_junior_learning_sessions')
    expect(previewFunction).not.toContain('chem_attempts')
    expect(previewFunction).not.toMatch(/\.insert\(|\.upsert\(|\.update\(|\.rpc\(/)
  })

  it('never sends provenance labels, local source paths or card assets to the future preview', () => {
    expect(accessSource).toContain('futurePreviewStructuredContent')
    expect(accessSource).toContain('asset: undefined')
    expect(previewFunction).toContain('const shapedCards = orderedCards.map(studentProvenanceFreeCardShape)')
    expect(previewFunction).toContain('const shapedPlan = juniorStudentPlanShape(')
    expect(previewFunction).toContain('{ failClosedOnUnsafeCopy: true }')
    expect(juniorPlanShape).toContain('filter(([key]) => key !== "source")')
    expect(juniorPlanShape).toContain('withoutSource.title, withoutSource.knowledgeSummaries')
    expect(juniorPlanShape).toContain('futurePreviewInstructionalTextIsSafe')
    expect(previewFunction).toContain('仍含来源标签或本地定位信息')
    expect(previewFunction).toContain('plan: shapedPlan')
    expect(previewFunction).toContain('cards: shapedCards')
  })

  it('uses an instructional-field allowlist and a label-shaped provenance filter', () => {
    const shapeFunction = accessSource.slice(
      accessSource.indexOf('function futurePreviewStructuredContent'),
      accessSource.indexOf('const studentProvenanceFreeCardShape'),
    )
    for (const field of ['version', 'intro', 'sections', 'overview', 'visualSummary', 'rootTree', 'workedExamples', 'checkpoints', 'scopeNote']) {
      expect(shapeFunction).toContain(field)
    }
    for (const forbidden of ['imageUrl', 'uri', 'citation', 'publisher', 'document', 'drive', 'sourceBasis', 'reference']) {
      expect(shapeFunction).not.toContain(forbidden)
    }

    const match = accessSource.match(/const FUTURE_PREVIEW_PROVENANCE_LABEL_PATTERN = (\/.+\/iu);/)
    expect(match?.[1]).toBeTruthy()
    const pattern = Function(`return ${match![1]}`)() as RegExp
    for (const ordinaryInstruction of ['酸碱先看来源，再看去向。', '先找粒子来源。', '物料守恒的来源是化学式。', '中考冲刺', '期末复习']) {
      expect(pattern.test(ordinaryInstruction), ordinaryInstruction).toBe(false)
    }
    for (const provenanceLeak of ['来源：某教材第12页', '本卡来源：某教材', '（选自：2025年某卷）', 'SRC-383CD86AB9D081C8', 'D:\\\\private\\\\source.docx', 'https://example.com/source', JSON.stringify({ intro: '来源：某教材', scopeNote: '本卡来源：本地讲义' })]) {
      expect(pattern.test(provenanceLeak), provenanceLeak).toBe(true)
    }
    expect(accessSource).not.toContain('Object.values(value as Record<string, unknown>).forEach')
    expect(accessSource).toContain('const maxDepth = 16')
    expect(accessSource).toContain('const maxNodes = 5_000')
    expect(accessSource).toContain('const maxCollectionWidth = 500')
    expect(accessSource).toContain('const maxStringLength = 20_000')
    expect(accessSource).toContain('const maxTotalCharacters = 200_000')
    expect(accessSource).toContain('while (complete && stack.length > 0)')
    expect(accessSource).toContain('if (value.length > maxCollectionWidth)')
    expect(accessSource).toContain('complete = false')
    expect(accessSource).toContain('break')
    expect(accessSource).toContain('return scan.complete && !FUTURE_PREVIEW_PROVENANCE_LABEL_PATTERN.test(scan.text)')
  })
})
