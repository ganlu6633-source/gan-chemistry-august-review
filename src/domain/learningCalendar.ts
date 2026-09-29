import type { LearningPlanDay } from './types'

export const isKnowledgeOnlyFuturePlan = (plan: LearningPlanDay, today: string) => plan.date > today && plan.canStudyAhead !== true

const isSingleReview = (plan: LearningPlanDay) => plan.mode === 'REVIEW' && plan.roundLimit === 1 && plan.deliveryMode !== 'junior_adaptive'

export function calendarPlanProgress(plan: LearningPlanDay): 'not_started' | 'in_progress' | 'completed' | 'blocked' {
  if (plan.deliveryMode === 'junior_adaptive' && ['blocked', 'abandoned'].includes(plan.juniorSessionStatus ?? '')) return 'blocked'
  if (plan.isComplete || plan.isResolved || plan.juniorSessionStatus === 'completed'
    || (plan.deliveryMode !== 'junior_adaptive' && plan.roundLimit > 0 && plan.attemptCount >= plan.roundLimit)) return 'completed'
  if (plan.hasStarted || plan.attemptCount > 0 || plan.juniorSessionStatus === 'active') return 'in_progress'
  return 'not_started'
}

export function calendarPlanShortStatus(plan: LearningPlanDay, today: string) {
  const progress = calendarPlanProgress(plan)
  if (progress === 'blocked') return '待修复'
  if (progress === 'completed') return '可复习'
  if (progress === 'in_progress') return '继续学'
  if (isKnowledgeOnlyFuturePlan(plan, today)) return '可预习'
  return plan.date > today ? '可提前' : plan.date < today ? '可补学' : '未开始'
}

export function calendarPlanStatus(plan: LearningPlanDay, enrollment: string, today: string) {
  // Date and enrollment describe the schedule. Only actual attempts/session
  // state can say the student has started or completed this lesson.
  const progress = calendarPlanProgress(plan)
  if (progress === 'blocked') return '进度已保留 · 题组待修复'
  if (progress === 'completed') {
    if (plan.deliveryMode === 'junior_adaptive' || plan.attemptCount === 0) return '学习已完成 · 可复习'
    if (isSingleReview(plan)) return plan.isResolved ? '题组已接稳 · 可复习' : '题组已完成 · 可复习'
    return plan.isResolved ? `第 ${plan.attemptCount} 轮已接稳 · 可复习` : `${plan.attemptCount} 轮已完成 · 可复习`
  }
  if (plan.deliveryMode === 'junior_adaptive' && progress === 'in_progress') return '学习进行中 · 接着练'
  if (plan.attemptCount > 0) {
    if (isSingleReview(plan)) return '题组进行中 · 接着练'
    if (plan.firstScore !== null && plan.latestScore !== null && plan.latestScore > plan.firstScore) return `复习后提升 ${plan.firstScore}→${plan.latestScore}`
    return `已完成 ${plan.attemptCount}/${plan.roundLimit} 轮 · 接着练`
  }
  if (progress === 'in_progress') return '学习进行中 · 接着练'
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
