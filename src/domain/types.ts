export type AppRole = 'student' | 'guardian' | 'teacher'
export type LearningMode = 'REVIEW' | 'CLASS_QUIZ' | 'EXAM_SPRINT'
export type GradeBand = '初三' | '高一' | '高二' | '高三'
export type RecordStatus = 'active' | 'legacy' | 'pending'
export type EvidenceStatus = 'confirmed' | 'conflict' | 'missing' | 'unknown'
export type QuestionReviewStatus = 'draft' | 'needs_review' | 'approved' | 'retired'
export type Visibility = 'student' | 'guardian' | 'teacher' | 'internal'

export interface SessionIdentity {
  role: AppRole
  token: string
  displayName: string
  expiresAt: string
}

export interface StudentProfile {
  id: string
  displayName: string
  gradeBand: GradeBand
  status: RecordStatus
  enrollmentStartDate: string
  schoolClass?: string | null
  textbookVersion: '苏教版' | '人教版' | '通用' | '待确认'
  confirmedLearnedSkillIds: string[]
  aliases: string[]
  needsInitialDiagnostic: boolean
  sources: SourceEvidence[]
  conflicts: DataConflict[]
  missingFields: string[]
}

export interface SourceEvidence {
  sourceId: string
  sourceType: 'teacher_note' | 'quiz_report' | 'course_record' | 'legacy_import'
  observedAt: string | null
  summary: string
  status: EvidenceStatus
}

export interface DataConflict {
  field: string
  values: Array<{ sourceId: string; value: unknown }>
  resolution: 'teacher_confirmation_required' | 'newest_verified_source' | 'unresolved'
}

export interface SkillDefinition {
  id: string
  title: string
  moduleId: string
  gradeBand: GradeBand
  maxLevel: number
  examImportance: 1 | 2 | 3 | 4 | 5
  examDepth: 1 | 2 | 3 | 4 | 5
  prerequisites: string[]
  levelCriteria: SkillLevelCriterion[]
}

export interface SkillLevelCriterion {
  level: number
  studentFacingGoal: string
  requiredAbility: string
}

export interface StudentSkillState {
  studentId: string
  skillId: string
  verifiedLevel: number
  candidateLevel: number | null
  maxLevel: number
  stability: 'unknown' | 'learning' | 'verified' | 'stable' | 'forgotten' | 'recovered'
  evidence: SkillEvidence[]
  consecutiveErrors: number
  nextReviewAt: string | null
  reviewIntervalIndex: number
  lastReviewedAt: string | null
  teacherIntervention: boolean
}

export interface SkillEvidence {
  id: string
  questionId: string
  motherId: string
  level: number
  correct: boolean
  uncertain: boolean
  durationSec: number
  observedAt: string
  mode: LearningMode
}

export interface Question {
  id: string
  motherId: string
  skillId: string
  /** Stable fine-grained concept used to choose a different same-concept variant in later rounds. */
  conceptKey?: string | null
  level: number
  gradeBand: GradeBand
  stem: string
  options: string[]
  correctOption: number
  explanation: string
  scaffold?: string
  reviewStatus: QuestionReviewStatus
  scopeStatus: 'IN' | 'CTX-IN' | 'POSTPONE' | 'OUT'
  sourceKind: 'teacher_original' | 'licensed_local' | 'original_variant'
  imageUrl?: string | null
}

export interface KnowledgeCard {
  id: string
  skillId: string
  title: string
  core: string
  detail: string
  steps: string[]
  commonMistakes: string[]
  microExample: string
  structuredContent?: StructuredKnowledgeContent
  asset?: { type: 'diagram' | 'image' | 'experiment' | 'curve'; url?: string; alt: string }
  reviewStatus: QuestionReviewStatus
}

export interface KnowledgeTreeNode {
  label: string
  rule: string
  examples?: string[]
  visualSteps?: string[]
  caution?: string
  children?: KnowledgeTreeNode[]
}

export interface KnowledgeSection {
  title: string
  summary?: string
  items: KnowledgeTreeNode[]
}

export interface KnowledgeWorkedExample {
  substance: string
  path: string
  labels: string[]
}

export interface KnowledgeVisualTreeNode {
  label: string
  children?: KnowledgeVisualTreeNode[]
}

export interface KnowledgeVisualStep {
  label: string
  caption?: string
}

export interface KnowledgeVisualGroup {
  label: string
  items: string[]
}

export interface KnowledgeVisualSummary {
  kind: 'tree' | 'flow' | 'cycle' | 'compare' | 'network' | 'balance'
  title: string
  center?: string
  steps?: KnowledgeVisualStep[]
  groups?: KnowledgeVisualGroup[]
  tree?: KnowledgeVisualTreeNode
  axes?: KnowledgeVisualGroup[]
}

export interface StructuredKnowledgeContent {
  version: number
  intro: string
  overview?: string[]
  visualSummary?: KnowledgeVisualSummary
  rootTree?: KnowledgeTreeNode
  sections: KnowledgeSection[]
  workedExamples?: KnowledgeWorkedExample[]
  checkpoints?: string[]
  scopeNote?: string
  sourceBasis?: string
}

export interface CourseMapNode {
  id: string
  gradeBand: GradeBand
  textbookVersion: string
  chapter: string
  title: string
  skillIds: string[]
  prerequisiteSkillIds: string[]
  sequence: number
  teacherApproved: boolean
}

export interface LearningPlanDay {
  id: string
  studentId: string
  date: string
  mode: LearningMode
  title: string
  skillIds: string[]
  knowledgeSummaries: string[]
  estimatedMinutes: number
  source: 'course' | 'exam' | 'memory' | 'mastery' | 'mixed'
  isScheduled: boolean
  attemptCount: number
  firstScore: number | null
  latestScore: number | null
  latestCompletedAt: string | null
  /** Number of questions in every review round. */
  questionCount: number
  /** Maximum review rounds allowed for this plan day. */
  roundLimit: number
  /** Optional teaching-scope difficulty ceiling fixed by the teacher. */
  maxQuestionLevel: number | null
  /** The latest complete round has no wrong or uncertain answer. */
  isResolved: boolean
  /** Resolved early or the configured round limit has been reached. */
  isComplete: boolean
  roundsRemaining: number
}

export interface QuestionCandidate {
  question: Question
  reason: 'course_prerequisite' | 'exam_value' | 'memory_due' | 'recent_error' | 'level_validation'
  score: number
}

export interface AttemptAnswer {
  questionId: string
  motherId: string
  skillId: string
  level: number
  correct: boolean
  uncertain: boolean
  durationSec: number
  selectedOption: number
}

export interface LearningAttempt {
  id: string
  studentId: string
  planDayId: string
  attemptKind: 'scheduled' | 'review'
  sequence: number
  mode: LearningMode
  startedAt: string
  completedAt: string
  answers: AttemptAnswer[]
  firstScore: number
}

export interface TeacherObservation {
  id: string
  studentId: string
  courseDate: string
  taughtContent: string
  observedEvidence: string
  internalNote: string
  studentMessage: string
  guardianMessage: string
  visibility: Visibility
}

export interface BehaviorSignal {
  kind: 'pace_fast' | 'pace_slow' | 'unstable' | 'uncertain' | 'guessing'
  evidenceCount: number
  sessionCount: number
  firstSeenAt: string
  lastSeenAt: string
  guardianCopy: string
}

export interface TimelineEvent {
  id: string
  at: string
  type: 'course' | 'attempt' | 'progress' | 'forgetting' | 'system_action' | 'teacher_action'
  title: string
  description: string
}

export type VideoRecommendationStatus = 'draft' | 'published' | 'withdrawn'
export type VideoTrackingMethod = 'link_open_only' | 'self_reported' | 'player_tracked'

export interface VideoRecommendationProgress {
  openedAt: string | null
  lastEngagedAt: string | null
  progressSeconds: number
  durationSeconds: number | null
  completionPercent: number | null
  completedAt: string | null
  trackingMethod: VideoTrackingMethod | null
  eventCount: number
}

export interface VideoRecommendation {
  id: string
  studentId: string
  skillId: string
  skillTitle: string
  title: string
  provider: string
  url: string
  teacherReason: string
  trackingCapability?: VideoTrackingMethod
  status: VideoRecommendationStatus
  publishedAt: string | null
  unresolvedOn?: string | null
  sourceAttemptId?: string | null
  sourceAlertId?: string | null
  createdBy?: string | null
  reviewedBy?: string | null
  reviewedAt?: string | null
  publishedBy?: string | null
  withdrawnBy?: string | null
  withdrawnAt?: string | null
  createdAt?: string
  progress: VideoRecommendationProgress
}

export interface RecordVideoEngagementInput {
  recommendationId: string
  event: 'open' | 'progress' | 'complete'
  progressSeconds?: number
  durationSeconds?: number
  trackingMethod?: VideoTrackingMethod
}

export interface CreateVideoRecommendationInput {
  studentId: string
  skillId: string
  title: string
  provider: string
  url: string
  teacherReason: string
  trackingCapability?: VideoTrackingMethod
  unresolvedDate?: string
  unresolvedSkillId?: string
}

export interface VideoRecommendationFilter {
  studentId?: string
  status?: VideoRecommendationStatus
  date?: string
}

export interface StudentDashboardData {
  profile: Pick<StudentProfile, 'id' | 'displayName' | 'gradeBand' | 'enrollmentStartDate' | 'needsInitialDiagnostic'> & {
    isDemo?: boolean
    availableDemoGrades?: GradeBand[]
  }
  plans: LearningPlanDay[]
  skillStates: StudentSkillState[]
  skillDefinitions: SkillDefinition[]
  todayQuestionCount: number
  achievements: Array<{ id: string; title: string; description: string; earnedAt: string }>
  videoRecommendations?: VideoRecommendation[]
}

export type LearningRecordEvidenceStatus = 'full' | 'partial' | 'unlit'
export type LearningRecordExposure = 'learned' | 'future'
export type LearningRecordRetention = 'forming' | 'stable' | 'due' | 'recovered' | 'unknown'

export interface LearningRecordKnowledgePoint {
  id: string
  title: string
  rule: string
}

export interface LearningRecordKnowledgeSection {
  id: string
  title: string
  summary?: string
  points: LearningRecordKnowledgePoint[]
}

export interface LearningRecordQuestionEvidence {
  questionId: string
  motherId: string
  level: number
  stem: string
  options: string[]
  selectedOption: number
  correctOption: number
  explanation: string
  imageUrl?: string | null
  correct: boolean
  uncertain: boolean
  durationSec: number
  answeredAt: string
  snapshotAvailable: boolean
  currentQuestionStatus: 'available' | 'retired' | 'out_of_scope' | 'unavailable'
}

export interface LearningRecordSkill {
  skillId: string
  title: string
  moduleId: string
  maxLevel: number
  verifiedLevel: number
  candidateLevel: number | null
  evidenceStatus: LearningRecordEvidenceStatus
  exposure: LearningRecordExposure
  retentionStatus: LearningRecordRetention
  lastReviewedAt: string | null
  nextReviewAt: string | null
  teacherIntervention: boolean
  attemptCount: number
  answeredQuestionCount: number
  correctQuestionCount: number
  uniqueMotherCount: number
  learnedTopics: string[]
  knowledgeSections: LearningRecordKnowledgeSection[]
  knowledgeEvidenceScope: 'module_directory_only'
  recentQuestions: LearningRecordQuestionEvidence[]
  recentQuestionsTruncated: boolean
  nextPlan: { id: string; date: string; title: string } | null
}

export interface LearningRecordData {
  generatedAt: string
  evidenceScope: string
  summary: {
    total: number
    learned: number
    full: number
    partial: number
    unlit: number
    due: number
    recovered: number
    answeredQuestions: number
  }
  historyWindow: {
    attemptLimit: number
    answerLimit: number
    recentQuestionsPerSkillLimit: number
    loadedAttempts: number
    totalAttempts: number
    loadedAnswers: number
    totalAnswersInLoadedAttempts: number
    attemptsTruncated: boolean
    answersTruncated: boolean
    hasMore: boolean
  }
  skills: LearningRecordSkill[]
}

export interface GuardianDashboardData {
  student: Pick<StudentProfile, 'displayName' | 'gradeBand'>
  weeklyCompleted: number
  weeklyPlanned: number
  weeklyQuizCompleted: number
  stableSkillCount: number
  growingSkillCount: number
  forgottenSkillCount: number
  teacherAttentionCount: number
  progress: string[]
  concerns: string[]
  behaviorSignals: BehaviorSignal[]
  timeline: TimelineEvent[]
  skillSummary: LearningRecordData['summary']
  videoRecommendations?: VideoRecommendation[]
}

export interface TeacherDashboardData {
  students: Array<Pick<StudentProfile, 'id' | 'displayName' | 'gradeBand' | 'status' | 'needsInitialDiagnostic'> & { guardianNames: string[]; curriculumCohort: string | null; planDays: number }>
  alerts: Array<{ id: string; studentId: string; severity: 'info' | 'attention' | 'urgent'; title: string; reason: string }>
  dailySummary: { generatedAt: string | null; classQuizCount: number; quizCompletedStudentCount: number; quizRosterCount: number; reviewCount: number; interventionCount: number }
  recentQuizSessions: Array<{
    id: string
    studentId: string | null
    studentName: string
    round: number
    trainingTheme: string
    correctCount: number
    totalCount: number
    totalSec: number
    wrongTags: string[]
    slowTags: string[]
    completedAt: string
  }>
  pendingCourseNodes: number
  pendingQuestions: number
}
