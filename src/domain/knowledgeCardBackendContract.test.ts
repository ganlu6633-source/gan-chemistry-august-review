import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const accessSource = readFileSync('supabase/functions/chemistry-access/index.ts', 'utf8')

describe('knowledge-card backend fail-closed contract', () => {
  it('rejects malformed non-empty structured content before issuing a review round', () => {
    expect(accessSource).toContain('function validStructuredKnowledgeContent(value: unknown): boolean')
    expect(accessSource).toContain('if (hasStructured && !validStructuredKnowledgeContent(structured))')
    expect(accessSource).toContain('展开内容结构不完整，已停止下发并通知甘老师')
  })

  it('requires exactly one approved knowledge card for every high-school planned skill', () => {
    expect(accessSource).toContain('const highSchoolReview = ["高一", "高二", "高三"].includes')
    expect(accessSource).toContain('(cardsBySkill.get(skillId) || []).length !== 1')
    expect(accessSource).toContain('当天知识卡没有与学习模块一一对应')
  })
})
