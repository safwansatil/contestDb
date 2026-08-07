import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'

export type ThemeId = 'guild' | 'sketchbook' | 'geometry'

export const THEMES: { id: ThemeId; label: string; blurb: string }[] = [
  { id: 'guild', label: 'Artisanal Guild', blurb: 'Parchment & letterpress' },
  { id: 'sketchbook', label: 'Playful Sketchbook', blurb: 'Indie zine, hand-drawn' },
  { id: 'geometry', label: 'Curated Geometry', blurb: 'Premium dark, geometric' },
]

const KEY = 'contestdb_theme'
function initial(): ThemeId {
  const saved = (typeof localStorage !== 'undefined' && localStorage.getItem(KEY)) as ThemeId | null
  return saved && THEMES.some((t) => t.id === saved) ? saved : 'guild'
}

interface Ctx { theme: ThemeId; setTheme: (t: ThemeId) => void }
const ThemeCtx = createContext<Ctx>({ theme: 'guild', setTheme: () => {} })

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setTheme] = useState<ThemeId>(initial)
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme)
    try { localStorage.setItem(KEY, theme) } catch { /* ignore */ }
  }, [theme])
  return <ThemeCtx.Provider value={{ theme, setTheme }}>{children}</ThemeCtx.Provider>
}

export const useTheme = () => useContext(ThemeCtx)
