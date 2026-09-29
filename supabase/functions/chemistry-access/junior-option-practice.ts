import type { JuniorAdaptiveCandidate, JuniorAdaptiveHistory, JuniorNextSelection } from './junior-adaptive.ts';
import type { JuniorDailyPolicy } from './junior-daily-policy.ts';

const LEGACY_POLICY: JuniorDailyPolicy = { initialTarget: 12, hardCap: 15, recoveryRoundLimit: 0 };

const FOUNDATION_ONLY_KNOWLEDGE_IDS = ['J_KY_1_1_K01', 'J_KY_1_1_K02', 'J_KY_1_1_K03'];

/** This narrow reviewed exception matches the database inventory contract.
 * It is opt-in through the new spaced-review calendar, never inferred from
 * a temporarily depleted candidate pool or applied to an old session. */
export function juniorRouteFoundationOnly(knowledgeId: string, repetitionPolicy: string | undefined) {
  return repetitionPolicy === 'spaced_review'
    && FOUNDATION_ONLY_KNOWLEDGE_IDS.includes(knowledgeId);
}

/** Match the source-release inventory gate using independent source parents,
 * not child-question counts. Only the reviewed three introductory routes are
 * foundation-only; a depleted pool must never invent this exception. */
export function juniorRouteInventoryReadiness(
  candidates: Array<{ knowledge_id?: unknown; parent_source_item_key?: unknown; level?: unknown }>,
  knowledgeId: string,
  textbookVersion: string,
) {
  const rows = candidates.filter((q) => q.knowledge_id === knowledgeId && Number.isInteger(Number(q.level)));
  const foundationLevel = Math.min(...rows.map((q) => Number(q.level)));
  const parents = (items: typeof rows) => new Set(items.map((q) => String(q.parent_source_item_key || '').trim()).filter(Boolean)).size;
  const parentCount = parents(rows);
  const foundationCount = parents(rows.filter((q) => Number(q.level) === foundationLevel));
  const higherCount = parents(rows.filter((q) => Number(q.level) > foundationLevel));
  const foundationOnly = textbookVersion === '科粤版' && FOUNDATION_ONLY_KNOWLEDGE_IDS.includes(knowledgeId);
  const ready = textbookVersion === '科粤版' && parentCount >= 7 && (foundationOnly
    ? foundationLevel === 1 && foundationCount >= 7
    : foundationCount >= 5 && higherCount >= 2);
  return { ready, foundationOnly, parentCount, foundationCount, higherCount, foundationLevel };
}

export type JuniorPracticeAvailability = {
  policy: 'fresh_only' | 'spaced_review';
  questions: Record<string, { eligible: boolean; kind: string; lastAnsweredDate?: string; reviewDueDate?: string; intervalDays?: number }>;
};

export type JuniorOptionBranch = {
  branchId: string; anchorStepId: string; anchorSessionId: string; knowledgeId: string;
  knowledgePoint: string; optionIndex: number;
  status: 'practicing' | 'pending' | 'consolidated' | 'needs_practice' | 'reserve_gap';
  reason: string; answered: number; correct: number; total: number;
  candidates: Array<{ questionId: string; revisionToken: string }>;
  nextQuestionId: string | null; nextRevisionToken: string | null;
  recoveryRound?: number;
  anchorQuestionId?: string; anchorRevisionToken?: string;
};
export type JuniorOptionState = { branches: JuniorOptionBranch[]; stepContexts: Array<{ stepId: string; branchId: string; position: number; recoveryRound?: number }>; dailyIssuedCount?: number; dailyBudgetEnabled?: boolean; pendingStepCountedToday?: boolean; unbranchedAnchors?: Array<Record<string, unknown>>;
  branchAnswerHistory?: Array<{ branchId: string; position: number; correct: boolean; uncertain: boolean }> };

export function juniorDailyBudgetEnabled(state: JuniorOptionState, policy: JuniorDailyPolicy) {
  return state.dailyBudgetEnabled === true || policy.recoveryRoundLimit > 0;
}

export function juniorDailyBudgetReached(state: JuniorOptionState, policy: JuniorDailyPolicy) {
  return juniorDailyBudgetEnabled(state, policy) && (state.dailyIssuedCount ?? 0) >= 30;
}

export function juniorReserveAllocationDeferred(policy: JuniorDailyPolicy, ordinaryAnsweredCount: number) {
  return policy.recoveryRoundLimit > 0 && ordinaryAnsweredCount < policy.initialTarget;
}

/** Only opaque student-owned step identifiers and instructional words leave Edge. */
export function juniorPublicOptionProgress(state: JuniorOptionState) {
  return state.branches.map((branch) => ({
    anchorStepId: branch.anchorStepId, optionIndex: branch.optionIndex,
    knowledgePoint: branch.knowledgePoint, skillId: branch.knowledgeId, status: branch.status,
    answered: branch.answered, correct: branch.correct, total: branch.total,
    pendingReason: branch.reason,
    ...(branch.recoveryRound !== undefined ? { recoveryRound: branch.recoveryRound } : {}),
  }));
}

export function juniorOptionContext(state: JuniorOptionState, stepId: string) {
  const context = state.stepContexts.find((row) => row.stepId === stepId);
  const branch = context && state.branches.find((row) => row.branchId === context.branchId);
  return branch && context ? { anchorStepId: branch.anchorStepId, optionIndex: branch.optionIndex,
    knowledgePoint: branch.knowledgePoint, position: context.position, total: branch.total,
    ...(branch.recoveryRound !== undefined ? { recoveryRound: branch.recoveryRound } : {}) } : undefined;
}

function distinct(candidate: JuniorAdaptiveCandidate, row: JuniorAdaptiveCandidate | JuniorAdaptiveHistory) {
  return candidate.id !== ('id' in row ? row.id : row.question_id)
    && candidate.mother_id !== row.mother_id && candidate.source_item_key !== row.source_item_key
    && candidate.parent_source_item_key !== row.parent_source_item_key && candidate.content_fingerprint !== row.content_fingerprint;
}

/** Ordinary scheduled practice is balanced across curriculum points. It never
 * calls a broad-knowledge error repair or spends a frozen option reserve. */
export function selectJuniorScheduledQuestion<T extends JuniorAdaptiveCandidate>(input: {
  candidates: T[]; knowledgeSkillIds: string[]; history: JuniorAdaptiveHistory[];
  issued: JuniorAdaptiveHistory[]; optionState: JuniorOptionState; policy?: JuniorDailyPolicy;
  availability?: JuniorPracticeAvailability;
}): JuniorNextSelection<T> {
  const policy = input.policy ?? LEGACY_POLICY;
  if (input.issued.length >= policy.initialTarget
    || juniorDailyBudgetReached(input.optionState, policy)) return null;
  const reserveIds = new Set(input.optionState.branches.filter((b) => ['practicing','pending','reserve_gap'].includes(b.status))
    .flatMap((branch) => branch.candidates.map((candidate) => candidate.questionId)));
  const reserved = input.candidates.filter((candidate) => reserveIds.has(candidate.id));
  const spaced = input.availability?.policy === 'spaced_review';
  const pool = input.candidates.filter((q) => input.knowledgeSkillIds.includes(q.knowledge_id)
    && (!juniorRouteFoundationOnly(q.knowledge_id, input.availability?.policy) || q.level === 1)
    && (!spaced || input.availability?.questions[q.id]?.eligible === true)
    && [...(spaced ? [] : input.history), ...input.issued, ...reserved].every((row) => distinct(q, row)));
  const count = (skill: string) => input.issued.filter((row) => (row.knowledge_id || row.skill_id) === skill).length;
  const skills = [...input.knowledgeSkillIds].sort((a,b) => count(a)-count(b) || a.localeCompare(b));
  for (const skill of skills) {
    const desiredLevel = count(skill) < 2 || juniorRouteFoundationOnly(skill, input.availability?.policy) ? 1 : 2;
    const question = pool.filter((q) => q.knowledge_id === skill)
      .sort((a,b) => (spaced ? Number(input.availability?.questions[b.id]?.kind === 'due_review')
        - Number(input.availability?.questions[a.id]?.kind === 'due_review') : 0)
        || Math.abs(a.level-desiredLevel)-Math.abs(b.level-desiredLevel) || a.id.localeCompare(b.id))[0];
    if (question) {
      const review = spaced && input.availability?.questions[question.id]?.kind === 'due_review';
      return { question, routeKind: review ? 'spaced_review' : count(skill) < 2 ? 'new_learning' : 'stability_validation',
        routeReason: review ? `到期复习：这道原题上次作答于 ${input.availability?.questions[question.id]?.lastAnsweredDate}，再练一次看看是否记牢。`
          : '今日课程练习；错项补练另按已审核的具体考点安排。' };
    }
  }
  return null;
}

/** Queue ordering/status is computed under database locks. An exhausted daily
 * budget never closes a branch or discards its remaining original versions. */
export function nextJuniorOptionBranch(state: JuniorOptionState, issuedCount: number, policy: JuniorDailyPolicy = LEGACY_POLICY) {
  if (issuedCount >= policy.hardCap
    || juniorDailyBudgetReached(state, policy)) return null;
  if (policy.recoveryRoundLimit === 0) return state.branches.find((branch) => branch.status === 'practicing') ?? null;
  if (issuedCount < policy.initialTarget) return null;
  // Read-only teacher replay uses the same phase gates as the transactional
  // queue; those two pending reasons are phase waits, never missing reserves.
  const eligible = state.branches.filter((branch) => {
    const round = branch.recoveryRound ?? 1;
    return round >= 1 && round <= policy.recoveryRoundLimit
      && (branch.status === 'practicing' || (branch.status === 'pending'
        && ['initial_round_in_progress', 'waiting_for_previous_recovery_round'].includes(branch.reason)));
  });
  return eligible.sort((a, b) => (a.recoveryRound ?? 1) - (b.recoveryRound ?? 1))[0] ?? null;
}
