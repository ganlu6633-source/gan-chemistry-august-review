import { describe, expect, it } from 'vitest'
import { buildRecoveryTargets } from './learningRecovery'

const question = (id: string, conceptKey = 'H3_ELECTRO__C01') => ({ id, skillId: 'H3_ELECTRO', conceptKey })
const answer = (questionId: string, correct: boolean) => ({ questionId, skillId: 'H3_ELECTRO', motherId: questionId,
  level: 1, correct, uncertain: false, durationSec: 5, selectedOption: 1 })

describe('buildRecoveryTargets', () => {
  it('uses a verified wrong-option branch and groups its follow-up mistakes under that precise point', () => {
    const targets = buildRecoveryTargets({ questions: [question('anchor'), { ...question('drill'), optionPractice: {
      anchorQuestionId: 'anchor', optionIndex: 1, knowledgePoint: '电极判断', position: 1, total: 3,
    } }], answers: [answer('anchor', false), answer('drill', false)], branches: [{ anchorQuestionId: 'anchor',
      optionIndex: 1, knowledgePoint: '电极判断', questionIds: ['drill'], answered: 1, correct: 0, status: 'practicing' }],
    cards: [], pointRatings: {}, conceptTitles: {} })
    expect(targets).toMatchObject([{ title: '电极判断', wrongCount: 2, branch: { status: 'practicing' } }])
  })

  it('does not invent an option-level diagnosis when the binding is missing', () => {
    const targets = buildRecoveryTargets({ questions: [question('anchor')], answers: [answer('anchor', false)], branches: [],
      cards: [], pointRatings: {}, conceptTitles: { H3_ELECTRO__C01: '原电池与燃料电池放电原理' } })
    expect(targets).toMatchObject([{ title: '原电池与燃料电池放电原理', branch: null, conceptKey: 'H3_ELECTRO__C01' }])
  })

  it('uses the current wrong reserve as the next-round anchor in choice training', () => {
    const targets = buildRecoveryTargets({ questions: [question('anchor'), { ...question('drill'),
      choiceContext: { recoveryRound: 1 }, optionPractice: { anchorQuestionId: 'anchor', optionIndex: 1,
        knowledgePoint: '电极判断', position: 3, total: 3 } }],
      answers: [answer('anchor', false), answer('drill', false)], branches: [
        { anchorQuestionId: 'anchor', optionIndex: 1, knowledgePoint: '电极判断', questionIds: ['drill'], answered: 3, correct: 2, status: 'needs_practice' },
        { anchorQuestionId: 'drill', optionIndex: 1, knowledgePoint: '电子经过外电路的方向', questionIds: ['next'], answered: 0, correct: 0, status: 'practicing' },
      ], cards: [], pointRatings: {}, conceptTitles: {} })
    expect(targets).toContainEqual(expect.objectContaining({ anchorQuestionId: 'drill', title: '电子经过外电路的方向', wrongCount: 1 }))
    expect(targets).toContainEqual(expect.objectContaining({ anchorQuestionId: 'anchor', title: '电极判断', wrongCount: 1 }))
  })

  it('does not reuse a prior option diagnosis when the new reserve has no verified micro-point', () => {
    const targets = buildRecoveryTargets({ questions: [question('anchor'), { ...question('drill', 'H3_ELECTRO__C04'),
      choiceContext: { recoveryRound: 1 }, optionPractice: { anchorQuestionId: 'anchor', optionIndex: 1,
        knowledgePoint: '电极判断', position: 3, total: 3 } }],
      answers: [answer('anchor', false), answer('drill', false)], branches: [
        { anchorQuestionId: 'anchor', optionIndex: 1, knowledgePoint: '电极判断', questionIds: ['drill'], answered: 3, correct: 2, status: 'needs_practice' },
        { anchorQuestionId: 'drill', optionIndex: 1, knowledgePoint: '', questionIds: [], answered: 0, correct: 0, status: 'reserve_gap' },
      ], cards: [], pointRatings: {}, conceptTitles: { H3_ELECTRO__C04: '离子交换膜与离子迁移' } })
    expect(targets).toContainEqual(expect.objectContaining({ anchorQuestionId: 'drill', title: '离子交换膜与离子迁移', branch: null }))
  })

  it('keeps correct but uncertain answers for review without calling them wrong', () => {
    const targets = buildRecoveryTargets({ questions: [{ ...question('anchor'), choiceContext: { recoveryRound: 0 } }],
      answers: [{ ...answer('anchor', true), uncertain: true }], branches: [], cards: [], pointRatings: {},
      conceptTitles: { H3_ELECTRO__C01: '原电池与燃料电池放电原理' } })
    expect(targets).toMatchObject([{ anchorQuestionId: 'anchor', title: '原电池与燃料电池放电原理', wrongCount: 0, uncertainCount: 1 }])
  })
})
