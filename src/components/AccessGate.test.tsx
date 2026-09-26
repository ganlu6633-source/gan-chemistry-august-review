import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { AccessGate } from './AccessGate'

afterEach(() => { cleanup(); window.localStorage.clear(); window.history.replaceState(null, '', '/'); vi.unstubAllGlobals() })

describe('phone registration', () => {
  it('requires a teacher-issued invite before collecting a guardian and child phone', async () => {
    const actions: Array<Record<string, unknown>> = []
    vi.stubGlobal('fetch', vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      const payload = JSON.parse(String(init?.body)) as Record<string, unknown>
      actions.push(payload)
      return new Response(JSON.stringify({ ok: true, message: '已提交' }), { status: 200 })
    }))
    render(<AccessGate onSuccess={vi.fn()} />)
    fireEvent.click(screen.getByRole('tab', { name: '加微信后注册' }))
    expect(screen.getByAltText('甘老师微信二维码，扫码添加好友')).toHaveAttribute('src', '/gan-chemistry-august-review/wechat-add.jpg')
    fireEvent.click(screen.getByRole('button', { name: '家长注册' }))
    fireEvent.change(screen.getByLabelText('家长姓名'), { target: { value: '测试家长' } })
    fireEvent.change(screen.getByLabelText('注册手机号'), { target: { value: '13800138000' } })
    fireEvent.change(screen.getByLabelText('孩子姓名'), { target: { value: '测试学生' } })
    fireEvent.change(screen.getByLabelText('孩子手机号'), { target: { value: '13900139000' } })
    fireEvent.change(screen.getByLabelText('设置密码（6—12位）'), { target: { value: 'Parent88' } })
    fireEvent.change(screen.getByLabelText('再输入一次密码'), { target: { value: 'Parent88' } })
    const submit = screen.getByRole('button', { name: /提交注册申请/ })
    expect(submit).toBeDisabled()
    fireEvent.change(screen.getByLabelText('第二步：输入邀请码'), { target: { value: 'A1B2C3D4E5' } })
    fireEvent.click(submit)
    await screen.findByRole('heading', { name: '申请已提交' })
    expect(actions).toEqual([{ action: 'register', data: {
      role: 'guardian', displayName: '测试家长', phone: '13800138000', password: 'Parent88', inviteCode: 'A1B2C3D4E5',
      childName: '测试学生', childPhone: '13900139000',
    } }])
  })

  it('keeps the original code login and offers phone login for approved students', async () => {
    const onSuccess = vi.fn()
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({
      session: { role: 'student', token: 'test-token', displayName: '测试学生', expiresAt: '2099-01-01T00:00:00Z' },
      dashboard: { profile: { id: 'student-1', displayName: '测试学生', gradeBand: '高一' }, plans: [], skillStates: [], skillDefinitions: [], todayQuestionCount: 0, achievements: [] },
    }), { status: 200 })))
    render(<AccessGate onSuccess={onSuccess} />)
    expect(screen.getByLabelText('登录码')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('tab', { name: '手机号登录' }))
    fireEvent.change(screen.getByLabelText('手机号'), { target: { value: '13800138000' } })
    fireEvent.change(screen.getByLabelText('密码'), { target: { value: 'Abc12345' } })
    fireEvent.click(screen.getByRole('button', { name: /进入学习/ }))
    await waitFor(() => expect(onSuccess).toHaveBeenCalledTimes(1))
  })

  it('opens registration with an invitation delivered by an enterprise WeChat link', () => {
    window.history.replaceState(null, '', '/gan-chemistry-august-review/#invite=ABCDEFGH23')
    render(<AccessGate onSuccess={vi.fn()} />)
    expect(screen.getByRole('heading', { name: '加入甘老师化学' })).toBeInTheDocument()
    expect(screen.getByLabelText('第二步：输入邀请码')).toHaveValue('ABCDEFGH23')
    expect(window.location.hash).toBe('')
    expect(screen.getByText('链接里的邀请码已填入')).toBeInTheDocument()
  })
})

describe('seven-day guest trial', () => {
  it('starts without a phone number and resumes with the original browser key', async () => {
    const actions: Array<Record<string, unknown>> = []
    const onSuccess = vi.fn()
    vi.stubGlobal('fetch', vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      const request = JSON.parse(String(init?.body)) as Record<string, unknown>
      actions.push(request)
      return new Response(JSON.stringify({
        session: { role: 'guest', token: 'guest-session', displayName: '访客', expiresAt: '2099-01-01T00:00:00Z' },
        trialKey: 'browser-trial-1', trialExpiresAt: '2099-01-07T00:00:00Z',
        dashboard: { profile: { id: 'guest-1', displayName: '访客', gradeBand: '高二' } },
      }), { status: 200 })
    }))
    const first = render(<AccessGate onSuccess={onSuccess} />)
    fireEvent.click(screen.getByRole('button', { name: /访客试用 7 天/ }))
    expect(screen.queryByLabelText('手机号')).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('想体验哪个年级？'), { target: { value: '高二' } })
    fireEvent.click(screen.getByRole('button', { name: /开始 7 天试用/ }))
    await waitFor(() => expect(onSuccess).toHaveBeenCalledTimes(1))
    expect(actions[0]).toEqual({ action: 'start_guest_trial', data: { gradeBand: '高二' } })
    expect(window.localStorage.getItem('gan-chemistry-guest-trial-key')).toBe('browser-trial-1')
    expect(onSuccess.mock.calls[0][0]).toMatchObject({ role: 'guest', trialExpiresAt: '2099-01-07T00:00:00Z' })

    first.unmount()
    render(<AccessGate onSuccess={onSuccess} />)
    fireEvent.click(screen.getByRole('button', { name: /访客试用 7 天/ }))
    fireEvent.click(screen.getByRole('button', { name: /继续试用/ }))
    await waitFor(() => expect(onSuccess).toHaveBeenCalledTimes(2))
    expect(actions[1]).toEqual({ action: 'start_guest_trial', data: { gradeBand: '初三', trialKey: 'browser-trial-1' } })
  })

  it('shows an expired trial error without silently starting a new trial', async () => {
    window.localStorage.setItem('gan-chemistry-guest-trial-key', 'expired-key')
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ message: '7 天试用已结束，请添加甘老师微信注册正式账号。' }), { status: 410 })))
    render(<AccessGate onSuccess={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /访客试用 7 天/ }))
    fireEvent.click(screen.getByRole('button', { name: /继续试用/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent('7 天试用已结束')
    expect(window.localStorage.getItem('gan-chemistry-guest-trial-key')).toBe('expired-key')
    expect(screen.getByRole('button', { name: '加甘老师微信，申请正式账号' })).toBeInTheDocument()
  })
})
