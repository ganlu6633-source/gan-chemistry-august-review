import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const accessSource = readFileSync('supabase/functions/chemistry-access/index.ts', 'utf8')

describe('knowledge-card backend fail-closed contract', () => {
  it('rejects malformed non-empty structured content before issuing a review round', () => {
    expect(accessSource).toContain('function validStructuredKnowledgeContent(value: unknown): boolean')
    expect(accessSource).toContain('function validOptionalStructuredKnowledgeContent(value: unknown)')
    expect(accessSource).toContain('if (!isPlainRecord(value)) return false')
    expect(accessSource).toContain('if (!validOptionalStructuredKnowledgeContent(structured))')
    expect(accessSource).toContain('展开内容结构不完整，已停止下发并通知甘老师')
  })

  it('requires one approved card per original high-school skill while managed choice-only plans keep source checks', () => {
    expect(accessSource).toContain('const highSchoolReview = delivery.requiresImages && !delivery.managed')
    expect(accessSource).toContain('(cardsBySkill.get(skillId) || []).length !== 1')
    expect(accessSource).toContain('当天知识卡没有与学习模块一一对应')
    expect(accessSource).toContain('const sourceControlledReview = highSchoolReview || delivery.managed')
    expect(accessSource).toContain('teachingAssignmentValid(delivery.managed, assignedQuestionIds, questionCount)')
  })
})
