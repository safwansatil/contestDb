import { Link, NavLink, useNavigate } from 'react-router-dom'
import { useAuth } from '../lib/auth'
import { useTheme, THEMES, type ThemeId } from '../lib/theme'

export function ThemeSwitcher() {
  const { theme, setTheme } = useTheme()
  return <label className="theme-select"><span>Theme</span><select aria-label="Choose theme" value={theme} onChange={(e) => setTheme(e.target.value as ThemeId)}>{THEMES.map(([id, label]) => <option key={id} value={id}>{label}</option>)}</select></label>
}

export function Nav() {
  const { user, logout } = useAuth(); const nav = useNavigate()
  return <header className="site-nav">
    <Link to={user?.is_developer ? '/dev' : user ? '/app' : '/'} className="wordmark"><b>Contest</b><i>DB</i><small>EST. 2026</small></Link>
    {user && <nav className="nav-links">{user.is_developer ? <NavLink to="/dev">Control room</NavLink> : <><NavLink to="/app" end>Explore</NavLink><NavLink to={`/users/${user.id}`}>Profile</NavLink></>}</nav>}
    <div className="nav-actions"><ThemeSwitcher />{user ? <><button className="user-chip" onClick={() => nav(`/users/${user.id}`)}>{user.username.slice(0, 2).toUpperCase()} <span>{user.username}</span></button><button className="nav-signout" onClick={() => { logout(); nav('/') }}>Sign out</button></> : <><Link to="/login">Sign in</Link><Link className="nav-join" to="/signup">Join</Link></>}</div>
  </header>
}
