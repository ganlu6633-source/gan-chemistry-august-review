import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { ChemText } from './ChemText'

describe('ChemText', () => {
  it('renders the Avogadro constant with an uppercase subscript A', () => {
    const { container } = render(<p><ChemText>N=nN_A，N_A≈6.02×10²³ mol⁻¹</ChemText></p>)

    const symbols = screen.getAllByLabelText('N 下标 A')
    expect(symbols).toHaveLength(2)
    expect(container.querySelectorAll('.chem-avogadro > span')).toHaveLength(2)
    expect(container.querySelectorAll('.chem-avogadro sub')).toHaveLength(2)
    expect([...container.querySelectorAll('.chem-avogadro sub')].every((node) => node.textContent === 'A')).toBe(true)
    expect(container.textContent).not.toContain('N_A')
    expect(container.textContent).not.toContain(`N${String.fromCodePoint(8336)}`)
  })

  it('preserves every item in long chemistry lists', () => {
    const objects = '分子、原子、离子、电子、质子、中子、离子晶体的化学式单位'
    render(<p><ChemText>{objects}</ChemText></p>)
    expect(screen.getByText(objects)).toBeInTheDocument()
  })
})
