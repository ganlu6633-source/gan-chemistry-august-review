/** Persisted plan/session values distinguish the new course from historical
 * 12/15 sessions. Never reinterpret an already-started session on deployment. */
export type JuniorDailyPolicy = {
  initialTarget: 8 | 12;
  hardCap: 30 | 15;
  recoveryRoundLimit: 3 | 0;
};

export const LEGACY_JUNIOR_POLICY: JuniorDailyPolicy = { initialTarget: 12, hardCap: 15, recoveryRoundLimit: 0 };
export const JUNIOR_THREE_ROUND_POLICY: JuniorDailyPolicy = { initialTarget: 8, hardCap: 30, recoveryRoundLimit: 3 };

/** New plans share one student/day budget, so unfinished dates can coexist.
 * Historical sessions retain their original single-active-session contract. */
export function juniorSessionBlocksDateSwitch(policy: JuniorDailyPolicy, other: Record<string, unknown>, planId: string) {
  if (String(other.plan_day_id || "") === planId) return false;
  return policy.initialTarget !== 8 || policy.hardCap !== 30 || policy.recoveryRoundLimit !== 3
    || Number(other.initial_question_target) !== 8 || Number(other.hard_question_cap) !== 30
    || Number(other.recovery_round_limit) !== 3;
}

export function juniorDailyPolicy(plan: Record<string, unknown>, session?: Record<string, unknown> | null): JuniorDailyPolicy {
  const initialTarget = Number(session?.initial_question_target ?? plan.question_count);
  if (initialTarget === 8 && Number(plan.question_count) === 8 && Number(plan.round_limit) === 4
    && (!session || (Number(session.hard_question_cap) === 30 && Number(session.recovery_round_limit) === 3))) {
    return JUNIOR_THREE_ROUND_POLICY;
  }
  if (initialTarget === 12 && Number(plan.question_count) === 12 && Number(plan.round_limit) === 1
    && (!session || (Number(session.hard_question_cap) === 15 && Number(session.recovery_round_limit ?? 0) === 0))) {
    return LEGACY_JUNIOR_POLICY;
  }
  throw new Error('初三计划与学习会话的题量、补练轮数配置不一致。');
}

export function juniorRecoveryRound(value: unknown) {
  const round = Number(value);
  return Number.isInteger(round) && round >= 0 && round <= 3 ? round : 0;
}
