import { render } from '@testing-library/react'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { ChemText } from './ChemText'

const hessExamples = [
  'ΔH₃=ΔH₁+ΔH₂',
  'ΔH₃=ΔH₁-ΔH₂',
  'ΔH₃=-(ΔH₁+ΔH₂)',
  '①A+B=C+D ΔH₁；②C+D=E ΔH₂；③A+B=E ΔH₃。',
  'A+B->C+D ΔH₁；C+D->E ΔH₂。',
  '将①A+B→C+D和②C+D→E相加，消去中间组分C+D得到③A+B→E，所以ΔH₃=ΔH₁+ΔH₂。',
]

describe('enthalpy arithmetic in real question and feedback text', () => {
  it.each(hessExamples)('keeps arithmetic operators and source indices in %s', (value) => {
    const { container } = render(<p><ChemText>{value}</ChemText></p>)
    expect(container.textContent).toBe(value)
    expect(container.querySelector('sup,sub')).toBeNull()
  })

  it('retains ion charges in text that also contains enthalpy arithmetic', () => {
    const value = 'ΔH₃=ΔH₁-ΔH₂；Fe2++2H+；H+'
    const { container } = render(<p><ChemText>{value}</ChemText></p>)
    expect(container.textContent).toBe(value)
    expect([...container.querySelectorAll('sup')].map((node) => node.textContent)).toEqual(['2+', '+', '+'])
    expect(container.querySelector('sub')).toBeNull()
  })

  it('keeps a real chemical reaction separate from abstract Hess placeholders', () => {
    const value = 'A+B=C+D ΔH₁；C+D=E ΔH₂；2H2+O2→2H2O'
    const { container } = render(<p><ChemText>{value}</ChemText></p>)
    expect(container.textContent).toBe(value)
    expect([...container.querySelectorAll('sub')].map((node) => node.textContent)).toEqual(['2', '2', '2'])
    expect(container.querySelector('sup')).toBeNull()
  })

  it('retains the arithmetic after the production notation script and its observer', async () => {
    const { container } = render(<section className="answer-explanation">{hessExamples.map((value) => <p key={value}><ChemText>{value}</ChemText></p>)}</section>)
    const pageScript = readFileSync(resolve(process.cwd(), 'public/chem-notation-patch.js'), 'utf8')
    const observers: MutationObserver[] = []
    class PageObserver extends MutationObserver {
      constructor(callback: MutationCallback) {
        super(callback)
        observers.push(this)
      }
    }
    try {
      new Function('document', 'NodeFilter', 'MutationObserver', 'Element', 'Node', pageScript)(document, NodeFilter, PageObserver, Element, Node)
      await Promise.resolve()
      expect([...container.querySelectorAll('p')].map((node) => node.textContent)).toEqual(hessExamples)
      expect(container.querySelector('sup,sub')).toBeNull()
      const inserted = container.querySelector('p')!.cloneNode(true) as HTMLParagraphElement
      delete inserted.dataset.chemNotationReady
      container.querySelector('section')!.append(inserted)
      await Promise.resolve()
      expect(inserted.dataset.chemNotationReady).toBe('true')
      expect(inserted.textContent).toBe(hessExamples[0])
      expect(inserted.querySelector('sup,sub')).toBeNull()
    } finally {
      observers.forEach((observer) => observer.disconnect())
    }
  })
})
