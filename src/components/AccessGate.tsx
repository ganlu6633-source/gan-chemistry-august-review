import { FormEvent, useState } from 'react'
import { ArrowRight, KeyRound, ShieldCheck, Sparkles, UserRound } from 'lucide-react'
import type { GuardianDashboardData, SessionIdentity, StudentDashboardData } from '../domain/types'
import { loginWithAccessCode, recoverAccessCode } from '../lib/api'

export function AccessGate({ onSuccess }: { onSuccess: (session: SessionIdentity, dashboard?: StudentDashboardData | GuardianDashboardData) => void }) {
  const [name, setName] = useState('')
  const [code, setCode] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [recoveryName, setRecoveryName] = useState('')
  const [recoverySecret, setRecoverySecret] = useState('')
  const [newCode, setNewCode] = useState('')
  const [confirmCode, setConfirmCode] = useState('')
  const [recoveryError, setRecoveryError] = useState('')
  const [recoveryMessage, setRecoveryMessage] = useState('')
  const [recovering, setRecovering] = useState(false)

  async function submit(event: FormEvent) {
    event.preventDefault()
    const cleanName = name.trim()
    if (!cleanName || cleanName.length > 50) {
      setError('请输入姓名。')
      return
    }
    if (!/^\d{6,12}$/.test(code)) {
      setError('请输入6—12位数字登录码。')
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

  async function recover(event: FormEvent) {
    event.preventDefault()
    const cleanName = recoveryName.trim()
    const cleanSecret = recoverySecret.trim()
    if (!cleanName || cleanName.length > 50) return setRecoveryError('请输入姓名。')
    if (cleanSecret.length < 6 || cleanSecret.length > 40) return setRecoveryError('私密找回短语需为6—40个字符。')
    if (/^\d+$/.test(cleanSecret)) return setRecoveryError('私密找回短语请至少包含一个汉字或字母，不能只用数字。')
    if (!/^\d{6,12}$/.test(newCode)) return setRecoveryError('新登录码需为6—12位数字。')
    if (newCode !== confirmCode) return setRecoveryError('两次输入的新登录码不一致。')
    setRecovering(true)
    setRecoveryError('')
    setRecoveryMessage('')
    try {
      const result = await recoverAccessCode(cleanName, cleanSecret, newCode)
      setRecoveryMessage(result.message || '登录码已更新，请使用新登录码进入。')
      setName(cleanName)
      setRecoverySecret('')
      setNewCode('')
      setConfirmCode('')
    } catch (reason) {
      setRecoveryError(reason instanceof Error ? reason.message : '暂时无法找回，请稍后重试。')
    } finally {
      setRecovering(false)
    }
  }

  return (
    <section className="login-layout">
      <div className="hero-copy">
        <div className="eyebrow"><Sparkles size={16} /> 你的化学世界，每天亮一点</div>
        <h1>把逻辑真正接起来，<br /><span>让理解自然迁移。</span></h1>
        <p>课堂刚学的、快要遗忘的、下一节要用的，系统会在合适的时候用新题带你重新找回来。</p>
        <div className="hero-proof">
          <div><b>每日 1 个题组</b><span>只复习真正需要回看的细点</span></div>
          <div><b>最多 8 道原题</b><span>每道题与知识点一一对应</span></div>
          <div><b>次日个性化</b><span>错题换原题，答对再升级</span></div>
        </div>
      </div>
      <div className="login-card">
        <div className="login-icon"><KeyRound size={28} /></div>
        <h2>欢迎回来</h2>
        <p>输入姓名和登录码，系统会自动进入对应页面。</p>
        <form onSubmit={submit}>
          <label htmlFor="login-name">输入姓名</label>
          <div className="login-input-wrap"><UserRound size={18} /><input id="login-name" className="name-input" value={name} onChange={(event) => setName(event.target.value.slice(0, 50))} autoComplete="name" placeholder="请输入姓名" /></div>
          <label htmlFor="access-code">登录码</label>
          <input id="access-code" className="code-input" value={code} onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 12))} inputMode="numeric" autoComplete="current-password" placeholder="6—12位数字" aria-describedby={error ? 'access-error' : undefined} />
          {error && <div id="access-error" className="form-error" role="alert">{error}</div>}
          <button className="primary-button" disabled={loading}>{loading ? '正在安全进入…' : '进入我的化学世界'} <ArrowRight size={18} /></button>
        </form>
        <details className="recovery-panel">
          <summary>忘记登录码？</summary>
          <form onSubmit={recover}>
            <p>使用你提前设置的私密找回短语重设登录码。</p>
            <label htmlFor="recovery-name">找回姓名</label>
            <input id="recovery-name" className="plain-input" value={recoveryName} onChange={(event) => setRecoveryName(event.target.value.slice(0, 50))} autoComplete="name" placeholder="输入需要找回的姓名" />
            <label htmlFor="recovery-secret">私密找回短语</label>
            <input id="recovery-secret" className="plain-input" type="password" value={recoverySecret} onChange={(event) => setRecoverySecret(event.target.value.slice(0, 40))} autoComplete="off" placeholder="6—40个字符" />
            <label htmlFor="new-access-code">设置新的数字码</label>
            <input id="new-access-code" className="code-input" value={newCode} onChange={(event) => setNewCode(event.target.value.replace(/\D/g, '').slice(0, 12))} inputMode="numeric" autoComplete="new-password" placeholder="新数字码：6至12位" />
            <label htmlFor="confirm-access-code">再次输入数字码</label>
            <input id="confirm-access-code" className="code-input" value={confirmCode} onChange={(event) => setConfirmCode(event.target.value.replace(/\D/g, '').slice(0, 12))} inputMode="numeric" autoComplete="new-password" placeholder="请再次输入" />
            {recoveryError && <div className="form-error" role="alert">{recoveryError}</div>}
            {recoveryMessage && <div className="success-message" role="status">{recoveryMessage}</div>}
            <button className="secondary-button recovery-submit" disabled={recovering}>{recovering ? '正在安全核验…' : '重设登录码'}</button>
            <small>找回短语只保存在加密摘要中。请不要使用身份证号、生日、手机号或常用密码。</small>
          </form>
        </details>
        <div className="security-note"><ShieldCheck size={16} />姓名和登录码仅用于安全核验。</div>
      </div>
    </section>
  )
}
