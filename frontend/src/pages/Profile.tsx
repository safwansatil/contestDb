import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { userApi } from '../lib/api'
import { fmtDate, verdictClass, verdictColor } from '../lib/format'
import { Page, Loader, Empty, RankBadge } from '../components/ui'

interface ProfileData {
  user_id: number; username: string; created_at: string
  stats: {
    total_submissions: number; total_contests_joined: number; unique_tasks_attempted: number
    fully_completed_tasks: number; average_score: number; max_score_single: number
    verdict_breakdown: Record<string, number>
  }
  activity_graph: { date: string; count: number }[]
}
interface History {
  contest_history: { contest_id: number; contest_title: string; role: string; total_score: number | null; rank: number | null }[]
}

export function Profile() {
  const { id } = useParams()
  const uid = Number(id)
  const nav = useNavigate()
  const [p, setP] = useState<ProfileData | null>(null)
  const [h, setH] = useState<History | null>(null)

  useEffect(() => {
    setP(null)
    userApi.profile(uid).then(setP).catch(() => setP(null))
    userApi.history(uid).then(setH).catch(() => setH(null))
  }, [uid])

  if (!p) return <Loader label="Loading profile…" />
  const st = p.stats
  const verdicts = Object.entries(st.verdict_breakdown || {})
  const totalV = verdicts.reduce((a, [, n]) => a + n, 0) || 1

  // build a 18-week heatmap keyed by date -> count
  const byDate = new Map(p.activity_graph.map((a) => [a.date, a.count]))
  const cells: { date: string; count: number }[] = []
  const start = new Date(); start.setDate(start.getDate() - 18 * 7)
  for (let i = 0; i < 18 * 7; i++) {
    const d = new Date(start); d.setDate(start.getDate() + i)
    const key = d.toISOString().slice(0, 10)
    cells.push({ date: key, count: byDate.get(key) || 0 })
  }
  const lvl = (n: number) => (n === 0 ? '' : n < 2 ? 'l1' : n < 4 ? 'l2' : n < 7 ? 'l3' : 'l4')

  return (
    <Page>
      <div className="editorial-page">
        <div className="profile-cover">
          <div className="profile-main"><span className="label" style={{color:'inherit'}}>Competitor file / {p.user_id}</span><h1>{p.username}</h1><p className="mono" style={{fontSize:11}}>ON THE BOARD SINCE {fmtDate(p.created_at)}</p></div>
          <div className="profile-stats">{[['Avg score', st.average_score.toFixed(1)], ['Best', st.max_score_single], ['Contests', st.total_contests_joined], ['Submissions', st.total_submissions]].map(([l, n]) => <div key={l}><strong>{n}</strong><span className="label" style={{display:'block',marginTop:6}}>{l}</span></div>)}</div>
        </div>

        <div className="glass pad-lg" style={{ marginBottom: 18 }}>
          <div className="label" style={{ marginBottom: 14 }}>Submission activity · last 18 weeks</div>
          <div style={{ overflowX: 'auto' }}>
            <div className="heat">{cells.map((c) => <i key={c.date} className={lvl(c.count)} title={`${c.date}: ${c.count}`} />)}</div>
          </div>
          <div className="row faint" style={{ gap: 6, justifyContent: 'flex-end', marginTop: 12, fontSize: 11 }}>
            Less <span className="heat" style={{ display: 'inline-flex', gridAutoFlow: 'column' }}>
              <i /><i className="l1" /><i className="l2" /><i className="l3" /><i className="l4" /></span> More
          </div>
        </div>

        <div className="two-col">
          <div className="glass" style={{ overflow: 'hidden' }}>
            <div className="pad" style={{ borderBottom: '1px solid var(--glass-border)' }}><div className="label">Contest history</div></div>
            {!h || h.contest_history.length === 0 ? <Empty>No contests yet.</Empty> :
              h.contest_history.map((c) => (
                <div key={c.contest_id} className="member" style={{ cursor: 'pointer' }} onClick={() => nav(`/contests/${c.contest_id}`)}>
                  {c.rank ? <RankBadge rank={c.rank} /> : <span className="rank mono faint" style={{ width: 28, textAlign: 'center' }}>–</span>}
                  <div className="grow"><b>{c.contest_title}</b><div className="faint" style={{ fontSize: 12 }}>{c.role}</div></div>
                  <span className="mono" style={{ fontWeight: 700 }}>{c.total_score ?? '–'}</span>
                </div>
              ))}
          </div>
          <div className="glass pad">
            <div className="label" style={{ marginBottom: 14 }}>Verdict breakdown</div>
            {verdicts.length === 0 ? <p className="faint" style={{ margin: 0, fontSize: 13 }}>No submissions yet.</p> :
              verdicts.map(([v, n]) => (
                <div key={v} className="vrow">
                  <span className={`pill ${verdictClass(v)}`} style={{ minWidth: 118, justifyContent: 'center' }}>{v}</span>
                  <div className="track"><span style={{ width: `${(n / totalV) * 100}%`, background: verdictColor(v) }} /></div>
                  <span className="mono" style={{ fontWeight: 700, minWidth: 24, textAlign: 'right' }}>{n}</span>
                </div>
              ))}
          </div>
        </div>
      </div>
    </Page>
  )
}
