import type { CreateVideoRecommendationInput, GuardianDashboardData, LearningAttempt, LearningRecordData, RecordVideoEngagementInput, SessionIdentity, StudentDashboardData, TeacherDashboardData, TeacherObservation, VideoRecommendation, VideoRecommendationFilter } from '../domain/types'
import { ACCESS_FUNCTION, functionUrl, SUPABASE_PUBLISHABLE_KEY, TEACHER_FUNCTION } from './config'
import { readAccessSession } from './session'

async function parseResponse<T>(response: Response): Promise<T> {
  const payload = await response.json().catch(() => ({})) as { message?: string; error?: string }
  if (!response.ok) throw new Error(payload.message || payload.error || '服务暂时不可用，请稍后重试。')
  return payload as T
}

export async function loginWithAccessCode(name: string, code: string) {
  const response = await fetch(functionUrl(ACCESS_FUNCTION), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPABASE_PUBLISHABLE_KEY },
    body: JSON.stringify({ action: 'login', name, code }),
  })
  return parseResponse<{ session: SessionIdentity; dashboard?: StudentDashboardData | GuardianDashboardData }>(response)
}

export async function recoverAccessCode(name: string, recoverySecret: string, newCode: string) {
  const response = await fetch(functionUrl(ACCESS_FUNCTION), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPABASE_PUBLISHABLE_KEY },
    body: JSON.stringify({ action: 'recover_access_code', data: { name, recoverySecret, newCode } }),
  })
  return parseResponse<{ ok: true; message: string }>(response)
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

export async function loadLearningRecord(session: SessionIdentity, studentId?: string) {
  return accessApi<{ record: LearningRecordData }>(session, 'learning_record', studentId ? { studentId } : undefined)
}

export async function submitAttempt(session: SessionIdentity, attempt: LearningAttempt) {
  return accessApi<{ dashboard: StudentDashboardData; achievements: string[] }>(session, 'submit_attempt', attempt)
}

export async function teacherApi<T>(action: string, data?: unknown): Promise<T> {
  const session = readAccessSession()
  if (!session?.token || session.role !== 'teacher') throw new Error('教师登录已失效，请重新输入姓名和登录码。')
  const response = await fetch(functionUrl(TEACHER_FUNCTION), {
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

export async function loadTeacherDashboard() {
  return teacherApi<{ dashboard: TeacherDashboardData }>('teacher_dashboard')
}

export async function saveTeacherObservation(observation: Omit<TeacherObservation, 'id'>) {
  return teacherApi<{ observation: TeacherObservation }>('save_observation', observation)
}

export async function recordVideoEngagement(session: SessionIdentity, input: RecordVideoEngagementInput) {
  return accessApi<{ recommendation?: VideoRecommendation; ok?: true }>(session, 'record_video_engagement', input)
}

export async function listVideoRecommendations(filter: VideoRecommendationFilter = {}) {
  return teacherApi<{ recommendations: VideoRecommendation[] }>('list_video_recommendations', filter)
}

export async function createVideoRecommendation(input: CreateVideoRecommendationInput) {
  return teacherApi<{ recommendation?: VideoRecommendation; ok?: true }>('create_video_recommendation', input)
}

export async function publishVideoRecommendation(recommendationId: string) {
  return teacherApi<{ recommendation?: VideoRecommendation; ok?: true }>('publish_video_recommendation', { recommendationId })
}

export async function withdrawVideoRecommendation(recommendationId: string) {
  return teacherApi<{ recommendation?: VideoRecommendation; ok?: true }>('withdraw_video_recommendation', { recommendationId })
}
