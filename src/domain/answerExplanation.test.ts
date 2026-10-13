import { describe, expect, it } from 'vitest'
import { splitAnswerExplanation } from './answerExplanation'

describe('splitAnswerExplanation', () => {
  it('removes the copied answer heading and separates A-D explanations', () => {
    expect(splitAnswerExplanation('答案\nB\n解析\nA项条件不成立，A错误；B项计算结果为10%，B正确；C项浓度应在3～6之间，C错误；D项缺少密度，D错误。')).toEqual([
      { option: 'A', text: '条件不成立，A错误' },
      { option: 'B', text: '计算结果为10%，B正确' },
      { option: 'C', text: '浓度应在3～6之间，C错误' },
      { option: 'D', text: '缺少密度，D错误。' },
    ])
  })

  it('keeps an ordinary explanation as one paragraph', () => {
    expect(splitAnswerExplanation('先判断电子转移，再校验电荷守恒。')).toEqual([{ text: '先判断电子转移，再校验电荷守恒。' }])
  })

  it('keeps A-D option explanations separate and ignores a trailing answer sentence', () => {
    expect(splitAnswerExplanation('A．总体积不能直接相加，A错误；B．溶质质量守恒，B正确；C．混合后浓度介于两者之间，C错误；D．缺少密度，D错误；故选B。')).toEqual([
      { option: 'A', text: '总体积不能直接相加，A错误' },
      { option: 'B', text: '溶质质量守恒，B正确' },
      { option: 'C', text: '混合后浓度介于两者之间，C错误' },
      { option: 'D', text: '缺少密度，D错误' },
    ])
  })

  it('recognizes concise option headings and numbered statement explanations', () => {
    expect(splitAnswerExplanation('A错误：总体积不能机械相加；B：溶质质量守恒，判断正确；C正确：按离子计量数换算；D：缺少密度，无法计算。')).toEqual([
      { option: 'A', text: '总体积不能机械相加' },
      { option: 'B', text: '溶质质量守恒，判断正确' },
      { option: 'C', text: '按离子计量数换算' },
      { option: 'D', text: '缺少密度，无法计算。' },
    ])
    expect(splitAnswerExplanation('①：该说法成立；②错误：忽略了水解；③：由电荷守恒可知错误。')).toEqual([
      { option: '①', text: '该说法成立' },
      { option: '②', text: '忽略了水解' },
      { option: '③', text: '由电荷守恒可知错误。' },
    ])
  })
})

describe('complete explanation paragraphs', () => {
  it('groups a semicolon continuation by its existing option without duplicating cards', () => {
    expect(splitAnswerExplanation('A项：产物总质量为64 g；碳氧化物只能全为CO，A错误；B项：由质量守恒求得56 g，B正确；C项：未满足题设比例，C错误；D项：最大质量为44 g；超过上限，D错误。')).toEqual([
      { option: 'A', text: '产物总质量为64 g；碳氧化物只能全为CO，A错误' },
      { option: 'B', text: '由质量守恒求得56 g，B正确' },
      { option: 'C', text: '未满足题设比例，C错误' },
      { option: 'D', text: '最大质量为44 g；超过上限，D错误。' },
    ])
  })

  it('preserves standalone option conclusions rather than stripping them empty', () => {
    expect(splitAnswerExplanation('A项：质量不守恒；A错误。；B项：质量守恒；B项正确。')).toEqual([
      { option: 'A', text: '质量不守恒；A错误。' },
      { option: 'B', text: '质量守恒；B项正确。' },
    ])
  })

  it('preserves calculation assumptions and intermediate prose before option labels', () => {
    expect(splitAnswerExplanation('已知n=2 mol；由m=nM可得m=36 g；A：不成立；B：成立；故选B。')).toEqual([
      { text: '已知n=2 mol；由m=nM可得m=36 g' },
      { option: 'A', text: '不成立' },
      { option: 'B', text: '成立' },
    ])
  })

  it('keeps repeated labels separated by another option in their original order', () => {
    expect(splitAnswerExplanation('A：第一判断；B：第二判断；A：独立第三判断')).toEqual([
      { option: 'A', text: '第一判断' },
      { option: 'B', text: '第二判断' },
      { option: 'A', text: '独立第三判断' },
    ])
  })

  it('preserves numbered statement conclusions', () => {
    expect(splitAnswerExplanation('①：推算；①错误；②：条件；②正确。')).toEqual([
      { option: '①', text: '推算；①错误' },
      { option: '②', text: '条件；②正确。' },
    ])
  })

  it('does not mistake a preface for an additional option and preserves unlabelled prose', () => {
    expect(splitAnswerExplanation('由条件得到结论；A错误。')).toEqual([{ text: '由条件得到结论；A错误。' }])
    expect(splitAnswerExplanation('只有普通推理；没有选项标签。')).toEqual([{ text: '只有普通推理；没有选项标签。' }])
    expect(splitAnswerExplanation('')).toEqual([])
  })
})
