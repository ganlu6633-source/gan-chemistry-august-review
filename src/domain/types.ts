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

export interface StructuredKnowledgeContent {
  version: number
  intro: string
  rootTree: KnowledgeTreeNode
  sections: KnowledgeSection[]
  workedExamples?: KnowledgeWorkedExample[]
  checkpoints?: string[]
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

export interface StudentDashboardData {
  profile: Pick<StudentProfile, 'id' | 'displayName' | 'gradeBand' | 'enrollmentStartDate' | 'needsInitialDiagnostic'>
  plans: LearningPlanDay[]
  skillStates: StudentSkillState[]
  skillDefinitions: SkillDefinition[]
  todayQuestionCount: number
  achievements: Array<{ id: string; title: string; description: string; earnedAt: string }>
}

export interface GuardianDashboardData {
  student: Pick<StudentProfile, 'displayName' | 'gradeBand'>
  weeklyCompleted: number
  weeklyPlanned: number
  stableSkillCount: number
  growingSkillCount: number
  forgottenSkillCount: number
  teacherAttentionCount: number
  progress: string[]
  concerns: string[]
  behaviorSignals: BehaviorSignal[]
  timeline: TimelineEvent[]
}

export interface TeacherDashboardData {
  students: Array<Pick<StudentProfile, 'id' | 'displayName' | 'gradeBand' | 'status' | 'needsInitialDiagnostic'> & { guardianNames: string[]; curriculumCohort: string | null; planDays: number }>
  alerts: Array<{ id: string; studentId: string; severity: 'info' | 'attention' | 'urgent'; title: string; reason: string }>
  dailySummary: { generatedAt: string | null; classQuizCount: number; reviewCount: number; interventionCount: number }
  pendingCourseNodes: number
  pendingQuestions: number
}
