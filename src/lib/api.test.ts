import { afterEach, describe, expect, it, vi } from 'vitest'
import type { SessionIdentity } from '../domain/types'
import { openJuniorAdaptiveSession, previewQuestionFeedback } from './api'
import { clearAccessSession, writeAccessSession } from './session'

const session: SessionIdentity = { role: 'student', token: 'student-session', displayName: '测试学生', expiresAt: '2099-01-01T00:00:00Z' }

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
