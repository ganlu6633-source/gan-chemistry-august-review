import { describe, expect, it } from 'vitest'
import type { KnowledgeCard, KnowledgeTreeNode } from './types'
import { getKnowledgeReviewLeaves, getKnowledgeReviewPoints } from './knowledgeReviewPoints'
import { knowledgeReviewPointExamples } from './knowledgeReviewPointExamples'
import { buildRecoveryTargets } from './learningRecovery'

const leaves: KnowledgeTreeNode[] = [
  { label: '化合价升高时电子怎样变化', rule: '化合价升高对应失电子。', reviewPointIndex: 50,
    examples: ['Fe²⁺变成Fe³⁺时，每个Fe失去1个电子。'] },
  { label: '如何判断还原剂', rule: '提供电子的反应物是还原剂。', reviewPointIndex: 51,
    examples: ['Zn+Cu²⁺=Zn²⁺+Cu中，Zn提供电子，是还原剂。'], caution: '还原剂是反应物。' },
]
const card: KnowledgeCard = {
  id: 'KC_H1_REDOX', skillId: 'H1_REDOX', title: '氧化还原', core: '独立识别', detail: '',
  steps: [], commonMistakes: [], microExample: '', reviewStatus: 'approved',
  structuredContent: { version: 1, intro: '逐个判断', sections: [{ title: '价态和角色', items: [
    { label: '化合价升高的一侧', rule: '升价、失电子、还原剂及氧化产物。',
      examples: ['这是父级综合例子，不应继承到每个叶点。'], caution: '父级提示',
      children: [{ label: '本侧规则', rule: '继续展开', children: leaves }] },
    { label: '未拆分的原有知识点', rule: '原规则保持。', examples: ['原例子保持。'] },
  ] }] },
}

describe('authored leaf self-rating identities', () => {
  it('asks only terminal points with their own rule, example and caution', () => {
    const points = getKnowledgeReviewPoints(card)
    expect(points.map((point) => point.id)).toEqual([
      'KC_H1_REDOX:s0:i0:p50', 'KC_H1_REDOX:s0:i0:p51', 'KC_H1_REDOX:s0:i1:p0',
    ])
    expect(points[0]).toMatchObject({ title: leaves[0].label, rule: leaves[0].rule, examples: leaves[0].examples })
    expect(points[0].caution).toBeUndefined()
    expect(points[1].caution).toBe('还原剂是反应物。')
    expect(knowledgeReviewPointExamples(card, points[0])).toEqual(leaves[0].examples)
    expect(knowledgeReviewPointExamples(card, points[1])).toEqual(leaves[1].examples)
    expect(knowledgeReviewPointExamples(card, { ...points[0], title: '不匹配的标题' })).toEqual([])
    expect(knowledgeReviewPointExamples(card, points[2])).toEqual(['原例子保持。'])
  })

  it('does not turn a historical parent rating into ratings for new children', () => {
    const pointRatings = { 'KC_H1_REDOX:s0:i0:p0': 'unknown', 'KC_H1_REDOX:s0:i0:p51': 'familiar' } as const
    const targets = buildRecoveryTargets({ questions: [], answers: [], branches: [], cards: [card], pointRatings, conceptTitles: {} })
    expect(targets.map((target) => target.pointId)).toEqual(['KC_H1_REDOX:s0:i0:p51'])
    expect(pointRatings['KC_H1_REDOX:s0:i0:p0']).toBe('unknown')
  })

  it('retains authored slots after reorder and insertion', () => {
    const root: KnowledgeTreeNode = { label: '父节点', rule: '总览', children: [leaves[1],
      { label: '发生的反应', rule: '失电子的一侧发生氧化反应。', reviewPointIndex: 55 }, leaves[0]] }
    expect(getKnowledgeReviewLeaves(root).map(({ node, pointIndex }) => [node.label, pointIndex])).toEqual([
      [leaves[1].label, 51], ['发生的反应', 55], [leaves[0].label, 50],
    ])
  })

  it('keeps old points unchanged when no authored children are present', () => {
    const old = { ...card, structuredContent: { version: 1, intro: '原卡', sections: [
      { title: '原节', items: [{ label: '未拆分的原有知识点', rule: '原规则保持。' }] },
    ] } }
    expect(getKnowledgeReviewPoints(old)).toMatchObject([{ id: 'KC_H1_REDOX:s0:i0:p0', title: '未拆分的原有知识点' }])
  })

  it('uses unreserved legacy slots and rejects duplicate or out-of-range authored identities', () => {
    const root = (children: KnowledgeTreeNode[]): KnowledgeTreeNode => ({ label: '父', rule: '总览', children })
    expect(getKnowledgeReviewLeaves(root([leaves[0], { label: '旧叶', rule: '旧规则' }])).map((leaf) => leaf.pointIndex)).toEqual([50, 51])
    expect(getKnowledgeReviewLeaves(root([leaves[0], { ...leaves[1], reviewPointIndex: 50 }]))).toEqual([])
    expect(getKnowledgeReviewLeaves(root([{ ...leaves[0], reviewPointIndex: 100 }]))).toEqual([])
    expect(getKnowledgeReviewLeaves(root(Array.from({ length: 51 }, (_, i) => ({ label: `叶${i}`, rule: '规则' }))))).toEqual([])
  })
})
