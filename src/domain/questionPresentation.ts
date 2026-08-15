const SOURCE_HINT = /(?:20\d{2}|高考|模拟|联考|校考|卷|省|市|区|中学)/

export function stripLeadingQuestionSource(value: string) {
  return value.replace(/^(\s*(?:\d+\s*[．.、]\s*)?)[（(]([^）)\r\n]{2,80})[）)]\s*/, (match, prefix: string, label: string) => (
    SOURCE_HINT.test(label) ? prefix : match
  ))
}
