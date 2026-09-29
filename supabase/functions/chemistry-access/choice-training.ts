/** Private SQL context stays on the server. Only issued questions, locked
 * feedback and the small progress contract may cross the student boundary. */
export type ChoiceTrainingContext = {
  policyVersion: 'choice_8_3_30_v1';
  planId: string;
  baseQuestionIds: string[];
  questions: Array<Record<string, unknown>>;
  lockedAnswers: Array<Record<string, unknown>>;
  branches: Array<Record<string, unknown>>;
  dailyUsed: number;
  dailyRemaining: number;
  complete: boolean;
  pendingReason?: string | null;
  startedAt?: string;
};

export function parseChoiceContext(value: unknown): ChoiceTrainingContext {
  const c = value as ChoiceTrainingContext;
  if (!c || c.policyVersion !== 'choice_8_3_30_v1' || !Array.isArray(c.baseQuestionIds)
    || !Array.isArray(c.questions) || c.questions.length > 30 || !Array.isArray(c.lockedAnswers)
    || !Array.isArray(c.branches) || c.questions.some(q => !q || typeof q.id !== 'string')
    || new Set(c.questions.map(q => q.id)).size !== c.questions.length
    || (c.questions.length > 0 && (c.baseQuestionIds.length !== 8 || c.baseQuestionIds.some((id, i) => c.questions[i]?.id !== id)))
    || !Number.isInteger(c.dailyUsed) || c.dailyUsed < 0
    || !Number.isInteger(c.dailyRemaining) || c.dailyRemaining < 0 || c.dailyRemaining > 30
    || c.dailyRemaining > Math.max(0, 30 - c.dailyUsed)
    || new Set(c.lockedAnswers.map(a => a.question_id)).size !== c.lockedAnswers.length) {
    throw new Error('专项练习数据不完整，请重新打开；已保存的答案不会丢失。');
  }
  return c;
}

export function choiceQuestionContext(value: Record<string, unknown>) {
  return { recoveryRound: Number(value.recoveryRound), anchorQuestionId: value.anchorQuestionId || value.anchorId
    ? String(value.anchorQuestionId || value.anchorId) : null,
    knowledgePoint: value.knowledgePoint ? String(value.knowledgePoint) : null,
    position: Number(value.position), total: Number(value.total),
    learningPurpose: ['first_learning', 'spaced_review', 'targeted_practice'].includes(String(value.learningPurpose)) ? String(value.learningPurpose) : null,
    lastAnsweredDate: value.lastAnsweredDate ? String(value.lastAnsweredDate) : null,
    reviewDueDate: value.reviewDueDate ? String(value.reviewDueDate) : null };
}

export function choiceProgress(c: ChoiceTrainingContext) {
  return { policyVersion: c.policyVersion, baseQuestionCount: c.baseQuestionIds.length,
    dailyUsed: c.dailyUsed, dailyRemaining: c.dailyRemaining,
    complete: c.complete, pendingReason: c.pendingReason ?? null };
}

export function choiceBranches(c: ChoiceTrainingContext) {
  const statuses = new Set(['practicing', 'consolidated', 'needs_practice', 'reserve_gap']);
  return c.branches.map(b => ({ anchorQuestionId: String(b.anchorQuestionId),
    optionIndex: Number(b.optionIndex ?? b.anchorOptionIndex), knowledgePoint: String(b.knowledgePoint || ''),
    questionIds: Array.isArray(b.questionIds) ? b.questionIds.map(String) : [],
    answered: Number(b.answered) || 0, correct: Number(b.correct) || 0,
    status: (statuses.has(String(b.status)) ? b.status : 'reserve_gap') as 'practicing' | 'consolidated' | 'needs_practice' | 'reserve_gap',
    recoveryRound: Number(b.recoveryRound), gap: b.gap ? String(b.gap) : null }));
}

export function choiceErrorMessage(code: string): string | null {
  if (!code.startsWith('choice_')) return null;
  if (/daily_limit/.test(code)) return '今天的题量已到上限，已提交的答案都已保存，剩下的明天接着练。';
  if (/source|revision|binding|issuance/.test(code)) return '原题正在核对更新，已保存的进度不会覆盖；请联系甘老师处理这一组。';
  if (/first_answer_immutable|answer_order|out_of_order|answer_not_issued/.test(code)) return '答案已按第一次选择保存，请重新打开这一组，接着当前题目练习。';
  if (/future_plan/.test(code)) return '这个日期的正式题组还未开放，可以先到知识点任选里学习。';
  if (/not_finished/.test(code)) return '请先完成当前题组，再查看本轮结果。';
  if (/base_source_gap/.test(code)) return '这个阶段的合格原题暂时不足，先复习知识点，甘老师正在补齐题目。';
  return '这组练习暂时不能继续，请返回日历重新进入；已保存的答案会保留。';
}

/** Reject stale/forged completion before asking the atomic SQL finalizer. */
export function choiceAnswersMatch(c: ChoiceTrainingContext, submitted: Array<Record<string, unknown>>) {
  if (!c.complete || c.questions.length < 8 || submitted.length !== c.questions.length
    || c.lockedAnswers.length !== c.questions.length) return false;
  return c.questions.every((q, i) => {
    const answer = submitted[i];
    const locked = c.lockedAnswers.find(a => a.question_id === q.id);
    return answer?.questionId === q.id && locked
      && answer.selectedOption === Number(locked.selected_option)
      && (answer.revisionToken ?? null) === (q.question_revision_token ?? null)
      && (locked.revision_token ?? null) === (q.question_revision_token ?? null);
  });
}
