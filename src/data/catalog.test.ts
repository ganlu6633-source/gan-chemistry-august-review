import { describe, expect, it } from 'vitest'
import { COURSE_MAP, KNOWLEDGE_CARDS, QUESTIONS, SKILLS } from './catalog'

describe('catalog quality gate', () => {
  it('has unique IDs and valid skill references', () => {
    expect(new Set(SKILLS.map((item) => item.id)).size).toBe(SKILLS.length)
    expect(new Set(QUESTIONS.map((item) => item.id)).size).toBe(QUESTIONS.length)
    const ids = new Set(SKILLS.map((item) => item.id))
    for (const question of QUESTIONS) expect(ids.has(question.skillId)).toBe(true)
    for (const card of KNOWLEDGE_CARDS) expect(ids.has(card.skillId)).toBe(true)
    for (const node of COURSE_MAP) for (const id of [...node.skillIds, ...node.prerequisiteSkillIds]) expect(ids.has(id)).toBe(true)
  })
  it('uses variable maximum levels instead of a fake universal L20', () => {
    expect(new Set(SKILLS.map((item) => item.maxLevel)).size).toBeGreaterThan(3)
    expect(Math.max(...SKILLS.map((item) => item.maxLevel))).toBeLessThan(20)
    for (const skill of SKILLS) expect(skill.levelCriteria).toHaveLength(skill.maxLevel)
  })
  it('contains no out-of-scope or unreviewed question in the student catalog', () => {
    expect(QUESTIONS.every((item) => item.scopeStatus !== 'OUT' && item.reviewStatus === 'approved')).toBe(true)
    expect(QUESTIONS.every((item) => item.options.length === 4 && item.correctOption >= 0 && item.correctOption < 4)).toBe(true)
  })
  it('covers every grade band with at least two independent mother questions', () => {
    for (const grade of ['初三','高一','高二','高三'] as const) {
      const mothers = new Set(QUESTIONS.filter((item) => item.gradeBand === grade).map((item) => item.motherId))
      expect(mothers.size).toBeGreaterThanOrEqual(2)
    }
  })
})
