import type { SessionIdentity } from '../domain/types'

const KEY = 'gan-chemistry-v2-session'

// Undefined means storage has not been read. Null also remembers a logout when
// the browser refuses to delete an older stored session.
let tabSession: SessionIdentity | null | undefined

function isActiveSession(value: unknown): value is SessionIdentity {
  if (!value || typeof value !== 'object') return false
  const session = value as Partial<SessionIdentity>
  return typeof session.token === 'string' && Boolean(session.token)
    && typeof session.displayName === 'string'
    && ['student', 'guardian', 'teacher', 'guest'].includes(session.role ?? '')
    && typeof session.expiresAt === 'string'
    && Number.isFinite(Date.parse(session.expiresAt))
    && Date.parse(session.expiresAt) > Date.now()
}

export function readAccessSession(): SessionIdentity | null {
  if (tabSession !== undefined) {
    if (isActiveSession(tabSession)) return tabSession
    if (tabSession) clearAccessSession()
    return null
  }
  try {
    const parsed: unknown = JSON.parse(sessionStorage.getItem(KEY) || 'null')
    if (isActiveSession(parsed)) {
      tabSession = parsed
      return parsed
    }
  } catch { /* A browser may block storage access entirely. */ }
  clearAccessSession()
  return null
}

export function writeAccessSession(session: SessionIdentity) {
  if (!isActiveSession(session)) { clearAccessSession(); return }
  tabSession = session
  try { sessionStorage.setItem(KEY, JSON.stringify(session)) } catch { /* Continue in this tab. */ }
}

export function clearAccessSession() {
  tabSession = null
  try { sessionStorage.removeItem(KEY) } catch { /* The in-memory logout remains authoritative. */ }
}
