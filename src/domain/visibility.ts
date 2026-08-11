import type { BehaviorSignal, TeacherObservation, Visibility } from './types'

export function canView(role: 'student' | 'guardian' | 'teacher', visibility: Visibility) {
  if (role === 'teacher') return true
  if (visibility === 'internal' || visibility === 'teacher') return false
  if (role === 'guardian') return visibility === 'guardian'
  return visibility === 'student'
}

export function observationForRole(observation: TeacherObservation, role: 'teacher'): TeacherObservation
export function observationForRole(observation: TeacherObservation, role: 'student' | 'guardian'): {
  id: string
  studentId: string
  courseDate: string
  taughtContent: string
  message: string
}
export function observationForRole(observation: TeacherObservation, role: 'student' | 'guardian' | 'teacher') {
  if (role === 'teacher') return observation
  return {
    id: observation.id,
    studentId: observation.studentId,
    courseDate: observation.courseDate,
    taughtContent: observation.taughtContent,
    message: role === 'guardian' ? observation.guardianMessage : observation.studentMessage,
  }
}

export function buildBehaviorSignal(
  kind: BehaviorSignal['kind'],
  evidence: Array<{ at: string; matched: boolean; sessionId: string }>,
): BehaviorSignal | null {
  const matched = evidence.filter((item) => item.matched)
  const sessions = new Set(matched.map((item) => item.sessionId))
  if (matched.length < 3 || sessions.size < 3) return null
  const copy: Record<BehaviorSignal['kind'], string> = {
    pace_fast: '从近期作答表现看，作答节奏有时偏快，系统已加入提交前复核提示。',
    pace_slow: '从近期作答表现看，部分题目停留时间偏长，系统正在用更清晰的步骤帮助提取规律。',
    unstable: '近期表现有一定波动，系统会继续用不同题目确认是否真正稳定。',
    uncertain: '近期多次出现“做对但不确定”，系统正在增加判断依据的练习。',
    guessing: '近期快速错误重复出现，系统推测有时没有充分读完条件，已加入审题提醒。',
  }
  return {
    kind,
    evidenceCount: matched.length,
    sessionCount: sessions.size,
    firstSeenAt: matched[0].at,
    lastSeenAt: matched[matched.length - 1].at,
    guardianCopy: copy[kind],
  }
}
