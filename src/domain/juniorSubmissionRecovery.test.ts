import { describe, expect, it, vi } from 'vitest'
import ts from 'typescript'
import accessSource from '../../supabase/functions/chemistry-access/index.ts?raw'

// Execute the actual action body, rather than a second implementation of its
// state machine. Only database/network boundaries are replaced in these tests.
const start = accessSource.indexOf('if (body.action === "junior_submit_step"')
const action = accessSource.slice(start, accessSource.indexOf('if (body.action === "student_dashboard"', start))
const shape = accessSource.slice(accessSource.indexOf('function juniorQuestionFeedbackShape('), accessSource.indexOf('function validKnowledgeTreeNode('))
const dependencies = ['body', 'identity', 'req', 'supabase', 'validUuid', 'reply', 'isDemoStudent', 'juniorSessionPayload', 'studentDashboard', 'excludeHeldQuestions', 'juniorNativeQuestionIsSafe', 'RequestError', 'JUNIOR_TEXTBOOK_VERSION', 'JUNIOR_SOURCE_KIND']
const execute = new Function(...dependencies, ts.transpileModule(`${shape}\nreturn (async () => { ${action} })();`, {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None },
}).outputText)

const planId = '11111111-1111-4111-8111-111111111111'
const stepId = '22222222-2222-4222-8222-222222222222'
const sessionId = 'session-owned-by-student'
const revision = 'immutable-revision-1'
const snapshot = { questionId: 'private-question-id', revisionToken: revision, options: ['A', 'B', 'C', 'D'], correctOption: 0, explanation: '已下发版本解析', scaffold: '已下发提示' }
const baseStep = { question_id: snapshot.questionId, skill_id: 'K03', knowledge_id: 'K03', session_id: sessionId, question_snapshot: snapshot, answered_at: null }
const saved = { ...baseStep, selected_option: 1, correct: false, uncertain: true, duration_sec: 8, answered_at: '2026-09-08T00:00:00Z' }
const current = { completed: false, currentStepId: stepId, currentQuestion: { options: snapshot.options, skillId: 'K03', revisionToken: revision }, session: { id: sessionId } }
const next = { completed: false, currentStepId: 'next-step', currentQuestion: { options: snapshot.options }, session: { id: sessionId } }
type Row = Record<string, unknown>

function setup({ locked = false, owned = true, demo = false } = {}) {
  let step: Row = locked ? structuredClone(saved) : structuredClone(baseStep)
  const queries: { table: string; filters: Record<string, unknown> }[] = []
  const from = vi.fn((table: string) => {
    const query = { table, filters: {} as Record<string, unknown> }
    queries.push(query)
    const builder = {
      select: () => builder,
      eq: (key: string, value: unknown) => { query.filters[key] = value; return builder },
      maybeSingle: async () => {
        if (table === 'chem_junior_daily_sessions') return { data: owned && query.filters.student_id === 'student-1' && query.filters.plan_day_id === planId ? { id: sessionId } : null, error: null }
        if (table === 'chem_junior_session_steps') return { data: query.filters.id === stepId && query.filters.session_id === sessionId ? structuredClone(step) : null, error: null }
        if (table === 'chem_questions') return { data: { correct_option: 0, explanation: '已下发版本解析', question_revision_token: revision }, error: null }
        throw new Error(`Unexpected table ${table}`)
      },
    }
    return builder
  })
  const rpc = vi.fn(async (_name: string, values: Row) => {
    step = { ...baseStep, ...saved, selected_option: values.p_selected_option, uncertain: values.p_uncertain, duration_sec: values.p_duration_sec, correct: values.p_selected_option === 0 }
    return { data: [step], error: null as { message: string } | null }
  })
  const juniorSessionPayload = vi.fn<() => Promise<Row>>().mockResolvedValue(next)
  const studentDashboard = vi.fn<() => Promise<Row>>().mockResolvedValue({ plans: [] })
  const run = (changes: Row = {}) => execute(
    { action: 'junior_submit_step', data: { planId, stepId, selectedOption: 1, durationSec: 4, uncertain: false, revisionToken: revision, ...changes } },
    { role: 'student', studentId: 'student-1' }, {}, { from, rpc },
    (value: string) => /^[0-9a-f-]{36}$/i.test(value),
    (_req: unknown, body: Row, status = 200) => ({ status, body }),
    async () => demo, juniorSessionPayload, studentDashboard,
    async (rows: Row[]) => rows, () => true,
    class RequestError extends Error { constructor(public status: number, message: string) { super(message) } },
    '科粤版', 'user_provided_local',
  ) as Promise<{ status: number; body: Row }>
  return { run, rpc, juniorSessionPayload, studentDashboard, queries, setStep: (value: Row) => { step = value } }
}

describe('junior committed-answer recovery in the real action body', () => {
  it('returns saved feedback when preparing the next question fails, then replays without a second write', async () => {
    const env = setup()
    env.juniorSessionPayload.mockResolvedValueOnce(current).mockRejectedValueOnce(new Error('private source path must not leak'))
    const first = await env.run()
    expect(first.status).toBe(200)
    expect(first.body).toMatchObject({ payload: null, replayed: false, continuation: { status: 'unavailable' }, feedback: { stepId, selectedOption: 1, correct: false, correctOption: 0, explanation: snapshot.explanation } })
    expect(JSON.stringify(first)).not.toContain('private source path')
    expect(env.rpc).toHaveBeenCalledTimes(1)
    const retry = await env.run({ uncertain: true, durationSec: 99 })
    expect(retry.body).toMatchObject({ payload: next, replayed: true, feedback: { selectedOption: 1, uncertain: false, durationSec: 4 } })
    expect(env.rpc).toHaveBeenCalledTimes(1)
  })

  it('reads the owned immutable snapshot after retirement and never reads the current question or rewrites metadata', async () => {
    const env = setup({ locked: true })
    const response = await env.run({ uncertain: false, durationSec: 999 })
    expect(response.body).toMatchObject({ replayed: true, feedback: { explanation: snapshot.explanation, uncertain: true, durationSec: 8, revisionToken: revision } })
    expect(env.queries.some((query) => query.table === 'chem_questions')).toBe(false)
    expect(env.queries[0].filters).toEqual({ student_id: 'student-1', plan_day_id: planId })
    expect(env.queries[1].filters).toEqual({ id: stepId, session_id: sessionId })
    expect(JSON.stringify(response.body.feedback)).not.toContain('private-question-id')
    expect(env.rpc).not.toHaveBeenCalled()
  })

  it.each([{ selectedOption: 0 }, { revisionToken: 'different-version' }])('rejects changed option or revision on a locked step: %j', async (changes) => {
    const env = setup({ locked: true })
    expect((await env.run(changes)).status).toBe(409)
    expect(env.rpc).not.toHaveBeenCalled()
    expect(env.juniorSessionPayload).not.toHaveBeenCalled()
  })

  it('does not expose feedback for a plan outside the authenticated student session', async () => {
    const env = setup({ locked: true, owned: false })
    const result = await env.run()
    expect(result.status).toBe(409)
    expect(result.body.feedback).toBeUndefined()
    expect(env.queries).toHaveLength(1)
    expect(env.rpc).not.toHaveBeenCalled()
  })

  it('rejects demo access before reading or writing private session contents', async () => {
    const env = setup({ locked: true, demo: true })
    expect((await env.run()).status).toBe(403)
    expect(env.queries).toHaveLength(0)
    expect(env.rpc).not.toHaveBeenCalled()
  })

  it('recovers a concurrent first lock when the atomic RPC reports already locked', async () => {
    const env = setup()
    env.juniorSessionPayload.mockResolvedValueOnce(current)
    env.rpc.mockImplementationOnce(async () => {
      env.setStep(structuredClone(saved))
      return { data: [], error: { message: 'junior session step is already locked' } }
    })
    const result = await env.run()
    expect(result.body).toMatchObject({ replayed: true, feedback: { durationSec: 8, uncertain: true } })
    expect(env.rpc).toHaveBeenCalledTimes(1)
  })

  it('recovers a concurrent same-answer lock when resume has already advanced', async () => {
    const env = setup()
    env.juniorSessionPayload.mockImplementationOnce(async () => { env.setStep(structuredClone(saved)); return next })
    const result = await env.run()
    expect(result.body).toMatchObject({ replayed: true, feedback: { selectedOption: 1 } })
    expect(env.rpc).not.toHaveBeenCalled()
  })

  it('preserves final feedback if the dashboard fails and leaves a completed payload for safe exit', async () => {
    const env = setup({ locked: true })
    env.juniorSessionPayload.mockResolvedValue({ ...next, completed: true, currentQuestion: null })
    env.studentDashboard.mockRejectedValue(new Error('dashboard unavailable'))
    const result = await env.run()
    expect(result.body).toMatchObject({ feedback: { selectedOption: 1 }, payload: { completed: true }, continuation: { status: 'ready' } })
    expect(result.body.dashboard).toBeUndefined()
    expect(env.rpc).not.toHaveBeenCalled()
  })
})
