export type StudyHistoryAnswer = {
  skill_id: string;
  concept_key: string;
  correct: boolean;
  uncertain: boolean;
  completed_at: string;
};

export type StudyState = {
  skill_id: string;
  next_review_at?: string | null;
  last_reviewed_at?: string | null;
  review_interval_index?: number | null;
  consecutive_errors?: number | null;
};

export type StudyTopic = {
  skillId: string;
  conceptKey: string;
  freshCount: number;
  [key: string]: unknown;
};

const DAY = 86_400_000;
const INTERVAL_DAYS = [1, 3, 7, 14, 30] as const;

/** A suggestion is evidence, never an access gate. The learner can open any ready topic. */
export function recommendStudyTopics<T extends StudyTopic>(
  topics: T[], answers: StudyHistoryAnswer[], states: StudyState[], now = new Date(),
): Array<T & { answeredCount: number; recentCorrect: number; reviewDueAt: string | null; reviewPriority: number; reviewReason: string | null }> {
  const byConcept = new Map<string, StudyHistoryAnswer[]>();
  for (const answer of answers) {
    if (!answer.skill_id || !answer.concept_key || !Number.isFinite(Date.parse(answer.completed_at))) continue;
    const key = `${answer.skill_id}|${answer.concept_key}`;
    byConcept.set(key, [...(byConcept.get(key) || []), answer]);
  }
  const bySkill = new Map(states.map((state) => [state.skill_id, state]));
  return topics.map((topic) => {
    const history = [...(byConcept.get(`${topic.skillId}|${topic.conceptKey}`) || [])]
      .sort((a, b) => Date.parse(b.completed_at) - Date.parse(a.completed_at));
    if (!history.length) return { ...topic, answeredCount: 0, recentCorrect: 0, reviewDueAt: null, reviewPriority: 0, reviewReason: null };
    const recent = history.slice(0, 5);
    const recentCorrect = recent.filter((answer) => answer.correct && !answer.uncertain).length;
    const latest = history[0];
    const state = bySkill.get(topic.skillId);
    const weak = !latest.correct || latest.uncertain;
    const intervalIndex = weak ? 0 : Math.min(INTERVAL_DAYS.length - 1, Math.max(1, Number(state?.review_interval_index) || 1));
    const intervalDays = INTERVAL_DAYS[intervalIndex];
    const dueTime = Date.parse(latest.completed_at) + intervalDays * DAY;
    const stateDue = state?.next_review_at ? Date.parse(state.next_review_at) : NaN;
    // The state belongs to a broad skill. Apply an earlier skill reminder only
    // to the weak fine concept; a different concept's error must not reset this one.
    const effectiveDue = weak && Number.isFinite(stateDue) ? Math.min(dueTime, stateDue) : dueTime;
    const overdueDays = Math.max(0, Math.floor((now.getTime() - effectiveDue) / DAY));
    const isDue = effectiveDue <= now.getTime();
    const reviewPriority = isDue
      ? 100 + Math.min(overdueDays, 30) * 2 + (weak ? 30 : 0) + (recent.length - recentCorrect) * 4 + Math.min(history.length, 10)
      : 0;
    const reviewReason = !isDue ? null : weak
      ? '最近一次答错或标记不确定，建议用同知识点原题再巩固。'
      : recentCorrect < recent.length
        ? `最近 ${recent.length} 道中有 ${recent.length - recentCorrect} 道未稳，到了复查时间。`
        : `连续作答较稳定，间隔 ${intervalDays} 天后复查。`;
    return { ...topic, answeredCount: history.length, recentCorrect, reviewDueAt: new Date(effectiveDue).toISOString(), reviewPriority, reviewReason };
  });
}
