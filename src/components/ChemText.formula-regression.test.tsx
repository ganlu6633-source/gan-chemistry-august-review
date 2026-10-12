import { render } from '@testing-library/react'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { ChemText } from './ChemText'

describe('complete formulas and reaction notation', () => {
  it.each([
    ['Li2CO3', ['2', '3']],
    ['Li2O2', ['2', '2']],
    ['Fe2O3', ['2', '3']],
    ['Na2CO3', ['2', '3']],
    ['Ca(HCO3)2', ['3', '2']],
    ['Al2(SO4)3', ['2', '4', '3']],
    ['(NH4)2SO4', ['4', '2', '4']],
    ['CuSO4·5H2O', ['4', '2']],
    ['(NH4)2Fe(SO4)2·6H2O', ['4', '2', '4', '2', '2']],
  ])('keeps atom counts and hydrate coefficients in %s', (value, counts) => {
    const { container } = render(<p><ChemText>{value as string}</ChemText></p>)
    expect(container.textContent).toBe(value)
    expect([...container.querySelectorAll('sub')].map((node) => node.textContent)).toEqual(counts)
    expect(container.querySelector('sup')).toBeNull()
    expect(container.querySelectorAll('.chem-symbol')).toHaveLength(1)
    expect(container.querySelector('.chem-symbol')).toHaveStyle({ display: 'inline-block' })
  })

  it.each(['2Li₂O₂', '3O₂', 'H₂SO₄', 'Ba²⁺', '[Fe(CN)₆]⁴⁻', '(NH₄)₂SO₄'])('keeps the whole Unicode formula %s together', (value) => {
    const { container } = render(<p><ChemText>{value}</ChemText></p>)
    expect(container.textContent).toBe(value)
    expect(container.querySelectorAll('.chem-symbol')).toHaveLength(1)
    expect(container.querySelector('.chem-symbol')).toHaveAttribute('aria-label', value)
  })

  it.each([
    ['Fe2+', [], '2+'],
    ['2Fe3+', [], '3+'],
    ['NH4+', ['4'], '+'],
    ['SO4^2-', ['4'], '2-'],
    ['[Fe(CN)6]^4-', ['6'], '4-'],
    ['[Fe(CN)6]4-', ['6'], '4-'],
    ['2[Fe(CN)6]4-', ['6'], '4-'],
    ['[SO4]2-', ['4'], '2-'],
    ['[Fe(CN)6]4^-', ['6', '4'], '-'],
    ['[SO4]2^-', ['4', '2'], '-'],
  ])('distinguishes ion charge from atom or group count in %s', (value, counts, charge) => {
    const { container } = render(<p><ChemText>{value as string}</ChemText></p>)
    expect([...container.querySelectorAll('sub')].map((node) => node.textContent)).toEqual(counts)
    expect([...container.querySelectorAll('sup')].map((node) => node.textContent)).toEqual([charge])
    expect(container.textContent).toBe((value as string).replaceAll('^', ''))
  })

  it('keeps the neutral bracket compound neutral', () => {
    const { container } = render(<p><ChemText>K4[Fe(CN)6]</ChemText></p>)
    expect([...container.querySelectorAll('sub')].map((node) => node.textContent)).toEqual(['4', '6'])
    expect(container.querySelector('sup')).toBeNull()
    expect(container.textContent).toBe('K4[Fe(CN)6]')
  })

  it.each(['2H2+O2→2H2O', '2H2+O2->2H2O', '2KMnO4→K2MnO4+MnO2+O2（加热）'])('keeps reaction separators and arrows in %s', (value) => {
    const { container } = render(<p><ChemText>{value}</ChemText></p>)
    expect(container.textContent).toBe(value)
    expect(container.querySelector('sup')).toBeNull()
    if (value.startsWith('2H2')) {
      expect([...container.querySelectorAll('sub')].map((node) => node.textContent)).toEqual(['2', '2', '2'])
    }
  })

  it.each(['e^-', '2e^-'])('renders the explicit electron charge in %s', (value) => {
    const { container } = render(<p><ChemText>{value}</ChemText></p>)
    expect(container.textContent).toBe(value.replace('^', ''))
    expect([...container.querySelectorAll('sup')].map((node) => node.textContent)).toEqual(['-'])
    expect(container.querySelector('sub')).toBeNull()
  })

  it('keeps chlorine molecular count and the electron charge separate', () => {
    const { container } = render(<p><ChemText>{'2Cl^- ->Cl2+2e^-'}</ChemText></p>)
    expect(container.textContent).toBe('2Cl- ->Cl2+2e-')
    expect([...container.querySelectorAll('sub')].map((node) => node.textContent)).toEqual(['2'])
    expect([...container.querySelectorAll('sup')].map((node) => node.textContent)).toEqual(['-', '-'])
    expect(container.querySelector('[aria-label="Cl2"]')).toHaveTextContent('Cl2')
  })

  it('keeps iron ion charge before an electron reaction separator', () => {
    const { container } = render(<p><ChemText>{'Fe2++2e^- ->Fe'}</ChemText></p>)
    expect(container.textContent).toBe('Fe2++2e- ->Fe')
    expect([...container.querySelectorAll('sup')].map((node) => node.textContent)).toEqual(['2+', '-'])
    expect(container.querySelector('sub')).toBeNull()
  })

  it('keeps a separator before a literal Unicode electron', () => {
    const { container } = render(<p><ChemText>Cl2+2e⁻</ChemText></p>)
    expect(container.textContent).toBe('Cl2+2e⁻')
    expect([...container.querySelectorAll('sub')].map((node) => node.textContent)).toEqual(['2'])
    expect(container.querySelector('sup')).toBeNull()
  })

  it.each(['', ' ', '   '])('keeps reaction separators with a coefficient followed by "%s"', (gap) => {
    const chlorine = render(<p><ChemText>{`Cl2+2${gap}e^-→2Cl^-`}</ChemText></p>)
    expect([...chlorine.container.querySelectorAll('sub')].map((node) => node.textContent)).toEqual(['2'])
    expect([...chlorine.container.querySelectorAll('sup')].map((node) => node.textContent)).toEqual(['-', '-'])
    expect(chlorine.container.textContent).toBe(`Cl2+2${gap}e-→2Cl-`)
    chlorine.unmount()

    const unicode = render(<p><ChemText>{`Cl2+2${gap}e⁻→2Cl⁻`}</ChemText></p>)
    expect([...unicode.container.querySelectorAll('sub')].map((node) => node.textContent)).toEqual(['2'])
    expect(unicode.container.querySelector('sup')).toBeNull()
    expect(unicode.container.textContent).toBe(`Cl2+2${gap}e⁻→2Cl⁻`)
    unicode.unmount()

    const water = render(<p><ChemText>{`2H2+1${gap}O2→2H2O`}</ChemText></p>)
    expect([...water.container.querySelectorAll('sub')].map((node) => node.textContent)).toEqual(['2', '2', '2'])
    expect(water.container.querySelector('sup')).toBeNull()
    water.unmount()

    const iron = render(<p><ChemText>{`Fe2++2${gap}e^-→Fe`}</ChemText></p>)
    expect([...iron.container.querySelectorAll('sup')].map((node) => node.textContent)).toEqual(['2+', '-'])
    expect(iron.container.querySelector('sub')).toBeNull()
    iron.unmount()
  })

  it.each(['cm^3', 'dm^3', 'cm ^ 3', '2.5 dm^3'])('renders explicit volume units in %s', (value) => {
    const { container } = render(<p><ChemText>{value}</ChemText></p>)
    expect([...container.querySelectorAll('sup')].map((node) => node.textContent)).toEqual(['3'])
    expect(container.querySelector('sub')).toBeNull()
    expect(container.textContent).toBe(value.replace(/\s*\^\s*/g, ''))
  })

  it.each(['K-273', 'K−273', 'K－273', 'K - 273'])('keeps the temperature subtraction %s on the baseline', (value) => {
    const { container } = render(<p><ChemText>{value}</ChemText></p>)
    expect(container.textContent).toBe(value)
    expect(container.querySelector('sub,sup')).toBeNull()
  })

  it('retains an explicitly requested Kelvin exponent', () => {
    const { container } = render(<p><ChemText>K^-273</ChemText></p>)
    expect(container.querySelector('sup')).toHaveTextContent('−273')
  })

  it.each(['e^-x', 'some^-', 'x^3', 'cm^2', 'dm^2', 'cm^30', 'cm^3x', 'dm^3x'])('does not expand supported notation into %s', (value) => {
    const { container } = render(<p><ChemText>{value}</ChemText></p>)
    expect(container.textContent).toBe(value)
    expect(container.querySelector('sub,sup')).toBeNull()
  })

  it('keeps numbered Chinese prose and answer choices unchanged', () => {
    const value = '第2轮：9.2 g、320 kg、0.6 g，选A、B、C、D；从前一题继续。'
    const { container } = render(<p><ChemText>{value}</ChemText></p>)
    expect(container.textContent).toBe(value)
    expect(container.querySelector('sub,sup,.chem-symbol')).toBeNull()
  })

  it('keeps temperature subtraction correct after the actual page notation script runs', async () => {
    const values = ['K-273', 'K−273', 'K－273', 'K - 273']
    const { container } = render(<section className="knowledge-card">{values.map((value) => <p key={value}><ChemText>{value}</ChemText></p>)}</section>)
    const pageScript = readFileSync(resolve(process.cwd(), 'public/chem-notation-patch.js'), 'utf8')
    const observers: MutationObserver[] = []
    class PageObserver extends MutationObserver {
      constructor(callback: MutationCallback) {
        super(callback)
        observers.push(this)
      }
    }
    // Exercise the actual script loaded by app.html, including its observer.
    try {
      new Function('document', 'NodeFilter', 'MutationObserver', 'Element', 'Node', pageScript)(document, NodeFilter, PageObserver, Element, Node)
      await Promise.resolve()
      expect([...container.querySelectorAll('p')].map((node) => node.textContent)).toEqual(values)
      expect(container.querySelector('sub,sup')).toBeNull()
      const inserted = container.querySelector('p')!.cloneNode(true) as HTMLParagraphElement
      delete inserted.dataset.chemNotationReady
      container.querySelector('section')!.append(inserted)
      await Promise.resolve()
      expect(inserted.dataset.chemNotationReady).toBe('true')
      expect(inserted.textContent).toBe('K-273')
      expect(inserted.querySelector('sub,sup')).toBeNull()
    } finally {
      observers.forEach((observer) => observer.disconnect())
    }
  })
})
