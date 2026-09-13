import { useState } from 'react'
import { contestApi, formatRequestApi, apiError } from '../lib/api'
import { useToast } from '../lib/toast'
import { Modal, Spinner } from './ui'

// default datetimes: start tomorrow, freeze +2h, end +3h
function iso(offsetH: number) {
  const d = new Date(Date.now() + offsetH * 3600e3)
  d.setSeconds(0, 0)
  return new Date(d.getTime() - d.getTimezoneOffset() * 60e3).toISOString().slice(0, 16)
}

export function CreateContestModal({ onClose, onCreated }: { onClose: () => void; onCreated: (id?: number) => void }) {
  const toast = useToast()
  const [busy, setBusy] = useState(false)
  const [mode, setMode] = useState<'contest' | 'request'>('contest')
  const [f, setF] = useState({
    title: '', contest_format: 'icpc', judging_description: '', requested_tasks: '',
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
      if (mode === 'request') {
        const res = await formatRequestApi.create({
          title: f.title.trim(), requested_type: f.contest_format,
          rules_description: f.judging_description.trim(), requested_tasks: f.requested_tasks.trim() || null,
        })
        toast(`Request #${res.request_id} sent to Safwan's developer queue`, 'info')
        onCreated()
        return
      }
      const finalStrategy = f.contest_format === 'icpc' || f.contest_format === 'ctf' ? 'SUM' : 'MAX'
      const res = await contestApi.create({
        title: f.title.trim(), 
        ranking_strategy: finalStrategy,
        contest_type: f.contest_format,
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
    <Modal title={mode === 'contest' ? 'Host a new contest' : 'Request a new contest format'} subtitle={mode === 'contest' ? 'Built-in formats are reviewed before going live.' : 'A developer must build the screen and judge before it can be hosted.'} onClose={onClose}
      footer={<>
        <button className="btn ghost" onClick={onClose}>Cancel</button>
        <button className="btn primary" onClick={submit} disabled={busy}>{busy ? <Spinner /> : mode === 'request' ? 'Send request' : 'Create contest'}</button>
      </>}>
      <div className="seg" style={{ marginBottom: 18 }}>
        <button type="button" className={mode === 'contest' ? 'on' : ''} onPointerDown={() => setMode('contest')}>Host built-in format</button>
        <button type="button" className={mode === 'request' ? 'on' : ''} onPointerDown={() => setMode('request')}>Request a format</button>
      </div>
      <div className="field"><label>{mode === 'contest' ? 'Contest title' : 'Request title'}</label>
        <input value={f.title} onChange={(e) => set('title', e.target.value)} placeholder="e.g. Spring Robotics Sprint" /></div>
      <div className="field"><label>{mode === 'contest' ? 'Built-in format' : 'Requested format'}</label>
        <select value={f.contest_format} onChange={(e) => set('contest_format', e.target.value)}>
          <option value="icpc">ICPC Algorithm Contest</option>
          <option value="chess">Chess Puzzles</option>
          <option value="ctf">Beginner CTF</option>
          {mode === 'request' && <><option value="chess_variant">Chess variant / custom levels</option><option value="biology_olympiad">Biology Olympiad</option><option value="other">Other format</option></>}
        </select>
        <p className="faint" style={{ margin: '4px 0 0', fontSize: 12 }}>{mode === 'contest' ? 'Pick a format with an interface and demo judge already attached.' : 'Describe the player experience and scoring so a developer can assess the work.'}</p>
      </div>
      <div className="field"><label>{mode === 'contest' ? 'Judging description' : 'Rules and judging request'}</label>
        <textarea value={f.judging_description} onChange={(e) => set('judging_description', e.target.value)} placeholder="Explain how submissions are scored…" /></div>
      {mode === 'request' && <div className="field"><label>Suggested levels or tasks (optional)</label><textarea value={f.requested_tasks} onChange={(e) => set('requested_tasks', e.target.value)} placeholder="e.g. three mate-in-two positions, or genetics / ecology rounds" /></div>}
      {mode === 'request' ? null : <>
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
      </>}
    </Modal>
  )
}
