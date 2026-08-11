import type { LearningAttempt, LearningPlanDay } from './types'

export type PlanDayStatus = 'before_enrollment' | 'scheduled' | 'completed' | 'completed_early' | 'reviewed'

export function planDayStatus(plan: LearningPlanDay, enrollmentStartDate: string, attempts: LearningAttempt[], today: string): PlanDayStatus {
  if (plan.date < enrollmentStartDate) return 'before_enrollment'
  const dayAttempts = attempts.filter((attempt) => attempt.planDayId === plan.id)
  const scheduled = dayAttempts.find((attempt) => attempt.attemptKind === 'scheduled')
  if (scheduled) return plan.date > scheduled.completedAt.slice(0, 10) ? 'completed_early' : 'completed'
  if (dayAttempts.some((attempt) => attempt.attemptKind === 'review')) return 'reviewed'
  void today
  return 'scheduled'
}

export function appendAttempt(existing: LearningAttempt[], next: LearningAttempt): LearningAttempt[] {
  const scheduled = existing.find((attempt) => attempt.planDayId === next.planDayId && attempt.attemptKind === 'scheduled')
  if (!scheduled) return [...existing, next]
  const reviewSequence = existing.filter((attempt) => attempt.planDayId === next.planDayId).length
  return [...existing, { ...next, attemptKind: 'review' as const, sequence: reviewSequence }]
}

export function scoreComparison(attempts: LearningAttempt[], planDayId: string) {
  const relevant = attempts.filter((attempt) => attempt.planDayId === planDayId)
  if (!relevant.length) return null
  const first = relevant.find((attempt) => attempt.attemptKind === 'scheduled') ?? relevant[0]
  const latest = relevant[relevant.length - 1]
  return { first: first.firstScore, latest: latest.firstScore, improvedBy: latest.firstScore - first.firstScore }
}
