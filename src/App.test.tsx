import { StrictMode } from 'react'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { SessionIdentity, StudentDashboardData } from './domain/types'
import { clearAccessSession, readAccessSession, writeAccessSession } from './lib/session'
import App from './App'

const session: SessionIdentity = { role: 'student', token: 'login-speed-test', displayName: '测试学生', expiresAt: '2099-01-01T00:00:00Z' }
const dashboard: StudentDashboardData = {
  profile: { id: 'student-1', displayName: '测试学生', gradeBand: '高一', enrollmentStartDate: '2026-09-01', needsInitialDiagnostic: false },
  plans: [], skillStates: [], skillDefinitions: [], todayQuestionCount: 0, achievements: [],
}

describe('student login speed', () => {
  afterEach(() => { cleanup(); clearAccessSession(); vi.unstubAllGlobals() })

  it('uses the dashboard returned by login instead of loading it again', async () => {
    const actions: string[] = []
    vi.stubGlobal('fetch', vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      const action = JSON.parse(String(init?.body)).action as string
      actions.push(action)
      const payload = action === 'login' ? { session, dashboard } : action === 'self_study_catalog' ? { catalog: { topics: [] } } : { error: 'Unexpected request' }
      return new Response(JSON.stringify(payload), { status: action === 'student_dashboard' ? 500 : 200 })
    }))

    render(<StrictMode><MemoryRouter><App /></MemoryRouter></StrictMode>)
    fireEvent.change(screen.getByLabelText('输入姓名'), { target: { value: '测试学生' } })
    fireEvent.change(screen.getByLabelText('登录码'), { target: { value: '123456' } })
    fireEvent.click(screen.getByRole('button', { name: /进入我的化学世界/ }))

    // Cold transforms of the lazy student module can exceed Testing Library's
    // one-second default. This contract checks request reuse, not render timing.
    expect(await screen.findByRole('heading', { name: /测试学生，今天从哪儿开练/ }, { timeout: 5000 })).toBeInTheDocument()
    expect(actions.filter((action) => action === 'login')).toHaveLength(1)
    expect(actions.filter((action) => action === 'student_dashboard')).toHaveLength(0)
  })

  it('starts one teacher dashboard request as soon as login succeeds and reuses it on the teacher route', async () => {
    const actions: string[] = []
    const teacherSession = { ...session, role: 'teacher' as const, token: 'teacher-login-speed-test', displayName: '甘老师' }
    vi.stubGlobal('fetch', vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      const action = JSON.parse(String(init?.body)).action as string
      actions.push(action)
      const payload = action === 'login' ? { session: teacherSession } : { dashboard: {
        students: [], alerts: [], dailySummary: { generatedAt: null, classQuizCount: 0, quizCompletedStudentCount: 0,
          quizRosterCount: 0, reviewCount: 0, interventionCount: 0 }, recentQuizSessions: [], pendingCourseNodes: 0, pendingQuestions: 0,
      } }
      return new Response(JSON.stringify(payload), { status: 200 })
    }))

    render(<MemoryRouter><App /></MemoryRouter>)
    fireEvent.change(screen.getByLabelText('输入姓名'), { target: { value: '甘老师' } })
    fireEvent.change(screen.getByLabelText('登录码'), { target: { value: '123456' } })
    fireEvent.click(screen.getByRole('button', { name: /进入我的化学世界/ }))

    expect(await screen.findByRole('heading', { name: '今天最值得看的事' })).toBeInTheDocument()
    expect(actions).toEqual(['login', 'teacher_dashboard'])
  })

  it.each(['network', 'service'])('keeps a returning student signed in after a temporary %s failure and reconnects without another login', async (failure) => {
    writeAccessSession(session)
    const actions: string[] = []
    let dashboardCalls = 0
    vi.stubGlobal('fetch', vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      const action = JSON.parse(String(init?.body)).action as string
      actions.push(action)
      if (action === 'student_dashboard') {
        dashboardCalls += 1
        // Both the preferred region and its existing automatic fallback fail.
        if (dashboardCalls <= 2) {
          if (failure === 'network') throw new TypeError('Failed to fetch')
          return new Response(JSON.stringify({ error: '服务稍后恢复' }), { status: 503 })
        }
        expect(new Headers(init?.headers).get('x-app-session')).toBe(session.token)
        return new Response(JSON.stringify({ dashboard }), { status: 200 })
      }
      return new Response(JSON.stringify({ catalog: { topics: [] } }), { status: 200 })
    }))

    render(<StrictMode><MemoryRouter><App /></MemoryRouter></StrictMode>)
    expect(await screen.findByRole('heading', { name: '档案还在，再连一下' })).toBeInTheDocument()
    expect(screen.queryByLabelText('登录码')).not.toBeInTheDocument()
    expect(readAccessSession()?.token).toBe(session.token)
    expect(dashboardCalls).toBe(2)
    fireEvent.click(screen.getByRole('button', { name: '重新连接' }))
    expect(await screen.findByRole('heading', { name: /测试学生，今天从哪儿开练/ }, { timeout: 5000 })).toBeInTheDocument()
    expect(actions.filter((action) => action === 'login')).toHaveLength(0)
    expect(dashboardCalls).toBe(3)
  })

  it('keeps a returning guardian signed in during a connection failure', async () => {
    writeAccessSession({ ...session, role: 'guardian' })
    vi.stubGlobal('fetch', vi.fn(async () => { throw new TypeError('Failed to fetch') }))
    render(<MemoryRouter><App /></MemoryRouter>)
    expect(await screen.findByRole('button', { name: '重新连接' })).toBeInTheDocument()
    expect(readAccessSession()?.role).toBe('guardian')
  })

  it.each([401, 403])('clears a restored session only when the server confirms it is invalid (%s)', async (status) => {
    writeAccessSession(session)
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ error: '服务验证提示' }), { status })))
    render(<MemoryRouter><App /></MemoryRouter>)
    if (status === 401) {
      expect(await screen.findByLabelText('登录码')).toBeInTheDocument()
      expect(readAccessSession()).toBeNull()
    } else {
      expect(await screen.findByRole('button', { name: '重新连接' })).toBeInTheDocument()
      expect(readAccessSession()?.token).toBe(session.token)
      fireEvent.click(screen.getByRole('button', { name: '换个账号登录' }))
      expect(await screen.findByLabelText('登录码')).toBeInTheDocument()
      expect(readAccessSession()).toBeNull()
    }
  })
})
