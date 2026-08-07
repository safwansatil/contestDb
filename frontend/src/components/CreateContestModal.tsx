import { useState } from 'react'
import { contestApi, apiError } from '../lib/api'
import { useToast } from '../lib/toast'
import { Modal, Spinner } from './ui'

// default datetimes: start tomorrow, freeze +2h, end +3h
function iso(offsetH: number) {
  const d = new Date(Date.now() + offsetH * 3600e3)
  d.setSeconds(0, 0)
  return new Date(d.getTime() - d.getTimezoneOffset() * 60e3).toISOString().slice(0, 16)
}

export function CreateContestModal({ onClose, onCreated }: { onClose: () => void; onCreated: (id: number) => void }) {
  const toast = useToast()
  const [busy, setBusy] = useState(false)
  const [f, setF] = useState({
    title: '', ranking_strategy: 'SUM', judging_description: '',
    start_time: iso(24), freeze_time: iso(26), end_time: iso(27),
    max_participants: '', invitation_code: '', allow_late_enrollment: true,
  })
  const set = (k: string, v: unknown) => setF((s) => ({ ...s, [k]: v }))

  async function submit() {
    if (f.title.trim().length < 3) return toast('Title must be at least 3 characters', 'err')
    if (f.judging_description.trim().length < 5) return toast('Add a judging description (5+ chars)', 'err')
    const s = new Date(f.start_time), fr = new Date(f.freeze_time), e = new Date(f.end_time)
    if (!(s <= fr && fr <= e)) return toast('Times must satisfy: start ≤ freeze ≤ end', 'err')
    setBusy(true)
    try {
      const res = await contestApi.create({
        title: f.title.trim(), ranking_strategy: f.ranking_strategy,
        start_time: s.toISOString(), freeze_time: fr.toISOString(), end_time: e.toISOString(),
        judging_description: f.judging_description.trim(),
        max_participants: f.max_participants ? Number(f.max_participants) : null,
        invitation_code: f.invitation_code.trim() || null,
        allow_late_enrollment: f.allow_late_enrollment,
      })
      toast('Contest created · pending developer approval', 'info')
      onCreated(res.contest_id)
    } catch (e) { toast(apiError(e), 'err') } finally { setBusy(false) }
  }

  return (
    <Modal title="Host a new contest" subtitle="Created contests start as PENDING_APPROVAL" onClose={onClose}
      footer={<>
        <button className="btn ghost" onClick={onClose}>Cancel</button>
        <button className="btn primary" onClick={submit} disabled={busy}>{busy ? <Spinner /> : 'Create contest'}</button>
      </>}>
      <div className="field"><label>Title</label>
        <input value={f.title} onChange={(e) => set('title', e.target.value)} placeholder="e.g. Spring Robotics Sprint" /></div>
      <div className="field"><label>Ranking strategy</label>
        <select value={f.ranking_strategy} onChange={(e) => set('ranking_strategy', e.target.value)}>
          <option>SUM</option><option>MAX</option><option>ICPC</option><option>Custom</option></select></div>
      <div className="field"><label>Judging description</label>
        <textarea value={f.judging_description} onChange={(e) => set('judging_description', e.target.value)} placeholder="Explain how submissions are scored…" /></div>
      <div className="grid" style={{ gridTemplateColumns: '1fr 1fr 1fr' }}>
        <div className="field"><label>Start</label><input type="datetime-local" value={f.start_time} onChange={(e) => set('start_time', e.target.value)} /></div>
        <div className="field"><label>Freeze</label><input type="datetime-local" value={f.freeze_time} onChange={(e) => set('freeze_time', e.target.value)} /></div>
        <div className="field"><label>End</label><input type="datetime-local" value={f.end_time} onChange={(e) => set('end_time', e.target.value)} /></div>
      </div>
      <div className="grid" style={{ gridTemplateColumns: '1fr 1fr' }}>
        <div className="field"><label>Max participants (blank = ∞)</label><input type="number" min="1" value={f.max_participants} onChange={(e) => set('max_participants', e.target.value)} placeholder="unlimited" /></div>
        <div className="field"><label>Invitation code (optional)</label><input value={f.invitation_code} onChange={(e) => set('invitation_code', e.target.value)} placeholder="none" /></div>
      </div>
      <label className="row" style={{ gap: 10, cursor: 'pointer' }} onClick={() => set('allow_late_enrollment', !f.allow_late_enrollment)}>
        <span className={`switch ${f.allow_late_enrollment ? 'on' : ''}`}><i /></span>
        <span>Allow late enrollment after start</span>
      </label>
    </Modal>
  )
}
