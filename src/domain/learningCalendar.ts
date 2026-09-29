import type { LearningPlanDay } from './types'

export const isKnowledgeOnlyFuturePlan = (plan: LearningPlanDay, today: string) => plan.date > today && plan.canStudyAhead !== true

const isSingleReview = (plan: LearningPlanDay) => plan.mode === 'REVIEW' && plan.roundLimit === 1 && plan.deliveryMode !== 'junior_adaptive'

export function calendarPlanStatus(plan: LearningPlanDay, enrollment: string, today: string) {
  // Date and enrollment describe the schedule. Only actual attempts/session
  // state can say the student has started or completed this lesson.
  if (plan.deliveryMode === 'junior_adaptive') {
    if (plan.isComplete) return '学习已完成'
    if (plan.juniorSessionStatus === 'active') return '学习进行中 · 接着练'
    if (plan.juniorSessionStatus === 'blocked') return '进度已保留 · 题组待修复'
  }
  if (plan.attemptCount > 0) {
    if (isSingleReview(plan)) return plan.isResolved ? '题组已接稳' : plan.isComplete ? '题组已完成' : '题组进行中'
    if (plan.isResolved) return `第 ${plan.attemptCount} 轮已接稳`
    if (plan.isComplete || plan.attemptCount >= plan.roundLimit) return `${plan.roundLimit} 轮已完成`
    if (plan.firstScore !== null && plan.latestScore !== null && plan.latestScore > plan.firstScore) return `复习后提升 ${plan.firstScore}→${plan.latestScore}`
    return `已完成 ${plan.attemptCount}/${plan.roundLimit} 轮 · 接着练`
  }
  if (plan.date < today) return plan.date < enrollment ? '还没学过 · 可补学' : '还没学过 · 开始补学'
  if (plan.date > today) return isKnowledgeOnlyFuturePlan(plan, today) ? '可提前预习' : '还没学过 · 可提前学习'
  return '还没开始 · 今天开练'
}

export function splitCalendarWeeks(plans: LearningPlanDay[]) {
  const byWeek = new Map<string, LearningPlanDay[]>()
  for (const plan of [...plans].sort((a, b) => a.date.localeCompare(b.date))) {
    const date = new Date(`${plan.date}T12:00:00Z`)
    date.setUTCDate(date.getUTCDate() - (date.getUTCDay() + 6) % 7)
    const monday = date.toISOString().slice(0, 10)
    const week = byWeek.get(monday) ?? []
    week.push(plan)
    byWeek.set(monday, week)
  }
  return [...byWeek.values()]
}
