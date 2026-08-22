export type ExplanationParagraph = {
  option?: string
  text: string
}

const answerHeading = /^\s*答案\s*[A-D]\s*解析\s*/u
const explanationLabel = '[A-D①②③④⑤⑥⑦⑧⑨⑩]'
const optionConclusion = new RegExp(`(?:^|[，,。；;\\s])(${explanationLabel})\\s*(?:项)?\\s*(?:正确|错误)(?=\\s*[。；;]?$)`, 'u')
const leadingOption = new RegExp(`^\\s*(${explanationLabel})\\s*(?:[.．、：:]|项(?:认为|中|，|,|：|:|是|的)?|(?:正确|错误)(?:[，,:：]?))`, 'u')
const terminalAnswer = /^\s*(?:故|因此|所以)?\s*(?:答案|选择|选)\s*[A-D]\s*[。.]?\s*$/u

function normalizeExplanationText(value: string) {
  return value
    .replace(answerHeading, '')
    .replace(/[\r\n]+/gu, '；')
    .replace(/\t+/gu, ' ')
    .replace(/\s{2,}/gu, ' ')
    .trim()
}

export function splitAnswerExplanation(value: string): ExplanationParagraph[] {
  const normalized = normalizeExplanationText(value)
  if (!normalized) return []

  const clauses = normalized.split(/[；;]/u).map((item) => item.trim()).filter(Boolean)
  const grouped: ExplanationParagraph[] = []
  for (const text of clauses) {
    if (terminalAnswer.test(text)) continue
    const leading = text.match(leadingOption)
    const option = leading?.[1] ?? text.match(optionConclusion)?.[1]
    if (option) grouped.push({ option, text: leading ? text.slice(leading[0].length).trim() : text })
    else if (grouped.length > 0) grouped[grouped.length - 1].text = `${grouped[grouped.length - 1].text}；${text}`
  }
  if (new Set(grouped.map((item) => item.option)).size >= 2) return grouped
  return [{ text: normalized }]
}
