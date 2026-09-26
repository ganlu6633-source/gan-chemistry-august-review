import type { CreateVideoRecommendationInput, FuturePlanPreviewPayload, GuardianDashboardData, JuniorAdaptivePayload, JuniorStepSubmissionResult, LearningAttempt, LearningRecordData, OptionPracticeProgress, Question, QuestionFeedback, RecordVideoEngagementInput, SessionIdentity, StudentDashboardData, TeacherDashboardData, TeacherObservation, VideoRecommendation, VideoRecommendationFilter } from '../domain/types'
import { ACCESS_FUNCTION, functionUrl, SUPABASE_PUBLISHABLE_KEY, TEACHER_FUNCTION } from './config'
import { readAccessSession } from './session'

async function parseResponse<T>(response: Response): Promise<T> {
  const payload = await response.json().catch(() => ({})) as { message?: string; error?: string }
  if (!response.ok) throw new Error(payload.message || payload.error || '服务暂时不可用，请稍后重试。')
  return payload as T
}

const learningRecordRequests = new Map<string, { expiresAt: number; promise: Promise<{ record: LearningRecordData }> }>()
const LEARNING_RECORD_CACHE_MS = 60_000
const studentPreviewRequests = new Map<string, { expiresAt: number; promise: Promise<{ dashboard: StudentDashboardData }> }>()
const STUDENT_PREVIEW_CACHE_MS = 15_000
const teacherDashboardRequests = new Map<string, { expiresAt: number; promise: Promise<{ dashboard: TeacherDashboardData }> }>()
const TEACHER_DASHBOARD_CACHE_MS = 20_000

function invalidateLearningRecord(session: SessionIdentity) {
  for (const key of learningRecordRequests.keys()) {
    if (key.startsWith(`${session.token}:`)) learningRecordRequests.delete(key)
  }
}

export async function loginWithAccessCode(name: string, code: string) {
  const response = await fetch(functionUrl(ACCESS_FUNCTION), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPABASE_PUBLISHABLE_KEY },
    body: JSON.stringify({ action: 'login', name, code }),
  })
  return parseResponse<{ session: SessionIdentity; dashboard?: StudentDashboardData | GuardianDashboardData }>(response)
}

export type RegistrationData = {
  role: 'student' | 'guardian'; displayName: string; phone: string; password: string;
  gradeBand?: string; childName?: string; childPhone?: string;
}

export async function submitRegistration(data: RegistrationData) {
  const response = await fetch(functionUrl(ACCESS_FUNCTION), {
    method: 'POST', headers: { 'Content-Type': 'application/json', apikey: SUPABASE_PUBLISHABLE_KEY },
    body: JSON.stringify({ action: 'register', data }),
  })
  return parseResponse<{ ok: true; message: string }>(response)
}

export async function loginWithPhone(role: 'student' | 'guardian', phone: string, password: string) {
  const response = await fetch(functionUrl(ACCESS_FUNCTION), {
    method: 'POST', headers: { 'Content-Type': 'application/json', apikey: SUPABASE_PUBLISHABLE_KEY },
    body: JSON.stringify({ action: 'phone_login', data: { role, phone, password } }),
  })
  return parseResponse<{ session: SessionIdentity; dashboard: StudentDashboardData | GuardianDashboardData }>(response)
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
  const result = await parseResponse<T>(response)
  if (action === 'submit_attempt' || action === 'junior_submit_step' || action === 'open_self_study') invalidateLearningRecord(session)
  return result
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
  const key = `${session.token}:${studentId || 'self'}`
  const cached = learningRecordRequests.get(key)
  if (cached && cached.expiresAt > Date.now()) return cached.promise
  const promise = accessApi<{ record: LearningRecordData }>(session, 'learning_record', studentId ? { studentId } : undefined)
  learningRecordRequests.set(key, { expiresAt: Date.now() + LEARNING_RECORD_CACHE_MS, promise })
  void promise.catch(() => { if (learningRecordRequests.get(key)?.promise === promise) learningRecordRequests.delete(key) })
  return promise
}

export async function submitAttempt(session: SessionIdentity, attempt: LearningAttempt) {
  return accessApi<{ dashboard: StudentDashboardData; achievements: string[]; feedback?: QuestionFeedback[]; knowledgeRatingsSaved?: boolean }>(session, 'submit_attempt', attempt)
}

export async function saveKnowledgeRating(session: SessionIdentity, planDayId: string, attemptId: string,
  pointId: string, rating: 'unknown' | 'familiar' | 'fluent') {
  return accessApi<{ ok: true }>(session, 'save_knowledge_rating', { planDayId, attemptId, pointId, rating })
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
  previewAnswers?: Array<{ questionId: string; selectedOption: number; revisionToken?: string | null }>
  previewSelfStudy?: { skillId: string; conceptKey: string; releaseId: string }
}

export interface QuestionFeedbackResponse {
  feedback: QuestionFeedback
  simulated: boolean
  /** Complete ordered group, including follow-up questions selected by the server. */
  questions?: Question[]
  optionPractice?: OptionPracticeProgress[]
}

/** Lock a real student's first high-school source answer before revealing feedback. */
export async function loadQuestionFeedback(session: SessionIdentity, input: QuestionFeedbackInput) {
  return accessApi<QuestionFeedbackResponse>(session, 'question_feedback', input)
}

/** Open or resume a textbook-confirmed junior daily session. The server issues one reviewed original at a time. */
export async function openJuniorAdaptiveSession(session: SessionIdentity, planId: string, options?: ApiRequestOptions) {
  return accessApi<{ payload: JuniorAdaptivePayload }>(session, 'junior_open_session', { planId }, options)
}

/**
 * Open a future plan as knowledge-only preview. The server response never
 * includes questions or creates a learning session/evidence row.
 */
export async function loadFuturePlanPreview(session: SessionIdentity, planId: string, options?: ApiRequestOptions, studentId?: string) {
  return accessApi<{ preview: FuturePlanPreviewPayload }>(session, 'future_plan_preview', { planId, ...(studentId ? { studentId } : {}) }, options)
}

export interface JuniorStepAnswerInput {
  planId: string
  stepId: string
  selectedOption: number
  uncertain: boolean
  durationSec: number
  revisionToken?: string | null
}

/** Persist one immutable first answer and receive the server-selected next original. */
export async function submitJuniorAdaptiveStep(session: SessionIdentity, input: JuniorStepAnswerInput) {
  return accessApi<JuniorStepSubmissionResult>(session, 'junior_submit_step', input)
}

/** Read-only teacher simulation; no real attempt or answer lock is written. */
export async function previewQuestionFeedback(input: QuestionFeedbackInput) {
  const session = readAccessSession()
  if (!session?.token || session.role !== 'teacher') throw new Error('教师登录已失效，请重新输入姓名和登录码。')
  // Access already authenticates teacher sessions and enforces read-only preview.
  // Avoid a second edge invocation/authentication just to forward this request.
  return accessApi<QuestionFeedbackResponse & { simulated: true }>(session, 'question_feedback', input)
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
  const result = await parseResponse<T>(response)
  if (['manage_student', 'manage_class', 'apply_teaching_plan'].includes(action)) studentPreviewRequests.clear()
  if (['manage_student', 'manage_class', 'apply_teaching_plan', 'create_video_recommendation',
    'publish_video_recommendation', 'withdraw_video_recommendation', 'save_observation',
    'reset_access_code', 'reset_access_codes', 'review_question', 'approve_course_node'].includes(action)) teacherDashboardRequests.clear()
  return result
}

export function loadTeacherDashboard(force = false) {
  const session = readAccessSession()
  if (session?.role !== 'teacher') return Promise.reject(new Error('教师登录已失效，请重新输入姓名和登录码。'))
  const key = session.token
  const cached = teacherDashboardRequests.get(key)
  if (!force && cached && cached.expiresAt > Date.now()) return cached.promise
  const promise = teacherApi<{ dashboard: TeacherDashboardData }>('teacher_dashboard')
  const entry = { expiresAt: Date.now() + TEACHER_DASHBOARD_CACHE_MS, promise }
  teacherDashboardRequests.set(key, entry)
  void promise.catch(() => { if (teacherDashboardRequests.get(key) === entry) teacherDashboardRequests.delete(key) })
  return promise
}

/** Reuse the just-loaded read-only preview when entering its full-screen route. */
export function loadStudentPreviewDashboard(studentId: string) {
  const session = readAccessSession()
  if (session?.role !== 'teacher') return Promise.reject(new Error('教师登录已失效，请重新输入姓名和登录码。'))
  const key = `${session.token}:${studentId}`
  const cached = studentPreviewRequests.get(key)
  if (cached && cached.expiresAt > Date.now()) return cached.promise
  const promise = teacherApi<{ dashboard: StudentDashboardData }>('student_preview_dashboard', { studentId })
  const entry = { expiresAt: Date.now() + STUDENT_PREVIEW_CACHE_MS, promise }
  studentPreviewRequests.set(key, entry)
  void promise.catch(() => { if (studentPreviewRequests.get(key) === entry) studentPreviewRequests.delete(key) })
  return promise
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
