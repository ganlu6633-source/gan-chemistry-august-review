import { FormEvent, useState } from 'react'
import { ArrowRight, KeyRound, ShieldCheck, Sparkles, UserRound } from 'lucide-react'
import type { GuardianDashboardData, SessionIdentity, StudentDashboardData } from '../domain/types'
import { loginWithAccessCode } from '../lib/api'

export function AccessGate({ onSuccess }: { onSuccess: (session: SessionIdentity, dashboard?: StudentDashboardData | GuardianDashboardData) => void }) {
  const [name, setName] = useState('')
  const [code, setCode] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  async function submit(event: FormEvent) {
    event.preventDefault()
    const cleanName = name.trim()
    if (!cleanName || cleanName.length > 50) {
      setError('请输入姓名。')
      return
    }
    if (!/^\d{8}$/.test(code)) {
      setError('请输入8位数字登录码。')
      return
    }
    setLoading(true)
    setError('')
    try {
      const result = await loginWithAccessCode(cleanName, code)
      onSuccess(result.session, result.dashboard)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '验证失败，请稍后重试。')
    } finally {
      setLoading(false)
      setCode('')
    }
  }

  return (
    <section className="login-layout">
      <div className="hero-copy">
        <div className="eyebrow"><Sparkles size={16} /> 你的化学世界，每天亮一点</div>
        <h1>把逻辑真正接起来，<br /><span>让理解自然迁移。</span></h1>
        <p>课堂刚学的、快要遗忘的、下一节要用的，系统会在合适的时候用新题带你重新找回来。</p>
        <div className="hero-proof">
          <div><b>≤ 8题</b><span>默认每日必做预算</span></div>
          <div><b>新母题</b><span>举一反三，不背原答案</span></div>
          <div><b>能力星图</b><span>只和昨天的自己比较</span></div>
        </div>
      </div>
      <div className="login-card">
        <div className="login-icon"><KeyRound size={28} /></div>
        <h2>欢迎回来</h2>
        <p>输入姓名和登录码，即可进入自己的化学学习空间。</p>
        <form onSubmit={submit}>
          <label htmlFor="login-name">输入姓名</label>
          <div className="login-input-wrap"><UserRound size={18} /><input id="login-name" className="name-input" value={name} onChange={(event) => setName(event.target.value.slice(0, 50))} autoComplete="name" placeholder="请输入姓名" /></div>
          <label htmlFor="access-code">登录码</label>
          <input id="access-code" className="code-input" value={code} onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 8))} inputMode="numeric" autoComplete="one-time-code" placeholder="8位数字" aria-describedby={error ? 'access-error' : undefined} />
          {error && <div id="access-error" className="form-error" role="alert">{error}</div>}
          <button className="primary-button" disabled={loading}>{loading ? '正在安全进入…' : '进入我的化学世界'} <ArrowRight size={18} /></button>
        </form>
        <div className="security-note"><ShieldCheck size={16} />姓名和登录码仅用于安全核验。</div>
      </div>
    </section>
  )
}
