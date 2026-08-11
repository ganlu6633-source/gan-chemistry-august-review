import { FormEvent, useState } from 'react'
import { ArrowRight, KeyRound, ShieldCheck, Sparkles } from 'lucide-react'
import type { GuardianDashboardData, SessionIdentity, StudentDashboardData } from '../domain/types'
import { loginWithAccessCode } from '../lib/api'

export function AccessGate({ onSuccess }: { onSuccess: (session: SessionIdentity, dashboard: StudentDashboardData | GuardianDashboardData) => void }) {
  const [code, setCode] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!/^\d{8}$/.test(code)) {
      setError('请输入8位数字访问码。')
      return
    }
    setLoading(true)
    setError('')
    try {
      const result = await loginWithAccessCode(code)
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
        <h1>不是多做题，<br /><span>是把逻辑真正接起来。</span></h1>
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
        <p>输入访问码，系统会自动进入属于你的页面。</p>
        <form onSubmit={submit}>
          <label htmlFor="access-code">访问码</label>
          <input
            id="access-code"
            value={code}
            onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 8))}
            inputMode="numeric"
            autoComplete="one-time-code"
            placeholder="8位数字"
            aria-describedby={error ? 'access-error' : undefined}
          />
          {error && <div id="access-error" className="form-error" role="alert">{error}</div>}
          <button className="primary-button" disabled={loading}>{loading ? '正在安全进入…' : '进入我的化学世界'} <ArrowRight size={18} /></button>
        </form>
        <div className="security-note"><ShieldCheck size={16} />访问码不会出现在网址中，也不会以明文保存。</div>
      </div>
    </section>
  )
}
