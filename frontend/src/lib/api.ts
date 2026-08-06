import axios from 'axios'

const BASE = import.meta.env.VITE_API_BASE || 'http://127.0.0.1:8000'

export const api = axios.create({ baseURL: BASE })

// Attach the stored JWT to every request when present.
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('contestdb_token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

// Normalize FastAPI error payloads ({detail: "..."}) into a readable message.
export function apiError(e: unknown): string {
  if (axios.isAxiosError(e)) {
    const d = e.response?.data as { detail?: unknown } | undefined
    if (d?.detail) return Array.isArray(d.detail) ? (d.detail[0] as { msg?: string })?.msg || 'Invalid input' : String(d.detail)
    if (e.code === 'ERR_NETWORK') return 'Cannot reach the API. Is the backend running on :8000?'
    return e.message
  }
  return 'Something went wrong'
}

/* ---------- Types (mirror the API response shapes) ---------- */
export type Role = 'HOST' | 'MODERATOR' | 'PARTICIPANT' | null
export type ContestStatus = 'PENDING_APPROVAL' | 'ACTIVE' | 'COMPLETED'

export interface Visibility {
  show_participant_count: boolean; show_leaderboard: boolean; show_member_list: boolean
  show_task_list: boolean; show_statistics: boolean; show_submission_count: boolean
}
export interface Contest {
  id: number; title: string; ranking_strategy: string
  start_time: string; freeze_time: string; end_time: string
  status: ContestStatus; judging_description: string
  requires_invitation_code?: boolean; invitation_code?: string | null
  user_role: Role; max_participants: number | null; allow_late_enrollment: boolean
  visibility: Visibility
}
export interface Task {
  id: number; title: string; description: string; max_score: number
  submission_schema: { required_keys: string[]; numeric_keys: string[] }
  submission_cooldown_seconds: number; task_order: number
}
export interface LeaderRow { user_id: number; username: string; total_score: number; rank: number }
export interface Announcement { id: number; title: string; body: string; author: string; posted_at: string }
export interface Member { user_id: number; username: string; role: Role }
export interface User { id: number; username: string }

/* ---------- Auth ---------- */
export const authApi = {
  signup: (username: string, password: string) => api.post('/auth/signup', { username, password }).then(r => r.data),
  login: (username: string, password: string) => api.post('/auth/login', { username, password }).then(r => r.data),
  me: () => api.get('/auth/me').then(r => r.data as User),
}

/* ---------- Contests ---------- */
export const contestApi = {
  list: (params: { q?: string; timeline?: string; strategy?: string; status?: string } = {}) =>
    api.get('/contests', { params }).then(r => r.data as Contest[]),
  get: (id: number) => api.get(`/contests/${id}`).then(r => r.data as Contest),
  profile: (id: number) => api.get(`/contests/${id}/profile`).then(r => r.data),
  create: (body: Record<string, unknown>) => api.post('/contests', body).then(r => r.data),
  update: (id: number, body: Record<string, unknown>) => api.put(`/contests/${id}`, body).then(r => r.data),
  remove: (id: number) => api.delete(`/contests/${id}`).then(r => r.data),
  tasks: (id: number) => api.get(`/contests/${id}/tasks`).then(r => r.data as Task[]),
  addTask: (id: number, body: Record<string, unknown>) => api.post(`/contests/${id}/tasks`, body).then(r => r.data),
  leaderboard: (id: number) => api.get(`/contests/${id}/leaderboard`).then(r => r.data as { view_mode: string; leaderboard: LeaderRow[] }),
  statistics: (id: number) => api.get(`/contests/${id}/statistics`).then(r => r.data),
  enrollmentInfo: (id: number) => api.get(`/contests/${id}/enrollment-info`).then(r => r.data),
  enroll: (id: number, invitation_code?: string) => api.post(`/contests/${id}/enroll`, { invitation_code: invitation_code || null }).then(r => r.data),
  members: (id: number) => api.get(`/contests/${id}/members`).then(r => r.data as Member[]),
  setRole: (id: number, target_user_id: number, new_role: string) => api.post(`/contests/${id}/members/role`, { target_user_id, new_role }).then(r => r.data),
  kick: (id: number, target_user_id: number, reason?: string) => api.delete(`/contests/${id}/members/${target_user_id}`, { data: { reason: reason || null } }).then(r => r.data),
  kickLog: (id: number) => api.get(`/contests/${id}/kick-log`).then(r => r.data),
  announcements: (id: number) => api.get(`/contests/${id}/announcements`).then(r => r.data as Announcement[]),
  postAnnouncement: (id: number, title: string, body: string) => api.post(`/contests/${id}/announcements`, { title, body }).then(r => r.data),
  deleteAnnouncement: (aid: number) => api.delete(`/announcements/${aid}`).then(r => r.data),
  visibility: (id: number) => api.get(`/contests/${id}/visibility`).then(r => r.data),
  setVisibility: (id: number, v: Visibility) => api.put(`/contests/${id}/visibility`, v).then(r => r.data),
}

/* ---------- Submissions ---------- */
export const submissionApi = {
  create: (contest_id: number, task_id: number, submission_data: Record<string, unknown>) =>
    api.post('/submissions', { contest_id, task_id, submission_data }).then(r => r.data),
}

/* ---------- Users ---------- */
export const userApi = {
  profile: (id: number) => api.get(`/users/${id}/profile`).then(r => r.data),
  history: (id: number) => api.get(`/users/${id}/history`).then(r => r.data),
  search: (q: string) => api.get('/users/search', { params: { q } }).then(r => r.data as (User & { created_at: string })[]),
  serverTime: () => api.get('/time').then(r => r.data as { server_time: string }),
}
