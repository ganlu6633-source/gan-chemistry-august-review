import { describe, expect, it } from 'vitest'
import type { KnowledgeCard } from '../domain/types'
import { getKnowledgeReviewPoints } from '../domain/knowledgeReviewPoints'
import { knowledgeLegacyLeafExamples } from './knowledgeLegacyLeafExamples'

const legacyCards = [
  ['KC_H1_MATERIAL_ATOM', 'H1_MATERIAL_ATOM'],
  ['KC_H1_MATERIAL_DISPERSION', 'H1_MATERIAL_DISPERSION'],
  ['KC_H1_MATERIAL_EXPERIMENT', 'H1_MATERIAL_EXPERIMENT'],
  ['KC_H1_MATERIAL_SEAWATER', 'H1_MATERIAL_SEAWATER'],
  ['KC_J_CHEM_LANG', 'J_CHEM_LANG'],
  ['KC_J_EXPERIMENT', 'J_EXPERIMENT'],
  ['KC-J_KY_1_1_K01', 'J_KY_1_1_K01'],
  ['KC-J_KY_1_1_K02', 'J_KY_1_1_K02'],
  ['KC-J_KY_1_1_K03', 'J_KY_1_1_K03'],
  ['CARD_J_ATOM', 'J09_ATOM'],
  ['KC_J09_ATOM', 'J09_ATOM'],
] as const

function cardStub(id: string, skillId: string): KnowledgeCard {
  return {
    id, skillId, title: id, core: '原知识卡核心', detail: '原知识卡说明',
    steps: [], commonMistakes: [], microExample: '整张卡的旧示例', reviewStatus: 'approved',
  }
}

describe('legacy knowledge point examples', () => {
  it('covers each reviewed legacy leaf exactly once without falling back to the card-wide example', () => {
    const pointIds = legacyCards.flatMap(([id, skillId]) =>
      getKnowledgeReviewPoints(cardStub(id, skillId)).map((point) => point.id))

    expect(pointIds).toHaveLength(45)
    expect(Object.keys(knowledgeLegacyLeafExamples).sort()).toEqual([...pointIds].sort())
    for (const pointId of pointIds) {
      const examples = knowledgeLegacyLeafExamples[pointId]
      expect(examples, pointId).toHaveLength(1)
      expect(examples[0].trim().length, pointId).toBeGreaterThan(18)
      expect(examples[0], pointId).not.toBe('整张卡的旧示例')
    }
  })

  it('keeps easily confused ideas on their own matching leaf', () => {
    expect(knowledgeLegacyLeafExamples['KC_H1_MATERIAL_ATOM:s0:i3:p0'][0]).toContain('碳-12与碳-14')
    expect(knowledgeLegacyLeafExamples['KC_H1_MATERIAL_DISPERSION:s0:i4:p0'][0]).toContain('半透膜')
    expect(knowledgeLegacyLeafExamples['KC_H1_MATERIAL_EXPERIMENT:s0:i5:p0'][0]).toContain('AgCl')
    expect(knowledgeLegacyLeafExamples['KC_H1_MATERIAL_SEAWATER:s0:i2:p0'][0]).toContain('先加BaCl₂')
    expect(knowledgeLegacyLeafExamples['KC_J_CHEM_LANG:s0:i0:p0'][0]).toContain('2H₂O')
    expect(knowledgeLegacyLeafExamples['KC_J_CHEM_LANG:s0:i2:p0'][0]).toContain('铁生锈')
    expect(knowledgeLegacyLeafExamples['KC_J_EXPERIMENT:s0:i2:p0'][0]).toContain('凹液面')
    expect(knowledgeLegacyLeafExamples['KC_J_EXPERIMENT:s0:i3:p0'][0]).toContain('实际取到的液体少于10 mL')
    expect(knowledgeLegacyLeafExamples['KC_J09_ATOM:s0:i0:p0'][0]).toContain('11个质子')
    expect(knowledgeLegacyLeafExamples['KC_J09_ATOM:s0:i2:p0'][0]).toContain('10个电子')
  })
})
