import type { LearningPlanDay } from './types'

/** Only today or the earliest future date can be the primary task. */
export function selectFocusPlan(plans: LearningPlanDay[], today: string) {
  return plans.find((plan) => plan.date === today)
    ?? plans.filter((plan) => plan.date > today).sort((a, b) => a.date.localeCompare(b.date))[0]
}
