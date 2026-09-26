import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { AccessGate } from './AccessGate'

afterEach(() => { cleanup(); vi.unstubAllGlobals() })

describe('phone registration', () => {
  it('collects a guardian and child phone, requires WeChat confirmation, then submits a pending request', async () => {
    const actions: Array<Record<string, unknown>> = []
    vi.stubGlobal('fetch', vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      const payload = JSON.parse(String(init?.body)) as Record<string, unknown>
      actions.push(payload)
      return new Response(JSON.stringify({ ok: true, message: '已提交' }), { status: 200 })
    }))
    render(<AccessGate onSuccess={vi.fn()} />)
    fireEvent.click(screen.getByRole('tab', { name: '新用户注册' }))
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
    fireEvent.click(screen.getByRole('checkbox', { name: '我已添加甘老师微信' }))
    fireEvent.click(submit)
    await screen.findByRole('heading', { name: '申请已提交' })
    expect(actions).toEqual([{ action: 'register', data: {
      role: 'guardian', displayName: '测试家长', phone: '13800138000', password: 'Parent88',
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
})
