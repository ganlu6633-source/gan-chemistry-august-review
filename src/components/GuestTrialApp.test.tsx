import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { SessionIdentity } from '../domain/types'
import { GuestTrialApp } from './GuestTrialApp'

const session: SessionIdentity = {
  role: 'guest', token: 'guest-session', displayName: '访客',
  expiresAt: '2099-01-01T00:00:00Z', trialExpiresAt: '2099-01-01T00:00:00Z',
}

afterEach(() => { cleanup(); vi.unstubAllGlobals() })

describe('guest practice', () => {
  it('shows an unanswered multiple-choice example and reveals feedback only after submission', async () => {
    const actions: string[] = []
    vi.stubGlobal('fetch', vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      const request = JSON.parse(String(init?.body)) as { action: string; data?: { selectedOption: number } }
      actions.push(request.action)
      if (request.action === 'guest_practice') return new Response(JSON.stringify({ practice: {
        gradeBand: '初三', total: 1, answeredCount: 0, correctCount: 0, history: [],
        currentQuestion: { id: 'q1', stem: '水属于哪一类物质？', options: ['单质', '化合物', '混合物', '金属'] },
      } }), { status: 200 })
      expect(request.data?.selectedOption).toBe(1)
      return new Response(JSON.stringify({
        feedback: { questionId: 'q1', selectedOption: 1, correct: true, correctOption: 1, explanation: '水由两种元素组成，是化合物。' },
        practice: { gradeBand: '初三', total: 1, answeredCount: 1, correctCount: 1, currentQuestion: null,
          history: [{ questionId: 'q1', selectedOption: 1, correct: true }] },
      }), { status: 200 })
    }))
    render(<GuestTrialApp session={session} onLogout={vi.fn()} onRegister={vi.fn()} />)
    expect(await screen.findByRole('heading', { name: '水属于哪一类物质？' })).toBeInTheDocument()
    expect(screen.queryByText('水由两种元素组成，是化合物。')).not.toBeInTheDocument()
    const submit = screen.getByRole('button', { name: /提交答案/ })
    expect(submit).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: 'B 化合物' }))
    expect(submit).toBeEnabled()
    fireEvent.click(submit)
    expect(await screen.findByRole('heading', { name: '答对啦，手感不错！' })).toBeInTheDocument()
    expect(screen.getByText('水由两种元素组成，是化合物。')).toBeInTheDocument()
    expect(screen.getByText('已做 1/1 题')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /查看练习结果/ }))
    expect(screen.getByRole('heading', { name: '这组体验题做完啦！' })).toBeInTheDocument()
    expect(actions).toEqual(['guest_practice', 'guest_submit_practice'])
  })

  it('sends expired guests directly to registration without loading questions', async () => {
    const fetch = vi.fn()
    vi.stubGlobal('fetch', fetch)
    const onRegister = vi.fn()
    render(<GuestTrialApp session={{ ...session, trialExpiresAt: '2020-01-01T00:00:00Z' }} onLogout={vi.fn()} onRegister={onRegister} />)
    expect(screen.getByRole('heading', { name: '七天体验结束啦' })).toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
    fireEvent.click(screen.getByRole('button', { name: /去注册/ }))
    await waitFor(() => expect(onRegister).toHaveBeenCalledTimes(1))
  })
})
