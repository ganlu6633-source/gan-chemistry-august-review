import { describe, expect, it } from 'vitest'
import { isStructuredKnowledgeContent } from './knowledgeContent'

const validCard = {
  version: 1,
  intro: '先把概念讲清楚。',
  visualSummary: { kind: 'flow', title: '判断流程', steps: [{ label: '读题' }] },
  sections: [{
    title: '第一组知识点',
    items: [{ label: '概念', rule: '概念的完整表述。', children: [{ label: '边界', rule: '边界说明。' }] }],
  }],
}

describe('knowledge-card runtime contract', () => {
  it('accepts the official structured knowledge format', () => {
    expect(isStructuredKnowledgeContent(validCard)).toBe(true)
  })

  it('rejects a visually invented shape with no renderable sections', () => {
    expect(isStructuredKnowledgeContent({
      version: 1,
      intro: '错误候选',
      visualSummary: { kind: 'tree_and_network', title: '不存在的图形类型' },
      concepts: [{ title: '没有进入正式章节的数据' }],
    })).toBe(false)
  })

  it('rejects empty rules before the page tries to render them', () => {
    expect(isStructuredKnowledgeContent({
      ...validCard,
      sections: [{ title: '第一组知识点', items: [{ label: '只有标题', rule: '' }] }],
    })).toBe(false)
  })

  it('rejects a declared flow or comparison visual whose render data is missing', () => {
    expect(isStructuredKnowledgeContent({
      ...validCard,
      visualSummary: { kind: 'flow', title: '缺步骤的流程图' },
    })).toBe(false)
    expect(isStructuredKnowledgeContent({
      ...validCard,
      visualSummary: { kind: 'compare', title: '缺分组的对比图' },
    })).toBe(false)
  })

  it('rejects incomplete examples instead of letting an empty expansion reach students', () => {
    expect(isStructuredKnowledgeContent({
      ...validCard,
      sections: [{ title: '第一组知识点', items: [{ label: '概念', rule: '完整规则', examples: ['有效例子', ''] }] }],
    })).toBe(false)
  })
})
