import { describe, expect, it } from 'vitest'
import {
  issuedSolutionFields,
  issuedAssetRefs,
  matchingSourceAssetRef,
  shouldHideLicensedHighSchoolSolution,
  sourceAssetPhaseStatus,
  sourceQuestionPhaseStatus,
} from '../../supabase/functions/chemistry-access/source-security'

describe('high-school licensed answer-delivery security', () => {
  it.each(['高一', '高二', '高三'])('omits answer and explanation fields from the initial %s REVIEW question payload', (gradeBand) => {
    const row = {
      grade_band: gradeBand,
      source_kind: 'licensed_local',
      correct_option: 2,
      explanation: '原题解析',
      scaffold: '提示',
    }
    const hide = shouldHideLicensedHighSchoolSolution(row, true)
    const initialPayload = JSON.parse(JSON.stringify({ id: 'q1', ...issuedSolutionFields(row, hide) })) as Record<string, unknown>
    expect(Object.keys(initialPayload)).toEqual(['id'])
    expect(initialPayload).not.toHaveProperty('correctOption')
    expect(initialPayload).not.toHaveProperty('explanation')
    expect(initialPayload).not.toHaveProperty('scaffold')
    const initialAssetRefs = JSON.parse(JSON.stringify(issuedAssetRefs([
      { kind: 'question_image', assetId: 'question' },
      { kind: 'analysis_image', assetId: 'analysis' },
    ], hide))) as Array<{ kind: string; assetId: string }>
    expect(initialAssetRefs).toEqual([{ kind: 'question_image', assetId: 'question' }])
  })

  it('keeps original analysis assets teacher-only at every learner phase', () => {
    expect(sourceAssetPhaseStatus({ phase: 'analysis', assetKind: 'analysis_image', role: 'student', hasCompletedAnswer: false })).toBe(403)
    expect(sourceAssetPhaseStatus({ phase: 'analysis', assetKind: 'analysis_image', role: 'student', hasCompletedAnswer: false, hasLockedAnswer: true })).toBe(403)
    expect(sourceAssetPhaseStatus({ phase: 'analysis', assetKind: 'analysis_image', role: 'student', hasCompletedAnswer: true })).toBe(403)
    expect(sourceAssetPhaseStatus({ phase: 'analysis', assetKind: 'analysis_image', role: 'guardian', hasCompletedAnswer: true })).toBe(403)
    expect(sourceAssetPhaseStatus({ phase: 'analysis', assetKind: 'analysis_image', role: 'teacher', hasCompletedAnswer: false })).toBe(200)
  })

  it('rejects a forged or mismatched phase', () => {
    expect(sourceAssetPhaseStatus({ phase: 'solution', assetKind: 'analysis_image', role: 'student', hasCompletedAnswer: true })).toBe(400)
    expect(sourceAssetPhaseStatus({ phase: 'question', assetKind: 'analysis_image', role: 'student', hasCompletedAnswer: true })).toBe(409)
    expect(sourceAssetPhaseStatus({ phase: 'analysis', assetKind: 'question_image', role: 'student', hasCompletedAnswer: true })).toBe(409)
  })

  it('denies a forwarded question asset unless it is in this student current issued set', () => {
    expect(sourceQuestionPhaseStatus({ role: 'student', hasCompletedAnswer: false, isExpectedCurrentQuestion: true, revisionMatches: true })).toBe(200)
    expect(sourceQuestionPhaseStatus({ role: 'student', hasCompletedAnswer: false, isExpectedCurrentQuestion: false, revisionMatches: true })).toBe(403)
    expect(sourceQuestionPhaseStatus({ role: 'student', hasCompletedAnswer: false, isExpectedCurrentQuestion: true, revisionMatches: false })).toBe(403)
    expect(sourceQuestionPhaseStatus({ role: 'guardian', hasCompletedAnswer: false, isExpectedCurrentQuestion: true, revisionMatches: true })).toBe(403)
    expect(sourceQuestionPhaseStatus({ role: 'guardian', hasCompletedAnswer: true, isExpectedCurrentQuestion: false, revisionMatches: false })).toBe(200)
  })

  it('authorizes retired history from the immutable snapshot descriptor, not a changed current ref', () => {
    const asset = { asset_kind: 'analysis_image', sha256: 'a'.repeat(64), width: 900, height: 700 }
    const snapshotRefs = [{ path: 'private/history/analysis-q1', kind: 'analysis_image', sha256: 'a'.repeat(64), width: 900, height: 700 }]
    expect(matchingSourceAssetRef(snapshotRefs, 'private/history/analysis-q1', asset)).toEqual(snapshotRefs[0])
    expect(matchingSourceAssetRef([{ ...snapshotRefs[0], sha256: 'b'.repeat(64) }], 'private/history/analysis-q1', asset)).toBeNull()
    expect(matchingSourceAssetRef(snapshotRefs, 'private/current/different-q1', asset)).toBeNull()
  })
})
