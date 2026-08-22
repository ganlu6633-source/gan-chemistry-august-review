const SOURCE_HINT = /(?:20\d{2}|\d{2}\s*[-—–]\s*\d{2}\s*学年|高[一二三](?:上|下)?|高考|选考|学业考试|适应性考试|模拟|联考|校考|期中|期末|月考|质检|调研|测试|一模|二模|三检|卷|省|市|区|中学)/
const PRACTICE_HEADING = /^\s*(?:[▌|]?\s*对点练\s*\d+(?:\s*[-—–]\s*\d+)?|【\s*典例\s*\d*\s*】)\s*/u

export function stripLeadingQuestionSource(value: string) {
  let result = value.replace(PRACTICE_HEADING, '')
  // A source marker can follow a practice heading and/or the original question
  // number. Remove only exam/source-like parentheses; keep chemistry conditions
  // such as “（25 ℃）” and real subquestion markers such as “（1）”.
  result = result.replace(/^(\s*(?:\d+\s*[．.、]\s*)?)[（(]([^）)\r\n]{2,100})[）)]\s*/u, (match, prefix: string, label: string) => (
    SOURCE_HINT.test(label) ? prefix : match
  ))
  return result
}
