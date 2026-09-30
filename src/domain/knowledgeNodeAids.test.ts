import { describe, expect, it } from 'vitest'
import type { StructuredKnowledgeContent } from './types'
import { knowledgeSectionsWithFocusedAids } from './knowledgeNodeAids'

const shared = '【示范：粉碎—焙烧—酸浸】粉碎增大接触面积；焙烧改变原料；酸浸选择试剂。'
const content: StructuredKnowledgeContent = {
  version: 2, intro: '原料预处理与浸取。', sections: [{
    title: '原料预处理与浸取', items: [
      { label: '粉碎/研磨', rule: '增大接触面积，加快浸取速率。',
        examples: ['同质量石灰石粉末与盐酸接触，比大块石灰石反应更快。', shared],
        visualSteps: ['粉碎/研磨', '预处理目的', '判断焙烧气氛', '选择浸取剂'] },
      { label: '焙烧/煅烧', rule: '结合反应和气氛判断原料变化。', examples: [shared],
        visualSteps: ['焙烧/煅烧', '预处理目的', '判断焙烧气氛', '选择浸取剂'] },
    ],
  }],
}

describe('knowledge node aid isolation', () => {
  it('removes the copied chapter route and preserves the grinding example in an old cached card', () => {
    const before = structuredClone(content)
    const sections = knowledgeSectionsWithFocusedAids(content)
    expect(sections[0].items[0].examples).toEqual([content.sections[0].items[0].examples![0]])
    expect(sections[0].items[0].visualSteps).toBeUndefined()
    expect(sections[0].items[1].examples).toBeUndefined()
    expect(content).toEqual(before)
  })

  it('keeps a separately authored route and never copies it to a sibling', () => {
    const corrected = structuredClone(content)
    corrected.sections[0].items[0].examples = ['同质量矿石磨细，反应物接触面积增大。']
    corrected.sections[0].items[0].visualSteps = ['同质量矿石磨细', '接触面积增大', '浸取更快']
    const sections = knowledgeSectionsWithFocusedAids(corrected)
    expect(sections[0].items[0].visualSteps).toEqual(corrected.sections[0].items[0].visualSteps)
    expect(sections[0].items[1].visualSteps).toEqual(content.sections[0].items[1].visualSteps)
    expect(sections[0].items[1].examples).not.toContain(corrected.sections[0].items[0].examples[0])
  })

  it('does not attach index-keyed examples to a rearranged, unrecognised hierarchy', () => {
    const sections = knowledgeSectionsWithFocusedAids(content, 'H3_PROCESS')
    expect(sections[0].items[1].examples).toBeUndefined()
  })
})
