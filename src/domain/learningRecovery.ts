import type { KnowledgeCard, LearningAttempt, OptionPracticeProgress, Question } from './types'
import { getKnowledgeReviewPoints } from './knowledgeReviewPoints'

export type KnowledgeConfidence = 'unknown' | 'familiar' | 'fluent'

export type RecoveryTarget = {
  key: string
  skillId: string
  conceptKey: string | null
  title: string
  wrongCount: number
  anchorQuestionId: string | null
  branch: OptionPracticeProgress | null
  fromSelfRating: boolean
  pointId?: string
  selfRating?: KnowledgeConfidence
}

type RecoveryInput = {
  questions: Pick<Question, 'id' | 'skillId' | 'conceptKey' | 'optionPractice'>[]
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

  for (const answer of answers.filter((item) => !item.correct)) {
    const question = byQuestion.get(answer.questionId)
    if (!question) continue
    const anchorId = question.optionPractice?.anchorQuestionId ?? question.id
    const anchor = byQuestion.get(anchorId) ?? question
    const branch = branches.find((item) => item.anchorQuestionId === anchorId && item.knowledgePoint.trim()) ?? null
    const conceptKey = anchor.conceptKey ?? null
    const key = branch ? `branch:${anchorId}:${branch.optionIndex}` : `concept:${anchor.skillId}:${conceptKey ?? anchorId}`
    const card = cards.find((item) => item.skillId === anchor.skillId)
    const title = branch?.knowledgePoint || (conceptKey && conceptTitles[conceptKey]) || card?.title || anchor.skillId
    const previous = targets.get(key)
    targets.set(key, previous
      ? { ...previous, wrongCount: previous.wrongCount + 1 }
      : { key, skillId: anchor.skillId, conceptKey, title, wrongCount: 1, anchorQuestionId: anchorId, branch, fromSelfRating: false })
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
    || Number(b.selfRating === 'unknown') - Number(a.selfRating === 'unknown')
    || a.title.localeCompare(b.title, 'zh-CN'))
}
