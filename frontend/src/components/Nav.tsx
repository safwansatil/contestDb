import { Link, NavLink, useNavigate } from 'react-router-dom'
import { useAuth } from '../lib/auth'
import { useTheme, THEMES } from '../lib/theme'
import type { ThemeId } from '../lib/theme'

export function ThemeSwitcher() {
  const { theme, setTheme } = useTheme()
  return (
    <div className="dropdown dropdown-end">
      <div tabIndex={0} role="button" className="btn m-1 btn-sm btn-ghost">
        Theme
        <svg width="12px" height="12px" className="inline-block h-2 w-2 fill-current opacity-60" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2048 2048"><path d="M1799 349l242 241-1017 1017L7 590l242-241 775 775 775-775z"></path></svg>
      </div>
      <ul tabIndex={0} className="dropdown-content bg-base-300 rounded-box z-[1] w-52 p-2 shadow-2xl">
        {THEMES.map((t) => (
          <li key={t.id}>
            <input 
              type="radio"
              name="theme-dropdown"
              className="theme-controller btn btn-sm btn-block btn-ghost justify-start"
              aria-label={t.label}
              value={t.id}
              checked={theme === t.id}
              onChange={() => setTheme(t.id as ThemeId)}
            />
          </li>
        ))}
      </ul>
    </div>
  )
}

export function Nav() {
  const { user, logout } = useAuth()
  const nav = useNavigate()

  return (
    <div className="navbar bg-base-100 shadow-sm px-4 lg:px-8 border-b border-base-200">
      <div className="flex-1">
        <Link to={user ? '/app' : '/'} className="btn btn-ghost text-xl font-bold gap-2">
          ContestDB
        </Link>
        {user && !user.is_developer && (
          <div className="hidden lg:flex gap-2 ml-6">
            <NavLink to="/app" end className={({ isActive }) => `btn btn-sm ${isActive ? 'btn-primary' : 'btn-ghost'}`}>
              Explore
            </NavLink>
            <NavLink to={`/users/${user.id}`} className={({ isActive }) => `btn btn-sm ${isActive ? 'btn-primary' : 'btn-ghost'}`}>
              Profile
            </NavLink>
          </div>
        )}
        {user && user.is_developer && (
          <div className="hidden lg:flex gap-2 ml-6">
            <NavLink to="/dev" className={({ isActive }) => `btn btn-sm ${isActive ? 'btn-primary' : 'btn-ghost'}`}>
              Dev Portal
            </NavLink>
          </div>
        )}
      </div>

      <div className="flex-none gap-4">
        <ThemeSwitcher />
        {user ? (
          <div className="dropdown dropdown-end">
            <div tabIndex={0} role="button" className="btn btn-ghost btn-circle avatar">
              <div className="w-10 rounded-full bg-neutral text-neutral-content grid place-items-center">
                <span className="font-bold text-lg">{user.username[0].toUpperCase()}</span>
              </div>
            </div>
            <ul tabIndex={0} className="mt-3 z-[1] p-2 shadow menu menu-sm dropdown-content bg-base-200 rounded-box w-52">
              <li className="menu-title px-4 py-2 opacity-60">Signed in as <br/><strong className="opacity-100">{user.username}</strong></li>
              <li><a onClick={() => nav(`/users/${user.id}`)}>Profile</a></li>
              <li><a onClick={() => { logout(); nav('/') }} className="text-error">Sign out</a></li>
            </ul>
          </div>
        ) : (
          <div className="gap-2 hidden md:flex">
            <Link to="/login" className="btn btn-ghost btn-sm">Sign in</Link>
            <Link to="/signup" className="btn btn-primary btn-sm">Get started</Link>
          </div>
        )}
      </div>
    </div>
  )
}
