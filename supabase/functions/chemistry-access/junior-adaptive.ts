/**
 * Deterministic, source-safe selector for one junior-high daily session.
 *
 * The caller supplies only approved source-original candidates. This selector
 * never manufactures a question and it never permits a repeated question,
 * mother, source item, parent source item, or content fingerprint.
 */

export type JuniorAdaptiveCandidate = {
  id: string;
  mother_id: string;
  skill_id: string;
  knowledge_id: string;
  same_type_key: string;
  source_item_key: string;
  parent_source_item_key: string;
  content_fingerprint: string;
  level: number;
};

export type JuniorAdaptiveHistory = {
  question_id: string;
  mother_id?: string | null;
  skill_id: string;
  knowledge_id?: string | null;
  same_type_key?: string | null;
  source_item_key?: string | null;
  parent_source_item_key?: string | null;
  content_fingerprint?: string | null;
  level: number;
  correct: boolean;
  uncertain?: boolean | null;
  answered_at?: string | null;
  route_kind?: JuniorRouteKind | null;
};

export type JuniorRouteKind = 'new_learning' | 'advance' | 'stability_validation' | 'foundation_repair' | 'prior_error_recovery';

export type JuniorNextSelection<T extends JuniorAdaptiveCandidate> = {
  question: T;
  routeKind: JuniorRouteKind;
  routeReason: string;
} | null;

export type JuniorSelectionInput<T extends JuniorAdaptiveCandidate> = {
  candidates: T[];
  knowledgeSkillIds: string[];
  answered: JuniorAdaptiveHistory[];
  issued: JuniorAdaptiveHistory[];
  priorErrors: JuniorAdaptiveHistory[];
  curriculumDayNumber: number;
  initialTarget?: number;
  hardCap?: number;
};

function confidentCorrect(row: JuniorAdaptiveHistory) {
  return row.correct === true && row.uncertain !== true;
}

function identitySet(rows: JuniorAdaptiveHistory[], key: keyof JuniorAdaptiveHistory) {
  return new Set(rows.flatMap((row) => {
    const value = row[key];
    return typeof value === 'string' && value.length ? [value] : [];
  }));
}

function rowKnowledgeId(row: JuniorAdaptiveHistory) {
  return String(row.knowledge_id || row.skill_id || '');
}

function sourceDistinctPool<T extends JuniorAdaptiveCandidate>(candidates: T[], history: JuniorAdaptiveHistory[]) {
  const usedQuestions = identitySet(history, 'question_id');
  const usedMothers = identitySet(history, 'mother_id');
  const usedSourceItems = identitySet(history, 'source_item_key');
  const usedParentItems = identitySet(history, 'parent_source_item_key');
  const usedFingerprints = identitySet(history, 'content_fingerprint');
  return candidates
    .filter((candidate) => !usedQuestions.has(candidate.id)
      && !usedMothers.has(candidate.mother_id)
      && !usedSourceItems.has(candidate.source_item_key)
      && !usedParentItems.has(candidate.parent_source_item_key)
      && !usedFingerprints.has(candidate.content_fingerprint))
    .sort((a, b) => a.level - b.level || a.id.localeCompare(b.id));
}

function knowledgeRows(rows: JuniorAdaptiveHistory[], skillId: string) {
  return rows.filter((row) => rowKnowledgeId(row) === skillId);
}

function coreReadiness<T extends JuniorAdaptiveCandidate>(skillId: string, rows: JuniorAdaptiveHistory[], candidates: T[]) {
  const relevant = knowledgeRows(rows, skillId)
    .filter((row) => row.answered_at !== null && row.answered_at !== undefined);
  const pool = candidates.filter((candidate) => candidate.knowledge_id === skillId);
  const foundationLevel = Math.min(...pool.map((candidate) => candidate.level));
  if (!Number.isFinite(foundationLevel)) return { ready: false, foundationLevel: 1, foundationRun: 0, mediumConfirmed: false };
  let foundationRun = 0;
  for (const row of [...relevant].reverse()) {
    if (row.level !== foundationLevel) continue;
    if (!confidentCorrect(row)) break;
    foundationRun += 1;
    if (foundationRun >= 2) break;
  }
  const mediumConfirmed = relevant.some((row) => row.level > foundationLevel && confidentCorrect(row));
  return { ready: foundationRun >= 2 && mediumConfirmed, foundationLevel, foundationRun, mediumConfirmed };
}

function firstCandidate<T extends JuniorAdaptiveCandidate>(pool: T[], predicate: (candidate: T) => boolean) {
  return pool.filter(predicate).sort((a, b) => a.level - b.level || a.id.localeCompare(b.id))[0] || null;
}

function nextForCore<T extends JuniorAdaptiveCandidate>(
  skillId: string,
  pool: T[],
  rows: JuniorAdaptiveHistory[],
  allCandidates: T[],
): JuniorNextSelection<T> {
  // `pool` excludes originals already issued.  It therefore cannot be used to
  // infer the foundation level: after two foundation questions have been used,
  // the lowest remaining question may already be a medium question.  Keep the
  // level boundary anchored to the complete approved pool for this knowledge.
  const readiness = coreReadiness(skillId, rows, allCandidates);
  const skillPool = pool.filter((candidate) => candidate.knowledge_id === skillId);
  if (!skillPool.length) return null;
  const latest = knowledgeRows(rows, skillId).at(-1);
  const hasError = Boolean(latest && !confidentCorrect(latest));
  if (hasError) {
    const foundation = firstCandidate(skillPool, (candidate) => candidate.level === readiness.foundationLevel);
    if (foundation) return { question: foundation, routeKind: 'foundation_repair', routeReason: '基础判断尚未连续稳定，先用同知识点的另一道基础原题确认。' };
  }
  if (readiness.foundationRun < 2) {
    const foundation = firstCandidate(skillPool, (candidate) => candidate.level === readiness.foundationLevel);
    if (foundation) return { question: foundation, routeKind: 'new_learning', routeReason: '先收集两次独立的基础判断证据。' };
  }
  if (!readiness.mediumConfirmed) {
    const advanced = firstCandidate(skillPool, (candidate) => candidate.level > readiness.foundationLevel);
    if (advanced) return { question: advanced, routeKind: 'advance', routeReason: '基础连续正确后，进入同知识点的中档原题。' };
  }
  return null;
}

function recoveryCandidate<T extends JuniorAdaptiveCandidate>(pool: T[], priorErrors: JuniorAdaptiveHistory[]) {
  const orderedErrors = [...priorErrors]
    .filter((row) => !confidentCorrect(row) && Boolean(row.same_type_key))
    .sort((a, b) => String(a.answered_at || '').localeCompare(String(b.answered_at || '')));
  for (const error of orderedErrors) {
    const sameType = firstCandidate(pool, (candidate) => candidate.knowledge_id === rowKnowledgeId(error)
      && candidate.same_type_key === error.same_type_key);
    if (sameType) return { question: sameType, routeKind: 'prior_error_recovery' as const, routeReason: '用不同原题回收前一天同类型错误；不会重现昨天的原题。' };
  }
  return null;
}

/** Return exactly one next original or null when the target is legitimately complete. */
export function selectJuniorNextQuestion<T extends JuniorAdaptiveCandidate>(input: JuniorSelectionInput<T>): JuniorNextSelection<T> {
  const initialTarget = input.initialTarget ?? 12;
  const hardCap = input.hardCap ?? 15;
  const byQuestionId = new Map<string, JuniorAdaptiveHistory>();
  for (const row of [...input.answered, ...input.issued]) byQuestionId.set(row.question_id, row);
  const allHistory = [...byQuestionId.values()];
  // Prior-day answers are retained only for immutable source-identity
  // exclusion. Each new daily session must independently earn its own two
  // foundation successes plus one higher-level success per knowledge point.
  const currentSession = input.issued;
  const issuedCount = input.issued.length;
  if (issuedCount >= hardCap) return null;
  // A Day-2 recovery must be a *different* original from the error made on
  // the preceding day. Include prior errors in the identity exclusion set;
  // otherwise a same-type lookup could select yesterday's exact question.
  const pool = sourceDistinctPool(input.candidates, [...allHistory, ...input.priorErrors]);
  if (!pool.length) return null;

  // Day learning proceeds knowledge-by-knowledge until two basic successes and
  // one medium success have been observed. A wrong answer stays on that
  // knowledge point and receives a different original before moving forward.
  for (const skillId of input.knowledgeSkillIds) {
    const selection = nextForCore(skillId, pool, currentSession, input.candidates);
    if (selection) return selection;
  }

  // Once the three knowledge points are sound, a later day first reserves
  // space for 2--5 different-original recoveries of yesterday's error types.
  const issuedRecoveryCount = input.issued.filter((row) => row.route_kind === 'prior_error_recovery').length;
  if (input.curriculumDayNumber > 1 && issuedCount >= 6 && issuedRecoveryCount < 5) {
    const recovery = recoveryCandidate(pool, input.priorErrors);
    if (recovery) return recovery;
    // A later day with unstable prior evidence must collect at least two
    // different-original confirmations. Returning null before that minimum
    // lets the caller fail closed instead of silently replacing recovery with
    // generic stability filler.
    if (input.priorErrors.length > 0 && issuedRecoveryCount < 2) return null;
  }

  if (issuedCount < initialTarget) {
    const counts = new Map(input.knowledgeSkillIds.map((skillId) => [skillId, knowledgeRows(currentSession, skillId).length]));
    const orderedSkills = [...input.knowledgeSkillIds].sort((a, b) => (counts.get(a) || 0) - (counts.get(b) || 0) || a.localeCompare(b));
    for (const skillId of orderedSkills) {
      const rows = knowledgeRows(currentSession, skillId);
      const lastLevel = rows.at(-1)?.level || 1;
      const validation = firstCandidate(pool, (candidate) => candidate.knowledge_id === skillId && candidate.level >= lastLevel);
      if (validation) return { question: validation, routeKind: 'stability_validation', routeReason: '三项知识均已过核心关，补足当天 12 题的独立稳定性证据。' };
    }
  }

  // Questions 13--15 are never routine加量: only a newly exposed uncertainty
  // or incorrect foundation judgement may trigger them.
  if (issuedCount >= initialTarget) {
    for (const skillId of input.knowledgeSkillIds) {
      const rows = knowledgeRows(currentSession, skillId);
      const latest = rows.at(-1);
      if (latest && !confidentCorrect(latest)) {
        const readiness = coreReadiness(skillId, rows, input.candidates);
        const repair = firstCandidate(pool, (candidate) => candidate.knowledge_id === skillId && candidate.level === readiness.foundationLevel);
        if (repair) return { question: repair, routeKind: 'foundation_repair', routeReason: '12 题后发现基础仍不稳定，追加一题不同原题做针对性确认。' };
      }
    }
  }
  return null;
}
