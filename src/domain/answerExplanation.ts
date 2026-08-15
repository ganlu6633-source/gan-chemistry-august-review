export type ExplanationParagraph = {
  option?: string
  text: string
}

const answerHeading = /^\s*答案\s*[A-D]\s*解析\s*/u
const optionConclusion = /(?:^|[，,。；;\s])([A-D])\s*(?:项)?\s*(?:正确|错误)(?=\s*[。；;]?$)/u

function normalizeExplanationText(value: string) {
  return value
    .replace(answerHeading, '')
    .replace(/[\r\n\t]+/gu, ' ')
    .replace(/\s{2,}/gu, ' ')
    .trim()
}

export function splitAnswerExplanation(value: string): ExplanationParagraph[] {
  const normalized = normalizeExplanationText(value)
  if (!normalized) return []

  const clauses = normalized.split(/[；;]/u).map((item) => item.trim()).filter(Boolean)
  const optionClauses = clauses.map((text) => ({ option: text.match(optionConclusion)?.[1], text }))
  if (optionClauses.length > 1 && optionClauses.every((item) => item.option)) return optionClauses
  return [{ text: normalized }]
}
