/** The teacher's explicit, reviewed option-to-original mapping. Never infer a
 * match from a broad skill/concept label, and never manufacture a reserve. */
export type OptionPracticeQuestion = {
  id: string;
  mother_id?: unknown;
  source_item_key?: unknown;
  parent_source_item_key?: unknown;
  content_fingerprint?: unknown;
  question_revision_token?: unknown;
  correct_option?: unknown;
  source_info?: unknown;
};
export type OptionPracticeBinding = {
  optionIndex: number;
  knowledgePoint: string;
  sameTypeKey: string;
  candidates: Array<{ questionId: string; revisionToken: string; reason: string }>;
};
export type OptionPracticeLock = { question_id: string; selected_option: number; uncertain?: boolean };
export type OptionPracticeContext = {
  anchorQuestionId: string;
  optionIndex: number;
  knowledgePoint: string;
  position: number;
  total: number;
};
export type OptionPracticeProgress = {
  anchorQuestionId: string;
  optionIndex: number;
  knowledgePoint: string;
  questionIds: string[];
  answered: number;
  correct: number;
  status: 'practicing' | 'consolidated' | 'needs_practice' | 'reserve_gap';
};

export function optionPracticeBindings(question: OptionPracticeQuestion): OptionPracticeBinding[] {
  const source = question.source_info as Record<string, unknown> | null;
  const config = source?.optionPractice as Record<string, unknown> | undefined;
  if (config?.status !== 'verified' || config.anchorRevisionToken !== question.question_revision_token
    || !Array.isArray(config.bindings)) return [];
  const bindings: OptionPracticeBinding[] = [];
  for (const item of config.bindings) {
    if (!item || typeof item !== 'object') continue;
    const binding = item as OptionPracticeBinding;
    if (!Number.isInteger(binding.optionIndex) || binding.optionIndex < 0 || binding.optionIndex > 3
      || typeof binding.knowledgePoint !== 'string' || !binding.knowledgePoint.trim()
      || typeof binding.sameTypeKey !== 'string' || !binding.sameTypeKey.trim()
      || !Array.isArray(binding.candidates) || binding.candidates.length < 3 || binding.candidates.length > 5
      || binding.candidates.some((candidate) => !candidate || typeof candidate !== 'object'
        || typeof candidate.questionId !== 'string' || !candidate.questionId
        || typeof candidate.revisionToken !== 'string' || !candidate.revisionToken
        || typeof candidate.reason !== 'string' || !candidate.reason.trim())
      || new Set(binding.candidates.map((candidate) => candidate.questionId)).size !== binding.candidates.length
      || bindings.some((old) => old.optionIndex === binding.optionIndex)) continue;
    bindings.push(binding);
  }
  return bindings;
}

function identities(question: OptionPracticeQuestion) {
  return [question.id, question.mother_id, question.source_item_key, question.content_fingerprint, question.parent_source_item_key]
    .map((value, index) => value ? `${index}:${value}` : '').filter(Boolean);
}

/** Deterministic replay from immutable first answers. The first three real
 * questions diagnose the selected option; errors add the remaining reserves.
 * Drill questions cannot recursively branch, and all source identities remain
 * distinct from history, base work, and earlier branches. */
export function expandOptionPractice<T extends OptionPracticeQuestion>(input: {
  baseQuestions: T[];
  candidates: T[];
  locks: OptionPracticeLock[];
  excludedQuestions?: OptionPracticeQuestion[];
}) {
  const candidateById = new Map(input.candidates.map((question) => [question.id, question]));
  const lockById = new Map(input.locks.map((lock) => [lock.question_id, lock]));
  const used = new Set([...input.baseQuestions, ...(input.excludedQuestions ?? [])].flatMap(identities));
  const questions: T[] = [];
  const contexts: Record<string, OptionPracticeContext> = {};
  const progress: OptionPracticeProgress[] = [];
  for (const anchor of input.baseQuestions) {
    questions.push(anchor);
    const answer = lockById.get(anchor.id);
    if (!answer || answer.selected_option === Number(anchor.correct_option)) continue;
    const binding = optionPracticeBindings(anchor).find((item) => item.optionIndex === answer.selected_option);
    if (!binding) {
      progress.push({ anchorQuestionId: anchor.id, optionIndex: answer.selected_option,
        knowledgePoint: '', questionIds: [], answered: 0, correct: 0, status: 'reserve_gap' });
      continue;
    }
    const pool: T[] = [];
    const branchIdentities = new Set<string>();
    for (const item of binding.candidates) {
      const question = candidateById.get(item.questionId);
      if (!question || question.question_revision_token !== item.revisionToken
        || identities(question).some((identity) => used.has(identity) || branchIdentities.has(identity))) continue;
      pool.push(question);
      identities(question).forEach((identity) => branchIdentities.add(identity));
    }
    if (pool.length < 3) {
      progress.push({ anchorQuestionId: anchor.id, optionIndex: binding.optionIndex,
        knowledgePoint: binding.knowledgePoint, questionIds: [], answered: 0, correct: 0, status: 'reserve_gap' });
      continue;
    }
    const firstThreeWrong = pool.slice(0, 3).some((question) => {
      const lock = lockById.get(question.id);
      return lock && (lock.selected_option !== Number(question.correct_option) || lock.uncertain === true);
    });
    const issued = pool.slice(0, firstThreeWrong ? 5 : 3);
    const answered = issued.filter((question) => lockById.has(question.id));
    const correct = answered.filter((question) => lockById.get(question.id)!.selected_option === Number(question.correct_option)).length;
    const lastThreeCorrect = answered.length >= 3 && answered.slice(-3).every((question) => {
      const lock = lockById.get(question.id)!;
      return lock.selected_option === Number(question.correct_option) && lock.uncertain !== true;
    });
    const status = answered.length < issued.length ? 'practicing' : lastThreeCorrect ? 'consolidated' : 'needs_practice';
    progress.push({ anchorQuestionId: anchor.id, optionIndex: binding.optionIndex, knowledgePoint: binding.knowledgePoint,
      questionIds: issued.map((question) => question.id), answered: answered.length, correct, status });
    issued.forEach((question, index) => {
      questions.push(question);
      identities(question).forEach((identity) => used.add(identity));
      contexts[question.id] = { anchorQuestionId: anchor.id, optionIndex: binding.optionIndex,
        knowledgePoint: binding.knowledgePoint, position: index + 1, total: issued.length };
    });
  }
  return { questions, contexts, progress };
}
