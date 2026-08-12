export type AdaptiveQuestion = { id: string; skill_id: string; level: number }
export type AdaptiveState = { skill_id: string; verified_level?: number | null; consecutive_errors?: number | null; next_review_at?: string | null }
export type AdaptiveAnswer = { question_id: string; correct: boolean }

/**
 * Ranks approved in-scope questions against the learner's current evidence.
 * It first guarantees coverage of every skill in the plan, then fills the
 * remaining budget with the most useful unseen, due or previously-missed items.
 */
export function selectAdaptiveQuestions<T extends AdaptiveQuestion>(
  questions: T[],
  states: AdaptiveState[],
  history: AdaptiveAnswer[],
  attemptSequence: number,
  limit = 7,
  now = new Date(),
): T[] {
  const stateBySkill = new Map(states.map((state) => [state.skill_id, state]))
  const historyByQuestion = new Map<string, { correct: number; wrong: number }>()
  for (const answer of history) {
    const item = historyByQuestion.get(answer.question_id) ?? { correct: 0, wrong: 0 }
    if (answer.correct) item.correct += 1
    else item.wrong += 1
    historyByQuestion.set(answer.question_id, item)
  }

  const ranked = questions.map((question, sourceIndex) => {
    const state = stateBySkill.get(question.skill_id)
    const evidence = historyByQuestion.get(question.id)
    const targetLevel = Math.max(1, Number(state?.verified_level ?? 0) + 1)
    const due = !state?.next_review_at || new Date(state.next_review_at) <= now
    const rotation = (sourceIndex - attemptSequence + questions.length) % Math.max(questions.length, 1)
    const score =
      (evidence ? evidence.wrong * 15 - evidence.correct * 5 : 12) +
      Number(state?.consecutive_errors ?? 0) * 4 +
      (due ? 4 : 0) -
      Math.abs(Number(question.level) - targetLevel) * 2
    return { question, score, rotation }
  }).sort((a, b) => b.score - a.score || a.rotation - b.rotation || a.question.id.localeCompare(b.question.id))

  const selected: T[] = []
  const selectedIds = new Set<string>()
  const skills = [...new Set(questions.map((question) => question.skill_id))]
  for (const skillId of skills) {
    const candidate = ranked.find((item) => item.question.skill_id === skillId && !selectedIds.has(item.question.id))
    if (candidate && selected.length < limit) {
      selected.push(candidate.question)
      selectedIds.add(candidate.question.id)
    }
  }
  for (const item of ranked) {
    if (selected.length >= limit) break
    if (!selectedIds.has(item.question.id)) {
      selected.push(item.question)
      selectedIds.add(item.question.id)
    }
  }
  return selected
}
