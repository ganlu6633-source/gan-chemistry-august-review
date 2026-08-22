import { describe, expect, it } from 'vitest'
import accessSource from '../../supabase/functions/chemistry-access/index.ts?raw'
import {
  effectiveReviewRoundLimit,
  FORMAL_REVIEW_DAILY_QUESTION_CAP,
  prioritizeNextReviewTargets,
  validFormalReviewQuestionCount,
  validFormalReviewRoundLimit,
} from '../../supabase/functions/chemistry-access/review-daily-policy'

describe('formal REVIEW daily-package contract', () => {
  const formal = {
    mode: 'REVIEW',
    gradeBand: '高二',
    isDemo: false,
    questionCount: 5,
    storedRoundLimit: 5,
  }

  it('uses one bounded package for a formal high-school day', () => {
    expect(FORMAL_REVIEW_DAILY_QUESTION_CAP).toBe(8)
    expect(effectiveReviewRoundLimit({ ...formal, storedRoundLimit: 1 })).toBe(1)
    expect(validFormalReviewRoundLimit({ ...formal, storedRoundLimit: 1 })).toBe(true)
    expect(validFormalReviewRoundLimit({ ...formal, planDate: '2026-08-23' })).toBe(false)
    expect(validFormalReviewRoundLimit({ ...formal, planDate: '2026-08-22' })).toBe(true)
    expect(validFormalReviewRoundLimit({ ...formal, planDate: '2026-08-23', hasExistingAttempt: true })).toBe(true)
    expect(validFormalReviewRoundLimit({ ...formal, storedRoundLimit: 2, planDate: '2026-08-22', hasExistingAttempt: true })).toBe(false)
    expect(validFormalReviewQuestionCount({ ...formal, questionCount: 1 })).toBe(true)
    expect(validFormalReviewQuestionCount({ ...formal, questionCount: 8 })).toBe(true)
    expect(validFormalReviewQuestionCount({ ...formal, questionCount: 9 })).toBe(false)
  })

  it('does not alter demo or independent quiz limits', () => {
    expect(effectiveReviewRoundLimit({ ...formal, isDemo: true })).toBe(5)
    expect(effectiveReviewRoundLimit({ ...formal, mode: 'CLASS_QUIZ' })).toBe(5)
    expect(validFormalReviewRoundLimit({ ...formal, isDemo: true })).toBe(true)
    expect(validFormalReviewRoundLimit({ ...formal, mode: 'CLASS_QUIZ' })).toBe(true)
  })

  it('puts wrong and uncertain concepts before scheduled fallbacks', () => {
    expect(prioritizeNextReviewTargets([
      { conceptKey: 'A__C01', skillId: 'A', correct: true, uncertain: false },
      { conceptKey: 'A__C02', skillId: 'A', correct: false, uncertain: false },
      { conceptKey: 'B__C01', skillId: 'B', correct: true, uncertain: true },
    ], ['A__C01', 'A__C03'], 4)).toEqual([
      'A__C02', 'B__C01', 'A__C01', 'A__C03',
    ])
  })

  it('checks exact concept ownership and whole-history source freshness without requiring three artificial levels', () => {
    expect(accessSource).toContain('chem_review_answer_history')
    expect(accessSource).toContain("learner's complete REVIEW identity history")
    expect(accessSource).not.toContain('.filter((answer) => skillIds.includes(String(answer.skill_id)))')
    expect(accessSource).toContain('sourceDistinctQuestionPool(questionPool, selectionHistory)')
    expect(accessSource).toContain('conceptOwnerSkills')
    expect(accessSource).not.toContain('const conceptLevels = new Map')
    expect(accessSource).not.toContain('levels.size < 3')
    expect(accessSource).toContain('chem_personalize_next_review_plan')
    expect(accessSource).toContain('chem_enqueue_review_personalization')
    expect(accessSource).toContain('attemptSequence + 1 >= roundLimit')
    expect(accessSource).toContain('confirmedHighOneSkillIds')
    expect(accessSource).toContain('尚未确认学过的高一知识模块')
    expect(accessSource).toContain('正式复习当天必须明确配置 ${questionCount} 个细知识点')
    expect(accessSource).toContain('String(plan.plan_date || "") > shanghaiDate()')
    expect(accessSource).toContain('后续日期的正式复习尚未开放')
    expect(accessSource.match(/: \{ includeAnswerLocks: true \}/g)).toHaveLength(3)
    expect(accessSource).toContain('never touches independent quizzes')
  })

  it('fails closed unless the grade release and both source images are currently verified', () => {
    expect(accessSource).toContain('supabase.rpc("chem_active_verified_source_releases")')
    expect(accessSource).toContain('matching.length !== 1')
    expect(accessSource).toContain('.eq("source_release_id", activeSourceReleaseId!)')
    expect(accessSource).toContain('hasRequiredReviewSourceAssets(question.asset_refs)')
    expect(accessSource).toContain('ref.kind === "question_image"')
    expect(accessSource).toContain('ref.kind === "analysis_image"')
    expect(accessSource).toContain('本轮原题缺少经过核验的题面图或解析图')
    expect(accessSource).toContain('.select("concept_key,level,asset_refs")')
  })
})
