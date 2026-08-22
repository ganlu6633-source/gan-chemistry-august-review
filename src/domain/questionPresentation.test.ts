import { describe, expect, it } from 'vitest'
import { stripLeadingQuestionSource } from './questionPresentation'

describe('stripLeadingQuestionSource', () => {
  it('removes an exam citation after the question number', () => {
    expect(stripLeadingQuestionSource('14．（2025·广东卷）设 N_A 为阿伏加德罗常数的值。')).toBe('14．设 N_A 为阿伏加德罗常数的值。')
    expect(stripLeadingQuestionSource('7．（25-26 高一上·广东清远·期中）CaCl2常用于农业。')).toBe('7．CaCl2常用于农业。')
    expect(stripLeadingQuestionSource('【典例11】(2026·江苏南通期末) 8．下列说法正确的是')).toBe('8．下列说法正确的是')
    expect(stripLeadingQuestionSource('▌对点练2-1 3．下列说法正确的是')).toBe('3．下列说法正确的是')
  })

  it('does not remove chemistry conditions or subquestion markers', () => {
    expect(stripLeadingQuestionSource('（1）写出离子方程式。')).toBe('（1）写出离子方程式。')
    expect(stripLeadingQuestionSource('1．（25 ℃）测定该反应速率。')).toBe('1．（25 ℃）测定该反应速率。')
  })
})
