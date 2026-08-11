import { useEffect, useState } from 'react'
import { Navigate, Route, Routes, useNavigate } from 'react-router-dom'
import type { GuardianDashboardData, SessionIdentity, StudentDashboardData } from './domain/types'
import { AppShell } from './components/AppShell'
import { AccessGate } from './components/AccessGate'
import { StudentApp } from './components/StudentApp'
import { GuardianApp } from './components/GuardianApp'
import { TeacherGate } from './components/TeacherApp'
import { loadGuardianDashboard, loadStudentDashboard, supabase } from './lib/api'
import { clearAccessSession, readAccessSession, writeAccessSession } from './lib/session'

type Dashboard = StudentDashboardData | GuardianDashboardData

export default function App() {
  return <Routes><Route path="/" element={<AccessExperience />} /><Route path="/teacher" element={<TeacherGate />} /><Route path="*" element={<Navigate to="/" replace />} /></Routes>
}

function AccessExperience() {
  const navigate = useNavigate()
  const [session, setSession] = useState<SessionIdentity | null>(() => readAccessSession())
  const [dashboard, setDashboard] = useState<Dashboard | null>(null)
  const [loading, setLoading] = useState(Boolean(session))
  const [error, setError] = useState('')

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) navigate('/teacher', { replace: true })
    })
  }, [navigate])

  useEffect(() => {
    if (!session) return
    const load = session.role === 'student' ? loadStudentDashboard(session) : session.role === 'guardian' ? loadGuardianDashboard(session) : null
    if (!load) { clearAccessSession(); setSession(null); setLoading(false); return }
    load.then((result) => setDashboard(result.dashboard)).catch((reason) => { clearAccessSession(); setSession(null); setError(reason instanceof Error ? reason.message : '会话已失效。') }).finally(() => setLoading(false))
  }, [session])

  function success(nextSession: SessionIdentity, nextDashboard: Dashboard) {
    writeAccessSession(nextSession)
    setSession(nextSession)
    setDashboard(nextDashboard)
  }

  function logout() { clearAccessSession(); setSession(null); setDashboard(null); navigate('/') }

  if (loading) return <AppShell><div className="center-loading">正在读取属于你的学习档案…</div></AppShell>
  if (!session || !dashboard) return <AppShell>{error && <div className="inline-alert">{error}</div>}<AccessGate onSuccess={success} /></AppShell>
  if (session.role === 'student') return <AppShell identity={session.displayName} onLogout={logout}><StudentApp session={session} initialDashboard={dashboard as StudentDashboardData} onDashboard={setDashboard} /></AppShell>
  if (session.role === 'guardian') return <AppShell identity={`${session.displayName}家长`} onLogout={logout}><GuardianApp dashboard={dashboard as GuardianDashboardData} /></AppShell>
  return <AppShell><AccessGate onSuccess={success} /></AppShell>
}
