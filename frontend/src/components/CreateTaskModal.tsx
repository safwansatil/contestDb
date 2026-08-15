import { useState } from 'react'
import { contestApi, apiError } from '../lib/api'
import { useToast } from '../lib/toast'
import { Modal, Spinner } from './ui'
import { IconPlus } from './icons'

export function CreateTaskModal({ contestId, onClose, onCreated }: { contestId: number; onClose: () => void; onCreated: () => void }) {
  const toast = useToast()
  const [busy, setBusy] = useState(false)
  
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [maxScore, setMaxScore] = useState('100.0')
  const [cooldown, setCooldown] = useState('0')
  const [taskOrder, setTaskOrder] = useState('1')
  const [webhookUrl, setWebhookUrl] = useState('')
  
  const [keys, setKeys] = useState<{name: string, isNum: boolean}[]>([
    { name: 'run_time_seconds', isNum: true },
    { name: 'restarts', isNum: true }
  ])

  async function submit() {
    if (title.trim().length < 1) return toast('Title is required', 'err')
    if (description.trim().length < 1) return toast('Description is required', 'err')
    if (keys.length === 0) return toast('At least one schema key is required', 'err')
    
    setBusy(true)
    try {
      const required_keys = keys.map(k => k.name.trim()).filter(Boolean)
      const numeric_keys = keys.filter(k => k.isNum).map(k => k.name.trim()).filter(Boolean)
      
      await contestApi.addTask(contestId, {
        title: title.trim(),
        description: description.trim(),
        max_score: parseFloat(maxScore) || 100.0,
        submission_schema: { required_keys, numeric_keys },
        submission_cooldown_seconds: parseInt(cooldown) || 0,
        task_order: parseInt(taskOrder) || 1,
        webhook_url: webhookUrl.trim() || null
      })
      toast('Task added successfully', 'info')
      onCreated()
    } catch (e) { 
      toast(apiError(e), 'err') 
    } finally { 
      setBusy(false) 
    }
  }

  return (
    <Modal title="Add Task" subtitle="Configure a new task for this contest" onClose={onClose}
      footer={<>
        <button className="btn ghost" onClick={onClose}>Cancel</button>
        <button className="btn primary" onClick={submit} disabled={busy}>{busy ? <Spinner /> : 'Create task'}</button>
      </>}>
      <div className="field"><label>Task Title</label>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Line Follower Circuit" /></div>
      <div className="field"><label>Description</label>
        <textarea value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Instructions for the participants..." /></div>
      
      <div className="grid" style={{ gridTemplateColumns: '1fr 1fr 1fr' }}>
        <div className="field"><label>Max Score</label><input type="number" step="0.1" value={maxScore} onChange={(e) => setMaxScore(e.target.value)} /></div>
        <div className="field"><label>Cooldown (sec)</label><input type="number" min="0" value={cooldown} onChange={(e) => setCooldown(e.target.value)} /></div>
        <div className="field"><label>Task Order</label><input type="number" min="1" value={taskOrder} onChange={(e) => setTaskOrder(e.target.value)} /></div>
      </div>

      <div className="field"><label>Submission Schema Keys</label>
        <p className="faint" style={{ margin: '0 0 8px', fontSize: 12 }}>Define the JSON keys expected in the participant's telemetry payload.</p>
        <div className="stack" style={{ gap: 6, marginBottom: 10 }}>
          {keys.map((k, i) => (
            <div key={i} className="row" style={{ gap: 8 }}>
              <input className="grow" value={k.name} onChange={(e) => {
                const nw = [...keys]; nw[i].name = e.target.value; setKeys(nw)
              }} placeholder="key_name" />
              <label className="row" style={{ gap: 6, fontSize: 13, cursor: 'pointer', whiteSpace: 'nowrap' }}>
                <input type="checkbox" checked={k.isNum} onChange={(e) => {
                  const nw = [...keys]; nw[i].isNum = e.target.checked; setKeys(nw)
                }} /> Numeric
              </label>
              <button className="btn ghost sm" style={{ padding: '0 8px', color: '#ff5555' }} onClick={() => {
                setKeys(keys.filter((_, idx) => idx !== i))
              }}>×</button>
            </div>
          ))}
        </div>
        <button className="btn ghost sm" onClick={() => setKeys([...keys, { name: '', isNum: true }])}>
          <IconPlus size={14} /> Add Key
        </button>
      </div>

      <div className="field" style={{ marginTop: 12 }}><label>External Judge Webhook URL (Optional)</label>
        <input value={webhookUrl} onChange={(e) => setWebhookUrl(e.target.value)} placeholder="https://api.my-judge.com/evaluate" />
        <p className="faint" style={{ margin: '4px 0 0', fontSize: 12 }}>If set, the worker will asynchronously dispatch submissions to this URL instead of evaluating locally.</p>
      </div>
    </Modal>
  )
}
