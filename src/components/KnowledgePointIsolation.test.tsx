import { render } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { StructuredKnowledgeMap } from './StudentApp'
import type { StructuredKnowledgeContent } from '../domain/types'

const labels = ['粉碎/研磨', '焙烧/煅烧', '酸浸/碱浸/水浸', '浸取率条件']
const sharedDemo = '【示范：粉碎—焙烧—酸浸】粉碎、焙烧、酸浸的整套综合流程。'
const oldContent: StructuredKnowledgeContent = {
  version: 2, intro: '预处理与浸取的学习卡。',
  sections: [{ title: '原料预处理与浸取', items: labels.map((label, index) => ({
    label, rule: `第${index + 1}个知识点的判断依据。`,
    examples: [sharedDemo, `只解释${label}的具体例子。`],
    visualSteps: [label, '预处理目的', '判断焙烧气氛', '选择浸取剂', '优化温度时间'],
  })) }],
}

describe('full knowledge explanation uses the same focused aids as the tree', () => {
  it('never displays the inherited roasting/leaching chain inside a grinding item', () => {
    const { container } = render(<StructuredKnowledgeMap content={oldContent} />)
    const items = container.querySelectorAll('.classification-item')
    expect(items).toHaveLength(4)
    labels.forEach((label, index) => {
      expect(items[index].querySelector('.point-demo')).toHaveTextContent(`只解释${label}的具体例子。`)
      expect(items[index]).not.toHaveTextContent('整套综合流程')
      expect(items[index].querySelector('.memory-diagram')).toBeNull()
    })
    expect(items[0]).not.toHaveTextContent('判断焙烧气氛')
    expect(items[0]).not.toHaveTextContent('选择浸取剂')
  })

  it('shows explicit focused diagrams, while an example-only node receives no invented arrows', () => {
    const corrected = structuredClone(oldContent)
    corrected.sections[0].items[0].examples = ['同质量矿石磨细，接触面积变大。']
    corrected.sections[0].items[0].visualSteps = ['矿石磨细', '接触面积增大', '浸取更快']
    corrected.sections[0].items[1].examples = ['CaCO₃受热分解生成CaO和CO₂。']
    delete corrected.sections[0].items[1].visualSteps
    const { container } = render(<StructuredKnowledgeMap content={corrected} />)
    const items = container.querySelectorAll('.classification-item')
    expect(items[0].querySelector('.memory-flow')).toHaveTextContent('矿石磨细')
    expect(items[0].querySelector('.memory-flow')).not.toHaveTextContent('焙烧')
    expect(items[1].querySelector('.point-demo')).toHaveTextContent('CaCO₃受热分解')
    expect(items[1].querySelector('.memory-flow')).toBeNull()
  })
})
