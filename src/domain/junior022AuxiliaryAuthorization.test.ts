import { describe, expect, it, vi } from 'vitest'
import ts from 'typescript'
import accessSource from '../../supabase/functions/chemistry-access/index.ts?raw'

// Compile the actual current Edge function/action bodies. Only the existing
// source-text predicate and SQL/HTTP/authentication boundaries are injected.
// SQL permission tests and real authentication are Root's separate atomic QA.
type Row = Record<string, unknown>
const ast = ts.createSourceFile('current-edge.ts', accessSource, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS)
const actualFunction = (name: string) => {
  const matches = ast.statements.filter((node) => ts.isFunctionDeclaration(node) && node.name?.text === name)
  if (matches.length !== 1) throw new Error(`Expected one actual Edge function ${name}`)
  return matches[0].getText(ast)
}
class RequestError extends Error { constructor(public status: number, message: string) { super(message) } }
const actualHelpers = ['questionAssetRefs', 'juniorNativeQuestionIsSafe', 'junior022AuxiliaryRefs'].map(actualFunction).join('\n')
const helper = new Function('supabase', 'juniorSourceQuestionIsSafe', 'RequestError', ts.transpileModule(
  `${actualHelpers}\nreturn junior022AuxiliaryRefs;`,
  { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None } }).outputText)
const start = accessSource.indexOf('if (body.action === "junior_auxiliary_asset")')
const end = accessSource.indexOf('if (body.action === "junior_question_asset")', start)
if (start < 0 || end <= start) throw new Error('The applied J022 actual Edge action is absent')
const action = new Function('body', 'identity', 'req', 'supabase', 'validUuid', 'reply', ts.transpileModule(
  `return (async () => { ${accessSource.slice(start, end)} })();`,
  { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None } }).outputText)
const validUuid = (value: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
const reply = (_req: unknown, body: Row, status = 200) => ({ body, status })
const studentId = '11111111-1111-4111-8111-111111111111'
const planId = '22222222-2222-4222-8222-222222222222'
const stepId = '33333333-3333-4333-8333-333333333333'
const otherStudent = '55555555-5555-4555-8555-555555555555'
const release = '2d5adf4e-d2d1-5006-bb48-df97e4f1d1be'
const revision = '7b060cf1503c8775fd2a30946f11123fff7fee5ea8ccc61fdb5a35c59710a7c6'
const assetId = 'JCAUX022_ORIG_56D757684D49F25C'
const sha = '56d757684d49f25ca4ed1186d81ebf39e51ed754028c1b7acf85ee30bc04be43'
const original: Row = { id: 'JCAL-OCT-022-C61', source_release_id: release, question_revision_token: revision,
  render_mode: 'native', image_url: null, asset_refs: [], skill_id: 'J_KY_COMBUSTION', knowledge_id: 'J_KY_COMBUSTION',
  stem: '白磷和红磷燃烧条件实验。', options: ['选项甲', '选项乙', '选项丙', '选项丁'], correct_option: 3, explanation: '四项完整解析。' }
const asset = { kind: 'question_image', mimeType: 'image/png', sha256: sha, width: 235, height: 325, payloadBase64: 'cHJvdGVjdGVkLXVuaXQtZml4dHVyZQ==' }
const ref = { assetId, kind: 'question_image', sha256: sha, width: 235, height: 325 }
const proof = { questionId: original.id, revisionToken: revision, sourceReleaseId: release, answered: false,
  auxiliaryAssetRefs: [ref], asset }
const request = { action: 'junior_auxiliary_asset', data: { questionId: stepId, assetId, planId, revisionToken: revision, phase: 'question' } }
function environment(data: Row | null = structuredClone(proof), error: Row | null = null) {
  const rpc = vi.fn().mockResolvedValue({ data, error })
  const sourceSafe = vi.fn().mockReturnValue(true)
  const from = vi.fn(() => { throw new Error('Auxiliary route must not directly query or mutate question/history tables') })
  const supabase = { rpc, from }
  const runHelper = (row = structuredClone(original), preview = false) => helper(supabase, sourceSafe, RequestError)(studentId, planId, stepId, row, preview) as Promise<Row[]>
  const run = (changes: Row = {}, identity: Row = { role: 'student', studentId }) => action(
    { ...request, data: { ...request.data, ...changes } }, identity, {}, supabase, validUuid, reply) as Promise<{ body: Row; status: number }>
  return { rpc, from, sourceSafe, runHelper, run }
}

describe('J022 auxiliary refs in actual Edge current-step/preview helper', () => {
  it.each([false, true])('uses the proper bound student/plan/step or teacher-preview RPC (preview=%s)', async (preview) => {
    const env = environment(); const before = structuredClone(original)
    const refs = await env.runHelper(original, preview)
    expect(refs).toEqual([{ kind: 'question_image', assetId, sha256: sha, width: 235, height: 325,
      alt: '白磷和红磷燃烧条件对照实验原图' }])
    expect(env.rpc).toHaveBeenCalledWith(preview ? 'chem_junior022_preview_auxiliary_context' : 'chem_junior022_step_auxiliary_context',
      preview ? { p_student_id: studentId, p_plan_id: planId, p_question_id: original.id, p_revision_token: revision, p_asset_path: null }
        : { p_student_id: studentId, p_plan_id: planId, p_step_id: stepId, p_revision_token: revision, p_asset_path: null })
    expect(original).toEqual(before); expect(original.asset_refs).toEqual([]); expect(env.from).not.toHaveBeenCalled()
  })
  it('preserves native text delivery when no optional sidecar exists', async () => {
    const env = environment(null); expect(await env.runHelper()).toEqual([]); expect(env.from).not.toHaveBeenCalled()
  })
  it.each([{ id: 'JCAL-OCT-021-C61' }, { source_release_id: 'different-release' }, { render_mode: 'image_primary' },
    { asset_refs: [ref] }, { skill_id: 'different-skill' }, { correct_option: 4 }, { options: ['A', 'A', 'C', 'D'] }])(
    'never adds auxiliary refs to a different or unsafe original: %j', async (changed) => {
      const env = environment(); expect(await env.runHelper({ ...original, ...changed })).toEqual([]); expect(env.rpc).not.toHaveBeenCalled()
    })
  it('retains the existing native source-text gate', async () => {
    const env = environment(); env.sourceSafe.mockReturnValue(false)
    expect(await env.runHelper()).toEqual([]); expect(env.rpc).not.toHaveBeenCalled()
  })
  it.each([{ questionId: 'wrong-question' }, { revisionToken: 'wrong-revision' }, { sourceReleaseId: 'wrong-release' },
    { auxiliaryAssetRefs: [] }, { auxiliaryAssetRefs: [ref, ref] }, { auxiliaryAssetRefs: [{ ...ref, sha256: '0'.repeat(64) }] },
    { auxiliaryAssetRefs: [{ ...ref, assetId: 'OTHER_AUXILIARY' }] }, { auxiliaryAssetRefs: [{ ...ref, width: 236 }] }])(
    'rejects incomplete/mismatched server provenance instead of displaying a substitute: %j', async (changed) => {
      const env = environment({ ...proof, ...changed }); await expect(env.runHelper()).rejects.toMatchObject({ status: 503 })
    })
  it('propagates a real SQL-boundary error without treating it as missing optional evidence', async () => {
    const error = { message: 'ownership or revision denied' }; const env = environment(null, error)
    await expect(env.runHelper()).rejects.toEqual(error)
  })
})

describe('J022 protected binary action from actual authenticated-role boundary', () => {
  it('ignores a client studentId override for an authenticated student', async () => {
    const env = environment(); const response = await env.run({ studentId: otherStudent })
    expect(response.status).toBe(200)
    expect(env.rpc).toHaveBeenCalledWith('chem_junior022_step_auxiliary_context', {
      p_student_id: studentId, p_plan_id: planId, p_step_id: stepId, p_revision_token: revision, p_asset_path: assetId })
    expect(response.body.asset).toMatchObject({ sha256: sha, width: 235, height: 325 })
    expect(JSON.stringify(response.body)).not.toMatch(/sourceReleaseId|source_item_key|payloadBase64|private/)
    expect(env.from).not.toHaveBeenCalled()
  })
  it('uses an explicit selected student only for the authenticated teacher-preview role', async () => {
    const env = environment(); expect((await env.run({ studentId: otherStudent }, { role: 'teacher', studentId: null })).status).toBe(200)
    expect(env.rpc).toHaveBeenCalledWith('chem_junior022_preview_auxiliary_context', {
      p_student_id: otherStudent, p_plan_id: planId, p_question_id: original.id, p_revision_token: revision, p_asset_path: assetId })
  })
  it('rejects teacher preview without a valid selected student', async () => {
    const env = environment(); expect((await env.run({}, { role: 'teacher', studentId: null })).status).toBe(403)
    expect(env.rpc).not.toHaveBeenCalled()
  })
  it('denies a guardian current unanswered auxiliary and allows only an answered read-only context', async () => {
    const env = environment(); const identity = { role: 'guardian', studentId }
    expect((await env.run({ studentId: otherStudent }, identity)).status).toBe(403)
    env.rpc.mockResolvedValueOnce({ data: { ...proof, answered: true }, error: null })
    expect((await env.run({}, identity)).status).toBe(200)
    expect(env.rpc.mock.calls.every(([name]) => name === 'chem_junior022_step_auxiliary_context')).toBe(true)
    expect(env.rpc.mock.calls.every(([, args]) => args.p_student_id === studentId)).toBe(true)
    expect(env.from).not.toHaveBeenCalled()
  })
  it.each([{ questionId: 'JCAL-OCT-022-C61' }, { planId: 'invalid' }, { assetId: 'OTHER_AUXILIARY' },
    { revisionToken: 'wrong-revision' }, { phase: 'analysis' }])('rejects malformed or stale binary request before SQL: %j', async (changed) => {
      const env = environment(); expect((await env.run(changed)).status).toBe(400); expect(env.rpc).not.toHaveBeenCalled()
    })
  it('honors the SQL ownership/context denial and returns no asset', async () => {
    const env = environment(null, { message: 'student/plan/step belongs to another owner' })
    const response = await env.run(); expect(response.status).toBe(409); expect(response.body.asset).toBeUndefined()
  })
  it.each([null, { ...proof, questionId: 'other-question' }, { ...proof, revisionToken: 'other-token' }, { ...proof, sourceReleaseId: 'other-release' }])(
    'does not release bytes for null/mismatched proof: %j', async (bad) => {
      const response = await environment(bad).run(); expect(response.status).toBe(403); expect(response.body.asset).toBeUndefined()
    })
  it.each([{ kind: 'analysis_image' }, { mimeType: 'text/html' }, { sha256: '0'.repeat(64) }, { width: 236 },
    { height: 326 }, { payloadBase64: '' }, { payloadBase64: null }])('rejects corrupted binary metadata: %j', async (changed) => {
      const response = await environment({ ...proof, asset: { ...asset, ...changed } }).run()
      expect(response.status).toBe(500); expect(response.body.asset).toBeUndefined()
    })
})
