import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { SessionIdentity, StudentDashboardData } from '../domain/types'
import { StudentApp } from './StudentApp'

const session: SessionIdentity = { role: 'student', token: 'test-session', displayName: '测试学生', expiresAt: '2099-01-01T00:00:00Z' }
const dashboard: StudentDashboardData = {
  profile: { id: 'student-1', displayName: '测试学生', gradeBand: '高一', enrollmentStartDate: '2026-09-01', needsInitialDiagnostic: false },
  plans: [], skillStates: [], skillDefinitions: [], todayQuestionCount: 0, achievements: [],
}

describe('student choice and personal review entry', () => {
  afterEach(() => { cleanup(); vi.unstubAllGlobals() })

  it('keeps free choice on the landing page and opens the due same-concept original', async () => {
    const requests: Array<{ action: string; data?: Record<string, string> }> = []
    vi.stubGlobal('fetch', vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      const request = JSON.parse(String(init?.body)) as { action: string; data?: Record<string, string> }
      requests.push(request)
      if (request.action === 'self_study_catalog') return new Response(JSON.stringify({ catalog: { topics: [
        { skillId: 'H1_CLASSIFY', skillTitle: '物质分类', conceptKey: 'classification', title: '物质分类判断', sequence: 1, originalCount: 4, freshCount: 3, releaseId: 'release-1', releaseKind: 'primary', answeredCount: 2, recentCorrect: 0, reviewDueAt: '2026-09-24T00:00:00Z', reviewPriority: 140, reviewReason: '最近一次答错，建议再巩固。' },
      ] } }), { status: 200 })
      return new Response(JSON.stringify({ error: 'test stop after verifying request' }), { status: 422 })
    }))
    render(<StudentApp session={session} initialDashboard={dashboard} onDashboard={vi.fn()} />)
    expect(screen.getByRole('heading', { name: '测试学生，今天从哪儿开练？' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '我自己挑' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '打开复习雷达' }))
    expect(await screen.findByRole('heading', { name: '物质分类判断' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /开练同考点原题/ }))
    expect(requests.find((request) => request.action === 'open_self_study')?.data).toMatchObject({ skillId: 'H1_CLASSIFY', conceptKey: 'classification', releaseId: 'release-1' })
  })
})
