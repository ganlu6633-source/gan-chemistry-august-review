import { describe, expect, it } from 'vitest';
import { skillMasteryEvidence, type MasteryAnswer } from '../../supabase/functions/chemistry-access/mastery-evidence';
const answer = (id: string, correct: boolean, level = 3): MasteryAnswer => ({ question_id: id, skill_id: 'skill', concept_key: 'concept', level, correct, uncertain: false });
describe('mastery from independent choices', () => {
  it('keeps a single high-level success as candidate evidence', () => {
    expect(skillMasteryEvidence([answer('1', true, 5)], [], 'skill')).toEqual({ unresolvedErrors: 0, confirmedLevel: 0, candidateLevel: 5 });
  });
  it('does not confirm from three adjacent subquestions sharing a broad concept', () => {
    const answers = ['QH3FZ26_Q11_5a', 'QH3FZ26_Q11_5b', 'QH3FZ26_Q11_5c'].map((id) =>
      ({ ...answer(id, true), concept_key: 'H3_STRUCTURE__C04' }));
    expect(skillMasteryEvidence(answers, [], 'skill')).toEqual({ unresolvedErrors: 0, confirmedLevel: 0, candidateLevel: 3 });
  });
  it('resolves the original and early practice errors after the branch is consolidated', () => {
    const answers = [answer('original', false), answer('a', false), ...['b','c','d','e'].map((id) => answer(id, true))];
    expect(skillMasteryEvidence(answers, [{ anchorQuestionId: 'original', optionIndex: 1, knowledgePoint: 'point',
      questionIds: ['a','b','c','d','e'], answered: 5, correct: 4, status: 'consolidated' }], 'skill'))
      .toEqual({ unresolvedErrors: 0, confirmedLevel: 3, candidateLevel: 3 });
  });
  it('does not verify from an unrelated success while a mistake remains', () => {
    const evidence = skillMasteryEvidence([answer('bad', false), ...['1','2','3'].map((id) => ({ ...answer(id, true), concept_key: 'other' }))], [], 'skill');
    expect(evidence.confirmedLevel).toBe(0);
    expect(evidence.unresolvedErrors).toBe(1);
  });
  it('credits the reviewed original option when its reserve questions have another catalogue skill', () => {
    const answers = [answer('original', false), ...['a', 'b', 'c'].map((id) => ({ ...answer(id, true), skill_id: 'inventory-only' }))];
    const evidence = skillMasteryEvidence(answers, [{ anchorQuestionId: 'original', optionIndex: 1, knowledgePoint: 'point',
      questionIds: ['a', 'b', 'c'], answered: 3, correct: 3, status: 'consolidated' }], 'skill');
    expect(evidence.unresolvedErrors).toBe(0);
    expect(evidence.confirmedLevel).toBe(3);
  });
  it('does not erase uncertain historical answers even if a caller labels the branch consolidated', () => {
    const answers = [answer('original', false), ...['a', 'b', 'c'].map((id) => ({ ...answer(id, true), uncertain: true }))];
    const evidence = skillMasteryEvidence(answers, [{ anchorQuestionId: 'original', optionIndex: 1, knowledgePoint: 'point',
      questionIds: ['a', 'b', 'c'], answered: 3, correct: 3, status: 'consolidated' }], 'skill');
    expect(evidence.confirmedLevel).toBe(0);
    expect(evidence.unresolvedErrors).toBe(4);
  });
});
