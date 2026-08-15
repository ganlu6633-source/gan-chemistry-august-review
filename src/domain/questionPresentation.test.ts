import { describe, expect, it } from 'vitest'
import { stripLeadingQuestionSource } from './questionPresentation'

describe('stripLeadingQuestionSource', () => {
  it('removes an exam citation after the question number', () => {
    expect(stripLeadingQuestionSource('14．（2025·广东卷）设 N_A 为阿伏加德罗常数的值。')).toBe('14．设 N_A 为阿伏加德罗常数的值。')
  })

  it('does not remove chemistry conditions or subquestion markers', () => {
    expect(stripLeadingQuestionSource('（1）写出离子方程式。')).toBe('（1）写出离子方程式。')
    expect(stripLeadingQuestionSource('1．（25 ℃）测定该反应速率。')).toBe('1．（25 ℃）测定该反应速率。')
  })
})
