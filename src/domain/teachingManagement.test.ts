import { describe, expect, it } from 'vitest'
import { canSaveTeachingPreview, moveTeachingItem, nextPlanDate, teachingPlanProblems, topicLeaves, visibleTopicIds } from './teachingManagement'
import type { TeachingPlanPreview, TeachingTopic } from './teachingManagement'

const topics: TeachingTopic[] = [
  { id: 'root', parentId: null, title: '物质分类', gradeBands: ['高一'], order: 0, readyQuestionCount: 12, pendingQuestionCount: 2 },
  { id: 'pure', parentId: 'root', title: '纯净物与混合物', gradeBands: ['高一'], order: 0, readyQuestionCount: 6, pendingQuestionCount: 0 },
  { id: 'oxide', parentId: 'root', title: '氧化物', gradeBands: ['高一'], order: 1, readyQuestionCount: 6, pendingQuestionCount: 2 },
]
const ready: TeachingPlanPreview = { previewToken: 'reviewed-token', canApply: true, rows: [{ studentId: 's', studentName: '同学', date: '2026-09-12', title: '分类', questionCount: 3, questionIds: ['a', 'b', 'c'], status: 'ready' }], warnings: [], summary: { studentCount: 1, planCount: 1, questionCount: 3 } }

describe('teacher course choices', () => {
  it('keeps dates in position when the teacher moves a course earlier', () => {
    const items = [{ topicId: 'pure', date: '2026-09-12', questionCount: 3 }, { topicId: 'oxide', date: '2026-09-14', questionCount: 5 }]
    expect(moveTeachingItem(items, 1, -1)).toEqual([{ topicId: 'oxide', date: '2026-09-12', questionCount: 5 }, { topicId: 'pure', date: '2026-09-14', questionCount: 3 }])
    expect(items[0].topicId).toBe('pure')
  })
  it('selects leaf topics only and keeps ancestors visible in a narrow search', () => {
    expect(topicLeaves(topics, 'root').map((topic) => topic.id)).toEqual(['pure', 'oxide'])
    expect([...visibleTopicIds(topics, '氧化', '')].sort()).toEqual(['oxide', 'root'])
    expect([...visibleTopicIds(topics, '物质分类', '高一')].sort()).toEqual(['oxide', 'pure', 'root'])
  })
  it('blocks invalid dates and daily sums above the eight-question capacity', () => {
    expect(teachingPlanProblems({ targetType: 'class', targetId: 'c', replaceFuture: true, keepExistingPlanIds: [], items: [{ topicId: 'pure', date: '2026-09-12', questionCount: 5 }, { topicId: 'oxide', date: '2026-09-12', questionCount: 4 }] })).toContain('2026-09-12 合计9题；同一天最多安排8道基础题。')
    expect(teachingPlanProblems({ targetType: 'student', targetId: '', replaceFuture: true, keepExistingPlanIds: [], items: [{ topicId: 'pure', date: '2026-02-30', questionCount: 0 }] })).toHaveLength(3)
    expect(nextPlanDate('2026-09-30')).toBe('2026-10-01')
  })
  it('allows legacy twelve-question plans to be retained and blocks overlapping new content', () => {
    const old = { id: 'legacy-12', date: '2026-09-12', title: '原有初三课', questionCount: 12, started: false }
    const request = { targetType: 'student' as const, targetId: 's', replaceFuture: true as const, keepExistingPlanIds: [old.id], items: [] }
    expect(teachingPlanProblems(request, [old])).toEqual([])
    const items = [{ topicId: 'pure', date: old.date, questionCount: 1 }]
    expect(teachingPlanProblems({ ...request, items }, [old])).toEqual(['2026-09-12 已有保留的安排；请先取消该日保留，或为新内容换一个日期。'])
    expect(teachingPlanProblems({ ...request, keepExistingPlanIds: [], items }, [old])).toEqual([])
    expect(teachingPlanProblems({ ...request, keepExistingPlanIds: [], items }, [{ ...old, started: true }])).toHaveLength(1)
  })
  it('requires a complete reviewed token and permits an explicit empty-plan preview', () => {
    expect(canSaveTeachingPreview(ready)).toBe(true)
    expect(canSaveTeachingPreview({ ...ready, canApply: false })).toBe(false)
    expect(canSaveTeachingPreview({ ...ready, previewToken: null })).toBe(false)
    expect(canSaveTeachingPreview({ ...ready, rows: [] })).toBe(true)
    expect(canSaveTeachingPreview({ ...ready, rows: [{ ...ready.rows[0], status: 'blocked' }] })).toBe(false)
  })
})
