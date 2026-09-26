import { describe, expect, it } from 'vitest'
import type { KnowledgeCard } from './types'
import { getKnowledgeReviewPoints } from './knowledgeReviewPoints'
import { buildRecoveryTargets } from './learningRecovery'

const card: KnowledgeCard = {
  id: 'mole-card', skillId: 'H1_MOLE_INTRO', title: '物质的量', core: 'n=m/M，m=nM', detail: '',
  steps: [], commonMistakes: [], microExample: '', reviewStatus: 'approved',
  structuredContent: { version: 1, intro: '逐点学习', sections: [
    { title: '先认清', items: [{ label: '物质的量n', rule: '单位是mol。' }] },
    { title: '摩尔质量与质量换算', items: [{ label: '质量—物质的量', rule: 'n=m/M，m=nM。写公式前先统一g与g·mol⁻¹。' }] },
  ] },
}

describe('fine-grained knowledge review', () => {
  it('asks for each conversion direction separately while retaining its source card', () => {
    const points = getKnowledgeReviewPoints(card)
    expect(points.map((point) => point.title)).toEqual(['物质的量n', '已知质量 m，求物质的量 n', '已知物质的量 n，求质量 m'])
    expect(points[1].rule).toContain('n=m/M')
    expect(points[2].rule).toContain('m=nM')
    expect(new Set(points.map((point) => point.id)).size).toBe(3)
  })

  it('keeps mixed self-ratings separate rather than treating the whole card as unknown', () => {
    const [known, unknown, familiar] = getKnowledgeReviewPoints(card)
    const targets = buildRecoveryTargets({ questions: [], answers: [], branches: [], cards: [card],
      pointRatings: { [known.id]: 'fluent', [unknown.id]: 'unknown', [familiar.id]: 'familiar' }, conceptTitles: {} })
    expect(targets.map((target) => target.pointId)).toEqual([unknown.id, familiar.id])
    expect(targets.map((target) => target.title)).toEqual([unknown.title, familiar.title])
  })

  it('separates temperature measurement, temperature difference and heat calculation', () => {
    const thermo: KnowledgeCard = { ...card, id: 'thermo-card', skillId: 'H2_THERMO',
      structuredContent: { version: 1, intro: '反应热', sections: [{ title: '中和热实验', items: [{ label: '核心关系',
        rule: '取反应前的初始温度T₁和混合后的最高温度T₂，ΔT=T₂−T₁；一定近似下q=mcΔT。' }] }] } }
    const points = getKnowledgeReviewPoints(thermo)
    expect(points.map((point) => point.title)).toContain('温度差 ΔT 怎样算')
    expect(points.map((point) => point.title)).toContain('由温度差求热量 q')
    expect(points).toHaveLength(5)
  })

  it('gives older unstructured cards a question for each audited fact', () => {
    const older: KnowledgeCard = { ...card, id: 'KC_H1_MATERIAL_ATOM', skillId: 'H1_MATERIAL_ATOM', structuredContent: undefined }
    const points = getKnowledgeReviewPoints(older)
    expect(points.map((point) => point.title)).toContain('由质量数求中子数')
    expect(points.map((point) => point.title)).toContain('同位素怎样判断')
    expect(points).toHaveLength(5)
  })
})
