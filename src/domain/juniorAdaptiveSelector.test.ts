import { describe, expect, it } from 'vitest'

import {
  selectJuniorNextQuestion,
  type JuniorAdaptiveCandidate,
  type JuniorAdaptiveHistory,
  type JuniorRouteKind,
} from '../../supabase/functions/chemistry-access/junior-adaptive'

const KNOWLEDGE_SKILL_IDS = ['J_KNOWLEDGE_A', 'J_KNOWLEDGE_B', 'J_KNOWLEDGE_C']

function fingerprint(value: number) {
  return value.toString(16).padStart(64, '0')
}

function candidate(skillId: string, ordinal: number, level: number, seed: number): JuniorAdaptiveCandidate {
  const suffix = `${skillId.toLowerCase()}-${String(ordinal).padStart(2, '0')}`
  return {
    id: `question-${suffix}`,
    mother_id: `mother-original-${suffix}`,
    skill_id: skillId,
    knowledge_id: skillId,
    same_type_key: `same-type-${skillId.toLowerCase()}-${ordinal % 4}`,
    source_item_key: `source-item-original-${suffix}`,
    parent_source_item_key: `parent-source-original-${suffix}`,
    content_fingerprint: fingerprint(seed),
    level,
  }
}

function candidatePool() {
  let seed = 1
  return KNOWLEDGE_SKILL_IDS.flatMap((skillId) => [
    ...Array.from({ length: 8 }, (_, index) => candidate(skillId, index + 1, 1, seed++)),
    ...Array.from({ length: 8 }, (_, index) => candidate(skillId, index + 9, 2, seed++)),
  ])
}

function answeredRow(
  question: JuniorAdaptiveCandidate,
  sequence: number,
  routeKind: JuniorRouteKind = 'new_learning',
  overrides: Partial<JuniorAdaptiveHistory> = {},
): JuniorAdaptiveHistory {
  return {
    question_id: question.id,
    mother_id: question.mother_id,
    skill_id: question.skill_id,
    knowledge_id: question.knowledge_id,
    same_type_key: question.same_type_key,
    source_item_key: question.source_item_key,
    parent_source_item_key: question.parent_source_item_key,
    content_fingerprint: question.content_fingerprint,
    level: question.level,
    correct: true,
    uncertain: false,
    answered_at: new Date(Date.UTC(2026, 7, 29, 0, sequence)).toISOString(),
    route_kind: routeKind,
    ...overrides,
  }
}

function nextSelection(candidates: JuniorAdaptiveCandidate[], issued: JuniorAdaptiveHistory[], priorErrors: JuniorAdaptiveHistory[] = []) {
  return selectJuniorNextQuestion({
    candidates,
    knowledgeSkillIds: KNOWLEDGE_SKILL_IDS,
    answered: issued,
    issued,
    priorErrors,
    curriculumDayNumber: priorErrors.length ? 2 : 1,
    initialTarget: 12,
    hardCap: 15,
  })
}

function completeStableTwelve(candidates: JuniorAdaptiveCandidate[]) {
  const issued: JuniorAdaptiveHistory[] = []
  while (issued.length < 12) {
    const selection = nextSelection(candidates, issued)
    expect(selection, `expected question ${issued.length + 1} of the stable path`).not.toBeNull()
    if (!selection) throw new Error('stable selector stopped before 12 questions')
    issued.push(answeredRow(selection.question, issued.length + 1, selection.routeKind))
  }
  return issued
}

function identityValues(rows: JuniorAdaptiveHistory[], key: keyof JuniorAdaptiveHistory) {
  return rows.map((row) => String(row[key]))
}

describe('junior adaptive source-original selector', () => {
  it('finishes a stable three-knowledge path at exactly 12 originals without reusing any identity', () => {
    const candidates = candidatePool()
    const issued = completeStableTwelve(candidates)

    expect(nextSelection(candidates, issued)).toBeNull()
    expect(issued).toHaveLength(12)
    expect(issued.filter((row) => row.route_kind === 'new_learning')).toHaveLength(6)
    expect(issued.filter((row) => row.route_kind === 'advance')).toHaveLength(3)
    expect(issued.filter((row) => row.route_kind === 'stability_validation')).toHaveLength(3)

    for (const key of ['question_id', 'mother_id', 'source_item_key', 'parent_source_item_key', 'content_fingerprint'] as const) {
      const identities = identityValues(issued, key)
      expect(new Set(identities).size, `${key} must be unique within the day`).toBe(issued.length)
    }
  })

  it('requires fresh core evidence each day while excluding every prior-day source identity', () => {
    const candidates = candidatePool()
    const priorDay = completeStableTwelve(candidates).map((row, index) => ({
      ...row,
      answered_at: new Date(Date.UTC(2026, 7, 28, 0, index + 1)).toISOString(),
    }))
    const issued: JuniorAdaptiveHistory[] = []

    while (issued.length < 12) {
      const selection = selectJuniorNextQuestion({
        candidates,
        knowledgeSkillIds: KNOWLEDGE_SKILL_IDS,
        answered: priorDay,
        issued,
        priorErrors: [],
        curriculumDayNumber: 2,
        initialTarget: 12,
        hardCap: 15,
      })
      expect(selection, `expected fresh question ${issued.length + 1} on the new day`).not.toBeNull()
      if (!selection) throw new Error('new daily session reused prior mastery instead of collecting fresh evidence')
      issued.push(answeredRow(selection.question, issued.length + 1, selection.routeKind))
    }

    expect(issued.filter((row) => row.route_kind === 'new_learning')).toHaveLength(6)
    expect(issued.filter((row) => row.route_kind === 'advance')).toHaveLength(3)
    expect(issued.filter((row) => row.route_kind === 'stability_validation')).toHaveLength(3)
    expect(new Set([...identityValues(priorDay, 'question_id'), ...identityValues(issued, 'question_id')]).size).toBe(24)
    expect(selectJuniorNextQuestion({
      candidates,
      knowledgeSkillIds: KNOWLEDGE_SKILL_IDS,
      answered: priorDay,
      issued,
      priorErrors: [],
      curriculumDayNumber: 2,
      initialTarget: 12,
      hardCap: 15,
    })).toBeNull()
  })

  it('rejects candidates that collide with any previously issued source identity', () => {
    const used = candidate(KNOWLEDGE_SKILL_IDS[0], 90, 1, 900)
    const history = answeredRow(used, 1)
    const clean = candidate(KNOWLEDGE_SKILL_IDS[0], 99, 1, 999)
    const collisionBase = candidate(KNOWLEDGE_SKILL_IDS[0], 91, 1, 901)
    const collisions: JuniorAdaptiveCandidate[] = [
      { ...collisionBase, id: used.id },
      { ...candidate(KNOWLEDGE_SKILL_IDS[0], 92, 1, 902), mother_id: used.mother_id },
      { ...candidate(KNOWLEDGE_SKILL_IDS[0], 93, 1, 903), source_item_key: used.source_item_key },
      { ...candidate(KNOWLEDGE_SKILL_IDS[0], 94, 1, 904), parent_source_item_key: used.parent_source_item_key },
      { ...candidate(KNOWLEDGE_SKILL_IDS[0], 95, 1, 905), content_fingerprint: used.content_fingerprint },
    ]

    const selection = selectJuniorNextQuestion({
      candidates: [...collisions, clean],
      knowledgeSkillIds: KNOWLEDGE_SKILL_IDS,
      answered: [history],
      issued: [history],
      priorErrors: [],
      curriculumDayNumber: 1,
    })

    expect(selection?.question.id).toBe(clean.id)
  })

  it('recovers a prior-day error with the same type but a different source original', () => {
    const candidates = candidatePool()
    const issued = completeStableTwelve(candidates).slice(0, 9)
    const yesterdayOriginal = {
      ...candidate(KNOWLEDGE_SKILL_IDS[1], 80, 1, 800),
      same_type_key: 'same-type-prior-day-only',
    }
    const priorError = answeredRow(yesterdayOriginal, 1, 'new_learning', {
      correct: false,
      uncertain: false,
      answered_at: '2026-08-28T01:00:00.000Z',
    })
    const recovery = {
      ...candidate(KNOWLEDGE_SKILL_IDS[1], 81, 1, 801),
      same_type_key: priorError.same_type_key!,
    }

    const selection = nextSelection([...candidates, yesterdayOriginal, recovery], issued, [priorError])

    expect(selection?.routeKind).toBe('prior_error_recovery')
    expect(selection?.question.same_type_key).toBe(priorError.same_type_key)
    expect(selection?.question.id).toBe(recovery.id)
    for (const [candidateKey, historyKey] of [
      ['id', 'question_id'],
      ['mother_id', 'mother_id'],
      ['source_item_key', 'source_item_key'],
      ['parent_source_item_key', 'parent_source_item_key'],
      ['content_fingerprint', 'content_fingerprint'],
    ] as const) {
      expect(selection?.question[candidateKey]).not.toBe(priorError[historyKey])
    }
  })

  it('treats a correct-but-uncertain prior answer as evidence that needs a different-original recovery', () => {
    const candidates = candidatePool()
    const priorQuestion = {
      ...candidate(KNOWLEDGE_SKILL_IDS[0], 82, 1, 820),
      same_type_key: 'same-type-uncertain-prior-day',
    }
    const priorUncertain = answeredRow(priorQuestion, 1, 'new_learning', {
      correct: true,
      uncertain: true,
      answered_at: '2026-08-28T01:00:00.000Z',
    })
    const recovery = {
      ...candidate(KNOWLEDGE_SKILL_IDS[0], 83, 1, 821),
      same_type_key: priorUncertain.same_type_key!,
    }
    const issued = completeStableTwelve(candidates).slice(0, 9)

    const selection = nextSelection([...candidates, recovery], issued, [priorUncertain])

    expect(selection?.routeKind).toBe('prior_error_recovery')
    expect(selection?.question.id).toBe(recovery.id)
  })

  it('fails closed when fewer than two different originals can recover unstable prior evidence', () => {
    const candidates = candidatePool()
    const priorQuestion = {
      ...candidate(KNOWLEDGE_SKILL_IDS[2], 84, 1, 840),
      same_type_key: 'same-type-capacity-limited',
    }
    const priorError = answeredRow(priorQuestion, 1, 'new_learning', {
      correct: false,
      answered_at: '2026-08-28T01:00:00.000Z',
    })
    const onlyRecovery = {
      ...candidate(KNOWLEDGE_SKILL_IDS[2], 85, 1, 841),
      same_type_key: priorError.same_type_key!,
    }
    const issued: JuniorAdaptiveHistory[] = []

    while (true) {
      const selection = selectJuniorNextQuestion({
        candidates: [...candidates, onlyRecovery],
        knowledgeSkillIds: KNOWLEDGE_SKILL_IDS,
        answered: [priorError],
        issued,
        priorErrors: [priorError],
        curriculumDayNumber: 2,
        initialTarget: 12,
        hardCap: 15,
      })
      if (!selection) break
      issued.push(answeredRow(selection.question, issued.length + 1, selection.routeKind))
    }

    expect(issued).toHaveLength(10)
    expect(issued.filter((row) => row.route_kind === 'prior_error_recovery')).toHaveLength(1)
  })

  it('opens questions 13 through 15 only while instability persists and never exceeds the hard cap', () => {
    const candidates = candidatePool()
    const stable = completeStableTwelve(candidates)

    expect(nextSelection(candidates, stable)).toBeNull()

    const issued = stable.map((row) => ({ ...row }))
    issued[11] = { ...issued[11], correct: false }
    for (let expectedCount = 13; expectedCount <= 15; expectedCount += 1) {
      const selection = nextSelection(candidates, issued)
      expect(selection?.routeKind).toBe('foundation_repair')
      if (!selection) throw new Error(`instability did not fund question ${expectedCount}`)
      issued.push(answeredRow(selection.question, expectedCount, selection.routeKind, {
        correct: expectedCount === 14,
        uncertain: expectedCount === 14,
      }))
      expect(issued).toHaveLength(expectedCount)
    }

    expect(nextSelection(candidates, issued)).toBeNull()
    expect(issued).toHaveLength(15)
  })
})
