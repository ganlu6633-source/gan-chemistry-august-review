import type { GradeBand } from './types'

export const managementGrades: GradeBand[] = ['初三', '高一', '高二', '高三']
export type TeachingTopic = { id: string; parentId: string | null; title: string; gradeBands: string[]; order: number; readyQuestionCount: number; pendingQuestionCount: number }
export type TeachingClass = { id: string; name: string; gradeBand: GradeBand; memberCount: number; planItems?: TeachingPlanItem[] }
export type ExistingTeachingPlan = { id: string; date: string; title: string; questionCount: number; started: boolean; inCurrentProgram?: boolean; isScheduled?: boolean }
export type ManagedStudent = { id: string; displayName: string; gradeBand: GradeBand; classId: string | null; className: string; status: 'active' | 'archived'; progressSummary: string; topicIds: string[]; textbookVersion: string; planItems?: TeachingPlanItem[]; currentPlans?: ExistingTeachingPlan[] }
export type TeachingCatalog = { topics: TeachingTopic[]; classes: TeachingClass[]; students: ManagedStudent[]; catalogVersion: string }
export type TeachingPlanItem = { topicId: string; date: string; questionCount: number }
export type TeachingPlanRequest = { targetType: 'student' | 'class'; targetId: string; items: TeachingPlanItem[]; keepExistingPlanIds: string[]; replaceFuture: true }
export type TeachingPlanPreview = { previewToken: string | null; canApply: boolean; preservedPlanCount?: number; rows: Array<{ studentId: string; studentName: string; date: string; title: string; questionCount: number; questionIds: string[]; status: 'ready' | 'blocked'; reason?: string }>; warnings: string[]; summary: { studentCount: number; planCount: number; questionCount: number } }
export type ManageStudentResult = { studentId: string; message: string; accessCodes?: { studentCode: string; guardianCode: string } }

export function beijingToday() {
  return new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
}

export function isValidPlanDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const date = new Date(`${value}T00:00:00Z`)
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value
}

export function nextPlanDate(value: string) {
  if (!isValidPlanDate(value)) return beijingToday()
  const date = new Date(`${value}T00:00:00Z`)
  date.setUTCDate(date.getUTCDate() + 1)
  return date.toISOString().slice(0, 10)
}

/** Reordering moves a course and its question count into the existing date slots. */
export function moveTeachingItem(items: TeachingPlanItem[], index: number, direction: -1 | 1) {
  const to = index + direction
  if (index < 0 || index >= items.length || to < 0 || to >= items.length) return items
  const moved = [...items]
  const [item] = moved.splice(index, 1)
  moved.splice(to, 0, item)
  return moved.map((row, position) => ({ ...row, date: items[position].date }))
}

export function topicLeaves(topics: TeachingTopic[], rootId: string): TeachingTopic[] {
  const byId = new Map(topics.map((topic) => [topic.id, topic]))
  const visited = new Set<string>()
  const visit = (id: string): TeachingTopic[] => {
    if (visited.has(id)) return []
    visited.add(id)
    const topic = byId.get(id)
    if (!topic) return []
    const children = topics.filter((item) => item.parentId === id).sort((a, b) => a.order - b.order)
    return children.length ? children.flatMap((child) => visit(child.id)) : [topic]
  }
  return visit(rootId)
}

export function visibleTopicIds(topics: TeachingTopic[], search: string, grade: string) {
  const query = search.trim().toLocaleLowerCase()
  const visible = new Set<string>()
  const byId = new Map(topics.map((topic) => [topic.id, topic]))
  for (const topic of topics) {
    if ((grade && !topic.gradeBands.includes(grade)) || (query && !topic.title.toLocaleLowerCase().includes(query))) continue
    const subtree = [topic.id]
    while (subtree.length) {
      const id = subtree.pop()!
      if (visible.has(id)) continue
      visible.add(id)
      for (const child of topics.filter((item) => item.parentId === id)) if (!grade || child.gradeBands.includes(grade)) subtree.push(child.id)
    }
    let parent = topic.parentId
    const ancestors = new Set<string>()
    while (parent && !ancestors.has(parent)) {
      ancestors.add(parent); visible.add(parent); parent = byId.get(parent)?.parentId ?? null
    }
  }
  return visible
}

export function teachingPlanProblems(request: TeachingPlanRequest, existingPlans: ExistingTeachingPlan[] = []) {
  const problems: string[] = []
  if (!request.targetId) problems.push('请选择要安排的班级或学生。')
  const days = new Map<string, number>()
  for (const item of request.items) {
    if (!isValidPlanDate(item.date)) problems.push('请为每项内容填写有效日期。')
    if (!Number.isInteger(item.questionCount) || item.questionCount < 1 || item.questionCount > 8) problems.push('每项内容请安排1—8道题。')
    days.set(item.date, (days.get(item.date) ?? 0) + item.questionCount)
  }
  for (const [date, count] of days) if (count > 8) problems.push(`${date} 合计${count}题；同一天最多安排8道基础题。`)
  for (const plan of existingPlans) if (days.has(plan.date) && (plan.started || request.keepExistingPlanIds.includes(plan.id))) problems.push(`${plan.date} 已有保留的安排；请先取消该日保留，或为新内容换一个日期。`)
  return [...new Set(problems)]
}

export function canSaveTeachingPreview(preview: TeachingPlanPreview | null) {
  return Boolean(preview?.canApply && preview.previewToken && preview.rows.every((row) => row.status === 'ready'))
}
