import { createContext, useCallback, useContext, useState, type ReactNode } from 'react'
import { AnimatePresence, motion } from 'framer-motion'

type ToastType = 'ok' | 'err' | 'info'
interface Toast { id: number; msg: string; type: ToastType }
const Ctx = createContext<(msg: string, type?: ToastType) => void>(() => {})

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])

  const push = useCallback((msg: string, type: ToastType = 'ok') => {
    const id = Date.now() + Math.random()
    setToasts((t) => [...t, { id, msg, type }])
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 3600)
  }, [])

  const icon = { ok: '✓', err: '⚠', info: 'ℹ' }
  return (
    <Ctx.Provider value={push}>
      {children}
      <div className="toasts">
        <AnimatePresence>
          {toasts.map((t) => (
            <motion.div key={t.id} className={`glass glass-strong toast ${t.type}`}
              initial={{ opacity: 0, x: 30, scale: 0.9 }} animate={{ opacity: 1, x: 0, scale: 1 }}
              exit={{ opacity: 0, x: 30, scale: 0.9 }} transition={{ type: 'spring', stiffness: 400, damping: 30 }}>
              <span>{icon[t.type]}</span><span>{t.msg}</span>
            </motion.div>
          ))}
        </AnimatePresence>
      </div>
    </Ctx.Provider>
  )
}

export const useToast = () => useContext(Ctx)
