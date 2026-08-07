import { Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { AnimatePresence } from 'framer-motion'
import { Nav } from './components/Nav'
import { useAuth } from './lib/auth'
import { Landing } from './pages/Landing'
import { Auth } from './pages/Auth'
import { Dashboard } from './pages/Dashboard'
import { ContestDetail } from './pages/ContestDetail'
import { Profile } from './pages/Profile'
import { Loader } from './components/ui'
import type { ReactNode } from 'react'

function Protected({ children }: { children: ReactNode }) {
  const { user, loading } = useAuth()
  if (loading) return <Loader label="Loading your session…" />
  if (!user) return <Navigate to="/login" replace />
  return <>{children}</>
}

export function App() {
  const location = useLocation()
  const { user, loading } = useAuth()
  const onLanding = location.pathname === '/'

  return (
    <>
      {!onLanding && <Nav />}
      <AnimatePresence mode="wait">
        <Routes location={location} key={location.pathname.split('/')[1] || 'root'}>
          <Route path="/" element={loading ? <Loader /> : user ? <Navigate to="/app" replace /> : <Landing />} />
          <Route path="/login" element={<Auth mode="login" />} />
          <Route path="/signup" element={<Auth mode="signup" />} />
          <Route path="/app" element={<Protected><Dashboard /></Protected>} />
          <Route path="/contests/:id" element={<Protected><ContestDetail /></Protected>} />
          <Route path="/users/:id" element={<Protected><Profile /></Protected>} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </AnimatePresence>
    </>
  )
}
