import { describe, expect, it } from 'vitest';
import { expandOptionPractice, optionPracticeBindings } from '../../supabase/functions/chemistry-access/option-practice';
import type { OptionPracticeQuestion } from '../../supabase/functions/chemistry-access/option-practice';

const question = (id: string, correct = 0) => ({ id, mother_id: `mother-${id}`, source_item_key: `source-${id}`,
  content_fingerprint: `fingerprint-${id}`, question_revision_token: `revision-${id}`, correct_option: correct });
const reserves = Array.from({ length: 5 }, (_, index) => question(`reserve-${index}`));
const anchor = { ...question('anchor', 3), source_info: { optionPractice: { status: 'verified',
  anchorRevisionToken: 'revision-anchor', bindings: [{ optionIndex: 0, knowledgePoint: '同主族位置判断',
    sameTypeKey: 'same-group-position', candidates: reserves.map((item) => ({ questionId: item.id,
      revisionToken: item.question_revision_token, reason: '原题逐项核对：同主族位置判断，四选一。' })) }] } } };
const lock = (id: string, selected = 0) => ({ question_id: id, selected_option: selected });

describe('teacher reviewed option practice', () => {
  it('routes the wrong selected option to exactly its three original questions', () => {
    const result = expandOptionPractice({ baseQuestions: [anchor, question('next')], candidates: reserves, locks: [lock('anchor')] });
    expect(result.questions.map((item) => item.id)).toEqual(['anchor', 'reserve-0', 'reserve-1', 'reserve-2', 'next']);
    expect(result.contexts['reserve-0'].optionIndex).toBe(0);
    expect(result.progress[0].status).toBe('practicing');
  });
  it('does not mark an option weak from a correct answer or redirect to another option pool', () => {
    expect(expandOptionPractice({ baseQuestions: [anchor], candidates: reserves, locks: [lock('anchor', 3)] }).progress).toEqual([]);
    const result = expandOptionPractice({ baseQuestions: [anchor], candidates: reserves, locks: [lock('anchor', 1)] });
    expect(result.questions).toHaveLength(1);
    expect(result.progress[0].status).toBe('reserve_gap');
  });
  it('adds the remaining two questions after a practice error and replays on resume', () => {
    const input = { baseQuestions: [anchor], candidates: reserves, locks: [lock('anchor'), lock('reserve-0', 2)] };
    const result = expandOptionPractice(input);
    expect(result.questions).toHaveLength(6);
    expect(expandOptionPractice(structuredClone(input))).toEqual(result);
    const final = expandOptionPractice({ ...input, locks: [...input.locks, ...reserves.slice(1).map((item) => lock(item.id))] });
    expect(final.progress[0]).toMatchObject({ answered: 5, correct: 4, status: 'consolidated' });
  });
  it('requires three consecutive independent correct answers, never a self-rating', () => {
    const result = expandOptionPractice({ baseQuestions: [anchor], candidates: reserves,
      locks: [lock('anchor'), ...reserves.map((item, index) => lock(item.id, index === 3 ? 1 : 0))] });
    // A failed fourth answer cannot exist when the initial three passed. Only
    // the three actually issued questions count in this deterministic replay.
    expect(result.progress[0]).toMatchObject({ answered: 3, status: 'consolidated' });
    const failed = expandOptionPractice({ baseQuestions: [anchor], candidates: reserves,
      locks: [lock('anchor'), ...reserves.map((item, index) => lock(item.id, index === 2 ? 1 : 0))] });
    expect(failed.progress[0].status).toBe('needs_practice');
  });
  it('rejects stale revisions, repeated sources and a pool with fewer than three real questions', () => {
    const candidates = reserves.map((item, index) => index < 3 ? { ...item, question_revision_token: 'changed' } : item);
    const result = expandOptionPractice<OptionPracticeQuestion>({ baseQuestions: [anchor], candidates, locks: [lock('anchor')] });
    expect(result.questions).toHaveLength(1);
    expect(result.progress[0].status).toBe('reserve_gap');
    expect(optionPracticeBindings({ ...anchor, question_revision_token: 'new-anchor' })).toEqual([]);
    const excluded = expandOptionPractice({ baseQuestions: [anchor], candidates: reserves,
      locks: [lock('anchor')], excludedQuestions: reserves.slice(0, 3) });
    expect(excluded.progress[0].status).toBe('reserve_gap');
  });
  it('preserves uncertain historical locks without treating them as consolidation', () => {
    const result = expandOptionPractice({ baseQuestions: [anchor], candidates: reserves,
      locks: [lock('anchor'), ...reserves.slice(0, 3).map((item) => ({ ...lock(item.id), uncertain: true }))] });
    expect(result.questions).toHaveLength(6);
    expect(result.progress[0]).toMatchObject({ answered: 3, status: 'practicing' });
  });
  it('rejects malformed persisted candidate rows without crashing the lesson', () => {
    const broken = structuredClone(anchor);
    broken.source_info.optionPractice.bindings[0].candidates = [null, null, null] as never;
    expect(optionPracticeBindings(broken)).toEqual([]);
  });
  it('keeps reserve source identities distinct from base questions and other reserves', () => {
    const candidates = reserves.map((item, index) => index === 1 ? { ...item, source_item_key: reserves[0].source_item_key } : item);
    const result = expandOptionPractice({ baseQuestions: [anchor, reserves[4]], candidates, locks: [lock('anchor')] });
    expect(result.questions.map((item) => item.id)).toEqual(['anchor', 'reserve-0', 'reserve-2', 'reserve-3', 'reserve-4']);
  });
  it('does not count two extracted subquestions from one original as independent reserves', () => {
    const candidates = reserves.map((item, index) => ({ ...item,
      parent_source_item_key: index < 3 ? 'same-original-parent' : `parent-${index}` }));
    const result = expandOptionPractice<OptionPracticeQuestion>({ baseQuestions: [anchor], candidates, locks: [lock('anchor')] });
    expect(result.questions.map((item) => item.id)).toEqual(['anchor', 'reserve-0', 'reserve-3', 'reserve-4']);
    const previous = { ...question('previous-subquestion'), parent_source_item_key: 'same-original-parent' };
    const afterHistory = expandOptionPractice<OptionPracticeQuestion>({ baseQuestions: [anchor], candidates,
      locks: [lock('anchor')], excludedQuestions: [previous] });
    expect(afterHistory.progress[0].status).toBe('reserve_gap');
  });
});
