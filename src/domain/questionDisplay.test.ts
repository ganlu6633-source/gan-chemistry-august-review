import { describe, expect, it } from 'vitest'
import { displayQuestionStem } from './questionDisplay'

describe('displayQuestionStem', () => {
  it('shows a verified imported A–D block once', () => {
    const stem = '下列说法正确的是\nA．钠是单质\nB．水是混合物\nC．盐酸是纯净物\nD．氧气是化合物'
    expect(displayQuestionStem(stem, ['钠是单质', '水是混合物', '盐酸是纯净物', '氧气是化合物']))
      .toBe('下列说法正确的是')
  })

  it('keeps the original text when even one option differs', () => {
    const stem = '下列说法正确的是\nA．钠是单质\nB．水是混合物\nC．盐酸是纯净物\nD．氧气是化合物'
    expect(displayQuestionStem(stem, ['钠是单质', '水是混合物', '盐酸是纯净物', '氧气是单质']))
      .toBe(stem)
  })

  it('handles a legacy escaped newline and tab-delimited labels', () => {
    const stem = '题干\\nA．甲\\tB．乙\\nC．丙\\tD．丁'
    expect(displayQuestionStem(stem, ['甲', '乙', '丙', '丁'])).toBe('题干')
  })

  it('does not confuse element placeholders in the question with option labels', () => {
    const stem = 'A、B、C 均为短周期元素，求三者分别为\nA.Be、Na、Al\nB.B、Mg、Si\nC.O、P、Cl\nD.C、Al、P'
    expect(displayQuestionStem(stem, ['Be、Na、Al', 'B、Mg、Si', 'O、P、Cl', 'C、Al、P']))
      .toBe('A、B、C 均为短周期元素，求三者分别为')
  })
})
