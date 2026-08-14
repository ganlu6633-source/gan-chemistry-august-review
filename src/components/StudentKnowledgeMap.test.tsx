import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import type { StructuredKnowledgeContent } from '../domain/types'
import { StructuredKnowledgeMap } from './StudentApp'

const content: StructuredKnowledgeContent = {
  version: 3,
  intro: '从零复习',
  visualSummary: {
    kind: 'network',
    title: '物质的量对象总览',
    center: 'N=nN_A',
    groups: [{ label: '对象', items: ['分子', '原子', '离子', '电子', '质子', '中子', '离子晶体的化学式单位'] }],
  },
  rootTree: {
    label: '化合物',
    rule: '先沿总树向下判断。',
    children: [
      { label: '酸', rule: '在水中电离产生的阳离子全部是H⁺。', examples: ['H₂SO₄属于酸。'] },
      { label: '电解质', rule: '限定为化合物，并按自身在水中或熔融时能否产生自由移动离子判断。' },
    ],
  },
  sections: [{
    title: '对象必须写清',
    items: [{
      label: '阿伏加德罗常数N_A',
      rule: 'N=nN_A；对象包括分子、原子、离子、电子、质子、中子与离子晶体的化学式单位。',
      examples: ['1 mol ²³Na含11 mol质子、12 mol中子和11 mol电子。'],
    }],
  }],
}

describe('StructuredKnowledgeMap disclosure and formula rendering', () => {
  it('keeps the overview visible and lets each tree branch expand independently', () => {
    const { container } = render(<StructuredKnowledgeMap content={content} />)

    expect(screen.getByText('物质的量对象总览')).toBeInTheDocument()
    const branches = [...container.querySelectorAll('details.knowledge-branch-details')]
    expect(branches).toHaveLength(3)
    expect((branches[0] as HTMLDetailsElement).open).toBe(true)
    expect((branches[1] as HTMLDetailsElement).open).toBe(false)
    expect((branches[2] as HTMLDetailsElement).open).toBe(false)

    fireEvent.click(branches[1].querySelector('summary')!)
    expect((branches[1] as HTMLDetailsElement).open).toBe(true)
    expect((branches[2] as HTMLDetailsElement).open).toBe(false)
    expect(branches[1].querySelector('.point-demo')?.textContent).toContain('H₂SO₄属于酸。')
  })

  it('opens each classification item and renders every N_A with uppercase A in sub', () => {
    const { container } = render(<StructuredKnowledgeMap content={content} />)
    const item = container.querySelector('details.classification-item') as HTMLDetailsElement
    expect(item.open).toBe(false)
    fireEvent.click(item.querySelector('summary')!)
    expect(item.open).toBe(true)

    const formulas = screen.getAllByLabelText('N 下标 A')
    expect(formulas.length).toBeGreaterThanOrEqual(3)
    expect([...container.querySelectorAll('.chem-avogadro sub')].every((node) => node.textContent === 'A')).toBe(true)
    expect(item.querySelector('.point-copy')?.textContent).toContain('质子、中子与离子晶体的化学式单位')
  })
})
