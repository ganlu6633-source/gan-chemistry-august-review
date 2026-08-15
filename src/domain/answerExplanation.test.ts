import { describe, expect, it } from 'vitest'
import { splitAnswerExplanation } from './answerExplanation'

describe('splitAnswerExplanation', () => {
  it('removes the copied answer heading and separates A-D explanations', () => {
    expect(splitAnswerExplanation('答案\nB\n解析\nA项条件不成立，A错误；B项计算结果为10%，B正确；C项浓度应在3～6之间，C错误；D项缺少密度，D错误。')).toEqual([
      { option: 'A', text: 'A项条件不成立，A错误' },
      { option: 'B', text: 'B项计算结果为10%，B正确' },
      { option: 'C', text: 'C项浓度应在3～6之间，C错误' },
      { option: 'D', text: 'D项缺少密度，D错误。' },
    ])
  })

  it('keeps an ordinary explanation as one paragraph', () => {
    expect(splitAnswerExplanation('先判断电子转移，再校验电荷守恒。')).toEqual([{ text: '先判断电子转移，再校验电荷守恒。' }])
  })

  it('keeps A-D option explanations separate and ignores a trailing answer sentence', () => {
    expect(splitAnswerExplanation('A．总体积不能直接相加，A错误；B．溶质质量守恒，B正确；C．混合后浓度介于两者之间，C错误；D．缺少密度，D错误；故选B。')).toEqual([
      { option: 'A', text: 'A．总体积不能直接相加，A错误' },
      { option: 'B', text: 'B．溶质质量守恒，B正确' },
      { option: 'C', text: 'C．混合后浓度介于两者之间，C错误' },
      { option: 'D', text: 'D．缺少密度，D错误' },
    ])
  })
})
