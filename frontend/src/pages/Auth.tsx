import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { useAuth } from '../lib/auth'
import { useToast } from '../lib/toast'
import { apiError } from '../lib/api'
import { Spinner } from '../components/ui'

export function Auth({ mode }: { mode: 'login' | 'signup' }) {
  const { login, signup } = useAuth()
  const toast = useToast()
  const nav = useNavigate()
  const [username, setU] = useState('')
  const [password, setP] = useState('')
  const [busy, setBusy] = useState(false)
  const isLogin = mode === 'login'

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (username.trim().length < 3) return toast('Username must be at least 3 characters', 'err')
    if (!/^[a-zA-Z0-9_-]+$/.test(username)) return toast('Only letters, numbers, _ and - allowed', 'err')
    if (password.length < 6) return toast('Password must be at least 6 characters', 'err')
    setBusy(true)
    try {
      if (isLogin) await login(username.trim(), password)
      else await signup(username.trim(), password)
      toast(isLogin ? `Welcome back, ${username}` : `Account created — welcome, ${username}`)
      nav('/app')
    } catch (err) {
      toast(apiError(err), 'err')
    } finally { setBusy(false) }
  }

  return (
    <div style={{ minHeight: 'calc(100vh - 62px)', display: 'grid', placeItems: 'center', padding: 24 }}>
      <motion.form onSubmit={submit} className="glass glass-strong pad-lg" style={{ width: '100%', maxWidth: 410, padding: 34 }}
        initial={{ opacity: 0, y: 18, scale: 0.98 }} animate={{ opacity: 1, y: 0, scale: 1 }} transition={{ duration: 0.4 }}>
        <div className="mark" style={{ width: 48, height: 48, borderRadius: 14, fontSize: 22, marginBottom: 18,
          display: 'grid', placeItems: 'center', fontFamily: 'var(--mono)', fontWeight: 900,
          background: 'linear-gradient(145deg,var(--gold-2),var(--gold-deep))', color: '#231703' }}>C</div>
        <h1 style={{ fontSize: 23 }}>{isLogin ? 'Welcome back' : 'Create your account'}</h1>
        <p className="dim" style={{ fontSize: 13.5, margin: '7px 0 24px' }}>
          {isLogin ? 'Sign in to enroll, submit and climb the board.' : 'Pick a username to get started.'}
        </p>
        <div className="field">
          <label>Username</label>
          <input value={username} onChange={(e) => setU(e.target.value)} placeholder="3–50 chars · a-z 0-9 _ -" autoFocus autoComplete="username" />
        </div>
        <div className="field">
          <label>Password</label>
          <input type="password" value={password} onChange={(e) => setP(e.target.value)} placeholder="min 6 characters" autoComplete={isLogin ? 'current-password' : 'new-password'} />
        </div>
        <button className="btn primary block lg" disabled={busy} style={{ marginTop: 6 }}>
          {busy ? <Spinner /> : isLogin ? 'Sign in' : 'Create account'}
        </button>
        <div className="center dim" style={{ marginTop: 18, fontSize: 13 }}>
          {isLogin ? "No account? " : 'Have an account? '}
          <Link to={isLogin ? '/signup' : '/login'} style={{ color: 'var(--gold)', fontWeight: 650 }}>
            {isLogin ? 'Sign up' : 'Sign in'}
          </Link>
        </div>
        <div className="notice blue center" style={{ marginTop: 20, justifyContent: 'center' }}>
          Try the seed account <span className="k">sayma</span> / <span className="k">password123</span>
        </div>
      </motion.form>
    </div>
  )
}
