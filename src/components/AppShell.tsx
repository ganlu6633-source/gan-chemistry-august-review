import type { ReactNode } from 'react'
import { Atom, LogOut } from 'lucide-react'

export function AppShell({ children, identity, onLogout }: { children: ReactNode; identity?: string; onLogout?: () => void }) {
  return (
    <div className="app-shell">
      <header className="app-header">
        <a className="brand" href={import.meta.env.BASE_URL} aria-label="甘老师化学首页">
          <span className="brand-mark"><Atom size={20} /></span>
          <span><b>甘老师化学</b><small>理解 · 迁移 · 找回来</small></span>
        </a>
        {identity && <div className="identity"><span>{identity}</span>{onLogout && <button className="icon-button" onClick={onLogout} aria-label="退出登录"><LogOut size={18} /></button>}</div>}
      </header>
      <main className="main-content">{children}</main>
      <footer className="app-footer">每一次不会，都能被安排到一个重新搭上来的台阶。</footer>
    </div>
  )
}
