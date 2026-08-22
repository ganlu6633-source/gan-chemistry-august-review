export type SourceAssetPhase = 'question' | 'analysis'

export function shouldHideLicensedHighSchoolSolution(row: Record<string, unknown>, reviewMode: boolean) {
  return reviewMode
    && ['高一', '高二', '高三'].includes(String(row.grade_band))
    && row.source_kind === 'licensed_local'
}

export function issuedSolutionFields(row: Record<string, unknown>, hideSolution: boolean) {
  if (hideSolution) return {}
  return {
    correctOption: row.correct_option,
    explanation: row.explanation,
    scaffold: row.scaffold,
  }
}

export function issuedAssetRefs<T extends { kind: string }>(refs: T[], hideSolution: boolean) {
  // Original worked-solution scans are teacher-audit evidence, never learner
  // content. Students and guardians receive the option-by-option text written
  // for this system, so analysis refs are filtered even after submission.
  void hideSolution
  return refs.filter((ref) => ref.kind !== 'analysis_image')
}

export function matchingSourceAssetRef(
  value: unknown,
  assetId: string,
  asset: Record<string, unknown>,
) {
  if (!Array.isArray(value)) return null
  return value.find((candidate) => {
    if (!candidate || typeof candidate !== 'object' || Array.isArray(candidate)) return false
    const reference = candidate as Record<string, unknown>
    return String(reference.path || '') === assetId
      && String(reference.kind || '') === String(asset.asset_kind || '')
      && String(reference.sha256 || '') === String(asset.sha256 || '')
      && Number(reference.width) === Number(asset.width)
      && Number(reference.height) === Number(asset.height)
  }) as Record<string, unknown> | undefined || null
}

export function sourceAssetPhaseStatus(input: {
  phase: string
  assetKind: string
  role: 'student' | 'guardian' | 'teacher'
  hasCompletedAnswer: boolean
  hasLockedAnswer?: boolean
}) {
  if (input.phase !== 'question' && input.phase !== 'analysis') return 400
  const isAnalysis = input.assetKind === 'analysis_image'
  if ((input.phase === 'question' && isAnalysis) || (input.phase === 'analysis' && !isAnalysis)) return 409
  if (isAnalysis && input.role !== 'teacher') return 403
  return 200
}

export function sourceQuestionPhaseStatus(input: {
  role: 'student' | 'guardian' | 'teacher'
  hasCompletedAnswer: boolean
  isExpectedCurrentQuestion: boolean
  revisionMatches: boolean
}) {
  if (input.role === 'teacher' || input.hasCompletedAnswer) return 200
  if (input.role === 'guardian') return 403
  return input.isExpectedCurrentQuestion && input.revisionMatches ? 200 : 403
}
