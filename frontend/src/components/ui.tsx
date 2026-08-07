import { type ReactNode } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { useLottie } from 'lottie-react'
import loaderAnim from '../assets/loader.json'
import { IconClose } from './icons'

/* ---------- Aurora background (glassmorphism ground) ---------- */
export function Aurora() {
  return (
    <div className="aurora" aria-hidden>
      <div className="blob b1" /><div className="blob b2" /><div className="blob b3" />
      <div className="grain" />
    </div>
  )
}

/* ---------- Lottie loader (LottieFiles-style animation) ---------- */
export function Loader({ size = 64, label }: { size?: number; label?: string }) {
  const { View } = useLottie({ animationData: loaderAnim, loop: true }, { width: size, height: size })
  return (
    <div className="stack" style={{ alignItems: 'center', gap: 12, padding: '48px 0' }}>
      {View}
      {label && <span className="faint" style={{ fontSize: 13 }}>{label}</span>}
    </div>
  )
}

export function Spinner() { return <span className="spinner" /> }

/* ---------- Pills ---------- */
export function Pill({ children, className = 'tag-neutral', dot }: { children: ReactNode; className?: string; dot?: string }) {
  return <span className={`pill ${className}`}>{dot && <span className="d" style={{ background: dot }} />}{children}</span>
}

export function RankBadge({ rank }: { rank: number }) {
  if (rank <= 3) return <span className={`rk-badge rk${rank}`}>{rank}</span>
  return <span className="rank mono" style={{ width: 28, textAlign: 'center', display: 'inline-block' }}>{rank}</span>
}

export function Avatar({ name, size = 34 }: { name: string; size?: number }) {
  return <span className="avatar" style={{ width: size, height: size, fontSize: size * 0.38 }}>{name.slice(0, 2).toUpperCase()}</span>
}

export function Toggle({ on, onClick }: { on: boolean; onClick?: () => void }) {
  return <span className={`switch ${on ? 'on' : ''}`} onClick={onClick} role="switch" aria-checked={on}><i /></span>
}

export function Empty({ icon = '◎', children }: { icon?: string; children: ReactNode }) {
  return <div className="empty"><div className="ic">{icon}</div>{children}</div>
}

/* ---------- Modal ---------- */
export function Modal({ title, subtitle, onClose, children, footer }: {
  title: string; subtitle?: string; onClose: () => void; children: ReactNode; footer?: ReactNode
}) {
  return (
    <AnimatePresence>
      <motion.div className="overlay" onClick={onClose}
        initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
        <motion.div className="glass glass-strong modal" onClick={(e) => e.stopPropagation()}
          initial={{ opacity: 0, scale: 0.95, y: 12 }} animate={{ opacity: 1, scale: 1, y: 0 }}
          exit={{ opacity: 0, scale: 0.96, y: 8 }} transition={{ type: 'spring', stiffness: 380, damping: 30 }}>
          <header>
            <div><h3>{title}</h3>{subtitle && <div className="faint" style={{ fontSize: 12 }}>{subtitle}</div>}</div>
            <button className="iconbtn" onClick={onClose} aria-label="Close"><IconClose size={16} /></button>
          </header>
          <div className="body">{children}</div>
          {footer && <footer>{footer}</footer>}
        </motion.div>
      </motion.div>
    </AnimatePresence>
  )
}

/* ---------- Animated page wrapper ---------- */
const EASE = [0.22, 1, 0.36, 1] as const

export function Page({ children }: { children: ReactNode }) {
  return (
    <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35, ease: EASE }}>
      {children}
    </motion.div>
  )
}

/* Stagger container + item for lists */
export const stagger = { animate: { transition: { staggerChildren: 0.06 } } }
export const fadeUp = {
  initial: { opacity: 0, y: 16 },
  animate: { opacity: 1, y: 0, transition: { duration: 0.4, ease: EASE } },
}
