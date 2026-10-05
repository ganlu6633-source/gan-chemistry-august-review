import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { SessionIdentity } from '../domain/types'

const KEY = 'gan-chemistry-v2-session'
const session: SessionIdentity = {
  role: 'student', token: 'test-session', displayName: '测试学生', expiresAt: '2026-10-05T01:00:00Z',
}

describe('access session storage', () => {
  let sessions: typeof import('./session')
  let stored: Map<string, string>
  let storage: Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>

  beforeEach(async () => {
    vi.resetModules()
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-10-05T00:00:00Z'))
    stored = new Map()
    storage = {
      getItem: vi.fn((key: string) => stored.get(key) ?? null),
      setItem: vi.fn((key: string, value: string) => { stored.set(key, value) }),
      removeItem: vi.fn((key: string) => { stored.delete(key) }),
    }
    vi.stubGlobal('sessionStorage', storage)
    sessions = await import('./session')
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
    vi.resetModules()
  })

  it('loads a valid stored session and preserves its original expiry', () => {
    stored.set(KEY, JSON.stringify(session))
    expect(sessions.readAccessSession()).toEqual(session)
    expect(stored.get(KEY)).toBe(JSON.stringify(session))
    expect(storage.setItem).not.toHaveBeenCalled()
  })

  it('persists a normal login so a fresh module can restore it', async () => {
    sessions.writeAccessSession(session)
    expect(stored.get(KEY)).toBe(JSON.stringify(session))
    vi.resetModules()
    const reopened = await import('./session')
    expect(reopened.readAccessSession()).toEqual(session)
  })

  it('handles blocked reads and cleanup without throwing', () => {
    vi.mocked(storage.getItem).mockImplementation(() => { throw new DOMException('Blocked', 'SecurityError') })
    vi.mocked(storage.removeItem).mockImplementation(() => { throw new DOMException('Blocked', 'SecurityError') })
    expect(sessions.readAccessSession()).toBeNull()
    expect(() => sessions.clearAccessSession()).not.toThrow()
    expect(sessions.readAccessSession()).toBeNull()
  })

  it('continues a same-tab login when writing to storage is blocked', () => {
    vi.mocked(storage.setItem).mockImplementation(() => { throw new DOMException('Blocked', 'SecurityError') })
    expect(() => sessions.writeAccessSession(session)).not.toThrow()
    expect(stored.has(KEY)).toBe(false)
    expect(sessions.readAccessSession()).toEqual(session)
    sessions.clearAccessSession()
    expect(sessions.readAccessSession()).toBeNull()
  })

  it('retains the current login if a failed write leaves an older stored session', () => {
    stored.set(KEY, JSON.stringify({ ...session, token: 'older-session' }))
    vi.mocked(storage.setItem).mockImplementation(() => { throw new DOMException('Full', 'QuotaExceededError') })
    sessions.writeAccessSession(session)
    expect(sessions.readAccessSession()).toEqual(session)
  })

  it('keeps logout authoritative when removal fails and storage becomes readable again', () => {
    stored.set(KEY, JSON.stringify(session))
    expect(sessions.readAccessSession()).toEqual(session)
    vi.mocked(storage.removeItem).mockImplementation(() => { throw new DOMException('Blocked', 'SecurityError') })
    expect(() => sessions.clearAccessSession()).not.toThrow()
    expect(stored.has(KEY)).toBe(true)
    vi.mocked(storage.removeItem).mockImplementation((key: string) => { stored.delete(key) })
    expect(sessions.readAccessSession()).toBeNull()
  })

  it('expires a same-tab fallback at the original expiry even when cleanup is blocked', () => {
    vi.mocked(storage.setItem).mockImplementation(() => { throw new DOMException('Blocked', 'SecurityError') })
    vi.mocked(storage.removeItem).mockImplementation(() => { throw new DOMException('Blocked', 'SecurityError') })
    sessions.writeAccessSession(session)
    expect(sessions.readAccessSession()).toEqual(session)
    vi.setSystemTime(new Date(session.expiresAt))
    expect(sessions.readAccessSession()).toBeNull()
    vi.setSystemTime(new Date('2026-10-05T00:00:00Z'))
    expect(sessions.readAccessSession()).toBeNull()
  })

  it('never restores an expired stored session when its removal fails', () => {
    stored.set(KEY, JSON.stringify({ ...session, expiresAt: '2026-10-04T23:00:00Z' }))
    vi.mocked(storage.removeItem).mockImplementation(() => { throw new DOMException('Blocked', 'SecurityError') })
    expect(sessions.readAccessSession()).toBeNull()
    vi.setSystemTime(new Date('2026-10-04T22:00:00Z'))
    expect(sessions.readAccessSession()).toBeNull()
  })

  it.each([
    'not JSON',
    'null',
    JSON.stringify({ ...session, token: '' }),
    JSON.stringify({ ...session, role: 'unknown' }),
    JSON.stringify({ ...session, expiresAt: 'not a date' }),
    JSON.stringify({ ...session, expiresAt: null }),
  ])('rejects and removes an invalid stored session: %s', (value) => {
    stored.set(KEY, value)
    expect(sessions.readAccessSession()).toBeNull()
    expect(stored.has(KEY)).toBe(false)
  })

  it.each(['2026-10-05T00:00:00Z', 'not a date'])('does not persist a login with an inactive expiry: %s', (expiresAt) => {
    sessions.writeAccessSession(session)
    sessions.writeAccessSession({ ...session, expiresAt })
    expect(sessions.readAccessSession()).toBeNull()
    expect(stored.has(KEY)).toBe(false)
  })
})
