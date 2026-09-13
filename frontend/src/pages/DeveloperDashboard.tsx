import { useEffect, useState } from 'react'
import { devApi, apiError, type Contest, type ContestTypeRequest } from '../lib/api'
import { useToast } from '../lib/toast'
import { Loader, Modal, Spinner } from '../components/ui'

export function DeveloperDashboard() {
  const [contests, setContests] = useState<Contest[]>([])
  const [requests, setRequests] = useState<ContestTypeRequest[]>([])
  const [selected, setSelected] = useState<ContestTypeRequest | null>(null)
  const toast = useToast()
  const load = () => {
    devApi.contests().then(setContests).catch(() => setContests([]))
    devApi.formatRequests().then(setRequests).catch((e) => toast(apiError(e), 'err'))
  }
  useEffect(load, [])
  const pending = requests.filter((r) => r.status === 'PENDING')

  return <div className="container mx-auto px-4 py-8 lg:px-8 lg:py-12 max-w-6xl">
    <div className="mb-10"><p className="text-primary font-semibold text-sm uppercase tracking-widest">Safwan · Developer Console</p><h1 className="text-4xl font-extrabold mt-2">Integration review queue</h1><p className="opacity-60 mt-2">Approve real contests only after their interface and judge are ready. Format requests stay separate from contests.</p></div>
    <section className="mb-12"><div className="flex items-center justify-between mb-4"><h2 className="text-2xl font-bold">Format requests</h2><span className="badge badge-warning">{pending.length} pending</span></div>
      {requests.length === 0 ? <Loader /> : <div className="grid md:grid-cols-2 gap-5">{requests.map((r) => <button key={r.id} className="text-left card bg-base-100 border border-base-200 shadow-sm hover:border-primary/50 transition-colors" onClick={() => setSelected(r)}><div className="card-body p-6"><div className="flex justify-between gap-3"><h3 className="card-title">{r.title}</h3><span className={`badge ${r.status === 'PENDING' ? 'badge-warning' : r.status === 'REJECTED' ? 'badge-error' : 'badge-success'}`}>{r.status}</span></div><p className="text-xs uppercase tracking-wider opacity-50">{r.requested_type.replace('_', ' ')} · requested by {r.requester}</p><p className="text-sm opacity-70 line-clamp-3">{r.rules_description}</p>{r.developer_note && <p className="text-sm bg-base-200 rounded-lg p-3">Your note: {r.developer_note}</p>}</div></button>)}</div>}
    </section>
    <section><h2 className="text-2xl font-bold mb-4">Contest approval queue</h2><div className="overflow-x-auto bg-base-100 border border-base-200 rounded-2xl"><table className="table"><thead><tr><th>Contest</th><th>Format</th><th>Status</th><th></th></tr></thead><tbody>{contests.map((c) => <tr key={c.id}><td><b>{c.title}</b><div className="text-xs opacity-50">{c.ranking_strategy}</div></td><td>{c.contest_type}</td><td><span className={`badge ${c.status === 'PENDING_APPROVAL' ? 'badge-warning' : 'badge-success'}`}>{c.status}</span></td><td>{c.status === 'PENDING_APPROVAL' && <button className="btn btn-sm btn-primary" onClick={async () => { try { await devApi.approve(c.id); toast('Contest approved'); load() } catch (e) { toast(apiError(e), 'err') } }}>Approve</button>}</td></tr>)}</tbody></table></div></section>
    {selected && <RequestDecision request={selected} onClose={() => setSelected(null)} onDone={() => { setSelected(null); load() }} />}
  </div>
}

function RequestDecision({ request, onClose, onDone }: { request: ContestTypeRequest; onClose: () => void; onDone: () => void }) {
  const [note, setNote] = useState(request.developer_note || '')
  const [busy, setBusy] = useState(false)
  const toast = useToast()
  async function decide(decision: 'APPROVED' | 'REJECTED') { setBusy(true); try { await devApi.decideFormatRequest(request.id, decision, note); toast(`Request ${decision.toLowerCase()}`); onDone() } catch (e) { toast(apiError(e), 'err'); setBusy(false) } }
  return <Modal title={request.title} subtitle={`${request.requested_type.replace('_', ' ')} · requested by ${request.requester}`} onClose={onClose} footer={<><button className="btn ghost" onClick={onClose}>Close</button>{request.status === 'PENDING' && <><button className="btn danger" disabled={busy} onClick={() => decide('REJECTED')}>{busy ? <Spinner /> : 'Reject request'}</button><button className="btn primary" disabled={busy} onClick={() => decide('APPROVED')}>{busy ? <Spinner /> : 'Approve request'}</button></>}</>}><p className="dim">{request.rules_description}</p>{request.requested_tasks && <div className="notice blue" style={{ margin: '16px 0' }}>Suggested tasks: {request.requested_tasks}</div>}<div className="field"><label>Developer decision note</label><textarea value={note} onChange={(e) => setNote(e.target.value)} placeholder="Explain what is missing or what will be integrated…" /></div></Modal>
}
