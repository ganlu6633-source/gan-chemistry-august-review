// Shared by the browser and Edge transport. This is a routing allowlist, never
// an authorization rule: every action still authenticates and checks ownership.
export const REGIONAL_LEARNING_ACTIONS = [
  'junior_open_session', 'junior_submit_step', 'preview_junior_open_session', 'preview_junior_submit_step',
  'student_dashboard', 'student_preview_dashboard', 'start_plan', 'preview_start_plan',
  'future_plan_preview', 'self_study_catalog', 'knowledge_skill_tree',
  'open_self_study', 'preview_self_study', 'question_feedback', 'question_asset',
  'submit_attempt', 'learning_record', 'student_learning_record', 'save_knowledge_rating',
] as const;

// A lost response can conceal a committed write. Only replay actions whose
// contract is read-only or explicitly idempotent; other writes return the error
// so their existing recovery flow can reconcile state before retrying.
const NO_TRANSPORT_REPLAY = new Set(['open_self_study', 'submit_attempt', 'save_knowledge_rating']);
export function regionalLearningReplaySafe(action: string): boolean {
  return (REGIONAL_LEARNING_ACTIONS as readonly string[]).includes(action) && !NO_TRANSPORT_REPLAY.has(action);
}
