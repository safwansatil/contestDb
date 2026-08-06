import type { Contest } from './api'

export function fmtRel(iso: string, now = Date.now()): string {
  const t = new Date(iso).getTime()
  const d = t - now, a = Math.abs(d), M = 60e3, H = 3600e3, D = 86400e3
  let s: string
  if (a < M) return 'just now'
  else if (a < H) s = Math.round(a / M) + 'm'
  else if (a < D) s = Math.round(a / H) + 'h'
  else s = Math.round(a / D) + 'd'
  return d < 0 ? s + ' ago' : 'in ' + s
}

export function fmtDate(iso: string): string {
  return new Date(iso).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}

export function timelineStatus(c: Contest, now = Date.now()): 'UPCOMING' | 'ONGOING' | 'COMPLETED' {
  const s = new Date(c.start_time).getTime(), e = new Date(c.end_time).getTime()
  if (now < s) return 'UPCOMING'
  if (now > e) return 'COMPLETED'
  return 'ONGOING'
}

export function isFrozen(c: Contest, now = Date.now()): boolean {
  const f = new Date(c.freeze_time).getTime(), e = new Date(c.end_time).getTime()
  return now >= f && now < e
}

export function statusColor(s: string): string {
  return { ACTIVE: 'var(--ac)', PENDING_APPROVAL: 'var(--tle)', COMPLETED: 'var(--ink-faint)' }[s] || 'var(--ink-faint)'
}

export function verdictClass(v: string): string {
  if (['ACCEPTED', 'RUN_SUCCESS', 'AC', 'GRADED', 'GENERIC_SUCCESS'].includes(v)) return 'tag-ac'
  if (['WRONG_ANSWER', 'WA', 'COMPILE_ERROR', 'FAILED'].includes(v)) return 'tag-wa'
  if (['TIME_LIMIT_EXCEEDED', 'TLE', 'PARTIAL'].includes(v)) return 'tag-tle'
  if (['PENDING', 'JUDGING'].includes(v)) return 'tag-pending'
  return 'tag-neutral'
}

export function verdictColor(v: string): string {
  const c = verdictClass(v)
  return c === 'tag-ac' ? 'var(--ac)' : c === 'tag-wa' ? 'var(--wa)' : c === 'tag-tle' ? 'var(--tle)' : c === 'tag-pending' ? 'var(--pending)' : 'var(--ink-dim)'
}

export function initials(name: string): string {
  return name.slice(0, 2).toUpperCase()
}

export function isAdmin(role: string | null | undefined): boolean {
  return role === 'HOST' || role === 'MODERATOR'
}
