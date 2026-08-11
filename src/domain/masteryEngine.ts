import type { SkillEvidence, StudentSkillState } from './types'

const REVIEW_INTERVALS = [3, 5, 7, 14, 30] as const

export function addDays(iso: string, days: number) {
  const date = new Date(`${iso.slice(0, 10)}T12:00:00+08:00`)
  date.setUTCDate(date.getUTCDate() + days)
  return date.toISOString()
}

function distinctCorrectMotherIds(evidence: SkillEvidence[], level: number) {
  return new Set(evidence.filter((item) => item.level === level && item.correct).map((item) => item.motherId))
}

export function applyEvidence(previous: StudentSkillState, evidence: SkillEvidence): StudentSkillState {
  const next: StudentSkillState = {
    ...previous,
    evidence: [...previous.evidence, evidence],
    lastReviewedAt: evidence.observedAt,
  }

  if (evidence.correct) {
    next.consecutiveErrors = 0
    const candidate = previous.candidateLevel ?? Math.min(previous.verifiedLevel + 1, previous.maxLevel)
    const motherIds = distinctCorrectMotherIds(next.evidence, candidate)
    if (evidence.level === candidate && motherIds.size >= 2) {
      next.verifiedLevel = Math.max(previous.verifiedLevel, candidate)
      next.candidateLevel = candidate < previous.maxLevel ? candidate + 1 : null
      next.stability = candidate === previous.maxLevel ? 'stable' : 'verified'
      const intervalIndex = Math.min(previous.reviewIntervalIndex + 1, REVIEW_INTERVALS.length - 1)
      next.reviewIntervalIndex = intervalIndex
      next.nextReviewAt = addDays(evidence.observedAt, REVIEW_INTERVALS[intervalIndex])
    } else {
      next.candidateLevel = candidate
      next.stability = previous.verifiedLevel > 0 ? previous.stability : 'learning'
    }
    if (previous.stability === 'forgotten') next.stability = 'recovered'
    return next
  }

  next.consecutiveErrors = previous.consecutiveErrors + 1
  next.nextReviewAt = addDays(evidence.observedAt, next.consecutiveErrors >= 2 ? 1 : 3)

  if (previous.candidateLevel && evidence.level === previous.candidateLevel) {
    next.candidateLevel = null
    next.stability = previous.verifiedLevel > 0 ? 'verified' : 'learning'
    return next
  }

  if (evidence.level <= previous.verifiedLevel) {
    const sameLevelRecent = next.evidence
      .filter((item) => item.level === evidence.level)
      .slice(-2)
    if (sameLevelRecent.length === 2 && sameLevelRecent.every((item) => !item.correct)) {
      next.stability = 'forgotten'
      next.reviewIntervalIndex = 0
      if (next.consecutiveErrors >= 3) next.teacherIntervention = true
    }
  }
  return next
}

export function achievementCopy(previous: StudentSkillState, next: StudentSkillState, skillTitle: string) {
  if (next.verifiedLevel > previous.verifiedLevel) {
    if (next.verifiedLevel === next.maxLevel) return `太棒了！“${skillTitle}”当前学习范围的全部检验已经通过。`
    return `真棒，通过了 L${next.verifiedLevel} 的检验！“${skillTitle}”已经点亮 ${next.verifiedLevel}/${next.maxLevel}。`
  }
  if (next.stability === 'recovered' && previous.stability === 'forgotten') return `你刚刚重新找回了“${skillTitle}”。`
  if (next.teacherIntervention && !previous.teacherIntervention) return `这个知识点值得带去问甘老师，系统已经帮你整理好了。`
  return null
}

export function initialSkillState(studentId: string, skillId: string, maxLevel: number): StudentSkillState {
  return {
    studentId,
    skillId,
    verifiedLevel: 0,
    candidateLevel: 1,
    maxLevel,
    stability: 'unknown',
    evidence: [],
    consecutiveErrors: 0,
    nextReviewAt: null,
    reviewIntervalIndex: 0,
    lastReviewedAt: null,
    teacherIntervention: false,
  }
}

export { REVIEW_INTERVALS }
