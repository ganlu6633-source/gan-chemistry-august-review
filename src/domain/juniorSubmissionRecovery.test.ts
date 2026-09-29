import { describe, expect, it, vi } from 'vitest'
import ts from 'typescript'
import accessSource from '../../supabase/functions/chemistry-access/index.ts?raw'

// Execute production action; only atomic SQL/network boundaries are mocked.
const start = accessSource.indexOf('if (body.action === "junior_submit_step"')
const action = accessSource.slice(start, accessSource.indexOf('if (body.action === "student_dashboard"', start))
const shape = accessSource.slice(accessSource.indexOf('function juniorQuestionFeedbackShape('), accessSource.indexOf('function validKnowledgeTreeNode('))
const execute = new Function('body', 'identity', 'req', 'supabase', 'validUuid', 'reply', 'juniorSessionPayload', 'studentDashboard', 'RequestError', ts.transpileModule(`${shape}\nreturn (async () => { ${action} })();`, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None } }).outputText)
const planId = '11111111-1111-4111-8111-111111111111'
const stepId = '22222222-2222-4222-8222-222222222222'
const revision = 'immutable-revision-1'
const snapshot = { questionId: 'private-question-id', revisionToken: revision, options: ['A', 'B', 'C', 'D'], correctOption: 0, explanation: '已下发版本解析', scaffold: '已下发提示', sourceInfo: { locator: 'private/source.pdf' } }
const saved = { stepId, questionId: snapshot.questionId, selectedOption: 1, correct: false, uncertain: true, durationSec: 8, answeredAt: '2026-09-29T00:00:00Z', questionSnapshot: snapshot, replayed: true }
const next = { completed: false, currentStepId: 'next-step', currentQuestion: { options: snapshot.options }, session: { id: 'session-owned-by-student' } }
type Row = Record<string, unknown>
function setup({ locked = false, owned = true, demo = false } = {}) {
  let committed: Row | null = locked ? structuredClone(saved) : null
  let writes = 0
  const rpc = vi.fn(async (name: string, args: Row): Promise<{ data: Row | null; error: { message: string } | null }> => {
    expect(name).toBe('chem_junior_submit_answer')
    expect(args.p_student_id).toBe('student-1')
    expect(args.p_plan_id).toBe(planId)
    expect(args.p_step_id).toBe(stepId)
    if (!owned || demo) return { data: null, error: { message: demo ? 'junior_demo_denied' : 'junior_session_unavailable' } }
    if (committed) {
      if (args.p_selected_option !== committed.selectedOption || args.p_revision_token !== revision || args.p_uncertain !== committed.uncertain) return { data: null, error: { message: 'junior step already locked: replay mismatch' } }
      return { data: { ...committed, replayed: true }, error: null }
    }
    writes += 1
    committed = { ...structuredClone(saved), selectedOption: args.p_selected_option, uncertain: args.p_uncertain, durationSec: args.p_duration_sec, correct: args.p_selected_option === 0, replayed: false }
    return { data: structuredClone(committed), error: null }
  })
  const juniorSessionPayload = vi.fn<() => Promise<Row>>().mockResolvedValue(next)
  const studentDashboard = vi.fn<() => Promise<Row>>().mockResolvedValue({ plans: [] })
  const from = vi.fn(() => { throw new Error('Submit must not rebuild the current question before atomic commit') })
  const run = (changes: Row = {}) => execute(
    { action: 'junior_submit_step', data: { planId, stepId, selectedOption: 1, durationSec: 4, uncertain: false, revisionToken: revision, ...changes } },
    { role: 'student', studentId: 'student-1' }, {}, { from, rpc },
    (value: string) => /^[0-9a-f-]{36}$/i.test(value), (_req: unknown, body: Row, status = 200) => ({ status, body }), juniorSessionPayload, studentDashboard,
    class RequestError extends Error { constructor(public status: number, message: string) { super(message) } },
  ) as Promise<{ status: number; body: Row }>
  return { run, rpc, from, juniorSessionPayload, studentDashboard, writeCount: () => writes }
}

describe('junior atomic committed-answer feedback in the real action body', () => {
  it('returns committed feedback without starting or waiting for continuation', async () => {
    const env = setup()
    env.juniorSessionPayload.mockImplementation(() => new Promise(() => {}))
    const response = await env.run({ feedbackOnly: true })
    expect(response.body).toMatchObject({ feedback: { stepId, correct: false, correctOption: 0, explanation: snapshot.explanation }, payload: null, replayed: false, continuation: { status: 'pending' } })
    expect(env.rpc).toHaveBeenCalledTimes(1)
    expect(env.writeCount()).toBe(1)
    expect(env.from).not.toHaveBeenCalled()
    expect(env.juniorSessionPayload).not.toHaveBeenCalled()
    expect(env.studentDashboard).not.toHaveBeenCalled()
  })
  it('does not reveal an answer before atomic commit resolves', async () => {
    const env = setup()
    let commit!: (value: { data: Row; error: null }) => void
    env.rpc.mockImplementationOnce(() => new Promise((resolve) => { commit = resolve }))
    let done = false
    const pending = env.run({ feedbackOnly: true }).then((value) => { done = true; return value })
    await Promise.resolve()
    expect(done).toBe(false)
    commit({ data: saved, error: null })
    expect((await pending).body.feedback).toBeDefined()
  })
  it('background continuation replays the first answer without rewriting its duration or uncertainty', async () => {
    const env = setup()
    const first = await env.run({ feedbackOnly: true })
    const continued = await env.run({ feedbackOnly: false, durationSec: 90, uncertain: false })
    expect(continued.body).toMatchObject({ payload: next, replayed: true, continuation: { status: 'ready' } })
    expect(continued.body.feedback).toEqual(first.body.feedback)
    expect(env.writeCount()).toBe(1)
    expect(env.juniorSessionPayload).toHaveBeenCalledTimes(1)
  })
  it('preserves combined response compatibility for old clients', async () => {
    const env = setup()
    expect((await env.run()).body).toMatchObject({ payload: next, replayed: false, continuation: { status: 'ready' }, feedback: { correct: false } })
    expect(env.writeCount()).toBe(1)
  })
  it('returns saved feedback after continuation fails and retries without a second write', async () => {
    const env = setup()
    env.juniorSessionPayload.mockRejectedValueOnce(new Error('private source path must not leak'))
    const first = await env.run()
    expect(first.body).toMatchObject({ payload: null, continuation: { status: 'unavailable' }, feedback: { explanation: snapshot.explanation } })
    expect(JSON.stringify(first)).not.toContain('private source path')
    expect((await env.run({ uncertain: false, durationSec: 99 })).body).toMatchObject({ payload: next, replayed: true, feedback: { uncertain: false, durationSec: 4 } })
    expect(env.writeCount()).toBe(1)
  })
  it('replays immutable feedback without live question reads or leaking provenance', async () => {
    const env = setup({ locked: true })
    const response = await env.run({ feedbackOnly: true, uncertain: true, durationSec: 999 })
    expect(response.body).toMatchObject({ replayed: true, feedback: { explanation: snapshot.explanation, uncertain: true, durationSec: 8, revisionToken: revision } })
    for (const secret of ['private-question-id', 'private/source.pdf', 'questionSnapshot', 'sourceInfo']) expect(JSON.stringify(response.body)).not.toContain(secret)
    expect(env.from).not.toHaveBeenCalled()
    expect(env.writeCount()).toBe(0)
  })
  it.each([{ selectedOption: 0 }, { revisionToken: 'different-version' }, { uncertain: false }])('rejects changed first option/revision/uncertainty: %j', async (changes) => {
    const env = setup({ locked: true })
    const response = await env.run({ uncertain: true, ...changes, feedbackOnly: true })
    expect(response.status).toBe(409)
    expect(response.body.feedback).toBeUndefined()
    expect(env.writeCount()).toBe(0)
    expect(env.juniorSessionPayload).not.toHaveBeenCalled()
  })
  it.each([{ owned: false }, { demo: true }])('does not reveal feedback when the atomic ownership/non-demo check denies: %j', async (flags) => {
    const env = setup({ locked: true, ...flags })
    const response = await env.run({ feedbackOnly: true })
    expect(response.status).toBe(409)
    expect(response.body.feedback).toBeUndefined()
    expect(env.writeCount()).toBe(0)
    expect(env.juniorSessionPayload).not.toHaveBeenCalled()
  })
  it.each(['junior_daily_question_limit', 'junior revision changed', 'snapshot contract invalid', 'source ready denied'])('keeps database rejection and returns no answer for %s', async (message) => {
    const env = setup()
    env.rpc.mockResolvedValueOnce({ data: null, error: { message } })
    const response = await env.run({ feedbackOnly: true })
    expect(response.status).toBe(409)
    expect(response.body.feedback).toBeUndefined()
    expect(env.juniorSessionPayload).not.toHaveBeenCalled()
  })
  it('hides unexpected SQL diagnostics and safely retries an uncertain transport result', async () => {
    const env = setup()
    env.rpc.mockResolvedValueOnce({ data: null, error: { message: 'sensitive table /private/path secret' } })
    await expect(env.run({ feedbackOnly: true })).rejects.toMatchObject({ status: 503, message: expect.not.stringContaining('sensitive') })
    await expect(env.run({ feedbackOnly: true })).resolves.toMatchObject({ body: { feedback: { correct: false } } })
    expect(env.writeCount()).toBe(1)
  })
  it.each([{ stepId: 'different-step' }, { selectedOption: 3 }, { correct: true }, { answeredAt: null }, { questionSnapshot: { ...snapshot, revisionToken: 'changed' } }, { questionSnapshot: { ...snapshot, correctOption: 5 } }, { questionSnapshot: { ...snapshot, options: ['A'] } }])('rejects inconsistent committed DTO before showing feedback: %j', async (broken) => {
    const env = setup()
    env.rpc.mockResolvedValueOnce({ data: { ...saved, ...broken }, error: null })
    await expect(env.run({ feedbackOnly: true })).rejects.toMatchObject({ status: 503 })
    expect(env.juniorSessionPayload).not.toHaveBeenCalled()
  })
  it.each([{ selectedOption: 4 }, { durationSec: -1 }, { durationSec: 3601 }, { stepId: '' }])('rejects bad input before SQL: %j', async (changes) => {
    const env = setup()
    expect((await env.run(changes)).status).toBe(400)
    expect(env.rpc).not.toHaveBeenCalled()
  })
  it('keeps final feedback and completed payload even when dashboard fails', async () => {
    const env = setup({ locked: true })
    env.juniorSessionPayload.mockResolvedValue({ ...next, completed: true, currentQuestion: null })
    env.studentDashboard.mockRejectedValue(new Error('dashboard unavailable'))
    expect((await env.run({ uncertain: true })).body).toMatchObject({ feedback: { selectedOption: 1 }, payload: { completed: true }, continuation: { status: 'ready' } })
    expect(env.writeCount()).toBe(0)
  })
})
