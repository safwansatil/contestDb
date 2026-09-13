import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { contestApi, formatRequestApi, apiError, type Contest, type ContestTypeRequest } from '../lib/api'
import { fmtRel, timelineStatus } from '../lib/format'
import { CreateContestModal } from '../components/CreateContestModal'
import { useAuth } from '../lib/auth'
import { useToast } from '../lib/toast'

const TIMELINES = ['ALL', 'ONGOING', 'UPCOMING', 'COMPLETED']
export function Dashboard() {
  const [contests, setContests] = useState<Contest[] | null>(null); const [q, setQ] = useState(''); const [timeline, setTimeline] = useState('ALL'); const [creating, setCreating] = useState(false); const [requests, setRequests] = useState<ContestTypeRequest[]>([])
  const toast = useToast(); const { user } = useAuth(); const nav = useNavigate()
  async function load() { try { const params: Record<string,string> = {}; if(q.trim()) params.q=q.trim(); if(timeline !== 'ALL') params.timeline=timeline; setContests(await contestApi.list(params)) } catch(e) { toast(apiError(e),'err'); setContests([]) } }
  useEffect(() => { const delay = setTimeout(load, 220); return () => clearTimeout(delay) }, [q,timeline])
  useEffect(() => { formatRequestApi.mine().then(setRequests).catch(() => setRequests([])) }, [])
  const visible = useMemo(() => (contests || []).filter((c) => c.status !== 'PENDING_APPROVAL' || c.user_role === 'HOST' || c.user_role === 'MODERATOR'), [contests])
  return <main className="editorial-page">
    <header className="page-heading"><div><span className="index">01 / Field notes</span><h1>Explore<br/><em>contests.</em></h1><p>Choose a room, read its rules, and take your place on the board.</p></div>{!user?.is_developer && <button className="btn primary" onClick={() => setCreating(true)}>+ Host a contest</button>}</header>
    <section className="explore-controls"><input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search the index…" aria-label="Search contests" /><div className="timeline-filter">{TIMELINES.map((item) => <button key={item} className={timeline === item ? 'on' : ''} onClick={() => setTimeline(item)}>{item.toLowerCase()}</button>)}</div></section>
    {contests === null ? <div className="empty">Loading the index…</div> : visible.length === 0 ? <div className="empty">No contests match this edition. <button className="btn" onClick={() => {setQ('');setTimeline('ALL')}}>Reset filters</button></div> : <motion.section className="contest-editorial-grid" initial="hidden" animate="show" variants={{show:{transition:{staggerChildren:.05}}}}>{visible.map((c,i) => <ContestCard key={c.id} c={c} index={i+1} onClick={() => nav(`/contests/${c.id}`)} />)}</motion.section>}
    {requests.length > 0 && <section style={{marginTop:70}}><div className="page-heading" style={{paddingTop:0}}><div><span className="index">Your desk</span><h2 style={{fontSize:40}}>Format requests</h2></div></div><div className="request-grid">{requests.map((r) => <article className="request-note" key={r.id}><span className="label">{r.status}</span><h3 style={{fontSize:24,margin:'12px 0 8px'}}>{r.title}</h3><p className="dim">{r.requested_type.replace('_',' ')} · {r.rules_description}</p>{r.developer_note && <p className="mono" style={{fontSize:11}}>Editor’s note: {r.developer_note}</p>}</article>)}</div></section>}
    {creating && <CreateContestModal onClose={() => setCreating(false)} onCreated={(id) => { setCreating(false); if(id) nav(`/contests/${id}`); else formatRequestApi.mine().then(setRequests).catch(() => {}) }} />}
  </main>
}
function ContestCard({c,index,onClick}:{c:Contest;index:number;onClick:()=>void}) {
  const status = timelineStatus(c); const point = status === 'ONGOING' ? '● LIVE' : status === 'UPCOMING' ? '○ UPCOMING' : '— ARCHIVED'; const when = status === 'UPCOMING' ? c.start_time : c.end_time
  return <motion.button className="contest-editorial-card" onClick={onClick} variants={{hidden:{opacity:0,y:16},show:{opacity:1,y:0}}}><span className="card-no">#{String(index).padStart(2,'0')} · {point}</span><h3>{c.title}</h3><p className="dim">{c.judging_description || 'Rules and scoring information inside.'}</p><div className="card-meta"><span>{c.contest_type === 'leetcode' ? 'Algorithms' : c.contest_type}</span><span>{status === 'COMPLETED' ? 'Ended' : status === 'UPCOMING' ? 'Starts' : 'Ends'} {fmtRel(when)}</span></div></motion.button>
}
