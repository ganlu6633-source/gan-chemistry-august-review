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

  it('restores subscripts and unit exponents in OCR-style source text', () => {
    const { container } = render(<p><ChemText>已知反应4CO + 2NO2→N2 + 4CO2，ν(H2)=0.1 mol·L-1·min-1。</ChemText></p>)

    expect(container.querySelectorAll('sub')).toHaveLength(4)
    expect(container.querySelectorAll('sup')).toHaveLength(2)
    expect(screen.getByLabelText('2NO2')).toBeInTheDocument()
    expect(screen.getByLabelText('L-1')).toBeInTheDocument()
    expect(screen.getByLabelText('min-1')).toBeInTheDocument()
    expect(container.textContent).toContain('0.1 mol·L')
    expect(container.textContent).toContain('CO +')
  })

  it('renders teacher-source caret powers and molar-volume notation without showing carets', () => {
    const { container } = render(<p><ChemText>V_m=22.4 L·mol^-1，V×10^-3 L；Kc=c(C)^c·c(D)^d/[c(A)^a·c(B)^b]</ChemText></p>)

    expect(screen.getByLabelText('V 下标 m')).toBeInTheDocument()
    expect(screen.getByLabelText('mol^-1').querySelector('sup')?.textContent).toBe('−1')
    expect(screen.getByLabelText('10^-3').querySelector('sup')?.textContent).toBe('−3')
    expect(screen.getByLabelText('c(C)^c').querySelector('sup')?.textContent).toBe('c')
    expect(screen.getByLabelText('c(B)^b').querySelector('sup')?.textContent).toBe('b')
    expect(screen.getByLabelText('K 下标 c').querySelector('sub')?.textContent).toBe('c')
    expect(container.textContent).not.toContain('^')
    expect(container.textContent).not.toContain('V_m')
  })

  it('keeps ionic charges distinct from formula subscripts', () => {
    const { container } = render(<p><ChemText>Fe2+、NH4+、SO4^2-、Ca(OH)2和12 g·L-1。</ChemText></p>)

    expect(container.querySelector('[aria-label="Fe2+"] sup')?.textContent).toBe('2+')
    expect(container.querySelector('[aria-label="NH4+"] sub')?.textContent).toBe('4')
    expect(container.querySelector('[aria-label="NH4+"] sup')?.textContent).toBe('+')
    expect(container.querySelector('[aria-label="SO4^2-"] sub')?.textContent).toBe('4')
    expect(container.querySelector('[aria-label="SO4^2-"] sup')?.textContent).toBe('2-')
    expect(container.querySelector('[aria-label="Ca(OH)2"] sub')?.textContent).toBe('2')
    expect(container.querySelector('[aria-label="L-1"] sup')?.textContent).toBe('−1')
  })

  it('keeps ordinary numbered Chinese text unchanged', () => {
    const { container } = render(<p><ChemText>第1轮共5题，答案选B。</ChemText></p>)

    expect(container.querySelectorAll('sub')).toHaveLength(0)
    expect(container.textContent).toContain('第1轮共5题')
  })
})
