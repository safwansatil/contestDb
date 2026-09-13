import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'

export type ThemeId = 'light' | 'dark' | 'cupcake' | 'retro' | 'cyberpunk' | 'valentine' | 'aqua' | 'dracula' | 'night'

export const THEMES: { id: ThemeId; label: string }[] = [
  { id: 'light', label: 'Light' },
  { id: 'dark', label: 'Dark' },
  { id: 'cupcake', label: 'Cupcake' },
  { id: 'retro', label: 'Retro' },
  { id: 'cyberpunk', label: 'Cyberpunk' },
  { id: 'valentine', label: 'Valentine' },
  { id: 'aqua', label: 'Aqua' },
  { id: 'dracula', label: 'Dracula' },
  { id: 'night', label: 'Night' },
]

const KEY = 'contestdb_theme'
function initial(): ThemeId {
  const saved = (typeof localStorage !== 'undefined' && localStorage.getItem(KEY)) as ThemeId | null
  return saved && THEMES.some((t) => t.id === saved) ? saved : 'cupcake'
}

interface Ctx { theme: ThemeId; setTheme: (t: ThemeId) => void }
const ThemeCtx = createContext<Ctx>({ theme: 'cupcake', setTheme: () => {} })

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setTheme] = useState<ThemeId>(initial)
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme)
    try { localStorage.setItem(KEY, theme) } catch { /* ignore */ }
  }, [theme])
  return <ThemeCtx.Provider value={{ theme, setTheme }}>{children}</ThemeCtx.Provider>
}

export const useTheme = () => useContext(ThemeCtx)
