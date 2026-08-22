export const FORMAL_REVIEW_DAILY_QUESTION_CAP = 8
export const FORMAL_REVIEW_ONE_PACKAGE_CUTOVER_DATE = '2026-08-23'

const HIGH_SCHOOL_GRADES = new Set(['高一', '高二', '高三'])

export type ReviewDeliveryContext = {
  mode: string
  gradeBand: string
  isDemo: boolean
  questionCount: number
  storedRoundLimit: number
}

export type ReviewTargetEvidence = {
  conceptKey?: string | null
  skillId?: string | null
  correct: boolean
  uncertain?: boolean | null
  questionLevel?: number | null
}

export function isFormalHighSchoolReview(context: Pick<ReviewDeliveryContext, 'mode' | 'gradeBand' | 'isDemo'>) {
  return context.mode === 'REVIEW'
    && HIGH_SCHOOL_GRADES.has(context.gradeBand)
    && !context.isDemo
}

/**
 * The stored plan is the cut-over marker. The migration changes only unstarted
 * formal plans to one package; historical five-round evidence keeps its
 * original interpretation in dashboards and teacher preview.
 */
export function effectiveReviewRoundLimit(context: ReviewDeliveryContext) {
  return context.storedRoundLimit
}

export function validFormalReviewRoundLimit(
  context: Pick<ReviewDeliveryContext, 'mode' | 'gradeBand' | 'isDemo' | 'storedRoundLimit'> & {
    planDate?: string | null
    hasExistingAttempt?: boolean
  },
) {
  if (!isFormalHighSchoolReview(context) || context.storedRoundLimit === 1) return true
  if (context.storedRoundLimit !== 5) return false
  // Keep old evidence readable and let a learner finish an already-started
  // five-round plan. Only a never-started plan on/after the cut-over is
  // required to carry the new persisted one-package marker.
  if (context.hasExistingAttempt === true) return true
  return Boolean(context.planDate && context.planDate < FORMAL_REVIEW_ONE_PACKAGE_CUTOVER_DATE)
}

export function validFormalReviewQuestionCount(context: Pick<ReviewDeliveryContext, 'mode' | 'gradeBand' | 'isDemo' | 'questionCount'>) {
  return !isFormalHighSchoolReview(context)
    || (Number.isInteger(context.questionCount)
      && context.questionCount >= 1
      && context.questionCount <= FORMAL_REVIEW_DAILY_QUESTION_CAP)
}

/**
 * Keeps every wrong/uncertain fine concept before classroom/progression
 * targets. A concept is emitted once, and the exact plan size remains bounded.
 * Stable input order is intentional: the database personalizer supplies the
 * latest evidence first, then the learner's own progress fallback, then the
 * next classroom sequence.
 */
export function prioritizeNextReviewTargets(
  evidence: ReviewTargetEvidence[],
  fallbackConceptKeys: string[],
  limit: number,
) {
  const result: string[] = []
  const seen = new Set<string>()
  const append = (value: unknown) => {
    const conceptKey = String(value || '').trim()
    if (!conceptKey || seen.has(conceptKey) || result.length >= limit) return
    seen.add(conceptKey)
    result.push(conceptKey)
  }

  for (const answer of evidence) {
    if (answer.correct === true && answer.uncertain !== true) continue
    append(answer.conceptKey)
  }
  for (const conceptKey of fallbackConceptKeys) append(conceptKey)
  return result
}
