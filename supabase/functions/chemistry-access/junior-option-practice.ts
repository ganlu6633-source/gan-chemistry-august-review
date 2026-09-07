import type { JuniorAdaptiveCandidate, JuniorAdaptiveHistory, JuniorNextSelection } from './junior-adaptive.ts';

export type JuniorOptionBranch = {
  branchId: string; anchorStepId: string; anchorSessionId: string; knowledgeId: string;
  knowledgePoint: string; optionIndex: number;
  status: 'practicing' | 'pending' | 'consolidated' | 'needs_practice' | 'reserve_gap';
  reason: string; answered: number; correct: number; total: number;
  candidates: Array<{ questionId: string; revisionToken: string }>;
  nextQuestionId: string | null; nextRevisionToken: string | null;
};
export type JuniorOptionState = { branches: JuniorOptionBranch[]; stepContexts: Array<{ stepId: string; branchId: string; position: number }> };

/** Only opaque student-owned step identifiers and instructional words leave Edge. */
export function juniorPublicOptionProgress(state: JuniorOptionState) {
  return state.branches.map((branch) => ({
    anchorStepId: branch.anchorStepId, optionIndex: branch.optionIndex,
    knowledgePoint: branch.knowledgePoint, status: branch.status,
    answered: branch.answered, correct: branch.correct, total: branch.total,
    pendingReason: branch.reason,
  }));
}

export function juniorOptionContext(state: JuniorOptionState, stepId: string) {
  const context = state.stepContexts.find((row) => row.stepId === stepId);
  const branch = context && state.branches.find((row) => row.branchId === context.branchId);
  return branch && context ? { anchorStepId: branch.anchorStepId, optionIndex: branch.optionIndex,
    knowledgePoint: branch.knowledgePoint, position: context.position, total: branch.total } : undefined;
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
  issued: JuniorAdaptiveHistory[]; optionState: JuniorOptionState;
}): JuniorNextSelection<T> {
  if (input.issued.length >= 12) return null;
  const reserveIds = new Set(input.optionState.branches.filter((b) => ['practicing','pending','reserve_gap'].includes(b.status))
    .flatMap((branch) => branch.candidates.map((candidate) => candidate.questionId)));
  const reserved = input.candidates.filter((candidate) => reserveIds.has(candidate.id));
  const pool = input.candidates.filter((q) => input.knowledgeSkillIds.includes(q.knowledge_id)
    && [...input.history, ...input.issued, ...reserved].every((row) => distinct(q, row)));
  const count = (skill: string) => input.issued.filter((row) => (row.knowledge_id || row.skill_id) === skill).length;
  const skills = [...input.knowledgeSkillIds].sort((a,b) => count(a)-count(b) || a.localeCompare(b));
  for (const skill of skills) {
    const desiredLevel = count(skill) < 2 ? 1 : 2;
    const question = pool.filter((q) => q.knowledge_id === skill)
      .sort((a,b) => Math.abs(a.level-desiredLevel)-Math.abs(b.level-desiredLevel) || a.id.localeCompare(b.id))[0];
    if (question) return { question, routeKind: count(skill) < 2 ? 'new_learning' : 'stability_validation',
      routeReason: '今日课程练习；错项补练另按已审核的具体考点安排。' };
  }
  return null;
}

/** Queue ordering/status is computed under database locks. An exhausted daily
 * budget never closes a branch or discards its remaining original versions. */
export function nextJuniorOptionBranch(state: JuniorOptionState, issuedCount: number) {
  if (issuedCount >= 15) return null;
  return state.branches.find((branch) => branch.status === 'practicing') ?? null;
}
