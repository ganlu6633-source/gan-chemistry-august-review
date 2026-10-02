import { describe, expect, it } from 'vitest'
import type { KnowledgeWorkedExample, StructuredKnowledgeContent } from '../domain/types'
// @ts-expect-error The authored content generator is an ESM JavaScript module without declarations.
import { zeroForgettingCards } from '../../scripts/zero-forgetting-content.mjs'

type GeneratedContent = StructuredKnowledgeContent & {
  skillId: string
  overview: string[]
  workedExamples: KnowledgeWorkedExample[]
}

describe('the released high-one redox card', () => {
  it('keeps the current version and links each role to the reactant whose valence changes', () => {
    const contents = zeroForgettingCards as GeneratedContent[]
    const content = contents.find((entry) => entry.skillId === 'H1_REDOX')!
    expect(content.version).toBe(3)
    expect(contents.filter((entry) => entry.skillId !== 'H1_REDOX').every((entry) => entry.version === 2)).toBe(true)
    expect(content.overview[1]).toBe('升价=失电子=被氧化=发生氧化反应；发生变化的反应物是还原剂，生成氧化产物。')
    expect(content.overview[2]).toBe('降价=得电子=被还原=发生还原反应；发生变化的反应物是氧化剂，生成还原产物。')
  })

  it('uses concise reviewed labels while keeping role explanations and all conservation checks', () => {
    const content = (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === 'H1_REDOX')!
    const roles = content.workedExamples.find((entry) => entry.substance === 'Fe²⁺和Cl₂的身份链')!
    expect(roles.labels).toEqual(['升价失电子', '还原剂被氧化', '降价得电子', '氧化剂被还原'])
    expect(roles.path).toContain('Fe²⁺是还原剂，Fe³⁺是氧化产物')
    expect(roles.path).toContain('Cl₂是氧化剂，Cl⁻是还原产物')
    const sodium = content.workedExamples.find((entry) => entry.substance === '2Na+Cl₂→2NaCl')!
    expect(sodium.labels).toEqual(['升失氧', '降得还', '得失电子相等'])
    expect(sodium.path).toContain('NaCl也是还原产物')
    const alkaline = content.sections.find((entry) => entry.title === '歧化、归中与缺项配平')!
      .items.find((entry) => entry.label === '碱性介质缺项：最后只留氢氧根和水')!
    expect(alkaline.visualSteps?.at(-1)).toBe('最终无H⁺并查三守恒')
    expect(alkaline.examples?.join('')).toContain('Cl₂+2OH⁻=Cl⁻+ClO⁻+H₂O')
  })
})
