import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import type { StructuredKnowledgeContent } from '../domain/types'
import { StructuredKnowledgeMap } from './StudentApp'

const content: StructuredKnowledgeContent = {
  version: 4,
  intro: '按组成逐层分类。',
  visualSummary: { kind: 'tree', title: '物质分类总树', tree: { label: '物质' } },
  rootTree: {
    label: '物质', rule: '先数样品中有几种物质。', examples: ['空气是混合物。'], children: [
      { label: '混合物', rule: '含有两种或两种以上物质。', examples: ['空气、盐酸。'], children: [
        { label: '分散系', rule: '一种物质分散在另一种物质中。', examples: ['NaCl溶液。'] },
      ] },
      { label: '纯净物', rule: '只含一种物质。', examples: ['液氯、蒸馏水。'], children: [
        { label: '化合物', rule: '由不同元素组成的纯净物。', examples: ['H₂O、CO₂。'], children: [
          { label: '氧化物', rule: '两种元素，其中一种是氧。', children: [
            { label: '分类1', rule: '按另一种元素分类。', examples: ['Na₂O是金属氧化物。'] },
          ] },
          { label: '酸', rule: '水溶液中电离出的阳离子都是H⁺。', children: [
            { label: '分类1', rule: '按可电离的H⁺数分类。', examples: ['HCl是一元酸。'] },
          ] },
          { label: '横向轴｜电解质与非电解质', rule: '只针对化合物的另一条分类轴。' },
        ] },
      ] },
    ],
  },
  sections: [],
}

afterEach(cleanup)

describe('物质分类横向交互树', () => {
  it('从物质逐层向右展开，每个节点单独显示知识点和已有范例', () => {
    render(<StructuredKnowledgeMap content={content} skillId="H1_CLASSIFY" />)
    const tree = within(screen.getByRole('region', { name: '物质分类交互树' }))

    const matter = tree.getByRole('button', { name: '物质' })
    expect(matter).toHaveAttribute('aria-expanded', 'false')
    expect(tree.queryByRole('button', { name: '混合物' })).not.toBeInTheDocument()

    fireEvent.click(matter)
    expect(matter).toHaveAttribute('aria-expanded', 'true')
    expect(tree.getByText('先数样品中有几种物质。')).toBeInTheDocument()
    fireEvent.click(tree.getByRole('button', { name: '混合物' }))
    expect(tree.getByRole('button', { name: '分散系' })).toBeInTheDocument()

    fireEvent.click(tree.getByRole('button', { name: '纯净物' }))
    expect(tree.getByRole('button', { name: '分散系' })).toBeInTheDocument()
    expect(tree.getByRole('button', { name: '化合物' })).toBeInTheDocument()
    fireEvent.click(tree.getByRole('button', { name: '范例' }))
    expect(tree.getByText('液氯、蒸馏水。')).toBeInTheDocument()

    fireEvent.click(tree.getByRole('button', { name: '混合物' }))
    expect(tree.queryByRole('button', { name: '分散系' })).not.toBeInTheDocument()
    expect(tree.getByRole('button', { name: '化合物' })).toBeInTheDocument()
  })

  it('同名节点分别打开对应知识，并标明交叉分类不是主树的新类别', () => {
    render(<StructuredKnowledgeMap content={content} skillId="H1_CLASSIFY" />)
    const tree = within(screen.getByRole('region', { name: '物质分类交互树' }))
    for (const label of ['物质', '纯净物', '化合物', '氧化物', '酸']) {
      fireEvent.click(tree.getByRole('button', { name: label }))
    }
    const sameNamedNodes = tree.getAllByRole('button', { name: '分类1' })
    expect(sameNamedNodes).toHaveLength(2)
    fireEvent.click(sameNamedNodes[1])
    expect(tree.getByText('按可电离的H⁺数分类。')).toBeInTheDocument()
    fireEvent.click(tree.getByRole('button', { name: '范例' }))
    expect(tree.getByText('HCl是一元酸。')).toBeInTheDocument()
    expect(tree.getByText('交叉分类')).toBeInTheDocument()
  })
})
