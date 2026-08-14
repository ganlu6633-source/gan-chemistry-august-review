import { useEffect, useState } from 'react'
import { Navigate, Route, Routes, useNavigate, useParams } from 'react-router-dom'
import type { GuardianDashboardData, SessionIdentity, StudentDashboardData } from './domain/types'
import { AppShell } from './components/AppShell'
import { AccessGate } from './components/AccessGate'
import { StudentApp } from './components/StudentApp'
import { GuardianApp } from './components/GuardianApp'
import { TeacherGate } from './components/TeacherApp'
import { loadGuardianDashboard, loadStudentDashboard, teacherApi } from './lib/api'
import { clearAccessSession, readAccessSession, writeAccessSession } from './lib/session'

type Dashboard = StudentDashboardData | GuardianDashboardData

export default function App() {
  return <Routes><Route path="/" element={<AccessExperience />} /><Route path="/teacher" element={<TeacherExperience />} /><Route path="/teacher/preview/:studentId" element={<TeacherStudentPreview />} /><Route path="*" element={<Navigate to="/" replace />} /></Routes>
}

function TeacherExperience() {
  const navigate = useNavigate()
  return <TeacherGate onPreviewStudent={(studentId) => navigate(`/teacher/preview/${studentId}`)} />
}

function TeacherStudentPreview() {
  const navigate = useNavigate()
  const { studentId = '' } = useParams()
  const session = readAccessSession()
  const [dashboard, setDashboard] = useState<StudentDashboardData | null>(null)
  const [error, setError] = useState('')

  useEffect(() => {
    if (session?.role !== 'teacher' || !studentId) return
    let active = true
    setDashboard(null)
    setError('')
    void teacherApi<{ dashboard: StudentDashboardData }>('student_preview_dashboard', { studentId })
      .then((result) => { if (active) setDashboard(result.dashboard) })
      .catch((reason) => { if (active) setError(reason instanceof Error ? reason.message : '只读预览暂时无法打开。') })
    return () => { active = false }
  }, [session?.role, studentId])

  if (session?.role !== 'teacher') return <Navigate to="/" replace />
  if (error) return <AppShell identity={session.displayName}><div className="inline-alert" role="alert">{error}</div><button className="secondary-button" onClick={() => navigate('/teacher')}>返回教师后台</button></AppShell>
  if (!dashboard) return <AppShell identity={session.displayName}><div className="center-loading">正在准备只读模拟界面…</div></AppShell>
  return <AppShell identity={`${session.displayName} · 只读模拟`}><StudentApp key={dashboard.profile.id} session={session} initialDashboard={dashboard} onDashboard={setDashboard} previewMode onExitPreview={() => navigate('/teacher')} /></AppShell>
}

function AccessExperience() {
  const navigate = useNavigate()
  const [session, setSession] = useState<SessionIdentity | null>(() => readAccessSession())
  const [dashboard, setDashboard] = useState<Dashboard | null>(null)
  const [loading, setLoading] = useState(Boolean(session))
  const [error, setError] = useState('')

  useEffect(() => {
    if (!session) return
    if (session.role === 'teacher') { navigate('/teacher', { replace: true }); setLoading(false); return }
    const load = session.role === 'student' ? loadStudentDashboard(session) : session.role === 'guardian' ? loadGuardianDashboard(session) : null
    if (!load) { clearAccessSession(); setSession(null); setLoading(false); return }
    load.then((result) => setDashboard(result.dashboard)).catch((reason) => { clearAccessSession(); setSession(null); setError(reason instanceof Error ? reason.message : '会话已失效。') }).finally(() => setLoading(false))
  }, [session, navigate])

  useEffect(() => {
    if (session?.role !== 'guardian') return
    let active = true
    let refreshing = false
    const refreshGuardian = async () => {
      if (refreshing) return
      refreshing = true
      try {
        const result = await loadGuardianDashboard(session)
        if (active) setDashboard(result.dashboard)
      } catch {
        // Keep the last successful view during a transient background refresh failure.
      } finally {
        refreshing = false
      }
    }
    const onFocus = () => { void refreshGuardian() }
    const onVisibility = () => { if (document.visibilityState === 'visible') void refreshGuardian() }
    const timer = window.setInterval(() => { void refreshGuardian() }, 10000)
    window.addEventListener('focus', onFocus)
    document.addEventListener('visibilitychange', onVisibility)
    return () => {
      active = false
      window.clearInterval(timer)
      window.removeEventListener('focus', onFocus)
      document.removeEventListener('visibilitychange', onVisibility)
    }
  }, [session])

  function success(nextSession: SessionIdentity, nextDashboard?: Dashboard) {
    writeAccessSession(nextSession)
    setSession(nextSession)
    if (nextSession.role === 'teacher') { setDashboard(null); navigate('/teacher'); return }
    if (nextDashboard) setDashboard(nextDashboard)
  }

  function logout() { clearAccessSession(); setSession(null); setDashboard(null); navigate('/') }

  if (loading) return <AppShell><div className="center-loading">正在读取属于你的学习档案…</div></AppShell>
  if (session?.role === 'teacher') return <Navigate to="/teacher" replace />
  if (!session || !dashboard) return <AppShell>{error && <div className="inline-alert">{error}</div>}<AccessGate onSuccess={success} /></AppShell>
  if (session.role === 'student') return <AppShell identity={session.displayName} onLogout={logout}><StudentApp session={session} initialDashboard={dashboard as StudentDashboardData} onDashboard={setDashboard} /></AppShell>
  if (session.role === 'guardian') return <AppShell identity={session.displayName} onLogout={logout}><GuardianApp dashboard={dashboard as GuardianDashboardData} /></AppShell>
  return <AppShell><AccessGate onSuccess={success} /></AppShell>
}
