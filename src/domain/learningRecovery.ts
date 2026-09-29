import type { KnowledgeCard, LearningAttempt, OptionPracticeProgress, Question } from './types'
import { getKnowledgeReviewPoints } from './knowledgeReviewPoints'

export type KnowledgeConfidence = 'unknown' | 'familiar' | 'fluent'

export type RecoveryTarget = {
  key: string
  skillId: string
  conceptKey: string | null
  title: string
  wrongCount: number
  uncertainCount?: number
  anchorQuestionId: string | null
  branch: OptionPracticeProgress | null
  fromSelfRating: boolean
  pointId?: string
  selfRating?: KnowledgeConfidence
}

type RecoveryInput = {
  questions: Pick<Question, 'id' | 'skillId' | 'conceptKey' | 'optionPractice' | 'choiceContext'>[]
  answers: LearningAttempt['answers']
  branches: OptionPracticeProgress[]
  cards: KnowledgeCard[]
  pointRatings: Record<string, KnowledgeConfidence>
  conceptTitles: Record<string, string>
}

/** A wrong option is a clue, not proof of which microscopic rule failed.
 * Use the teacher-verified option branch when available; otherwise stop at
 * the question's audited concept and let the learner choose the weak point. */
export function buildRecoveryTargets({ questions, answers, branches, cards, pointRatings, conceptTitles }: RecoveryInput): RecoveryTarget[] {
  const byQuestion = new Map(questions.map((question) => [question.id, question]))
  const targets = new Map<string, RecoveryTarget>()

  for (const answer of answers.filter((item) => !item.correct || item.uncertain)) {
    const question = byQuestion.get(answer.questionId)
    if (!question) continue
    // The three-round policy diagnoses the newly wrong reserve's own option.
    // Its incoming optionPractice identifies why it was issued, not why this
    // new answer is wrong. Legacy single-branch practice still groups follow-ups
    // under the original anchor as before.
    const anchorId = question.choiceContext ? question.id : question.optionPractice?.anchorQuestionId ?? question.id
    const anchor = byQuestion.get(anchorId) ?? question
    const branch = branches.find((item) => item.anchorQuestionId === anchorId && item.knowledgePoint.trim()) ?? null
    const conceptKey = anchor.conceptKey ?? null
    const key = branch ? `branch:${anchorId}:${branch.optionIndex}` : `concept:${anchor.skillId}:${conceptKey ?? anchorId}`
    const card = cards.find((item) => item.skillId === anchor.skillId)
    const title = branch?.knowledgePoint || (conceptKey && conceptTitles[conceptKey]) || card?.title || anchor.skillId
    const previous = targets.get(key)
    targets.set(key, previous
      ? { ...previous, wrongCount: previous.wrongCount + Number(!answer.correct), uncertainCount: (previous.uncertainCount ?? 0) + Number(answer.uncertain) }
      : { key, skillId: anchor.skillId, conceptKey, title, wrongCount: Number(!answer.correct), uncertainCount: Number(answer.uncertain), anchorQuestionId: anchorId, branch, fromSelfRating: false })
  }

  for (const card of cards) {
    for (const point of getKnowledgeReviewPoints(card)) {
      const rating = pointRatings[point.id]
      if (rating !== 'unknown' && rating !== 'familiar') continue
      const key = `rating:${point.id}`
      targets.set(key, { key, skillId: card.skillId, conceptKey: null, title: point.title, wrongCount: 0,
        anchorQuestionId: null, branch: null, fromSelfRating: true, pointId: point.id, selfRating: rating })
    }
  }

  return [...targets.values()].sort((a, b) => Number(Boolean(b.branch)) - Number(Boolean(a.branch))
    || b.wrongCount - a.wrongCount
    || (b.uncertainCount ?? 0) - (a.uncertainCount ?? 0)
    || Number(b.selfRating === 'unknown') - Number(a.selfRating === 'unknown')
    || a.title.localeCompare(b.title, 'zh-CN'))
}
