import { render, screen, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import type { StructuredKnowledgeContent } from '../domain/types'
import { StructuredKnowledgeMap } from './StudentApp'

function content(title: string): StructuredKnowledgeContent {
  return {
    version: 4,
    intro: '图解',
    visualSummary: { kind: 'compare', title, groups: [] },
    sections: [],
  }
}

describe('scientific knowledge diagrams', () => {
  it('shows every third-period highest oxide and corresponding hydrate without collapsing the mapping', () => {
    render(<StructuredKnowledgeMap content={content('元素周期律完整趋势图')} />)
    const table = screen.getByRole('table', { name: '第三周期最高价氧化物及对应水化物逐元素对照' })
    expect(within(table).getAllByRole('row')).toHaveLength(8)
    for (const formula of ['Na₂O', 'MgO', 'Al₂O₃', 'SiO₂', 'P₄O₁₀（常简写P₂O₅）', 'SO₃', 'Cl₂O₇', 'NaOH', 'Mg(OH)₂', 'Al(OH)₃', 'H₂SiO₃', 'H₃PO₄', 'H₂SO₄', 'HClO₄']) {
      expect(within(table).getByText(formula)).toBeInTheDocument()
    }
    expect(screen.getByText(/SiO₂不能直接与水生成H₂SiO₃/)).toBeInTheDocument()
    expect(screen.getByText('SiH₄ ＜ PH₃ ＜ H₂S ＜ HCl')).toBeInTheDocument()
  })

  it('uses two real energy-profile diagrams and states both enthalpy definitions', () => {
    render(<StructuredKnowledgeMap content={content('反应热的能量账本')} />)
    expect(screen.getByRole('img', { name: '放热反应能量随反应进程变化图' })).toBeInTheDocument()
    expect(screen.getByRole('img', { name: '吸热反应能量随反应进程变化图' })).toBeInTheDocument()
    expect(screen.getByText('ΔH = H（生成物）− H（反应物）')).toBeInTheDocument()
    expect(screen.getByText(/ΔH ≈ ΣE（反应物断键吸收）− ΣE（生成物成键释放）/)).toBeInTheDocument()
    expect(screen.getAllByText('正反应活化能 Eₐ')).toHaveLength(2)
  })

  it('places one concrete H₂ combustion picture beside its worked example and distinguishes both height differences', () => {
    const thermo = content('反应热的能量账本')
    thermo.workedExamples = [{
      substance: 'H₂燃烧的能量账',
      path: '曲线峰顶表示反应过程中能量最高的位置；反应物能量线到峰顶的高度差表示正反应活化能，生成物与反应物的高度差表示ΔH。',
      labels: ['区分两种高度差'],
    }]

    render(<StructuredKnowledgeMap content={thermo} skillId="H2_THERMO" />)

    const figures = screen.getAllByRole('figure', { name: 'H₂燃烧生成液态水的放热反应能量图' })
    expect(figures).toHaveLength(1)
    const figure = figures[0]
    expect(figure).toHaveTextContent('2H₂(g) + O₂(g) → 2H₂O(l)')
    expect(figure).toHaveTextContent('正反应活化能 Eₐ')
    expect(figure).toHaveTextContent('H（生成物）− H（反应物）＜0')
    expect(figure).toHaveTextContent('体系 → 环境：放出热量')
    expect(figure).toHaveTextContent('峰顶本身不是活化能')
    expect(figure).toHaveTextContent('不表示氢气燃烧只有一个反应步骤')
    expect(figure.querySelector('.hydrogen-example-platform')).toHaveAttribute('d', 'M88 150H177M458 252H550')
    expect(figure.querySelector('.hydrogen-ea-arrow')).toHaveAttribute('d', 'M174 145V78')
    expect(figure.querySelector('.hydrogen-dh-arrow')).toHaveAttribute('d', 'M431 158V244')
    expect(figure.querySelector('.hydrogen-energy-svg-desktop')).toHaveAttribute('viewBox', '0 0 640 370')
    expect(figure.querySelector('.hydrogen-energy-svg-mobile')).toHaveAttribute('viewBox', '0 0 280 390')
    expect(figure).toHaveTextContent('手机竖版氢气燃烧放热反应能量图')
  })
})
