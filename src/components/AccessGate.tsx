import { FormEvent, useState } from 'react'
import { ArrowRight, KeyRound, ShieldCheck, Sparkles, UserRound } from 'lucide-react'
import type { GuardianDashboardData, SessionIdentity, StudentDashboardData } from '../domain/types'
import { loginWithAccessCode, loginWithPhone, recoverAccessCode, submitRegistration } from '../lib/api'
import './AccessGate.css'

export function AccessGate({ onSuccess }: { onSuccess: (session: SessionIdentity, dashboard?: StudentDashboardData | GuardianDashboardData) => void }) {
  const [name, setName] = useState('')
  const [code, setCode] = useState('')
  const [showCode, setShowCode] = useState(false)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [recoveryName, setRecoveryName] = useState('')
  const [recoverySecret, setRecoverySecret] = useState('')
  const [newCode, setNewCode] = useState('')
  const [confirmCode, setConfirmCode] = useState('')
  const [recoveryError, setRecoveryError] = useState('')
  const [recoveryMessage, setRecoveryMessage] = useState('')
  const [recovering, setRecovering] = useState(false)
  const [mode, setMode] = useState<'code' | 'phone' | 'register'>('code')
  const [role, setRole] = useState<'student' | 'guardian'>('student')
  const [phone, setPhone] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [gradeBand, setGradeBand] = useState('高一')
  const [childName, setChildName] = useState('')
  const [childPhone, setChildPhone] = useState('')
  const [inviteCode, setInviteCode] = useState('')
  const [registrationDone, setRegistrationDone] = useState(false)

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
      setCode('')
      onSuccess(result.session, result.dashboard)
    } catch (reason) {
      setError(reason instanceof TypeError ? '暂时无法连接复习服务，请检查网络后重试，已填写的信息保留。' : reason instanceof Error ? reason.message : '验证失败，请稍后重试。')
    } finally {
      setLoading(false)
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

  async function phoneSubmit(event: FormEvent) {
    event.preventDefault()
    if (!/^1[3-9]\d{9}$/.test(phone)) return setError('请输入11位中国大陆手机号。')
    if (password.length < 6 || password.length > 12) return setError('密码需为6—12位。')
    setLoading(true); setError('')
    try {
      const result = await loginWithPhone(role, phone, password)
      setPassword('')
      onSuccess(result.session, result.dashboard)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '暂时无法登录，请稍后重试。')
    } finally { setLoading(false) }
  }

  async function register(event: FormEvent) {
    event.preventDefault()
    if (!/^[A-Z0-9]{10}$/.test(inviteCode.trim())) return setError('请先添加甘老师微信，向老师领取10位邀请码。')
    if (!name.trim() || name.trim().length > 30) return setError('请填写不超过30字的姓名。')
    if (!/^1[3-9]\d{9}$/.test(phone)) return setError('请输入11位中国大陆手机号。')
    if (password.length < 6 || password.length > 12 || password.trim() !== password) return setError('密码需为6—12位，首尾不要留空格。')
    if (password !== confirmPassword) return setError('两次输入的密码不一致。')
    if (role === 'guardian' && (!childName.trim() || !/^1[3-9]\d{9}$/.test(childPhone))) return setError('请填写孩子姓名和11位手机号。')
    setLoading(true); setError('')
    try {
      await submitRegistration({ role, displayName: name.trim(), phone, password, inviteCode: inviteCode.trim(),
        ...(role === 'student' ? { gradeBand } : { childName: childName.trim(), childPhone }) })
      setRegistrationDone(true); setPassword(''); setConfirmPassword(''); setInviteCode('')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '申请暂时未能提交，请稍后重试。')
    } finally { setLoading(false) }
  }

  return (
    <section className="login-layout">
      <div className="hero-copy">
        <div className="eyebrow"><Sparkles size={16} /> 你的化学世界，每天亮一点</div>
        <h1>把逻辑真正接起来，<br /><span>让理解自然迁移。</span></h1>
        <p>课堂刚学的、快要遗忘的、下一节要用的，系统会在合适的时候用新题带你重新找回来。</p>
        </div>
        <div className="hero-proof">
          <div><b>每日 1 个题组</b><span>只复习真正需要回看的细点</span></div>
          <div><b>按年级安排题量</b><span>登录后查看今日题数与预计时间</span></div>
          <div><b>次日个性化</b><span>错题换原题，答对再升级</span></div>
        </div>
      <div className="login-card">
        <div className="login-icon"><KeyRound size={28} /></div>
        <div className="access-tabs" role="tablist" aria-label="登录或注册">
          <button type="button" role="tab" aria-selected={mode === 'code'} className={mode === 'code' ? 'active' : ''} onClick={() => { setMode('code'); setError('') }}>原登录码</button>
          <button type="button" role="tab" aria-selected={mode === 'phone'} className={mode === 'phone' ? 'active' : ''} onClick={() => { setMode('phone'); setError('') }}>手机号登录</button>
          <button type="button" role="tab" aria-selected={mode === 'register'} className={mode === 'register' ? 'active' : ''} onClick={() => { setMode('register'); setError('') }}>加微信后注册</button>
        </div>
        <h2>{mode === 'register' ? '加入甘老师化学' : '欢迎回来'}</h2>
        <p>{mode === 'code' ? '输入姓名和登录码，系统会自动进入对应页面。' : mode === 'phone' ? '审核通过后，用注册时的手机号和密码进入。' : '先添加甘老师微信，拿到老师发的一次性邀请码，才能填写手机号注册。'}</p>
        {mode === 'code' && <>
        <form onSubmit={submit}>
          <label htmlFor="login-name">输入姓名</label>
          <div className="login-input-wrap"><UserRound size={18} /><input id="login-name" className="name-input" value={name} onChange={(event) => setName(event.target.value.slice(0, 50))} autoComplete="name" placeholder="请输入姓名" /></div>
          <label htmlFor="access-code">登录码</label>
          <div className="secret-input-wrap"><input id="access-code" type={showCode ? 'text' : 'password'} className="code-input" value={code} onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 12))} inputMode="numeric" autoComplete="current-password" placeholder="6—12位数字" aria-describedby={error ? 'access-error login-help' : 'login-help'} /><button type="button" className="secret-toggle" aria-label={showCode ? '隐藏登录码' : '显示登录码'} aria-pressed={showCode} onClick={() => setShowCode(!showCode)}>{showCode ? '隐藏' : '显示'}</button></div>
          {error && <div id="access-error" className="form-error" role="alert">{error}</div>}
          <button className="primary-button" disabled={loading}>{loading ? '正在安全进入…' : '进入我的化学世界'} <ArrowRight size={18} /></button>
        </form>
        <p id="login-help" className="login-help">已有登录码的同学继续从这里进入。</p>
        <details className="recovery-panel">
          <summary>忘记登录码？</summary>
          <form onSubmit={recover}>
            <p>使用你提前设置的私密找回短语重设登录码。未设置或忘记短语时，请联系甘老师重置。</p>
            <label htmlFor="recovery-name">找回姓名</label>
            <input id="recovery-name" className="plain-input" value={recoveryName} onChange={(event) => setRecoveryName(event.target.value.slice(0, 50))} autoComplete="name" placeholder="输入需要找回的姓名" />
            <label htmlFor="recovery-secret">私密找回短语</label>
            <input id="recovery-secret" className="plain-input" type="password" value={recoverySecret} onChange={(event) => setRecoverySecret(event.target.value.slice(0, 40))} autoComplete="off" placeholder="6—40个字符" />
            <label htmlFor="new-access-code">设置新的数字码</label>
            <input id="new-access-code" type="password" className="code-input" value={newCode} onChange={(event) => setNewCode(event.target.value.replace(/\D/g, '').slice(0, 12))} inputMode="numeric" autoComplete="new-password" placeholder="新数字码：6至12位" />
            <label htmlFor="confirm-access-code">再次输入数字码</label>
            <input id="confirm-access-code" type="password" className="code-input" value={confirmCode} onChange={(event) => setConfirmCode(event.target.value.replace(/\D/g, '').slice(0, 12))} inputMode="numeric" autoComplete="new-password" placeholder="请再次输入" />
            {recoveryError && <div className="form-error" role="alert">{recoveryError}</div>}
            {recoveryMessage && <div className="success-message" role="status">{recoveryMessage}</div>}
            <button className="secondary-button recovery-submit" disabled={recovering}>{recovering ? '正在安全核验…' : '重设登录码'}</button>
            <small>找回短语只保存在加密摘要中。请不要使用身份证号、生日、手机号或常用密码。</small>
          </form>
        </details>
        <div className="security-note"><ShieldCheck size={16} />姓名和登录码仅用于安全核验。</div>
        </>}
        {mode === 'phone' && <form onSubmit={phoneSubmit} className="phone-access-form">
          <div className="access-role-picker" role="group" aria-label="选择身份"><button type="button" className={role === 'student' ? 'active' : ''} onClick={() => setRole('student')}>我是学生</button><button type="button" className={role === 'guardian' ? 'active' : ''} onClick={() => setRole('guardian')}>我是家长</button></div>
          <label htmlFor="phone-login">手机号</label><input id="phone-login" type="tel" inputMode="numeric" autoComplete="tel" value={phone} onChange={(event) => setPhone(event.target.value.replace(/\D/g, '').slice(0, 11))} placeholder="11位手机号" required />
          <label htmlFor="phone-password">密码</label><input id="phone-password" type="password" autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value.slice(0, 12))} placeholder="注册时设置的6—12位密码" required />
          {error && <div className="form-error" role="alert">{error}</div>}
          <button className="primary-button" disabled={loading}>{loading ? '正在登录…' : '进入学习'} <ArrowRight size={18} /></button>
          <p className="login-help">还没注册？先加甘老师微信，再点上方“加微信后注册”。已有数字登录码也可以照常使用。</p>
        </form>}
        {mode === 'register' && (registrationDone ? <div className="registration-done" role="status"><ShieldCheck /><h3>申请已提交</h3><p>甘老师会在后台核对身份、班级或孩子档案；开通后，你就可以用手机号和自定密码登录。</p><button className="secondary-button" onClick={() => { setMode('phone'); setRegistrationDone(false) }}>去手机号登录</button></div> : <form onSubmit={register} className="phone-access-form">
          <div className="access-role-picker" role="group" aria-label="注册身份"><button type="button" className={role === 'student' ? 'active' : ''} onClick={() => setRole('student')}>学生注册</button><button type="button" className={role === 'guardian' ? 'active' : ''} onClick={() => setRole('guardian')}>家长注册</button></div>
          <div className="wechat-register"><b>第一步：扫码添加甘老师微信</b><img src={`${import.meta.env.BASE_URL}wechat-add.jpg`} alt="甘老师微信二维码，扫码添加好友" /><small>在微信里告诉老师姓名和注册手机号。老师核对后会发给你一次性邀请码。</small></div>
          <label htmlFor="register-invite">第二步：输入老师发的邀请码</label><input id="register-invite" value={inviteCode} onChange={(event) => setInviteCode(event.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 10))} autoComplete="off" inputMode="text" maxLength={10} placeholder="10位一次性邀请码" required />
          <label htmlFor="register-name">{role === 'student' ? '学生姓名' : '家长姓名'}</label><input id="register-name" value={name} onChange={(event) => setName(event.target.value.slice(0, 30))} autoComplete="name" placeholder="填写真实姓名" required />
          <label htmlFor="register-phone">注册手机号</label><input id="register-phone" type="tel" inputMode="numeric" autoComplete="tel" value={phone} onChange={(event) => setPhone(event.target.value.replace(/\D/g, '').slice(0, 11))} placeholder="11位中国大陆手机号" required />
          {role === 'student' ? <><label htmlFor="register-grade">所在年级</label><select id="register-grade" value={gradeBand} onChange={(event) => setGradeBand(event.target.value)}>{['初三', '高一', '高二', '高三'].map((grade) => <option key={grade}>{grade}</option>)}</select></> : <><label htmlFor="child-name">孩子姓名</label><input id="child-name" value={childName} onChange={(event) => setChildName(event.target.value.slice(0, 40))} placeholder="填写孩子在网站上的姓名" required /><label htmlFor="child-phone">孩子手机号</label><input id="child-phone" type="tel" inputMode="numeric" value={childPhone} onChange={(event) => setChildPhone(event.target.value.replace(/\D/g, '').slice(0, 11))} placeholder="用于核对孩子档案" required /></>}
          <label htmlFor="register-password">设置密码（6—12位）</label><input id="register-password" type="password" autoComplete="new-password" minLength={6} maxLength={12} value={password} onChange={(event) => setPassword(event.target.value)} required />
          <label htmlFor="register-confirm">再输入一次密码</label><input id="register-confirm" type="password" autoComplete="new-password" minLength={6} maxLength={12} value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} required />
          {error && <div className="form-error" role="alert">{error}</div>}
          <button className="primary-button" disabled={loading || inviteCode.length !== 10}>{loading ? '正在提交…' : '提交注册申请'} <ArrowRight size={18} /></button>
          <small className="registration-note">不能直接凭手机号注册。邀请码只对老师确认的身份和手机号有效，使用一次即失效；提交后仍须审核开通。</small>
        </form>)}
      </div>
    </section>
  )
}
