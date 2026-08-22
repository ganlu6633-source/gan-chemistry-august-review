export type AdaptiveQuestion = { id: string; mother_id?: string; skill_id: string; concept_key?: string | null; level: number }
export type AdaptiveState = { skill_id: string; verified_level?: number | null; consecutive_errors?: number | null; next_review_at?: string | null }
export type AdaptiveAnswer = {
  question_id: string
  mother_id?: string | null
  skill_id?: string | null
  concept_key?: string | null
  question_level?: number | null
  attempt_sequence?: number | null
  correct: boolean
  uncertain?: boolean | null
}

/**
 * Selects one unseen original question for every fine-grained concept.
 *
 * Round 1 starts at the lowest available difficulty and covers each concept
 * exactly once. In later rounds, a correct and confident answer moves to the
 * nearest strictly harder unseen original; a wrong or uncertain answer stays
 * at the same level when another original exists, otherwise it uses the
 * nearest easier unseen original. The caller supplies the student's complete
 * REVIEW history, so question and mother IDs never repeat on a later date.
 */
export function selectAdaptiveQuestions<T extends AdaptiveQuestion>(
  questions: T[],
  _states: AdaptiveState[],
  history: AdaptiveAnswer[],
  attemptSequence: number,
  limit = 5,
  _now = new Date(),
  requireExactConceptCoverage = false,
): T[] {
  void _now
  const usedQuestionIds = new Set(history.map((answer) => answer.question_id))
  const usedMotherIds = new Set(history.flatMap((answer) => answer.mother_id ? [answer.mother_id] : []))
  const latestByConcept = new Map<string, AdaptiveAnswer>()
  for (const answer of history) {
    if (!answer.concept_key) continue
    const previous = latestByConcept.get(answer.concept_key)
    const answerSequence = Number.isInteger(answer.attempt_sequence) ? Number(answer.attempt_sequence) : -1
    const previousSequence = Number.isInteger(previous?.attempt_sequence) ? Number(previous?.attempt_sequence) : -1
    if (!previous || answerSequence >= previousSequence) latestByConcept.set(answer.concept_key, answer)
  }

  const unseen = questions.filter((question) =>
    Boolean(question.mother_id)
    && !usedQuestionIds.has(question.id)
    && !usedMotherIds.has(question.mother_id!))
  const concepts = [...new Set(questions.flatMap((question) => question.concept_key ? [question.concept_key] : []))].sort()
  const selected: T[] = []

  for (const conceptKey of concepts) {
    if (selected.length >= limit) break
    const candidates = unseen.filter((question) => question.concept_key === conceptKey)
    if (!candidates.length) continue
    const previous = latestByConcept.get(conceptKey)
    const previousLevel = Number(previous?.question_level ?? 0)
    const mastered = previous?.correct === true && previous.uncertain !== true

    candidates.sort((a, b) => {
      if (!previous) return a.level - b.level || a.id.localeCompare(b.id)
      if (mastered) {
        const aHarder = a.level > previousLevel ? 0 : 1
        const bHarder = b.level > previousLevel ? 0 : 1
        return aHarder - bHarder
          || Math.abs(a.level - previousLevel) - Math.abs(b.level - previousLevel)
          || a.level - b.level
          || a.id.localeCompare(b.id)
      }
      const aNotHarder = a.level <= previousLevel ? 0 : 1
      const bNotHarder = b.level <= previousLevel ? 0 : 1
      return aNotHarder - bNotHarder
        || Math.abs(a.level - previousLevel) - Math.abs(b.level - previousLevel)
        || a.level - b.level
        || a.id.localeCompare(b.id)
    })
    selected.push(candidates[0])
  }

  // A REVIEW day must never disguise an exhausted fine concept by taking a
  // second question from another concept. Returning fewer than `limit` lets
  // the caller fail closed and tell the teacher exactly which pool is short.
  if (requireExactConceptCoverage && concepts.length > 0) return selected

  // Non-REVIEW callers or legacy pools may not have concept keys. Preserve a
  // deterministic unseen fill without weakening the no-repeat rule.
  for (const question of unseen.sort((a, b) => a.level - b.level || a.id.localeCompare(b.id))) {
    if (selected.length >= limit) break
    if (!selected.some((item) => item.id === question.id)) selected.push(question)
  }
  return selected
}
