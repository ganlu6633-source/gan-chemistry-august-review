import type { OptionPracticeProgress } from './option-practice.ts';

export type MasteryAnswer = { question_id: string; skill_id: string; concept_key: string | null; level: number; correct: boolean; uncertain: boolean };

/** An isolated correct choice is a candidate signal, never sufficient proof
 * of mastery. Resolved branch errors remain in the record without cancelling
 * the three subsequent independent correct answers that resolved them. */
export function skillMasteryEvidence(answers: MasteryAnswer[], branches: OptionPracticeProgress[], skillId: string) {
  const relevant = answers.filter((answer) => answer.skill_id === skillId);
  const resolved = new Set<string>();
  const confirmedLevels: number[] = [];
  for (const branch of branches.filter((item) => item.status === 'consolidated')) {
    const lastThree = branch.questionIds.map((id) => answers.find((answer) => answer.question_id === id))
      .filter((answer): answer is MasteryAnswer => Boolean(answer)).slice(-3);
    if (lastThree.length !== 3 || lastThree.some((answer) => !answer.correct || answer.uncertain)) continue;
    resolved.add(branch.anchorQuestionId);
    branch.questionIds.forEach((id) => resolved.add(id));
    // A multi-topic source question may be indexed under another broad skill.
    // The explicit reviewed binding, rather than that inventory label, defines
    // which original option these three independent answers confirm.
    const anchor = answers.find((answer) => answer.question_id === branch.anchorQuestionId);
    if (anchor?.skill_id === skillId) confirmedLevels.push(Math.min(...lastThree.map((answer) => answer.level)));
  }
  // A catalogue concept is not proof of the same question type or independent
  // source. Adjacent subquestions of one exam must remain candidate evidence;
  // confirmation requires the explicitly reviewed, identity-deduped branch.
  const unresolvedErrors = relevant.filter((answer) => (!answer.correct || answer.uncertain) && !resolved.has(answer.question_id)).length;
  return {
    unresolvedErrors,
    confirmedLevel: unresolvedErrors ? 0 : Math.max(0, ...confirmedLevels),
    candidateLevel: Math.max(0, ...relevant.filter((answer) => answer.correct).map((answer) => answer.level)),
  };
}
