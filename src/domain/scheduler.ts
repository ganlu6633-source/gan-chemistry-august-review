import type { LearningMode, QuestionCandidate } from './types'

export interface SchedulerContext {
  mode: LearningMode
  firstRoundTarget?: number
  hardLimit?: number
  alreadyUsedMotherIds: string[]
}

const REASON_WEIGHT: Record<QuestionCandidate['reason'], number> = {
  course_prerequisite: 50,
  exam_value: 45,
  memory_due: 35,
  recent_error: 40,
  level_validation: 30,
}

export function rankCandidate(candidate: QuestionCandidate, mode: LearningMode) {
  const modeBonus =
    mode === 'CLASS_QUIZ' && candidate.reason === 'course_prerequisite'
      ? 40
      : mode === 'EXAM_SPRINT' && candidate.reason === 'exam_value'
        ? 40
        : mode === 'REVIEW' && candidate.reason === 'memory_due'
          ? 25
          : 0
  return candidate.score + REASON_WEIGHT[candidate.reason] + modeBonus
}

export function selectFirstRound(candidates: QuestionCandidate[], context: SchedulerContext) {
  const target = Math.max(3, Math.min(context.firstRoundTarget ?? 6, 7))
  const hardLimit = Math.max(target, Math.min(context.hardLimit ?? 10, 10))
  const usedMotherIds = new Set(context.alreadyUsedMotherIds)
  const usedQuestionIds = new Set<string>()
  const selected: QuestionCandidate[] = []

  const sorted = [...candidates]
    .filter((candidate) => candidate.question.reviewStatus === 'approved')
    .filter((candidate) => candidate.question.scopeStatus !== 'OUT')
    .sort((a, b) => rankCandidate(b, context.mode) - rankCandidate(a, context.mode))

  for (const candidate of sorted) {
    if (selected.length >= target || selected.length >= hardLimit) break
    if (usedQuestionIds.has(candidate.question.id) || usedMotherIds.has(candidate.question.motherId)) continue
    selected.push(candidate)
    usedQuestionIds.add(candidate.question.id)
    usedMotherIds.add(candidate.question.motherId)
  }
  return selected
}

export function selectOptionalSecondRound(candidates: QuestionCandidate[], firstRound: QuestionCandidate[], max = 4) {
  const usedMotherIds = new Set(firstRound.map((candidate) => candidate.question.motherId))
  const usedQuestionIds = new Set(firstRound.map((candidate) => candidate.question.id))
  return candidates
    .filter((candidate) => candidate.question.reviewStatus === 'approved' && candidate.question.scopeStatus !== 'OUT')
    .filter((candidate) => !usedMotherIds.has(candidate.question.motherId) && !usedQuestionIds.has(candidate.question.id))
    .sort((a, b) => b.score - a.score)
    .slice(0, Math.max(0, Math.min(max, 4)))
}

export function enforceDailyBudget(firstRoundCount: number, optionalRoundCount: number, special = false) {
  const limit = special ? 10 : 8
  return Math.min(firstRoundCount + optionalRoundCount, limit)
}
