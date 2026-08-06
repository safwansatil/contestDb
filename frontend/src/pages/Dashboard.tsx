import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { contestApi, apiError, type Contest } from '../lib/api'
import { fmtRel, timelineStatus, statusColor } from '../lib/format'
import { Page, Loader, Empty, Pill, fadeUp, stagger } from '../components/ui'
import { CreateContestModal } from '../components/CreateContestModal'
import { useToast } from '../lib/toast'

const TIMELINES = ['ALL', 'ONGOING', 'UPCOMING', 'COMPLETED']

export function Dashboard() {
  const [contests, setContests] = useState<Contest[] | null>(null)
  const [q, setQ] = useState('')
  const [timeline, setTimeline] = useState('ALL')
  const [creating, setCreating] = useState(false)
  const toast = useToast()
  const nav = useNavigate()

  async function load() {
    try {
      const params: Record<string, string> = {}
      if (q.trim()) params.q = q.trim()
      if (timeline !== 'ALL') params.timeline = timeline
      setContests(await contestApi.list(params))
    } catch (e) { toast(apiError(e), 'err'); setContests([]) }
  }
  // reload when filters change (debounced for the search box)
  useEffect(() => { const t = setTimeout(load, 220); return () => clearTimeout(t) }, [q, timeline])

  const visible = useMemo(() => (contests || []).filter(
    (c) => c.status !== 'PENDING_APPROVAL' || c.user_role === 'HOST' || c.user_role === 'MODERATOR'
  ), [contests])

  return (
    <Page>
      <div className="page">
        <div className="row" style={{ justifyContent: 'space-between', alignItems: 'flex-end', flexWrap: 'wrap', gap: 12 }}>
          <div>
            <h1 style={{ fontSize: 27 }}>Explore contests</h1>
            <p className="dim" style={{ margin: '7px 0 0' }}>Any contest, any format — ranked natively inside PostgreSQL.</p>
          </div>
          <button className="btn primary" onClick={() => setCreating(true)}>＋ Host a contest</button>
        </div>

        <div className="filters">
          <div className="input-icon grow" style={{ minWidth: 220 }}>
            <span className="ic">⌕</span>
            <input placeholder="Search contests by title…" value={q} onChange={(e) => setQ(e.target.value)} />
          </div>
          <div className="seg">
            {TIMELINES.map((t) => (
              <button key={t} className={timeline === t ? 'on' : ''} onClick={() => setTimeline(t)}>
                {t[0] + t.slice(1).toLowerCase()}
              </button>
            ))}
          </div>
        </div>

        {contests === null ? (
          <Loader label="Fetching contests…" />
        ) : visible.length === 0 ? (
          <div className="glass"><Empty>No contests match your filters.</Empty></div>
        ) : (
          <motion.div className="contest-grid" variants={stagger} initial="initial" animate="animate">
            {visible.map((c) => <ContestCard key={c.id} c={c} onClick={() => nav(`/contests/${c.id}`)} />)}
          </motion.div>
        )}
      </div>

      {creating && <CreateContestModal onClose={() => setCreating(false)} onCreated={(id) => { setCreating(false); nav(`/contests/${id}`) }} />}
    </Page>
  )
}

function ContestCard({ c, onClick }: { c: Contest; onClick: () => void }) {
  const tstat = timelineStatus(c)
  const col = statusColor(c.status)
  const joinedLabel = tstat === 'UPCOMING' ? 'Starts' : tstat === 'COMPLETED' ? 'Ended' : 'Ends'
  const joinedTime = tstat === 'UPCOMING' ? c.start_time : c.end_time
  return (
    <motion.div className="glass ccard" variants={fadeUp} onClick={onClick}
      whileHover={{ y: -4, transition: { duration: 0.18 } }}>
      <div className="rail" style={{ background: col }} />
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <Pill className="" dot={col}>{/* status */}<span style={{ color: col }}>{c.status === 'PENDING_APPROVAL' ? 'PENDING' : tstat}</span></Pill>
        <span className="strat">{c.ranking_strategy}</span>
      </div>
      <div>
        <h3>{c.title}</h3>
        <div className="wrap-row" style={{ marginTop: 7 }}>
          {c.user_role && <Pill className="tag-gold">{c.user_role}</Pill>}
          {c.requires_invitation_code && <Pill className="tag-neutral">🔒 Invite only</Pill>}
        </div>
      </div>
      <p className="desc">{c.judging_description}</p>
      <div className="divider" />
      <div className="meta">
        <span>{joinedLabel} <b>{fmtRel(joinedTime)}</b></span>
        <span className="strat" style={{ background: 'transparent', padding: 0 }}>{c.max_participants ? `cap ${c.max_participants}` : 'unlimited'}</span>
      </div>
    </motion.div>
  )
}
