import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  devApi,
  apiError,
  type Contest,
  type ContestTypeRequest
} from '../lib/api'
import { useToast } from '../lib/toast'
import { Loader, Modal, Spinner } from '../components/ui'

export function DeveloperDashboard() {
  const [contests, setContests] = useState<Contest[]>([])
  const [requests, setRequests] = useState<ContestTypeRequest[]>([])
  const [selected, setSelected] = useState<ContestTypeRequest | null>(null)

  const toast = useToast()
  const navigate = useNavigate()

  const load = () => {
    devApi
      .contests()
      .then(setContests)
      .catch(() => setContests([]))

    devApi
      .formatRequests()
      .then(setRequests)
      .catch((e) => toast(apiError(e), 'err'))
  }

  useEffect(load, [])

  const pending = requests.filter((r) => r.status === 'PENDING')

  return (
    <main className="editorial-page">
      <header className="page-heading">
        <div>
          <span className="index">Control room / private</span>

          <h1>
            Review
            <br />
            the <em>record.</em>
          </h1>

          <p>
            Approve formats only when their judge and player interface are ready
            for the board.
          </p>
        </div>

        <div className="mono">
          {pending.length} PENDING
        </div>
      </header>

      <section style={{ marginTop: 32 }}>
        <span className="label">Format requests</span>

        {requests.length === 0 ? (
          <Loader />
        ) : (
          <div className="contest-editorial-grid">
            {requests.map((r, i) => (
              <button
                className="contest-editorial-card"
                key={r.id}
                disabled={r.status !== 'PENDING'}
                onClick={() => {
                  if (r.status === 'PENDING') {
                    setSelected(r)
                  }
                }}
              >
                <span className="card-no">
                  #{String(i + 1).padStart(2, '0')} / {r.status}
                </span>

                <h3>{r.title}</h3>

                <p className="dim">
                  {r.rules_description}
                </p>

                <div className="card-meta">
                  <span>{r.requested_type.replace('_', ' ')}</span>
                  <span>{r.requester}</span>
                </div>
              </button>
            ))}
          </div>
        )}
      </section>

      <section style={{ marginTop: 64 }}>
        <span className="label">Contest approval desk</span>

        <div
          className="glass"
          style={{
            marginTop: 14,
            overflow: 'hidden'
          }}
        >
          <table className="lb">
            <thead>
              <tr>
                <th>Contest</th>
                <th>Format</th>
                <th>Status</th>
                <th />
              </tr>
            </thead>

            <tbody>
              {contests.map((c) => (
                <tr
                  key={c.id}
                  onClick={() => navigate(`/contests/${c.id}?dev=1`)}
                  style={{ cursor: 'pointer' }}
                >
                  <td>
                    <b>{c.title}</b>
                    <div className="faint">
                      {c.ranking_strategy}
                    </div>
                  </td>

                  <td>{c.contest_type}</td>

                  <td>
                    {c.status.replace('_', ' ')}
                  </td>

                  <td>
                    {c.status === 'PENDING_APPROVAL' && (
                      <button
                        className="btn primary sm"
                        onClick={async (e) => {
                          e.stopPropagation()

                          try {
                            await devApi.approve(c.id)
                            toast('Contest approved')
                            load()
                          } catch (e) {
                            toast(apiError(e), 'err')
                          }
                        }}
                      >
                        Approve
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      {selected && (
        <RequestDecision
          request={selected}
          onClose={() => setSelected(null)}
          onDone={() => {
            setSelected(null)
            load()
          }}
        />
      )}
    </main>
  )
}

function RequestDecision({
  request,
  onClose,
  onDone
}: {
  request: ContestTypeRequest
  onClose: () => void
  onDone: () => void
}) {
  const [note, setNote] = useState(request.developer_note || '')
  const [busy, setBusy] = useState(false)
  const toast = useToast()

  async function decide(
    decision: 'APPROVED' | 'REJECTED'
  ) {
    setBusy(true)

    try {
      await devApi.decideFormatRequest(
        request.id,
        decision,
        note
      )

      toast(`Request ${decision.toLowerCase()}`)
      onDone()
    } catch (e) {
      toast(apiError(e), 'err')
      setBusy(false)
    }
  }

  return (
    <Modal
      title={request.title}
      subtitle={`${request.requested_type.replace('_', ' ')} · requested by ${request.requester}`}
      onClose={onClose}
      footer={
        <>
          <button
            className="btn ghost"
            onClick={onClose}
          >
            Close
          </button>

          {request.status === 'PENDING' && (
            <>
              <button
                className="btn danger"
                disabled={busy}
                onClick={() => decide('REJECTED')}
              >
                {busy ? <Spinner /> : 'Reject'}
              </button>

              <button
                className="btn primary"
                disabled={busy}
                onClick={() => decide('APPROVED')}
              >
                {busy ? <Spinner /> : 'Approve'}
              </button>
            </>
          )}
        </>
      }
    >
      <p className="dim">
        {request.rules_description}
      </p>

      <div className="field">
        <label>Decision note</label>

        <textarea
          value={note}
          onChange={(e) => setNote(e.target.value)}
        />
      </div>
    </Modal>
  )
}