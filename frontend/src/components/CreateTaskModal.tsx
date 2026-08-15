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
  const [taskOrder, setTaskOrder] = useState('1')

  async function submit() {
    if (title.trim().length < 1) return toast('Title is required', 'err')
    if (description.trim().length < 1) return toast('Description is required', 'err')
    
    setBusy(true)
    try {
      await contestApi.addTask(contestId, {
        title: title.trim(),
        description: description.trim(),
        max_score: parseFloat(maxScore) || 100.0,
        submission_schema: { required_keys: [], numeric_keys: [] }, // Developer configures this later
        submission_cooldown_seconds: 0,
        task_order: parseInt(taskOrder) || 1,
        webhook_url: null
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
      
      <div className="grid" style={{ gridTemplateColumns: '1fr 1fr' }}>
        <div className="field"><label>Max Score</label><input type="number" step="0.1" value={maxScore} onChange={(e) => setMaxScore(e.target.value)} /></div>
        <div className="field"><label>Task Order</label><input type="number" min="1" value={taskOrder} onChange={(e) => setTaskOrder(e.target.value)} /></div>
      </div>
      <div className="notice" style={{ marginTop: 12 }}>
        Note: The technical integration (webhooks & payload evaluation schemas) will be automatically configured by our developer team upon approval.
      </div>
    </Modal>
  )
}
