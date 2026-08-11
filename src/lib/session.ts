import type { SessionIdentity } from '../domain/types'

const KEY = 'gan-chemistry-v2-session'

export function readAccessSession(): SessionIdentity | null {
  try {
    const parsed = JSON.parse(sessionStorage.getItem(KEY) || 'null') as SessionIdentity | null
    if (!parsed?.token || !parsed.role || !parsed.expiresAt) return null
    if (Date.parse(parsed.expiresAt) <= Date.now()) {
      sessionStorage.removeItem(KEY)
      return null
    }
    return parsed
  } catch {
    sessionStorage.removeItem(KEY)
    return null
  }
}

export function writeAccessSession(session: SessionIdentity) {
  sessionStorage.setItem(KEY, JSON.stringify(session))
}

export function clearAccessSession() {
  sessionStorage.removeItem(KEY)
}
