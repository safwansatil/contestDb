import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { apiError, devApi, type Contest, type ContestTypeRequest } from '../lib/api'
import { useToast } from '../lib/toast'
import { Loader, Modal, Spinner } from '../components/ui'

export function DeveloperDashboard() {
  const [contests, setContests] = useState<Contest[]>([])
  const [requests, setRequests] = useState<ContestTypeRequest[]>([])
  const [selected, setSelected] = useState<ContestTypeRequest | null>(null)
  const [cancelTarget, setCancelTarget] = useState<Contest | null>(null)
  const [rejectTarget, setRejectTarget] = useState<Contest | null>(null)
  const toast = useToast()
  const navigate = useNavigate()

  const load = () => {
    devApi.contests().then(setContests).catch(() => setContests([]))
    devApi.formatRequests().then(setRequests).catch((error) => toast(apiError(error), 'err'))
  }

  useEffect(load, [])
  const pending = requests.filter((request) => request.status === 'PENDING')

  async function approve(contestId: number) {
    try {
      await devApi.approve(contestId)
      toast('Contest approved and activated')
      load()
    } catch (error) {
      toast(apiError(error), 'err')
    }
  }

  return (
    <main className="editorial-page">
      <header className="page-heading">
        <div>
          <span className="index">Control room / private</span>
          <h1>Review<br />the <em>record.</em></h1>
          <p>Approve formats only when their judge and player interface are ready for the board.</p>
        </div>
        <div className="mono">{pending.length} PENDING</div>
      </header>

      <section style={{ marginTop: 32 }}>
        <span className="label">Format requests</span>
        {requests.length === 0 ? <Loader /> : (
          <div className="contest-editorial-grid">
            {requests.map((request, index) => (
              <button className="contest-editorial-card" key={request.id} disabled={request.status !== 'PENDING'} onClick={() => request.status === 'PENDING' && setSelected(request)}>
                <span className="card-no">#{String(index + 1).padStart(2, '0')} / {request.status}</span>
                <h3>{request.title}</h3>
                <p className="dim">{request.rules_description}</p>
                <div className="card-meta"><span>{request.requested_type.replaceAll('_', ' ')}</span><span>{request.requester}</span></div>
              </button>
            ))}
          </div>
        )}
      </section>

      <section style={{ marginTop: 64 }}>
        <span className="label">Contest approval desk</span>
        <div className="glass" style={{ marginTop: 14, overflow: 'hidden' }}>
          <table className="lb">
            <thead><tr><th>Contest</th><th>Format</th><th>Status</th><th /></tr></thead>
            <tbody>
              {contests.map((contest) => (
                <tr key={contest.id} onClick={() => navigate(`/contests/${contest.id}?dev=1`)} style={{ cursor: 'pointer' }}>
                  <td><b>{contest.title}</b><div className="faint">{contest.ranking_strategy}</div></td>
                  <td>{contest.contest_type?.replaceAll('_', ' ') || 'custom'}</td>
                  <td>{contest.status.replaceAll('_', ' ')}</td>
                  <td>
                    {contest.status === 'PENDING_APPROVAL' && <div className="row" style={{ justifyContent: 'flex-end', gap: 8 }}>
                      <button className="btn danger sm" onClick={(event) => { event.stopPropagation(); setRejectTarget(contest) }}>Reject</button>
                      <button className="btn primary sm" onClick={(event) => { event.stopPropagation(); approve(contest.id) }}>Approve</button>
                    </div>}
                    {contest.status === 'ACTIVE' && <button className="btn danger sm" onClick={(event) => { event.stopPropagation(); setCancelTarget(contest) }}>Cancel</button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      {selected && <RequestDecision request={selected} onClose={() => setSelected(null)} onDone={() => { setSelected(null); load() }} />}
      {rejectTarget && <RejectContestDialog contest={rejectTarget} onClose={() => setRejectTarget(null)} onDone={() => { setRejectTarget(null); load() }} />}
      {cancelTarget && <CancelContestDialog contest={cancelTarget} onClose={() => setCancelTarget(null)} onDone={() => { setCancelTarget(null); load() }} />}
    </main>
  )
}

function RequestDecision({ request, onClose, onDone }: { request: ContestTypeRequest; onClose: () => void; onDone: () => void }) {
  const [note, setNote] = useState(request.developer_note || '')
  const [busy, setBusy] = useState(false)
  const toast = useToast()
  async function decide(decision: 'APPROVED' | 'REJECTED') {
    setBusy(true)
    try { await devApi.decideFormatRequest(request.id, decision, note); toast(`Request ${decision.toLowerCase()}`); onDone() }
    catch (error) { toast(apiError(error), 'err'); setBusy(false) }
  }
  return <Modal title={request.title} subtitle={`Format proposal · ${request.requested_type.replaceAll('_', ' ')}`} onClose={onClose}
    footer={<><button className="btn ghost" onClick={onClose}>Close</button><button className="btn danger" disabled={busy} onClick={() => decide('REJECTED')}>{busy ? <Spinner /> : 'Reject request'}</button><button className="btn primary" disabled={busy} onClick={() => decide('APPROVED')}>{busy ? <Spinner /> : 'Approve request'}</button></>}>
    <div className="notice blue" style={{ marginBottom: 16 }}><b>Requested by {request.requester || 'a member'}</b><br />Review the player experience and judge requirements before adding this format to the platform.</div>
    <div className="field"><label>Proposed rules and scoring</label><p className="dim" style={{ whiteSpace: 'pre-wrap', margin: '4px 0 0' }}>{request.rules_description}</p></div>
    {request.requested_tasks && <div className="field"><label>Suggested levels or tasks</label><p className="dim" style={{ whiteSpace: 'pre-wrap', margin: '4px 0 0' }}>{request.requested_tasks}</p></div>}
    <div className="field"><label>Decision note</label><textarea value={note} onChange={(event) => setNote(event.target.value)} placeholder="Explain what is ready, missing, or needs revision…" /></div>
  </Modal>
}

function CancelContestDialog({ contest, onClose, onDone }: { contest: Contest; onClose: () => void; onDone: () => void }) {
  const [busy, setBusy] = useState(false)
  const toast = useToast()
  async function cancel() { setBusy(true); try { await devApi.cancel(contest.id); toast('Contest cancelled'); onDone() } catch (error) { toast(apiError(error), 'err'); setBusy(false) } }
  return <Modal title={`Cancel ${contest.title}?`} subtitle="Developer action / active contest" onClose={onClose}
    footer={<><button className="btn ghost" disabled={busy} onClick={onClose}>Keep active</button><button className="btn danger" disabled={busy} onClick={cancel}>{busy ? <Spinner /> : 'Cancel contest'}</button></>}>
    <div className="notice red"><b>This stops the contest immediately.</b><br />New enrollments and submissions will be blocked. Existing tasks, members, and submission history remain available in the record.</div>
  </Modal>
}

function RejectContestDialog({ contest, onClose, onDone }: { contest: Contest; onClose: () => void; onDone: () => void }) {
  const [busy, setBusy] = useState(false)
  const toast = useToast()
  async function reject() { setBusy(true); try { await devApi.reject(contest.id); toast('Contest rejected'); onDone() } catch (error) { toast(apiError(error), 'err'); setBusy(false) } }
  return <Modal title={`Reject ${contest.title}?`} subtitle="Developer action / pending contest" onClose={onClose}
    footer={<><button className="btn ghost" disabled={busy} onClick={onClose}>Keep pending</button><button className="btn danger" disabled={busy} onClick={reject}>{busy ? <Spinner /> : 'Reject contest'}</button></>}>
    <div className="notice red"><b>This contest will not go live.</b><br />Its record remains visible to its host, but participants cannot enroll or submit to a rejected contest.</div>
  </Modal>
}
