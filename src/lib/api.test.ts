import { afterEach, describe, expect, it, vi } from 'vitest'
import type { SessionIdentity } from '../domain/types'
import { accessApi, loadLearningRecord, loadStudentPreviewDashboard, loadTeacherDashboard, openJuniorAdaptiveSession, previewQuestionFeedback, teacherApi } from './api'
import { clearAccessSession, writeAccessSession } from './session'

const session: SessionIdentity = { role: 'student', token: 'student-session', displayName: '测试学生', expiresAt: '2099-01-01T00:00:00Z' }

describe('regional junior access routing', () => {
  afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); vi.resetModules() })
  const actions = ['junior_open_session', 'junior_submit_step', 'preview_junior_open_session', 'preview_junior_submit_step']
  const response = (status = 200) => new Response(JSON.stringify(status >= 400 ? { error: `failure-${status}` } : { ok: true }), { status })

  it.each(actions)('routes only the approved junior action %s to Sydney', async (action) => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValueOnce(response())
    vi.stubGlobal('fetch', fetchMock)
    const identity = action.startsWith('preview_') ? { ...session, role: 'teacher' as const } : session
    await accessApi(identity, action, { planId: 'plan', feedbackOnly: true })
    expect(fetchMock).toHaveBeenCalledTimes(1)
    const [url, init] = fetchMock.mock.calls[0]
    expect(new URL(String(url)).searchParams.get('forceFunctionRegion')).toBe('ap-southeast-2')
    expect(new Headers(init?.headers).get('x-app-session')).toBe(identity.token)
    expect(new Headers(init?.headers).has('x-region')).toBe(false)
    expect(JSON.parse(String(init?.body))).toEqual({ action, data: { planId: 'plan', feedbackOnly: true } })
  })

  it.each(['student_dashboard', 'question_feedback', 'start_plan', 'submit_attempt', 'preview_start_plan', 'question_asset'])('leaves %s on its original route without adding a retry', async (action) => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValueOnce(response(503))
    vi.stubGlobal('fetch', fetchMock)
    await expect(accessApi(session, action, {})).rejects.toThrow('failure-503')
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(new URL(String(fetchMock.mock.calls[0][0])).searchParams.has('forceFunctionRegion')).toBe(false)
  })

  it.each(actions)('falls back once after regional 5xx with the identical %s request', async (action) => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValueOnce(response(503)).mockResolvedValueOnce(response())
    vi.stubGlobal('fetch', fetchMock)
    const identity = action.startsWith('preview_') ? { ...session, role: 'teacher' as const } : session
    const data = { planId: 'plan', stepId: 'step', selectedOption: 2, uncertain: false, durationSec: 7, revisionToken: 'revision', feedbackOnly: false }
    await expect(accessApi(identity, action, data)).resolves.toEqual({ ok: true })
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(new URL(String(fetchMock.mock.calls[0][0])).searchParams.get('forceFunctionRegion')).toBe('ap-southeast-2')
    expect(new URL(String(fetchMock.mock.calls[1][0])).searchParams.has('forceFunctionRegion')).toBe(false)
    expect(fetchMock.mock.calls[1][1]).toBe(fetchMock.mock.calls[0][1])
    expect(JSON.parse(String(fetchMock.mock.calls[1][1]?.body))).toEqual({ action, data })
  })

  it('serializes the first answer once even if the caller changes its object during a lost response', async () => {
    const data = { planId: 'plan', stepId: 'step', selectedOption: 1, durationSec: 5, revisionToken: 'first', feedbackOnly: true }
    const original = { ...data }
    const fetchMock = vi.fn<typeof fetch>().mockImplementationOnce(async () => {
      data.selectedOption = 3
      data.revisionToken = 'changed'
      throw new TypeError('Failed to fetch')
    }).mockResolvedValueOnce(response())
    vi.stubGlobal('fetch', fetchMock)
    await accessApi(session, 'junior_submit_step', data)
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(fetchMock.mock.calls[1][1]?.body).toBe(fetchMock.mock.calls[0][1]?.body)
    expect(JSON.parse(String(fetchMock.mock.calls[1][1]?.body)).data).toEqual(original)
  })

  it.each([new TypeError('Failed to fetch'), new DOMException('Network unavailable', 'NetworkError')])('falls back for a connection failure', async (failure) => {
    const fetchMock = vi.fn<typeof fetch>().mockRejectedValueOnce(failure).mockResolvedValueOnce(response())
    vi.stubGlobal('fetch', fetchMock)
    await accessApi(session, 'junior_open_session', { planId: 'plan' })
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it.each([400, 401, 403, 409, 422, 429])('does not retry a %s response', async (status) => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValueOnce(response(status))
    vi.stubGlobal('fetch', fetchMock)
    await expect(accessApi(session, 'junior_submit_step', {})).rejects.toThrow(`failure-${status}`)
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('does not retry a second failure from the automatic route', async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValueOnce(response(502)).mockResolvedValueOnce(response(503))
    vi.stubGlobal('fetch', fetchMock)
    await expect(accessApi(session, 'junior_submit_step', {})).rejects.toThrow('failure-503')
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('propagates a fallback connection failure without a third request', async () => {
    const fetchMock = vi.fn<typeof fetch>().mockRejectedValue(new TypeError('Failed to fetch'))
    vi.stubGlobal('fetch', fetchMock)
    await expect(accessApi(session, 'junior_submit_step', {})).rejects.toThrow('Failed to fetch')
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('does not reinterpret unrelated exceptions as connection failures', async () => {
    const fetchMock = vi.fn<typeof fetch>().mockRejectedValueOnce(new Error('unexpected failure'))
    vi.stubGlobal('fetch', fetchMock)
    await expect(accessApi(session, 'junior_open_session', {})).rejects.toThrow('unexpected failure')
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('rejects a malformed successful response without silently accepting it or retrying the request', async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValueOnce(new Response('<html>gateway response</html>', { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)
    await expect(accessApi(session, 'junior_open_session', {})).rejects.toThrow('服务返回的内容不完整')
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('preserves a readable error for non-JSON denial responses without a retry', async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValueOnce(new Response('Denied', { status: 403 }))
    vi.stubGlobal('fetch', fetchMock)
    await expect(accessApi(session, 'junior_open_session', {})).rejects.toThrow('服务暂时不可用')
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it.each(['already-aborted', 'regional-abort', 'abort-before-fallback'])('never falls back when cancelled: %s', async (scenario) => {
    const controller = new AbortController()
    if (scenario === 'already-aborted') controller.abort()
    const fetchMock = vi.fn<typeof fetch>().mockImplementationOnce(async () => {
      if (scenario === 'regional-abort') throw new DOMException('Cancelled', 'AbortError')
      controller.abort()
      return response(503)
    })
    vi.stubGlobal('fetch', fetchMock)
    await expect(accessApi(session, 'junior_submit_step', {}, { signal: controller.signal })).rejects.toMatchObject({ name: 'AbortError' })
    expect(fetchMock).toHaveBeenCalledTimes(scenario === 'already-aborted' ? 0 : 1)
  })

  it.each(['ap-northeast-1', 'any', ''])('respects the build-time region override %s', async (region) => {
    vi.stubEnv('VITE_JUNIOR_FUNCTION_REGION', region)
    vi.resetModules()
    const configuredApi = await import('./api')
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValueOnce(response())
    vi.stubGlobal('fetch', fetchMock)
    await configuredApi.accessApi(session, 'preview_junior_open_session', {})
    expect(new URL(String(fetchMock.mock.calls[0][0])).searchParams.get('forceFunctionRegion')).toBe(region && region !== 'any' ? region : null)
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })
})

describe('teacher feedback direct access', () => {
  afterEach(() => { clearAccessSession(); vi.unstubAllGlobals() })
  const input = { studentId: 'preview-student', planId: 'plan', questionId: 'question', selectedOption: 1, uncertain: false, durationSec: 5, previewAnswers: [] }
  it('uses one authenticated access request and preserves the preview context', async () => {
    writeAccessSession({ ...session, role: 'teacher', token: 'teacher-session' })
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({ simulated: true, feedback: {} }), { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)
    await previewQuestionFeedback(input)
    expect(fetchMock).toHaveBeenCalledTimes(1)
    const [url, init] = fetchMock.mock.calls[0]
    expect(url).toContain('/chemistry-access')
    expect(init.headers['x-app-session']).toBe('teacher-session')
    expect(JSON.parse(init.body)).toEqual({ action: 'question_feedback', data: input })
  })
  it('does not send a teacher-preview request with a student session', async () => {
    writeAccessSession(session)
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)
    await expect(previewQuestionFeedback(input)).rejects.toThrow('教师登录已失效')
    expect(fetchMock).not.toHaveBeenCalled()
  })
})

describe('openJuniorAdaptiveSession', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it('forwards the caller AbortSignal to the junior_open_session fetch', async () => {
    const controller = new AbortController()
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      void input
      void init
      return new Response(JSON.stringify({ payload: null }), { status: 200, headers: { 'Content-Type': 'application/json' } })
    })
    vi.stubGlobal('fetch', fetchMock)

    await openJuniorAdaptiveSession(session, 'junior-plan', { signal: controller.signal })

    expect(fetchMock).toHaveBeenCalledTimes(1)
    const init = fetchMock.mock.calls[0][1] as RequestInit
    expect(init.signal).toBe(controller.signal)
    expect(JSON.parse(String(init.body))).toEqual({ action: 'junior_open_session', data: { planId: 'junior-plan' } })
  })

  it('rejects the in-flight request when that signal is aborted', async () => {
    const controller = new AbortController()
    const fetchMock = vi.fn((_input: RequestInfo | URL, init?: RequestInit) => new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener('abort', () => reject(new DOMException('The operation was aborted.', 'AbortError')))
    }))
    vi.stubGlobal('fetch', fetchMock)

    const request = openJuniorAdaptiveSession(session, 'junior-plan', { signal: controller.signal })
    controller.abort()

    await expect(request).rejects.toMatchObject({ name: 'AbortError' })
    expect((fetchMock.mock.calls[0][1] as RequestInit).signal).toBe(controller.signal)
  })
})

describe('learning record navigation cache', () => {
  afterEach(() => { vi.unstubAllGlobals() })

  it('shares a pending read and refreshes after an answer is saved', async () => {
    const currentSession = { ...session, token: 'record-cache-test-session' }
    const actions: string[] = []
    const fetchMock = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      const action = JSON.parse(String(init?.body)).action as string
      actions.push(action)
      return new Response(JSON.stringify(action === 'learning_record' ? { record: { plans: [] } } : { dashboard: {} }), { status: 200 })
    })
    vi.stubGlobal('fetch', fetchMock)

    await Promise.all([loadLearningRecord(currentSession), loadLearningRecord(currentSession)])
    await loadLearningRecord(currentSession)
    expect(actions).toEqual(['learning_record'])

    await accessApi(currentSession, 'submit_attempt', {})
    await loadLearningRecord(currentSession)
    expect(actions).toEqual(['learning_record', 'submit_attempt', 'learning_record'])
  })
})

describe('teacher student preview navigation cache', () => {
  afterEach(() => { clearAccessSession(); vi.unstubAllGlobals() })

  it('reuses the same authorized preview between the summary and full-screen page, then invalidates after management changes', async () => {
    writeAccessSession({ ...session, role: 'teacher', token: 'teacher-preview-cache-session' })
    const actions: string[] = []
    vi.stubGlobal('fetch', vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      const request = JSON.parse(String(init?.body)) as { action: string }
      actions.push(request.action)
      return new Response(JSON.stringify(request.action === 'student_preview_dashboard'
        ? { dashboard: { profile: { id: 'student-one' } } } : { ok: true }), { status: 200 })
    }))

    await Promise.all([loadStudentPreviewDashboard('student-one'), loadStudentPreviewDashboard('student-one')])
    await loadStudentPreviewDashboard('student-one')
    expect(actions).toEqual(['student_preview_dashboard'])

    await teacherApi('manage_student', { action: 'update' })
    await loadStudentPreviewDashboard('student-one')
    expect(actions).toEqual(['student_preview_dashboard', 'manage_student', 'student_preview_dashboard'])
  })

  it('opens the teacher workspace from a recent in-memory dashboard while explicit refresh still requests current data', async () => {
    writeAccessSession({ ...session, role: 'teacher', token: 'teacher-dashboard-cache-session' })
    const fetchMock = vi.fn(async () => new Response(JSON.stringify({ dashboard: { students: [] } }), { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)
    await loadTeacherDashboard()
    await loadTeacherDashboard()
    expect(fetchMock).toHaveBeenCalledTimes(1)
    await loadTeacherDashboard(true)
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })
})
