import { StrictMode } from 'react'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { SessionIdentity, StudentDashboardData } from './domain/types'
import { clearAccessSession } from './lib/session'
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

    expect(await screen.findByRole('heading', { name: /测试学生，今天从哪儿开练/ })).toBeInTheDocument()
    expect(actions.filter((action) => action === 'login')).toHaveLength(1)
    expect(actions.filter((action) => action === 'student_dashboard')).toHaveLength(0)
  })
})
