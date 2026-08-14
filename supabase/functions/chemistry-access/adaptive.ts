export type AdaptiveQuestion = { id: string; mother_id?: string; skill_id: string; level: number }
export type AdaptiveState = { skill_id: string; verified_level?: number | null; consecutive_errors?: number | null; next_review_at?: string | null }
export type AdaptiveAnswer = { question_id: string; mother_id?: string | null; skill_id?: string | null; correct: boolean; uncertain?: boolean | null }

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
  const unresolvedBySkill = new Map<string, number>()
  const unresolvedByMother = new Map<string, number>()
  for (const answer of history) {
    const item = historyByQuestion.get(answer.question_id) ?? { correct: 0, wrong: 0 }
    if (answer.correct && !answer.uncertain) item.correct += 1
    else item.wrong += 1
    historyByQuestion.set(answer.question_id, item)
    if (!answer.correct || answer.uncertain) {
      if (answer.skill_id) unresolvedBySkill.set(answer.skill_id, (unresolvedBySkill.get(answer.skill_id) ?? 0) + 1)
      if (answer.mother_id) unresolvedByMother.set(answer.mother_id, (unresolvedByMother.get(answer.mother_id) ?? 0) + 1)
    }
  }

  const ranked = questions.map((question, sourceIndex) => {
    const state = stateBySkill.get(question.skill_id)
    const evidence = historyByQuestion.get(question.id)
    const targetLevel = Math.max(1, Number(state?.verified_level ?? 0) + 1)
    const due = !state?.next_review_at || new Date(state.next_review_at) <= now
    const rotation = (sourceIndex - attemptSequence + questions.length) % Math.max(questions.length, 1)
    const unresolvedSkill = unresolvedBySkill.get(question.skill_id) ?? 0
    const unresolvedMother = question.mother_id ? unresolvedByMother.get(question.mother_id) ?? 0 : 0
    // Rounds 2—4 use a different mother question to promote transfer. The
    // fifth round may return to the original mother for final verification.
    const exactHistoryScore = !evidence
      ? 12
      : attemptSequence >= 4
        ? evidence.wrong * 8 - evidence.correct * 5
        : -evidence.wrong * 4 - evidence.correct * 7
    const motherScore = attemptSequence >= 4 ? unresolvedMother * 4 : -unresolvedMother * 2
    const score =
      exactHistoryScore +
      motherScore +
      unresolvedSkill * 6 +
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
