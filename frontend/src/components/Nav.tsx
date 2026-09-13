import {
  Link,
  NavLink,
  useNavigate,
} from 'react-router-dom'

import { useAuth } from '../lib/auth'
import {
  useTheme,
  THEMES,
  type ThemeId,
} from '../lib/theme'

export function ThemeSwitcher() {
  const { theme, setTheme } = useTheme()

  return (
    <label className="theme-select">
      <span className="theme-select__label">
        Theme
      </span>

      <select
        aria-label="Choose color theme"
        value={theme}
        onChange={(event) =>
          setTheme(event.target.value as ThemeId)
        }
      >
        {THEMES.map(([id, label]) => (
          <option key={id} value={id}>
            {label}
          </option>
        ))}
      </select>
    </label>
  )
}

export function Nav() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()

  const destination = user?.is_developer
    ? '/dev'
    : user
      ? '/app'
      : '/'

  return (
    <header className="site-nav">
      <Link to={destination} className="wordmark">
        <b>Contest</b>
        <i>DB</i>
        <small>EST. 2026</small>
      </Link>

      {user && (
        <nav className="nav-links">
          {user.is_developer ? (
            <NavLink to="/dev">
              Control room
            </NavLink>
          ) : (
            <>
              <NavLink to="/app" end>
                Explore
              </NavLink>

              <NavLink to={`/users/${user.id}`}>
                Profile
              </NavLink>
            </>
          )}
        </nav>
      )}

      <div className="nav-actions">
        <ThemeSwitcher />

        {user ? (
          <>
            <button
              type="button"
              className="user-chip"
              onClick={() =>
                navigate(`/users/${user.id}`)
              }
            >
              {user.username
                .slice(0, 2)
                .toUpperCase()}

              <span>{user.username}</span>
            </button>

            <button
              type="button"
              className="nav-signout"
              onClick={() => {
                logout()
                navigate('/')
              }}
            >
              Sign out
            </button>
          </>
        ) : (
          <>
            <Link to="/login">
              Sign in
            </Link>

            <Link
              className="nav-join"
              to="/signup"
            >
              Join
            </Link>
          </>
        )}
      </div>
    </header>
  )
}
