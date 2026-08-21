import type { CreateVideoRecommendationInput, GuardianDashboardData, LearningAttempt, LearningRecordData, QuestionFeedback, RecordVideoEngagementInput, SessionIdentity, StudentDashboardData, TeacherDashboardData, TeacherObservation, VideoRecommendation, VideoRecommendationFilter } from '../domain/types'
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

export interface ApiRequestOptions {
  signal?: AbortSignal
}

export async function accessApi<T>(session: SessionIdentity, action: string, data?: unknown, options?: ApiRequestOptions): Promise<T> {
  const response = await fetch(functionUrl(ACCESS_FUNCTION), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_PUBLISHABLE_KEY,
      'x-app-session': session.token,
    },
    body: JSON.stringify({ action, data }),
    signal: options?.signal,
  })
  return parseResponse<T>(response)
}

export interface LoadedQuestionAsset {
  dataUrl: string
  mimeType: string
  sha256: string
  width: number
  height: number
}

/** Load one authenticated, server-owned question image without exposing its storage path. */
export interface QuestionAssetAccessContext {
  planId: string
  attemptSequence: number
  revisionToken?: string | null
  previewRound?: number
  studentId?: string
}

export async function loadQuestionAsset(session: SessionIdentity, questionId: string, assetId: string, phase: 'question' | 'analysis', context?: QuestionAssetAccessContext) {
  return accessApi<{ asset: LoadedQuestionAsset }>(session, 'question_asset', { questionId, assetId, phase, ...(context ?? {}) })
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
  return accessApi<{ dashboard: StudentDashboardData; achievements: string[]; feedback?: QuestionFeedback[] }>(session, 'submit_attempt', attempt)
}

export interface QuestionFeedbackInput {
  studentId?: string
  planId: string
  questionId: string
  selectedOption: number
  uncertain: boolean
  durationSec: number
  revisionToken?: string | null
  previewRound?: number
}

/** Lock a real student's first High-3 source answer before revealing feedback. */
export async function loadQuestionFeedback(session: SessionIdentity, input: QuestionFeedbackInput) {
  return accessApi<{ feedback: QuestionFeedback; simulated: boolean }>(session, 'question_feedback', input)
}

/** Read-only teacher simulation; no real attempt or answer lock is written. */
export async function previewQuestionFeedback(input: QuestionFeedbackInput) {
  return teacherApi<{ feedback: QuestionFeedback; simulated: true }>('question_feedback', input)
}

export async function teacherApi<T>(action: string, data?: unknown, options?: ApiRequestOptions): Promise<T> {
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
    signal: options?.signal,
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
