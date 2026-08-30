import { describe, expect, it } from 'vitest'

import {
  MAX_KNOWLEDGE_LIST_ITEMS,
  validKnowledgeVisual,
} from '../../supabase/functions/chemistry-access/knowledge-visual-safety'

const validTree = {
  kind: 'tree',
  title: '分类总树',
  tree: { label: '根', children: [{ label: '分支' }] },
  axes: [{ label: '横向分类轴', items: ['类别一', '类别二'] }],
}

describe('learner-facing knowledge visual safety', () => {
  it('accepts the bounded production tree-plus-axes shape', () => {
    expect(validKnowledgeVisual(validTree)).toBe(true)
  })

  it('rejects malformed fields even when the declared kind does not require them', () => {
    expect(validKnowledgeVisual({ ...validTree, groups: [null] })).toBe(false)
    expect(validKnowledgeVisual({ ...validTree, axes: [null] })).toBe(false)
  })

  it('rejects an over-deep extra tree on an otherwise valid flow', () => {
    let extraTree: Record<string, unknown> = { label: '叶子' }
    for (let index = 0; index < 9; index += 1) {
      extraTree = { label: `第${index + 1}层`, children: [extraTree] }
    }
    expect(validKnowledgeVisual({
      kind: 'flow',
      title: '合法流程',
      steps: [{ label: '第一步' }],
      tree: extraTree,
    })).toBe(false)
  })

  it('rejects the 101st visual axis before the response shaper can map it', () => {
    expect(validKnowledgeVisual({
      ...validTree,
      axes: Array.from(
        { length: MAX_KNOWLEDGE_LIST_ITEMS + 1 },
        (_, index) => ({ label: `轴${index + 1}`, items: ['项目'] }),
      ),
    })).toBe(false)
  })
})
