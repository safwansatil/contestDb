import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { contestApi, formatRequestApi, apiError, type Contest, type ContestTypeRequest } from '../lib/api'
import { fmtRel, timelineStatus } from '../lib/format'
import { CreateContestModal } from '../components/CreateContestModal'
import { useAuth } from '../lib/auth'
import { useToast } from '../lib/toast'

const TIMELINES = ['ALL', 'ONGOING', 'UPCOMING', 'COMPLETED']

const stagger = {
  animate: { transition: { staggerChildren: 0.05 } }
}
const fadeUp = {
  initial: { opacity: 0, y: 10 },
  animate: { opacity: 1, y: 0, transition: { duration: 0.3 } }
}

export function Dashboard() {
  const [contests, setContests] = useState<Contest[] | null>(null)
  const [q, setQ] = useState('')
  const [timeline, setTimeline] = useState('ALL')
  const [creating, setCreating] = useState(false)
  const [requests, setRequests] = useState<ContestTypeRequest[]>([])
  const toast = useToast()
  const { user } = useAuth()
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
  useEffect(() => { formatRequestApi.mine().then(setRequests).catch(() => setRequests([])) }, [])

  const visible = useMemo(() => (contests || []).filter(
    (c) => c.status !== 'PENDING_APPROVAL' || c.user_role === 'HOST' || c.user_role === 'MODERATOR'
  ), [contests])

  return (
    <div className="container mx-auto px-4 py-8 lg:px-8 lg:py-12 max-w-7xl">
      <div className="flex flex-col md:flex-row justify-between items-start md:items-end gap-6 mb-10">
        <div>
          <h1 className="text-4xl font-extrabold tracking-tight mb-2">Explore Contests</h1>
          <p className="text-base-content/60 text-lg">Any contest, any format — ranked natively inside PostgreSQL.</p>
        </div>
        {!user?.is_developer && (
          <button className="btn btn-primary shadow-lg hover:shadow-xl transition-shadow" onClick={() => setCreating(true)}>
            <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clipRule="evenodd" />
            </svg>
            Host a Contest
          </button>
        )}
      </div>

      <div className="flex flex-col md:flex-row gap-4 mb-8 bg-base-200/50 p-4 rounded-2xl">
        <div className="relative flex-1">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
          <input 
            type="text" 
            placeholder="Search contests by title…" 
            className="input input-bordered w-full pl-10 bg-base-100 shadow-sm"
            value={q} 
            onChange={(e) => setQ(e.target.value)} 
          />
        </div>
        
        <div className="join w-full md:w-auto overflow-x-auto shadow-sm">
          {TIMELINES.map((t) => (
            <button 
              key={t} 
              className={`btn join-item flex-1 md:flex-none ${timeline === t ? 'btn-neutral' : 'btn-ghost bg-base-100'}`}
              onClick={() => setTimeline(t)}
            >
              {t === 'ALL' ? 'All' : t.charAt(0) + t.slice(1).toLowerCase()}
            </button>
          ))}
        </div>
      </div>

      {contests === null ? (
        <div className="py-20 flex justify-center"><span className="loading loading-spinner loading-lg text-primary"></span></div>
      ) : visible.length === 0 ? (
        <div className="hero bg-base-200/40 rounded-3xl py-20 border border-base-300 border-dashed">
          <div className="hero-content text-center">
            <div className="max-w-md">
              <h2 className="text-2xl font-bold mb-4">No Contests Found</h2>
              <p className="opacity-60 mb-6">There are no contests matching your current filters.</p>
              <button className="btn btn-outline" onClick={() => { setQ(''); setTimeline('ALL') }}>Clear Filters</button>
            </div>
          </div>
        </div>
      ) : (
        <motion.div 
          className="columns-1 md:columns-2 xl:columns-3 gap-6 space-y-6" 
          variants={stagger} 
          initial="initial" 
          animate="animate"
        >
          {visible.map((c) => <ContestCard key={c.id} c={c} onClick={() => nav(`/contests/${c.id}`)} />)}
        </motion.div>
      )}

      {requests.length > 0 && (
        <section className="mt-12">
          <div className="flex items-end justify-between mb-4"><div><h2 className="text-2xl font-bold">Your format requests</h2><p className="opacity-60 text-sm">These need a developer-built player interface and judge.</p></div></div>
          <div className="grid md:grid-cols-2 gap-4">
            {requests.map((r) => <div key={r.id} className="card bg-base-100 border border-base-200 shadow-sm"><div className="card-body p-5">
              <div className="flex justify-between gap-3"><h3 className="font-bold text-lg">{r.title}</h3><span className={`badge ${r.status === 'PENDING' ? 'badge-warning' : r.status === 'REJECTED' ? 'badge-error' : 'badge-success'}`}>{r.status}</span></div>
              <p className="text-sm opacity-70">{r.requested_type.replace('_', ' ')} · {r.rules_description}</p>
              {r.developer_note && <p className="text-sm bg-base-200 rounded-lg p-3">Developer note: {r.developer_note}</p>}
            </div></div>)}
          </div>
        </section>
      )}

      {creating && <CreateContestModal onClose={() => setCreating(false)} onCreated={(id) => { setCreating(false); if (id) nav(`/contests/${id}`); else formatRequestApi.mine().then(setRequests).catch(() => {}) }} />}
    </div>
  )
}

function ContestCard({ c, onClick }: { c: Contest; onClick: () => void }) {
  const tstat = timelineStatus(c)
  
  let statusBadge = "badge-neutral"
  if (c.status === 'PENDING_APPROVAL') statusBadge = "badge-warning"
  else if (tstat === 'ONGOING') statusBadge = "badge-success"
  else if (tstat === 'UPCOMING') statusBadge = "badge-info"
  
  const joinedLabel = tstat === 'UPCOMING' ? 'Starts' : tstat === 'COMPLETED' ? 'Ended' : 'Ends'
  const joinedTime = tstat === 'UPCOMING' ? c.start_time : c.end_time

  return (
    <motion.div 
      className="break-inside-avoid cursor-pointer group" 
      variants={fadeUp} 
      onClick={onClick}
    >
      <div className="card bg-base-100 shadow-sm border border-base-200 hover:shadow-xl hover:border-primary/30 transition-all duration-300 h-full overflow-hidden">
        {/* Top Accent Strip */}
        <div className={`h-1.5 w-full ${tstat === 'ONGOING' ? 'bg-success' : tstat === 'UPCOMING' ? 'bg-info' : 'bg-neutral/20'}`} />
        
        <div className="card-body p-6">
          <div className="flex justify-between items-start mb-3 gap-2">
            <div className={`badge badge-sm font-semibold uppercase tracking-wider ${statusBadge}`}>
              {c.status === 'PENDING_APPROVAL' ? 'Pending' : tstat}
            </div>
            <div className="flex flex-wrap justify-end gap-1.5 text-xs opacity-70 font-medium">
              <span className="bg-base-200 px-2 py-0.5 rounded-full">
                {c.contest_type === 'leetcode' ? 'Algorithms' : c.contest_type === 'chess' ? 'Chess' : c.contest_type.toUpperCase()}
              </span>
              <span className="bg-base-200 px-2 py-0.5 rounded-full">{c.ranking_strategy}</span>
            </div>
          </div>
          
          <h3 className="card-title text-2xl font-bold leading-tight mt-1 mb-3 group-hover:text-primary transition-colors">
            {c.title}
          </h3>
          
          <div className="flex flex-wrap gap-2 mb-4">
            {c.user_role && <div className="badge badge-accent badge-outline font-medium text-xs">{c.user_role}</div>}
            {c.requires_invitation_code && <div className="badge badge-outline font-medium text-xs gap-1"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" className="w-3 h-3"><path fillRule="evenodd" d="M8 1a3.5 3.5 0 0 0-3.5 3.5V7A1.5 1.5 0 0 0 3 8.5v5A1.5 1.5 0 0 0 4.5 15h7a1.5 1.5 0 0 0 1.5-1.5v-5A1.5 1.5 0 0 0 11.5 7V4.5A3.5 3.5 0 0 0 8 1Zm2 6V4.5a2 2 0 1 0-4 0V7h4Z" clipRule="evenodd" /></svg> Private</div>}
          </div>
          
          <p className="text-base-content/80 text-sm line-clamp-3 mb-6">
            {c.judging_description || "No description provided."}
          </p>
          
          <div className="mt-auto pt-4 border-t border-base-200 flex justify-between items-center text-sm">
            <div className="font-medium text-base-content/70">
              {joinedLabel} <span className="text-base-content">{fmtRel(joinedTime)}</span>
            </div>
            <div className="opacity-60 text-xs font-semibold uppercase tracking-wider">
              {c.max_participants ? `${c.max_participants} Spots` : 'Open'}
            </div>
          </div>
        </div>
      </div>
    </motion.div>
  )
}
