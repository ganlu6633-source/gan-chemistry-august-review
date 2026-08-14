export type AdaptiveQuestion = { id: string; mother_id?: string; skill_id: string; concept_key?: string | null; level: number }
export type AdaptiveState = { skill_id: string; verified_level?: number | null; consecutive_errors?: number | null; next_review_at?: string | null }
export type AdaptiveAnswer = {
  question_id: string
  mother_id?: string | null
  skill_id?: string | null
  concept_key?: string | null
  attempt_sequence?: number | null
  correct: boolean
  uncertain?: boolean | null
}

/**
 * Ranks approved in-scope questions against the learner's current evidence.
 * A plan-day never repeats a question or a mother question in later rounds.
 * It first replaces every unresolved fine-grained concept from the latest
 * round with a different mother question of the same concept. It then
 * guarantees skill coverage and fills the remaining budget with unseen
 * concepts. A question or mother question is never repeated that day.
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
  const usedQuestionIds = new Set<string>()
  const usedMotherIds = new Set<string>()
  const unresolvedBySkill = new Map<string, number>()
  const latestSequence = history.reduce((latest, answer) =>
    Math.max(latest, Number.isInteger(answer.attempt_sequence) ? Number(answer.attempt_sequence) : -1), -1)
  const latestRound = latestSequence >= 0
    ? history.filter((answer) => Number(answer.attempt_sequence) === latestSequence)
    : history
  const unresolvedConcepts = new Set(latestRound
    .filter((answer) => !answer.correct || answer.uncertain)
    .map((answer) => answer.concept_key)
    .filter((concept): concept is string => Boolean(concept)))
  for (const answer of history) {
    usedQuestionIds.add(answer.question_id)
    if (answer.mother_id) usedMotherIds.add(answer.mother_id)
    const item = historyByQuestion.get(answer.question_id) ?? { correct: 0, wrong: 0 }
    if (answer.correct && !answer.uncertain) item.correct += 1
    else item.wrong += 1
    historyByQuestion.set(answer.question_id, item)
    if (!answer.correct || answer.uncertain) {
      if (answer.skill_id) unresolvedBySkill.set(answer.skill_id, (unresolvedBySkill.get(answer.skill_id) ?? 0) + 1)
    }
  }

  const ranked = questions.filter((question) => {
    if (!question.mother_id) return false
    if (usedQuestionIds.has(question.id)) return false
    return !usedMotherIds.has(question.mother_id)
  }).map((question, sourceIndex) => {
    const state = stateBySkill.get(question.skill_id)
    const evidence = historyByQuestion.get(question.id)
    const targetLevel = Math.max(1, Number(state?.verified_level ?? 0) + 1)
    const due = !state?.next_review_at || new Date(state.next_review_at) <= now
    const rotation = (sourceIndex - attemptSequence + questions.length) % Math.max(questions.length, 1)
    const unresolvedSkill = unresolvedBySkill.get(question.skill_id) ?? 0
    const unresolvedConcept = question.concept_key ? unresolvedConcepts.has(question.concept_key) : false
    const exactHistoryScore = !evidence ? 12 : -evidence.wrong * 4 - evidence.correct * 7
    const score =
      exactHistoryScore +
      (unresolvedConcept ? 100 : 0) +
      unresolvedSkill * 6 +
      Number(state?.consecutive_errors ?? 0) * 4 +
      (due ? 4 : 0) -
      Math.abs(Number(question.level) - targetLevel) * 2
    return { question, score, rotation }
  }).sort((a, b) => b.score - a.score || a.rotation - b.rotation || a.question.id.localeCompare(b.question.id))

  const selected: T[] = []
  const selectedIds = new Set<string>()
  const selectedMotherIds = new Set<string>()
  const selectedConcepts = new Set<string>()
  function addCandidate(candidate: (typeof ranked)[number] | undefined) {
    if (!candidate || selected.length >= limit) return
    selected.push(candidate.question)
    selectedIds.add(candidate.question.id)
    if (candidate.question.mother_id) selectedMotherIds.add(candidate.question.mother_id)
    if (candidate.question.concept_key) selectedConcepts.add(candidate.question.concept_key)
  }

  // An error or uncertainty must return as a different question that tests the
  // same fine-grained concept. Never substitute a merely related skill.
  for (const conceptKey of unresolvedConcepts) {
    addCandidate(ranked.find((item) => item.question.concept_key === conceptKey &&
      !selectedIds.has(item.question.id) &&
      !selectedMotherIds.has(item.question.mother_id!)))
  }

  const skills = [...new Set(questions.map((question) => question.skill_id))]
  for (const skillId of skills) {
    const candidate = ranked.find((item) => item.question.skill_id === skillId &&
      !selectedIds.has(item.question.id) &&
      !selectedMotherIds.has(item.question.mother_id!) &&
      (!item.question.concept_key || !selectedConcepts.has(item.question.concept_key)))
    addCandidate(candidate)
  }

  // Prefer one question per concept in a round so five questions diagnose five
  // separate points instead of spending the student's small budget twice.
  for (const item of ranked) {
    if (selected.length >= limit) break
    if (!selectedIds.has(item.question.id) &&
      !selectedMotherIds.has(item.question.mother_id!) &&
      (!item.question.concept_key || !selectedConcepts.has(item.question.concept_key))) addCandidate(item)
  }
  // A plan with fewer than five available concepts may still use another
  // unseen variant, while the question and mother non-repeat rules remain hard.
  for (const item of ranked) {
    if (selected.length >= limit) break
    if (!selectedIds.has(item.question.id) && !selectedMotherIds.has(item.question.mother_id!)) addCandidate(item)
  }
  return selected
}
