import type { LearningPlanDay } from './types'

/** Keep today's assignment visible; otherwise help the student resume the oldest unfinished plan. */
export function selectFocusPlan(plans: LearningPlanDay[], today: string) {
  return plans.find((plan) => plan.date === today)
    ?? plans.filter((plan) => plan.date < today && !plan.isComplete).sort((a, b) => a.date.localeCompare(b.date))[0]
    ?? plans.filter((plan) => plan.date > today).sort((a, b) => a.date.localeCompare(b.date))[0]
}
