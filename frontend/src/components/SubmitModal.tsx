import { useState } from 'react'
import { motion } from 'framer-motion'
import { submissionApi, userApi, apiError, type Task, type Contest } from '../lib/api'
import { verdictClass, verdictColor } from '../lib/format'
import { useAuth } from '../lib/auth'
import { useToast } from '../lib/toast'
import { Modal, Spinner } from './ui'

type Phase = 'form' | 'PENDING' | 'JUDGING' | 'done'

export function SubmitModal({ contest, tasks, initialTask, onClose, onJudged }: {
  contest: Contest; tasks: Task[]; initialTask?: Task; onClose: () => void; onJudged: () => void
}) {
  const { user } = useAuth()
  const toast = useToast()
  const [taskId, setTaskId] = useState(initialTask?.id ?? tasks[0]?.id)
  const [values, setValues] = useState<Record<string, string>>({})
  const [phase, setPhase] = useState<Phase>('form')
  const [result, setResult] = useState<{ score: number; verdict: string } | null>(null)

  const task = tasks.find((t) => t.id === taskId)!

  function setVal(k: string, v: string) { setValues((s) => ({ ...s, [k]: v })) }

  // Poll the user's submission history until the given submission is judged (verdict present).
  async function pollVerdict(submissionId: number): Promise<{ score: number; verdict: string }> {
    for (let i = 0; i < 15; i++) {
      await new Promise((r) => setTimeout(r, 1300))
      if (i === 0) setPhase('JUDGING')
      try {
        const hist = await userApi.history(user!.id)
        const found = (hist.submissions_history as { submission_id: number; score: number; verdict: string | null }[])
          .find((s) => s.submission_id === submissionId)
        if (found && found.verdict) return { score: found.score, verdict: found.verdict }
      } catch { /* keep polling */ }
    }
    return { score: 0, verdict: 'PENDING' }
  }

  async function submit() {
    const payload: Record<string, unknown> = {}
    for (const k of task.submission_schema.required_keys) {
      const raw = values[k]
      if (raw == null || raw === '') { toast(`Missing required field: ${k}`, 'err'); return }
      payload[k] = task.submission_schema.numeric_keys.includes(k) ? Number(raw) : raw
    }
    setPhase('PENDING')
    try {
      const res = await submissionApi.create(contest.id, task.id, payload)
      toast(`Submission #${res.submission_id} queued · PENDING`, 'info')
      const verdict = await pollVerdict(res.submission_id)
      setResult(verdict)
      setPhase('done')
      onJudged()
    } catch (e) {
      setPhase('form')
      toast(apiError(e), 'err')
    }
  }

  if (phase === 'done' && result) {
    const cls = verdictClass(result.verdict), col = verdictColor(result.verdict)
    const glyph = cls === 'tag-ac' ? '✓' : cls === 'tag-wa' ? '✕' : '◔'
    return (
      <Modal title="" onClose={onClose}>
        <div className="center" style={{ padding: '10px 6px 6px' }}>
          <motion.div initial={{ scale: 0, rotate: -20 }} animate={{ scale: 1, rotate: 0 }} transition={{ type: 'spring', stiffness: 300, damping: 16 }}
            style={{ width: 70, height: 70, borderRadius: '50%', margin: '0 auto 16px', display: 'grid', placeItems: 'center', fontSize: 32, background: col + '22', color: col }}>
            {glyph}
          </motion.div>
          <div className="label">{task.title}</div>
          <motion.div className="mono" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}
            style={{ fontSize: 50, fontWeight: 800, margin: '6px 0', color: col }}>{result.score}</motion.div>
          <span className={`pill ${cls}`} style={{ fontSize: 13, padding: '5px 12px' }}>{result.verdict}</span>
          <p className="dim" style={{ fontSize: 12.5, margin: '18px 0 0' }}>
            Judged by the worker and written back to PostgreSQL. Standings update on the leaderboard.
          </p>
          <button className="btn primary block" style={{ marginTop: 18 }} onClick={onClose}>Done</button>
        </div>
      </Modal>
    )
  }

  if (phase === 'PENDING' || phase === 'JUDGING') {
    return (
      <Modal title="Judging your submission" onClose={() => { /* block close mid-judge */ }}>
        <div className="center" style={{ padding: '18px 6px' }}>
          <div style={{ display: 'grid', placeItems: 'center', marginBottom: 20 }}><Spinner /></div>
          <div className="row" style={{ justifyContent: 'center', gap: 8 }}>
            {['PENDING', 'JUDGING', 'COMPLETED'].map((s, i) => {
              const active = (phase === 'PENDING' && i === 0) || (phase === 'JUDGING' && i === 1)
              const done = (phase === 'JUDGING' && i === 0)
              return <span key={s} className={`pill ${active ? 'tag-pending' : done ? 'tag-ac' : 'tag-neutral'}`}>{s}</span>
            })}
          </div>
          <p className="dim" style={{ fontSize: 13, marginTop: 18 }}>
            Your payload passed schema validation and entered the queue. The judge worker is scoring it now…
          </p>
        </div>
      </Modal>
    )
  }

  return (
    <Modal title="Submit solution" subtitle={contest.title} onClose={onClose}
      footer={<>
        <button className="btn ghost" onClick={onClose}>Cancel</button>
        <button className="btn primary" onClick={submit}>↑ Submit to queue</button>
      </>}>
      <div className="field"><label>Task</label>
        <select value={taskId} onChange={(e) => { setTaskId(Number(e.target.value)); setValues({}) }}>
          {tasks.map((t) => <option key={t.id} value={t.id}>{t.title}</option>)}
        </select>
      </div>
      {task.submission_schema.required_keys.map((k) => {
        const numeric = task.submission_schema.numeric_keys.includes(k)
        return (
          <div className="field" key={k}>
            <label>{k} <span className={`chip ${numeric ? 'num' : ''}`} style={{ fontSize: 10 }}>{numeric ? 'number' : 'text'}</span></label>
            {k === 'source_code'
              ? <textarea rows={5} value={values[k] || ''} onChange={(e) => setVal(k, e.target.value)} placeholder="paste your code…" />
              : <input type={numeric ? 'number' : 'text'} step="any" value={values[k] || ''} onChange={(e) => setVal(k, e.target.value)} placeholder={numeric ? '0' : 'value'} />}
          </div>
        )
      })}
      {task.submission_cooldown_seconds > 0 &&
        <div className="notice">⏱ This task enforces a {task.submission_cooldown_seconds}s cooldown between submissions.</div>}
      <div className="notice blue" style={{ marginTop: 10 }}>Payload is validated against the task schema before it enters the judge queue.</div>
    </Modal>
  )
}
