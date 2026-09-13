import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'

export const THEMES = [
  ['magazine-red', 'Magazine red'], ['corporate-blue', 'Corporate blue'], ['yellow', 'Newsprint yellow'],
  ['lime', 'Acid lime'], ['purple', 'Royal purple'], ['night', 'Night'], ['ice', 'Ice'],
  ['tea', 'Tea'], ['coffee', 'Coffee'], ['corporate', 'Corporate'],
] as const
export type ThemeId = typeof THEMES[number][0]
const KEY = 'contestdb_theme'
const valid = (value: string | null): value is ThemeId => THEMES.some(([id]) => id === value)
interface Ctx { theme: ThemeId; setTheme: (theme: ThemeId) => void }
const ThemeCtx = createContext<Ctx>({ theme: 'magazine-red', setTheme: () => {} })

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setTheme] = useState<ThemeId>(() => {
    const saved = typeof localStorage === 'undefined' ? null : localStorage.getItem(KEY)
    return valid(saved) ? saved : 'magazine-red'
  })
  useEffect(() => { document.documentElement.dataset.theme = theme; localStorage.setItem(KEY, theme) }, [theme])
  return <ThemeCtx.Provider value={{ theme, setTheme }}>{children}</ThemeCtx.Provider>
}
export const useTheme = () => useContext(ThemeCtx)
