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
})
