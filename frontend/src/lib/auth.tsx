import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import { authApi, type User } from './api'

interface AuthCtx {
  user: User | null
  loading: boolean
  login: (u: string, p: string) => Promise<void>
  signup: (u: string, p: string) => Promise<void>
  logout: () => void
}

const Ctx = createContext<AuthCtx>(null as unknown as AuthCtx)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [loading, setLoading] = useState(true)

  // On boot, validate any stored token against /auth/me.
  useEffect(() => {
    const token = localStorage.getItem('contestdb_token')
    if (!token) { setLoading(false); return }
    authApi.me()
      .then(setUser)
      .catch(() => localStorage.removeItem('contestdb_token'))
      .finally(() => setLoading(false))
  }, [])

  function persist(data: { access_token: string; user: User }) {
    localStorage.setItem('contestdb_token', data.access_token)
    setUser(data.user)
  }

  const login = async (u: string, p: string) => persist(await authApi.login(u, p))
  const signup = async (u: string, p: string) => persist(await authApi.signup(u, p))
  const logout = () => { localStorage.removeItem('contestdb_token'); setUser(null) }

  return <Ctx.Provider value={{ user, loading, login, signup, logout }}>{children}</Ctx.Provider>
}

export const useAuth = () => useContext(Ctx)
