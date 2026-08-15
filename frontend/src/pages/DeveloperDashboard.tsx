import { useEffect, useState } from 'react'
import { devApi, contestApi, apiError, type Contest, type Task } from '../lib/api'
import { useToast } from '../lib/toast'
import { Page, Loader, Empty, Pill, Modal, Spinner } from '../components/ui'
import { IconSettings, IconCheck } from '../components/icons'
import { fmtDate } from '../lib/format'

export function DeveloperDashboard() {
  const [contests, setContests] = useState<Contest[] | null>(null)
  const [selectedContest, setSelectedContest] = useState<Contest | null>(null)
  const toast = useToast()

  async function load() {
    try {
      setContests(await devApi.contests())
    } catch (e) { toast(apiError(e), 'err'); setContests([]) }
  }

  useEffect(() => { load() }, [])

  return (
    <Page>
      <div className="page">
        <div className="row" style={{ justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: 24 }}>
          <div>
            <h1 style={{ fontSize: 27 }}>Developer Portal</h1>
            <p className="dim" style={{ margin: '7px 0 0' }}>Configure technical integrations and approve contests.</p>
          </div>
        </div>

        {contests === null ? <Loader /> : contests.length === 0 ? <Empty icon="◲">No contests in the system.</Empty> : (
          <div className="grid">
            {contests.map((c) => (
              <div key={c.id} className="card p-lg row" style={{ gap: 16, cursor: 'pointer', border: c.status === 'PENDING_APPROVAL' ? '1px solid var(--border)' : '' }} onClick={() => setSelectedContest(c)}>
                <div className="grow stack" style={{ gap: 6 }}>
                  <div className="row" style={{ gap: 10 }}>
                    <h3 style={{ margin: 0, fontSize: 17 }}>{c.title}</h3>
                    {c.status === 'PENDING_APPROVAL' ? <Pill className="tag-red">Pending Approval</Pill> : <Pill className="tag-green">Active</Pill>}
                  </div>
                  <div className="faint" style={{ fontSize: 13 }}>
                    Strategy: {c.ranking_strategy} · Starts {fmtDate(c.start_time)}
                  </div>
                </div>
                <button className="btn ghost"><IconSettings size={20} /></button>
              </div>
            ))}
          </div>
        )}
      </div>
      
      {selectedContest && <DevContestModal contest={selectedContest} onClose={() => setSelectedContest(null)} onUpdate={() => { setSelectedContest(null); load() }} />}
    </Page>
  )
}

function DevContestModal({ contest, onClose, onUpdate }: { contest: Contest; onClose: () => void; onUpdate: () => void }) {
  const toast = useToast()
  const [tasks, setTasks] = useState<Task[] | null>(null)
  const [busy, setBusy] = useState(false)
  
  async function loadTasks() {
    try {
      setTasks(await contestApi.tasks(contest.id))
    } catch (e) { toast(apiError(e), 'err'); setTasks([]) }
  }
  
  useEffect(() => { loadTasks() }, [contest.id])

  async function approve() {
    setBusy(true)
    try {
      await devApi.approve(contest.id)
      toast('Contest approved and is now ACTIVE', 'info')
      onUpdate()
    } catch (e) { toast(apiError(e), 'err') } finally { setBusy(false) }
  }

  return (
    <Modal title={`Dev Config: ${contest.title}`} subtitle={`Format: ${contest.ranking_strategy} · Status: ${contest.status}`} onClose={onClose}
      footer={<>
        <button className="btn ghost" onClick={onClose}>Close</button>
        {contest.status === 'PENDING_APPROVAL' && (
          <button className="btn primary" onClick={approve} disabled={busy}>{busy ? <Spinner /> : <><IconCheck size={16}/> Approve Contest</>}</button>
        )}
      </>}>
      
      <div className="stack" style={{ gap: 16 }}>
        <h4 style={{ margin: 0 }}>Task Configurations</h4>
        {tasks === null ? <Loader /> : tasks.length === 0 ? <Empty>No tasks created by the host yet.</Empty> : (
          <div className="grid">
            {tasks.map((t) => (
              <TaskConfigRow key={t.id} task={t} />
            ))}
          </div>
        )}
      </div>
    </Modal>
  )
}

function TaskConfigRow({ task }: { task: Task }) {
  const toast = useToast()
  const [busy, setBusy] = useState(false)
  const [webhookUrl, setWebhookUrl] = useState(task.webhook_url || '')
  const [schemaStr, setSchemaStr] = useState(JSON.stringify(task.submission_schema, null, 2))

  async function save() {
    setBusy(true)
    try {
      let schema = {}
      try { schema = JSON.parse(schemaStr) } catch { return toast('Invalid JSON in schema', 'err') }
      await devApi.updateTaskConfig(task.id, webhookUrl.trim() || null, schema)
      toast('Task config saved', 'info')
    } catch (e) { toast(apiError(e), 'err') } finally { setBusy(false) }
  }

  return (
    <div className="glass stack" style={{ gap: 10, padding: 16 }}>
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <b>{task.title}</b>
        <span className="mono faint">ID: {task.id}</span>
      </div>
      <p className="dim" style={{ fontSize: 13, margin: 0 }}>{task.description}</p>
      
      <div className="field"><label>Webhook URL</label>
        <input value={webhookUrl} onChange={(e) => setWebhookUrl(e.target.value)} placeholder="https://api.my-judge.com/evaluate" />
      </div>
      
      <div className="field"><label>Submission Schema (JSON)</label>
        <textarea value={schemaStr} onChange={(e) => setSchemaStr(e.target.value)} style={{ fontFamily: 'monospace', minHeight: 120 }} />
      </div>
      
      <div style={{ textAlign: 'right' }}>
        <button className="btn ghost sm" onClick={save} disabled={busy}>{busy ? 'Saving...' : 'Save Config'}</button>
      </div>
    </div>
  )
}
