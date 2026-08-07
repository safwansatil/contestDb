import { Link, NavLink, useNavigate } from 'react-router-dom'
import { useState } from 'react'
import { useAuth } from '../lib/auth'
import { useTheme, THEMES } from '../lib/theme'
import { Avatar } from './ui'
import {
  IconExplore, IconQuill, EmblemGuild, EmblemSketch, EmblemGeometry,
} from './icons'

const EMBLEM = { guild: EmblemGuild, sketchbook: EmblemSketch, geometry: EmblemGeometry }

export function ThemeSwitcher() {
  const { theme, setTheme } = useTheme()
  return (
    <div className="themeswitch" role="group" aria-label="Theme">
      {THEMES.map((t) => {
        const E = EMBLEM[t.id]
        return (
          <button key={t.id} className={theme === t.id ? 'on' : ''} onClick={() => setTheme(t.id)}
            title={`${t.label} — ${t.blurb}`} aria-pressed={theme === t.id} aria-label={t.label}>
            <E size={16} />
          </button>
        )
      })}
    </div>
  )
}

export function Nav() {
  const { user, logout } = useAuth()
  const nav = useNavigate()
  const [menu, setMenu] = useState(false)

  return (
    <nav className="nav">
      <Link to={user ? '/app' : '/'} className="brand">
        <span className="mark"><EmblemGuild size={19} /></span>ContestDB
      </Link>
      {user && (
        <div className="nav-links">
          <NavLink to="/app" end className={({ isActive }) => (isActive ? 'active' : '')}>
            <span className="row" style={{ gap: 7 }}><IconExplore size={16} />Explore</span>
          </NavLink>
          <NavLink to={`/users/${user.id}`} className={({ isActive }) => (isActive ? 'active' : '')}>
            <span className="row" style={{ gap: 7 }}><IconQuill size={16} />Profile</span>
          </NavLink>
        </div>
      )}
      <div className="grow" />
      <ThemeSwitcher />
      {user ? (
        <div style={{ position: 'relative' }}>
          <div onClick={() => setMenu((m) => !m)} className="row" style={{ cursor: 'pointer', gap: 9 }}>
            <Avatar name={user.username} />
            <span style={{ fontWeight: 650, fontSize: 13.5 }} className="dim">{user.username}</span>
          </div>
          {menu && (
            <div className="glass glass-strong" style={{ position: 'absolute', right: 0, top: 46, minWidth: 170, padding: 6, zIndex: 60 }}
              onMouseLeave={() => setMenu(false)}>
              <button className="btn ghost sm block" style={{ justifyContent: 'flex-start' }}
                onClick={() => { setMenu(false); nav(`/users/${user.id}`) }}>View profile</button>
              <button className="btn ghost sm block" style={{ justifyContent: 'flex-start', color: 'var(--wa)' }}
                onClick={() => { setMenu(false); logout(); nav('/') }}>Sign out</button>
            </div>
          )}
        </div>
      ) : (
        <div className="row" style={{ gap: 8 }}>
          <Link to="/login" className="btn ghost sm">Sign in</Link>
          <Link to="/signup" className="btn primary sm">Get started</Link>
        </div>
      )}
    </nav>
  )
}
