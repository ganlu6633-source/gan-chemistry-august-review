import { describe, expect, it } from 'vitest'
import type { KnowledgeCard } from './types'
import { juniorReviewPoint } from './juniorReviewPoint'

const card: KnowledgeCard = { id: 'oxygen', skillId: 'oxygen', title: '氧气制备', core: '多种操作', detail: '逐项学习',
  steps: [], commonMistakes: [], microExample: '大卡片综合例子', reviewStatus: 'approved',
  structuredContent: { version: 1, intro: '制氧', sections: [{ title: '操作', items: [
    { label: '停止时先移导管', rule: '先移出导管，再熄灭酒精灯。', examples: ['防止冷却后倒吸。'] },
    { label: '试管口放棉花', rule: '防止粉末进入导管。', examples: ['棉花挡住粉末。'] },
  ] }] } }

describe('exact junior recovery micro-point', () => {
  it('shows only the selected leaf rule and its own example', () => {
    expect(juniorReviewPoint(card, '停止时先移导管')).toMatchObject({ title: '停止时先移导管',
      rule: '先移出导管，再熄灭酒精灯。', examples: ['防止冷却后倒吸。'] })
    expect(juniorReviewPoint(card, '停止时先移导管')?.rule).not.toContain('棉花')
  })
  it('does not guess from broad or merely similar labels', () => {
    expect(juniorReviewPoint(card, '氧气制备')).toBeNull()
    expect(juniorReviewPoint(card, '导管')).toBeNull()
    expect(juniorReviewPoint(null, '停止时先移导管')).toBeNull()
  })
})
