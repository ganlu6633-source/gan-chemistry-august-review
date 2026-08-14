import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import {
  SourceInformedChemVisual,
} from './SourceInformedChemVisuals'

afterEach(cleanup)

describe('source-informed chemistry visuals', () => {
  it('connects mass, amount and specified particles without corrupting the Avogadro symbol', () => {
    const { container } = render(<SourceInformedChemVisual skillId="H1_MOLE_INTRO" />)

    expect(screen.getByLabelText('物质的量、阿伏加德罗常数与摩尔质量关系图')).toBeInTheDocument()
    expect(screen.getByText('物质的量（中转站）')).toBeInTheDocument()
    expect(screen.getByText(/分子、原子、离子、电子、质子、中子/)).toBeInTheDocument()
    expect(screen.getByText(/离子晶体的化学式单位/)).toBeInTheDocument()
    expect(screen.getByText(/若问氢原子数/)).toBeInTheDocument()
    expect(container.querySelectorAll('.chem-avogadro sub').length).toBeGreaterThanOrEqual(6)
    expect([...container.querySelectorAll('.chem-avogadro sub')].every((node) => node.textContent === 'A')).toBe(true)
    expect(container.textContent).not.toContain('N_A')
    expect(container.querySelector('img')).not.toBeInTheDocument()
  })

  it('shows the gas-state and standard-condition gates before 22.4 L per mole', () => {
    const { container } = render(<SourceInformedChemVisual skillId="H1_GAS_MOLAR_VOLUME" />)

    expect(screen.getByLabelText('气体摩尔体积的条件闸门与换算关系图')).toBeInTheDocument()
    expect(screen.getByText('闸门 1｜对象')).toBeInTheDocument()
    expect(screen.getByText('闸门 2｜温压')).toBeInTheDocument()
    expect(screen.getByText(/0 ℃、101 kPa/)).toBeInTheDocument()
    expect(screen.getByText(/标准状况下H₂O是液体/)).toBeInTheDocument()
    expect(screen.getByText(/相同物质的量的气体/)).toBeInTheDocument()

    const diagrams = [...container.querySelectorAll('svg')]
    expect(diagrams).toHaveLength(2)
    expect(diagrams.every((diagram) => diagram.hasAttribute('viewBox'))).toBe(true)
    expect(diagrams.every((diagram) => diagram.style.width === '100%' && diagram.style.height === 'auto')).toBe(true)
  })

  it('keeps all six redox identities and the complete reaction names on both tracks', () => {
    render(<SourceInformedChemVisual skillId="H1_REDOX" />)

    expect(screen.getByLabelText('氧化还原反应双轨关系与电子守恒图')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: /氧化轨｜升价 → 失电子 → 被氧化 → 氧化反应 → 还原剂 → 氧化产物/ })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: /还原轨｜降价 → 得电子 → 被还原 → 还原反应 → 氧化剂 → 还原产物/ })).toBeInTheDocument()
    expect(screen.getAllByText('发生氧化反应')).not.toHaveLength(0)
    expect(screen.getAllByText('发生还原反应')).not.toHaveLength(0)
    expect(screen.getByText('失电子总数')).toBeInTheDocument()
    expect(screen.getByText('得电子总数')).toBeInTheDocument()
    expect(screen.getByText(/Fe失2e⁻ = Cu²⁺得2e⁻/)).toBeInTheDocument()
  })

  it('returns null for skills without a dedicated source-informed visual', () => {
    const { container } = render(<SourceInformedChemVisual skillId="H1_PERIODIC" />)
    expect(container).toBeEmptyDOMElement()
  })
})
