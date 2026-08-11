import { createClient } from '@supabase/supabase-js'
import type { GuardianDashboardData, LearningAttempt, SessionIdentity, StudentDashboardData, TeacherDashboardData, TeacherObservation } from '../domain/types'
import { ACCESS_FUNCTION, functionUrl, SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL, TEACHER_FUNCTION } from './config'

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
})

async function parseResponse<T>(response: Response): Promise<T> {
  const payload = await response.json().catch(() => ({})) as { message?: string; error?: string }
  if (!response.ok) throw new Error(payload.message || payload.error || '服务暂时不可用，请稍后重试。')
  return payload as T
}

export async function loginWithAccessCode(code: string) {
  const response = await fetch(functionUrl(ACCESS_FUNCTION), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPABASE_PUBLISHABLE_KEY },
    body: JSON.stringify({ action: 'login', code }),
  })
  return parseResponse<{ session: SessionIdentity; dashboard: StudentDashboardData | GuardianDashboardData }>(response)
}

export async function accessApi<T>(session: SessionIdentity, action: string, data?: unknown): Promise<T> {
  const response = await fetch(functionUrl(ACCESS_FUNCTION), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_PUBLISHABLE_KEY,
      'x-app-session': session.token,
    },
    body: JSON.stringify({ action, data }),
  })
  return parseResponse<T>(response)
}

export async function loadStudentDashboard(session: SessionIdentity) {
  return accessApi<{ dashboard: StudentDashboardData }>(session, 'student_dashboard')
}

export async function loadGuardianDashboard(session: SessionIdentity) {
  return accessApi<{ dashboard: GuardianDashboardData }>(session, 'guardian_dashboard')
}

export async function submitAttempt(session: SessionIdentity, attempt: LearningAttempt) {
  return accessApi<{ dashboard: StudentDashboardData; achievements: string[] }>(session, 'submit_attempt', attempt)
}

export async function teacherApi<T>(action: string, data?: unknown): Promise<T> {
  const { data: authData } = await supabase.auth.getSession()
  const accessToken = authData.session?.access_token
  if (!accessToken) throw new Error('教师登录已失效，请重新获取登录链接。')
  const response = await fetch(functionUrl(TEACHER_FUNCTION), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ action, data }),
  })
  return parseResponse<T>(response)
}

export async function loadTeacherDashboard() {
  return teacherApi<{ dashboard: TeacherDashboardData }>('teacher_dashboard')
}

export async function saveTeacherObservation(observation: Omit<TeacherObservation, 'id'>) {
  return teacherApi<{ observation: TeacherObservation }>('save_observation', observation)
}

export async function requestMagicLink(email: string) {
  const redirectTo = `${window.location.origin}${import.meta.env.BASE_URL}teacher`
  const { error } = await supabase.auth.signInWithOtp({ email, options: { emailRedirectTo: redirectTo, shouldCreateUser: true } })
  if (error) throw error
}
