import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { motion } from 'framer-motion'
import {
  contestApi, apiError, type Contest, type Task, type LeaderRow, type Announcement, type Member,
} from '../lib/api'
import { fmtDate, fmtRel, timelineStatus, isFrozen, statusColor, isAdmin } from '../lib/format'
import { useAuth } from '../lib/auth'
import { useToast } from '../lib/toast'
import { Page, Loader, Empty, Pill, RankBadge, Avatar, Modal, Spinner } from '../components/ui'
import { CreateTaskModal } from '../components/CreateTaskModal'
import { SubmitModal } from '../components/SubmitModal'
import { IconSeal, IconEye, IconArrowLeft } from '../components/icons'
import { Chess } from 'chess.js'
import { Chessboard } from 'react-chessboard'
import { submissionApi, userApi } from '../lib/api'

const TABS = (c: Contest, admin: boolean) => [
  ['overview', 'Overview', null],
  ...((c.visibility.show_task_list || admin ? [['tasks', 'Tasks', null]] : []) as [string, string, null][]),
  ['submissions', 'Submissions', null],
  ...((c.visibility.show_leaderboard || admin ? [['leaderboard', 'Leaderboard', null]] : []) as [string, string, null][]),
  ...((c.visibility.show_statistics || admin ? [['stats', 'Statistics', null]] : []) as [string, string, null][]),
  ['announcements', 'Announcements', null],
  ...((admin ? [['manage', 'Manage', null]] : []) as [string, string, null][]),
] as [string, string, null][]

export function ContestDetail() {
  const { id } = useParams()
  const cid = Number(id)
  const { user } = useAuth()
  const toast = useToast()
  const nav = useNavigate()
  const [c, setC] = useState<Contest | null>(null)
  const [tab, setTab] = useState('overview')
  const [enrolled, setEnrolled] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [enrolling, setEnrolling] = useState(false)
  const [tasks, setTasks] = useState<Task[]>([])

  const load = useCallback(async () => {
    try {
      const data = await contestApi.get(cid)
      setC(data)
      setEnrolled(data.user_role === 'PARTICIPANT')
      setTasks(await contestApi.tasks(cid).catch(() => []))
    } catch (e) { toast(apiError(e), 'err') }
  }, [cid, toast])

  useEffect(() => { load() }, [load])

  if (!c) return <Loader label="Loading contest…" />

  const role = c.user_role
  const admin = isAdmin(role)
  const tstat = timelineStatus(c)
  const frozen = isFrozen(c)

  function primaryAction() {
    if (admin) return { label: '⚙ Manage contest', fn: () => setTab('manage') }
    if (enrolled) {
      if (
        tstat === 'ONGOING' &&
        c!.status === 'ACTIVE' &&
       !['chess', 'icpc'].includes(
  c!.contest_type ?? '',
)
      ) {
        return {
          label: '↑ Submit solution',
          fn: () => setSubmitting(true)
        }
      }
      return { label: '✓ Enrolled', fn: () => {}, disabled: true }
    }
    if (tstat === 'COMPLETED') return { label: 'Contest ended', fn: () => {}, disabled: true }
    if (tstat === 'ONGOING' && !c!.allow_late_enrollment) return { label: 'Enrollment closed', fn: () => {}, disabled: true }
    return { label: c!.requires_invitation_code ? '🔒 Enroll with code' : '＋ Enroll', fn: () => setEnrolling(true) }
  }
  const action = primaryAction()

  return (
    <Page>
      <div className="contest-paper">
        <button className="btn ghost sm" onClick={() => nav('/app')} style={{ marginBottom: 14 }}><IconArrowLeft size={15} /> Explore</button>

        {/* Hero */}
        <div className="glass chero">
          <div className="row" style={{ justifyContent: 'space-between', gap: 20, flexWrap: 'wrap', alignItems: 'flex-start' }}>
            <div style={{ flex: 1, minWidth: 260 }}>
              <div className="wrap-row" style={{ marginBottom: 11 }}>
                <Pill className="tag-neutral" dot={statusColor(c.status)}><span style={{ color: statusColor(c.status) }}>{c.status.replace('_', ' ')}</span></Pill>
                <span className="strat">{c.ranking_strategy}</span>
                {role && <Pill className="tag-gold">You are {role}</Pill>}
              </div>
              <h1>{c.title}</h1>
              <p className="dim" style={{ margin: '11px 0 0', maxWidth: '60ch' }}>{c.judging_description}</p>
            </div>
            <div style={{ textAlign: 'right' }}>
              <div className="label" style={{ marginBottom: 8 }}>
                {tstat === 'UPCOMING' ? 'Starts in' : tstat === 'ONGOING' ? 'Ends in' : 'Contest ended'}
              </div>
              {tstat !== 'COMPLETED'
                ? <Countdown target={tstat === 'UPCOMING' ? c.start_time : c.end_time} />
                : <div className="mono dim" style={{ fontSize: 13 }}>{fmtDate(c.end_time)}</div>}
              <div style={{ marginTop: 14 }}>
                <button className="btn primary" onClick={action.fn} disabled={action.disabled}>{action.label}</button>
              </div>
            </div>
          </div>
          <Timeline c={c} />
        </div>

        {c.status === 'PENDING_APPROVAL' && admin &&
          <div className="notice" style={{ margin: '16px 0' }}>⏳ Awaiting developer approval — a terminal-only action: <span className="k">SELECT approve_contest_native({c.id});</span></div>}

        {/* Tabs */}
        <div className="tabs">
          {TABS(c, admin).map(([k, l]) => (
            <button key={k} className={tab === k ? 'on' : ''} onClick={() => setTab(k)}>
              {l}{k === 'tasks' && tasks.length ? <span className="badge">{tasks.length}</span> : null}
            </button>
          ))}
        </div>

        <motion.div key={tab} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.25 }}>
          {tab === 'overview' && <Overview c={c} tasks={tasks} admin={admin} onFullLb={() => setTab('leaderboard')} />}
          {tab === 'tasks' && <Tasks c={c} tasks={tasks} admin={admin} enrolled={enrolled} tstat={tstat} onSubmit={() => setSubmitting(true)} onRefresh={load} />}
          {tab === 'submissions' && <Submissions contest={c} />}
          {tab === 'leaderboard' && <Leaderboard c={c} admin={admin} frozen={frozen} meId={user?.id} />}
          {tab === 'stats' && <Stats c={c} />}
          {tab === 'announcements' && <Announcements c={c} admin={admin} />}
          {tab === 'manage' && admin && <Manage c={c} onChange={load} />}
        </motion.div>
      </div>

      {submitting && tasks.length > 0 &&
        <SubmitModal contest={c} tasks={tasks} onClose={() => setSubmitting(false)} onJudged={() => { /* leaderboard refreshes on tab open */ }} />}
      {enrolling &&
        <EnrollModal c={c} onClose={() => setEnrolling(false)} onEnrolled={() => { setEnrolling(false); load() }} />}
    </Page>
  )
}

/* ---------------- Countdown ---------------- */
function Countdown({ target }: { target: string }) {
  const [now, setNow] = useState(Date.now())

  useEffect(() => {
    const timer = window.setInterval(() => {
      setNow(Date.now())
    }, 1000)

    return () => {
      window.clearInterval(timer)
    }
  }, [])

  const targetTime = new Date(target).getTime()
  const difference = Math.max(0, targetTime - now)

  const hours = Math.floor(difference / 3_600_000)
  const minutes = Math.floor(
    (difference % 3_600_000) / 60_000
  )
  const seconds = Math.floor(
    (difference % 60_000) / 1_000
  )

  const unit = (
    value: number,
    label: string,
  ) => (
    <div className="cd-unit">
      <b>{String(value).padStart(2, '0')}</b>
      <small>{label}</small>
    </div>
  )

  return (
    <div
      className="contest-countdown"
      aria-label={`Time remaining: ${hours} hours, ${minutes} minutes and ${seconds} seconds`}
    >
      {unit(hours, 'hrs')}
      {unit(minutes, 'min')}
      {unit(seconds, 'sec')}
    </div>
  )
}

/* ---------------- Timeline ---------------- */
function Timeline({ c }: { c: Contest }) {
  const now = Date.now()
  const pts: [string, number][] = [['Start', new Date(c.start_time).getTime()], ['Freeze', new Date(c.freeze_time).getTime()], ['End', new Date(c.end_time).getTime()]]
  return (
    <div className="timeline">
      {pts.map(([label, t], i) => {
        const reached = now >= t
        const isNow = reached && (i + 1 >= pts.length || now < pts[i + 1][1])
        return (
          <div key={label} style={{ display: 'contents' }}>
            <div className="tl-node">
              <div className={`tl-dot ${reached ? (isNow ? 'now' : 'done') : ''}`} />
              <div className="center"><div className="label" style={{ fontSize: 10 }}>{label}</div>
                <div className="mono faint" style={{ fontSize: 10.5 }}>{fmtDate(c[i === 0 ? 'start_time' : i === 1 ? 'freeze_time' : 'end_time']).split(',')[0]}</div></div>
            </div>
            {i < pts.length - 1 && <div className={`tl-line ${now >= pts[i + 1][1] ? 'done' : ''}`} />}
          </div>
        )
      })}
    </div>
  )
}

/* ---------------- Overview ---------------- */
function Overview({ c, tasks, admin, onFullLb }: { c: Contest; tasks: Task[]; admin: boolean; onFullLb: () => void }) {
  const [lb, setLb] = useState<LeaderRow[]>([])
  const [ann, setAnn] = useState<Announcement[]>([])
  const [info, setInfo] = useState<{ current_participants: number; spots_remaining: number | null } | null>(null)
  useEffect(() => {
    if (c.visibility.show_leaderboard || admin) contestApi.leaderboard(c.id).then((r) => setLb(r.leaderboard.slice(0, 3))).catch(() => {})
    contestApi.announcements(c.id).then(setAnn).catch(() => {})
    contestApi.enrollmentInfo(c.id).then(setInfo).catch(() => {})
  }, [c.id, admin, c.visibility.show_leaderboard])
  void tasks
  return (
    <div className="two-col">
      <div className="grid">
        <div className="glass pad-lg">
          <div className="label" style={{ marginBottom: 10 }}>Judging & rules</div>
          <p style={{ margin: '0 0 16px' }}>{c.judging_description}</p>
          <div className="wrap-row" style={{ gap: 24, fontSize: 13 }}>
            <div><div className="label">Strategy</div><b className="mono">{c.ranking_strategy}</b></div>
            <div><div className="label">Late enroll</div><b>{c.allow_late_enrollment ? 'Allowed' : 'Closed at start'}</b></div>
            <div><div className="label">Capacity</div><b className="mono">{c.max_participants ?? '∞'}</b></div>
          </div>
        </div>
        {ann[0] && (
          <div className="glass ann">
            <div className="label" style={{ marginBottom: 8 }}>📣 Latest announcement</div>
            <h4>{ann[0].title}</h4><p className="dim" style={{ margin: '4px 0 0' }}>{ann[0].body}</p>
            <div className="by">{ann[0].author} · {fmtRel(ann[0].posted_at)}</div>
          </div>
        )}
        {(c.visibility.show_leaderboard || admin) && (
          <div className="glass pad-lg">
            <div className="row" style={{ justifyContent: 'space-between', marginBottom: 12 }}>
              <div className="label">Top standings</div>
              <button className="btn ghost sm" onClick={onFullLb}>View full →</button>
            </div>
            {lb.length === 0 ? <p className="faint" style={{ fontSize: 13, margin: 0 }}>No submissions yet.</p> :
              lb.map((r) => (
                <div key={r.user_id} className="row" style={{ padding: '8px 0', borderBottom: '1px solid var(--glass-border)' }}>
                  <RankBadge rank={r.rank} /><b style={{ marginLeft: 12 }}>{r.username}</b>
                  <div className="grow" /><span className="mono" style={{ fontWeight: 750 }}>{r.total_score}</span>
                </div>
              ))}
          </div>
        )}
      </div>
      <div className="grid">
        <div className="glass pad">
          <div className="label" style={{ marginBottom: 12 }}>Schedule (UTC-synced)</div>
          {[['Start', c.start_time], ['Freeze', c.freeze_time], ['End', c.end_time]].map(([l, t]) => (
            <div key={l} className="row" style={{ justifyContent: 'space-between', padding: '7px 0', borderBottom: '1px solid var(--glass-border)' }}>
              <span className="dim">{l}</span><span className="mono" style={{ fontSize: 12.5 }}>{fmtDate(t as string)}</span>
            </div>
          ))}
        </div>
        {(c.visibility.show_participant_count || admin) && info && (
          <div className="glass pad">
            <div className="label" style={{ marginBottom: 8 }}>Enrollment</div>
            <div className="mono" style={{ fontSize: 30, fontWeight: 800 }}>{info.current_participants}{c.max_participants ? <span className="faint" style={{ fontSize: 16 }}> / {c.max_participants}</span> : ''}</div>
            <div className="dim" style={{ fontSize: 12.5 }}>participants{c.max_participants ? ` · ${info.spots_remaining} spots left` : ' · unlimited'}</div>
          </div>
        )}
        {admin && c.invitation_code && (
          <div className="glass pad">
            <div className="label" style={{ marginBottom: 8 }}>🔑 Invitation code</div>
            <div className="mono" style={{ fontSize: 18, fontWeight: 700, letterSpacing: '.05em' }}>{c.invitation_code}</div>
            <div className="faint" style={{ fontSize: 11.5, marginTop: 4 }}>Visible to hosts & moderators only</div>
          </div>
        )}
      </div>
    </div>
  )
}

/* ---------------- Tasks ---------------- */
function Tasks({ c, tasks, admin, enrolled, tstat, onSubmit, onRefresh }: { c: Contest; tasks: Task[]; admin: boolean; enrolled: boolean; tstat: string; onSubmit: () => void; onRefresh: () => void }) {
  const [creating, setCreating] = useState(false)
  const canSubmit = enrolled && tstat === 'ONGOING' && c.status === 'ACTIVE'
  if (c.contest_type === 'icpc') return <IcpcArena contest={c} tasks={tasks} canSubmit={canSubmit} admin={admin} onAddTask={() => setCreating(true)} />
  if (c.contest_type === 'chess') return <ChessArena contest={c} tasks={tasks} canSubmit={canSubmit} />
  if (c.contest_type === 'ctf') return <CtfArena contest={c} tasks={tasks} canSubmit={canSubmit} />
  return (
    <div className="grid">
      <div className="row" style={{ justifyContent: 'space-between', marginBottom: 8 }}>
        <h3 style={{ margin: 0 }}>Tasks</h3>
        {admin && <button className="btn primary sm" onClick={() => setCreating(true)}>Add New Task</button>}
      </div>
      {tasks.length === 0 ? <div className="glass"><Empty icon="◲">No tasks published yet.</Empty></div> : (
        <div className="glass" style={{ overflow: 'hidden' }}>
          {tasks.map((t) => (
            <div className="task" key={t.id}>
              <div className="ord">{t.task_order}</div>
              <div className="grow">
                <h4>{t.title}</h4>
                <p className="dim" style={{ margin: 0, fontSize: 13 }}>{t.description}</p>
                <div className="schema">
                  <span className="label">payload</span>
                    {t.submission_schema.required_keys?.map((k) => (
                      <span key={k} className={`chip ${t.submission_schema.numeric_keys?.includes(k) ? 'num' : ''}`}>
                        {k}{t.submission_schema.numeric_keys?.includes(k) ? ' :num' : ''}
                      </span>
                    ))}
                  {t.submission_cooldown_seconds > 0 && <span className="chip">⏱ {t.submission_cooldown_seconds}s</span>}
                </div>
              </div>
              <div className="stack" style={{ alignItems: 'flex-end', gap: 8 }}>
                <span className="mono faint" style={{ fontSize: 12 }}>max {t.max_score}</span>
                {canSubmit && <button className="btn primary sm" onClick={onSubmit}>Submit</button>}
              </div>
            </div>
          ))}
        </div>
      )}
      {creating && <CreateTaskModal contestId={c.id} onClose={() => setCreating(false)} onCreated={() => { setCreating(false); onRefresh(); }} />}
    </div>
  )
}

const CODE_TEMPLATES: Record<string, string> = {
  python: '# Read input\n# Solve the problem\n\ndef solve():\n    pass\n\nif __name__ == "__main__":\n    solve()\n',
  cpp: '#include <bits/stdc++.h>\nusing namespace std;\n\nint main() {\n    ios::sync_with_stdio(false);\n    cin.tie(nullptr);\n\n    // solve\n    return 0;\n}\n',
  java: 'import java.io.*;\nimport java.util.*;\n\npublic class Main {\n    public static void main(String[] args) throws Exception {\n        // solve\n    }\n}\n',
}

function IcpcArena({ contest, tasks, canSubmit, admin, onAddTask }: { contest: Contest; tasks: Task[]; canSubmit: boolean; admin: boolean; onAddTask: () => void }) {
  const [activeId, setActiveId] = useState(tasks[0]?.id)
  const [language, setLanguage] = useState('python')
  const [code, setCode] = useState(CODE_TEMPLATES.python)
  const [status, setStatus] = useState<'idle' | 'queued'>('idle')
  const toast = useToast()
  const active = tasks.find((t) => t.id === activeId) || tasks[0]
  const selectProblem = (task: Task) => { setActiveId(task.id); setStatus('idle') }
  const changeLanguage = (next: string) => { setLanguage(next); setCode(CODE_TEMPLATES[next]) }
  async function submitCode() {
    if (!code.trim()) return toast('Write a solution before submitting.', 'err')
    if (!canSubmit) return toast('Only enrolled participants can submit while the contest is active.', 'err')
    try {
      const result = await submissionApi.create(contest.id, active.id, { source_code: code, language })
      setStatus('queued')
      toast(`Submission #${result.submission_id} added to the judge queue`, 'info')
    } catch (e) { toast(apiError(e), 'err') }
  }
  if (!active) return <div className="glass"><Empty>No problems published yet.</Empty></div>
  return <div className="code-arena">
    <aside className="problem-rail">
      <div className="rail-head"><div><span className="label">Problem set</span><b>{tasks.length} problems</b></div>{admin && <button className="btn ghost sm" onClick={onAddTask}>＋ Add</button>}</div>
      <div className="problem-list">{tasks.map((task) => <button key={task.id} className={`problem-link ${task.id === active.id ? 'active' : ''}`} onClick={() => selectProblem(task)}><span className="problem-letter">{String.fromCharCode(64 + task.task_order)}</span><span><b>{task.title.replace(/^[A-J]\.\s*/, '')}</b><small>{task.max_score} points</small></span><i>{task.id === active.id ? '›' : ''}</i></button>)}</div>
      <div className="rail-foot"><span className="live-dot" /> Live contest workspace</div>
    </aside>
    <main className="problem-pane">
      <div className="problem-toolbar"><div className="wrap-row"><span className="difficulty">ALGORITHM</span><span className="mono faint">Problem {String.fromCharCode(64 + active.task_order)}</span></div><div className="wrap-row"><button className="btn ghost sm" onClick={() => navigator.clipboard?.writeText(active.title).then(() => toast('Problem title copied', 'info')).catch(() => {})}>⧉ Share</button><span className="pill tag-gold">{active.max_score} pts</span></div></div>
      <article className="problem-statement"><h2>{active.title}</h2><p className="lead">{active.description}</p><div className="statement-grid"><section><h4>Input</h4><p>Read the input from standard input. Handle the stated constraints efficiently.</p></section><section><h4>Output</h4><p>Write the required answer to standard output for every valid test case.</p></section></div><section className="constraint-box"><span>⌘</span><div><b>Contest note</b><p>Your solution is judged asynchronously. Use the editor to submit; standings update once the worker records a verdict.</p></div></section></article>
    </main>
    <section className="editor-pane">
      <div className="editor-toolbar"><div className="file-tab"><span className="file-dot" />solution.{language === 'python' ? 'py' : language === 'cpp' ? 'cpp' : 'java'}</div><select aria-label="Language" value={language} onChange={(e) => changeLanguage(e.target.value)}><option value="python">Python 3</option><option value="cpp">C++17</option><option value="java">Java 21</option></select></div>
      <div className="editor-wrap"><div className="line-numbers">{Array.from({ length: Math.max(12, code.split('\n').length) }, (_, i) => <span key={i}>{i + 1}</span>)}</div><textarea aria-label="Solution editor" value={code} onChange={(e) => { setCode(e.target.value); setStatus('idle') }} spellCheck={false} /></div>
      <div className="editor-footer"><span className={`judge-state ${status === 'queued' ? 'queued' : ''}`}>{status === 'queued' ? '● Queued for judging' : '● Ready to submit'}</span><div className="row"><button className="btn ghost sm" onClick={() => setCode(CODE_TEMPLATES[language])}>Reset</button><button className="btn primary" onClick={submitCode}>Submit solution →</button></div></div>
    </section>
  </div>
}

function ChessArena({ contest, tasks, canSubmit }: { contest: Contest; tasks: Task[]; canSubmit: boolean }) {
  return <div><div className="notice" style={{ marginBottom: 16 }}>♟ Puzzle arena — find checkmate directly on the board. A completed mating line is sent to the judge queue.</div><div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(290px, 1fr))', rowGap: '5px' }}>{tasks.map((task) => <ChessLevel key={task.id} contest={contest} task={task} canSubmit={canSubmit} />)}</div></div>
}

function ChessLevel({
  contest,
  task,
  canSubmit
}: {
  contest: Contest
  task: Task
  canSubmit: boolean
}) {
  const initialPosition = '7k/6pp/8/7Q/8/8/6PP/6K1 w - - 0 1'

  const [game, setGame] = useState(() => new Chess(initialPosition))
  const [sent, setSent] = useState(false)
  const toast = useToast()

  function onDrop({
    sourceSquare,
    targetSquare
  }: {
    sourceSquare: string
    targetSquare: string | null
  }) {
    if (!targetSquare || sent) return false

    const next = new Chess(game.fen())

    const move = next.move({
      from: sourceSquare,
      to: targetSquare,
      promotion: 'q'
    })

    if (!move) return false

    // Only update the board.
    // DO NOT submit automatically.
    setGame(next)

    return true
  }

  async function submitChess() {
    if (!canSubmit) {
      return toast(
        'Enroll or wait for the contest to become active.',
        'err'
      )
    }

    if (game.history().length === 0) {
      return toast('Make a move before submitting.', 'err')
    }

    try {
      const result = await submissionApi.create(
        contest.id,
        task.id,
        {
          moves: game.history(),
          fen: game.fen()
        }
      )

      setSent(true)

      toast(
        `${task.title} submitted — submission #${result.submission_id} queued for judging`,
        'info'
      )
    } catch (e) {
      toast(apiError(e), 'err')
    }
  }

  function resetBoard() {
    setGame(new Chess(initialPosition))
    setSent(false)
  }

  return (
    <div className="glass pad">
      <div
        className="row"
        style={{
          justifyContent: 'space-between',
          marginBottom: 10
        }}
      >
        <div>
          <div className="label">
            Level {task.task_order}
          </div>

          <h3 style={{ margin: '4px 0' }}>
            {task.title}
          </h3>
        </div>

        <span className="pill tag-gold">
          {task.max_score} pts
        </span>
      </div>

      <p
        className="dim"
        style={{ fontSize: 13 }}
      >
        {task.description}
      </p>

      <div className="chess-board-wrap">
        <Chessboard
          options={{
            position: game.fen(),
            onPieceDrop: onDrop,
            boardOrientation: 'white'
          }}
        />
</div>

      <div
        className="row"
        style={{
          justifyContent: 'space-between',
          marginTop: 12
        }}
      >
        <span
          className="mono faint"
          style={{ fontSize: 11 }}
        >
          {game.history().join(' ') || 'White to move'}
        </span>

        <div className="row">
          <button
            className="btn ghost sm"
            onClick={resetBoard}
          >
            Reset
          </button>

          <button
            className="btn primary sm"
            disabled={sent}
            onClick={submitChess}
          >
            {sent ? 'Submitted' : 'Submit'}
          </button>
        </div>
      </div>

      {game.isCheckmate() && !sent && (
        <div
          className="notice"
          style={{ marginTop: 10 }}
        >
          ✓ Checkmate found. Click Submit to send your solution.
        </div>
      )}

      {sent && (
        <div
          className="notice"
          style={{ marginTop: 10 }}
        >
          ✓ Submission queued for judging.
        </div>
      )}
    </div>
  )
}

function CtfArena({ contest, tasks, canSubmit }: { contest: Contest; tasks: Task[]; canSubmit: boolean }) {
  return <section className="ctf-lab">
    <header className="ctf-masthead"><div><span className="label">CTFDB / Practice range</span><h2>First signals.</h2><p>Three safe, self-contained introductions to web inspection, encoding, and file metadata. There are no live targets and no tools beyond your browser or a local decoder.</p></div><aside><span className="label">Rules of engagement</span><ol><li>Submit exactly one flag per challenge.</li><li>Flags use <code>CTFDB&#123;...&#125;</code>.</li><li>Hints are free; points are fixed.</li></ol></aside></header>
    <div className="ctf-grid">{tasks.map((task) => <CtfChallenge key={task.id} contest={contest} task={task} canSubmit={canSubmit} />)}</div>
  </section>
}

function CtfChallenge({ contest, task, canSubmit }: { contest: Contest; task: Task; canSubmit: boolean }) {
  const [flag, setFlag] = useState(''); const [phase, setPhase] = useState<'ready' | 'queued' | 'correct' | 'wrong'>('ready')
  const toast = useToast()
  const { user } = useAuth()
  const brief = CTF_BRIEFS[task.task_order] || { category: 'General', time: '5 min', mission: task.description, evidence: 'No extra evidence supplied.', hint: 'Read the task statement closely.' }
  async function waitForVerdict(submissionId: number) { for (let i = 0; i < 15; i++) { await new Promise((resolve) => setTimeout(resolve, 1200)); try { const history = await userApi.history(user!.id); const found = history.submissions_history.find((item: { submission_id: number; verdict: string | null }) => item.submission_id === submissionId); if (found?.verdict) { const correct = found.verdict === 'CORRECT'; setPhase(correct ? 'correct' : 'wrong'); toast(correct ? `${task.title} solved — ${task.max_score} points` : 'Not this flag. Review the evidence and try again after the cooldown.', correct ? 'info' : 'err'); return } } catch { /* worker may still be processing */ } } setPhase('ready'); toast('Judging is taking longer than expected. Check your profile shortly.', 'info') }
  async function submitFlag() { if (!/^CTFDB\{.+\}$/.test(flag.trim())) return toast('Use the exact CTFDB{...} flag format.', 'err'); if (!canSubmit) return toast('Enroll or wait for the contest to become active.', 'err'); setPhase('queued'); try { const result = await submissionApi.create(contest.id, task.id, { flag: flag.trim() }); toast(`${task.title} entered the judge queue`, 'info'); await waitForVerdict(result.submission_id) } catch (e) { setPhase('ready'); toast(apiError(e), 'err') } }
  const locked = phase === 'queued' || phase === 'correct'
  return <article className={`ctf-card ${phase === 'correct' ? 'solved' : ''}`}><header><span className="ctf-number">{String(task.task_order).padStart(2, '0')}</span><div><span className="label">{brief.category} / easy</span><h3>{task.title}</h3></div><strong>{task.max_score}<small>pts</small></strong></header><div className="ctf-brief"><span className="label">Mission</span><p>{brief.mission}</p><span className="label">Evidence</span><pre>{brief.evidence}</pre><div className="ctf-meta"><span>EST. {brief.time}</span><span>20 SEC COOLDOWN</span></div><details><summary>Need a hint?</summary><p>{brief.hint}</p></details></div><div className="ctf-submit"><label htmlFor={`flag-${task.id}`}>{phase === 'correct' ? '✓ Flag accepted' : phase === 'queued' ? 'Judging your flag…' : phase === 'wrong' ? 'Try another flag' : 'Flag submission'}</label><div><input id={`flag-${task.id}`} value={flag} onChange={(e) => { setFlag(e.target.value); if (phase === 'wrong') setPhase('ready') }} placeholder="CTFDB{...}" disabled={locked} spellCheck={false} /><button className="btn primary" disabled={locked} onClick={submitFlag}>{phase === 'queued' ? 'Judging' : phase === 'correct' ? 'Solved' : 'Submit'}</button></div></div></article>
}

const CTF_BRIEFS: Record<number, { category: string; time: string; mission: string; evidence: string; hint: string }> = {
  1: { category: 'Web', time: '3 min', mission: 'The welcome page looks ordinary. Inspect the supplied HTML fragment and recover the author’s hidden note.', evidence: '<main>Welcome, competitor.</main>\n<!-- author-note: view_source_first -->', hint: 'Browsers let you inspect the page source or its elements. HTML comments are not displayed on the page.' },
  2: { category: 'Crypto', time: '5 min', mission: 'A compact radio transmission has been encoded for transport. Identify the encoding, decode it once, and submit the result.', evidence: 'Q1RGREJ7YmFzZTY0X2lzX2VuY29kaW5nfQ==', hint: 'The alphabet, padding characters, and length are clues. This is an encoding, not encryption.' },
  3: { category: 'Forensics', time: '6 min', mission: 'A responder left an evidence manifest. Follow the naming convention recorded in its metadata to reconstruct the flag.', evidence: 'case: LAB-03\nartifact: archive.jpg\ncomment: metadata matters\nflag style: CTFDB{comment_with_underscores}', hint: 'Use the value after “comment” and apply the declared flag style exactly.' },
}

function Submissions({ contest }: { contest: Contest }) {
  const [rows, setRows] = useState<any[] | null>(null)

  useEffect(() => {
    submissionApi
      .mine(contest.id)
      .then(setRows)
      .catch(() => setRows([]))
  }, [contest.id])

  if (rows === null) {
    return <Loader label="Loading submissions…" />
  }

  if (rows.length === 0) {
    return (
      <div className="glass">
        <Empty>No submissions yet.</Empty>
      </div>
    )
  }

  return (
    <div className="glass" style={{ overflow: 'hidden' }}>
      <table className="lb">
        <thead>
          <tr>
            <th>Task</th>
            <th>Status</th>
            <th>Verdict</th>
            <th style={{ textAlign: 'right' }}>Score</th>
            <th>Submitted</th>
          </tr>
        </thead>

        <tbody>
          {rows.map((s) => (
            <tr key={s.id}>
              <td>
                <b>
                  {String.fromCharCode(64 + s.task_order)}. {s.task_title}
                </b>
              </td>

              <td>
                <span className="mono">
                  {s.status}
                </span>
              </td>

              <td>
                <b
                  style={{
                    color:
                      s.verdict === 'AC'
                        ? 'var(--ac)'
                        : s.verdict
                        ? 'var(--wa)'
                        : 'var(--ink-faint)'
                  }}
                >
                  {s.verdict || '—'}
                </b>
              </td>

              <td
                className="mono"
                style={{ textAlign: 'right' }}
              >
                {s.status === 'COMPLETED' ? s.score : '—'}
              </td>

              <td className="mono faint">
                {fmtRel(s.submitted_at)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

/* ---------------- Leaderboard ---------------- */
function Leaderboard({ c, admin, frozen, meId }: { c: Contest; admin: boolean; frozen: boolean; meId?: number }) {
  const [rows, setRows] = useState<LeaderRow[] | null>(null)
  const [viewMode, setViewMode] = useState('')
  useEffect(() => { contestApi.leaderboard(c.id).then((r) => { setRows(r.leaderboard); setViewMode(r.view_mode) }).catch(() => setRows([])) }, [c.id])
  if (rows === null) return <Loader label="Loading standings…" />
  return (
    <div>
      {frozen && (admin
        ? <div className="freeze-banner admin"><span className="ic"><IconEye size={19} /></span><div><b>Admin view — live standings.</b> <span className="dim">Participants currently see the board sealed at {fmtDate(c.freeze_time)}.</span></div></div>
        : <div className="freeze-banner"><span className="ic"><IconSeal size={19} /></span><div><b>Standings sealed.</b> <span className="dim">Locked as of {fmtDate(c.freeze_time)}. Full results reveal when the contest ends.</span></div></div>)}
      <div className="glass" style={{ overflow: 'hidden' }}>
        <table className="lb">
          <thead><tr><th style={{ width: 70 }}>Rank</th><th>Participant</th><th style={{ textAlign: 'right' }}>{c.ranking_strategy === 'ICPC' ? 'Solved' : 'Score'}</th></tr></thead>
          <tbody>
            {rows.length === 0 ? <tr><td colSpan={3}><Empty>No submissions yet.</Empty></td></tr> :
              rows.map((r) => (
                <tr key={r.user_id} className={r.user_id === meId ? 'you' : ''}>
                  <td className="rank"><RankBadge rank={r.rank} /></td>
                  <td><div className="row" style={{ gap: 10 }}><Avatar name={r.username} size={28} /><b>{r.username}</b>{r.user_id === meId && <Pill className="tag-gold">you</Pill>}</div></td>
                  <td className="score">{r.total_score}</td>
                </tr>
              ))}
          </tbody>
        </table>
      </div>
      <div className="faint" style={{ fontSize: 11.5, marginTop: 8 }}>view mode: {viewMode} · freeze applied server-side</div>
    </div>
  )
}

/* ---------------- Stats ---------------- */
function Stats({ c }: { c: Contest }) {
  const [s, setS] = useState<{ total_participants: number; active_participants: number; total_submissions: number; task_statistics: unknown; submission_timeline: { count: number }[] } | null>(null)
  useEffect(() => { contestApi.statistics(c.id).then(setS).catch(() => setS(null)) }, [c.id])
  if (!s) return <Loader label="Loading statistics…" />
  const timeline = s.submission_timeline || []
  const max = Math.max(1, ...timeline.map((t) => t.count))
  return (
    <div className="grid">
      <div className="stat-grid">
        {[['Participants', s.total_participants], ['Active', s.active_participants], ['Submissions', s.total_submissions]].map(([l, n]) => (
          <div key={l} className="glass stat"><div className="n">{n}</div><div className="l">{l}</div></div>
        ))}
      </div>
      <div className="glass pad-lg">
        <div className="label" style={{ marginBottom: 14 }}>Submission activity over time</div>
        {timeline.length === 0 ? <p className="faint" style={{ margin: 0, fontSize: 13 }}>No activity yet.</p> :
          <div className="bars">{timeline.map((t, i) => <div key={i} style={{ height: `${Math.max(4, (t.count / max) * 100)}%` }} title={`${t.count} submissions`} />)}</div>}
      </div>
    </div>
  )
}

/* ---------------- Announcements ---------------- */
function Announcements({ c, admin }: { c: Contest; admin: boolean }) {
  const toast = useToast()
  const [items, setItems] = useState<Announcement[] | null>(null)
  const [posting, setPosting] = useState(false)
  const [title, setTitle] = useState(''); const [body, setBody] = useState('')
  const load = useCallback(() => { contestApi.announcements(c.id).then(setItems).catch(() => setItems([])) }, [c.id])
  useEffect(() => { load() }, [load])

  async function post() {
    if (!title.trim() || !body.trim()) return toast('Title and message are required', 'err')
    try { await contestApi.postAnnouncement(c.id, title.trim(), body.trim()); toast('Announcement published'); setTitle(''); setBody(''); setPosting(false); load() }
    catch (e) { toast(apiError(e), 'err') }
  }
  async function del(aid: number) {
    try { await contestApi.deleteAnnouncement(aid); toast('Announcement deleted'); load() } catch (e) { toast(apiError(e), 'err') }
  }
  if (items === null) return <Loader />
  return (
    <div className="grid">
      {admin && <div className="row" style={{ justifyContent: 'flex-end' }}><button className="btn primary sm" onClick={() => setPosting(true)}>＋ Post announcement</button></div>}
      {items.length === 0 ? <div className="glass"><Empty icon="📣">No announcements yet.</Empty></div> :
        <div className="glass" style={{ overflow: 'hidden' }}>
          {items.map((a) => (
            <div className="ann" key={a.id}>
              <div className="row" style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
                <h4>{a.title}</h4>{admin && <button className="btn ghost sm" onClick={() => del(a.id)} style={{ color: 'var(--wa)' }}>Delete</button>}
              </div>
              <p className="dim" style={{ margin: '4px 0 0' }}>{a.body}</p>
              <div className="by">{a.author} · {fmtRel(a.posted_at)}</div>
            </div>
          ))}
        </div>}
      {posting && (
        <Modal title="Post announcement" onClose={() => setPosting(false)}
          footer={<><button className="btn ghost" onClick={() => setPosting(false)}>Cancel</button><button className="btn primary" onClick={post}>Publish</button></>}>
          <div className="field"><label>Title</label><input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={150} placeholder="e.g. Round 2 released" /></div>
          <div className="field"><label>Message</label><textarea value={body} onChange={(e) => setBody(e.target.value)} placeholder="Write your announcement…" /></div>
        </Modal>
      )}
    </div>
  )
}

/* ---------------- Manage (host/mod) ---------------- */
function Manage({ c, onChange }: { c: Contest; onChange: () => void }) {
  const toast = useToast()
  const nav = useNavigate()
  const [members, setMembers] = useState<Member[] | null>(null)
  const [vis, setVis] = useState(c.visibility)
  const [kicking, setKicking] = useState<Member | null>(null)
  const load = useCallback(() => { contestApi.members(c.id).then(setMembers).catch((e) => { toast(apiError(e), 'err'); setMembers([]) }) }, [c.id, toast])
  useEffect(() => { load() }, [load])
    const moderatorCount =
    members?.filter(
      (member) =>
        member.role === 'MODERATOR',
    ).length ?? 0

  const moderatorCapacity =
    c.max_moderators ?? 0

  const moderatorCapacityReached =
    moderatorCount >= moderatorCapacity

  async function toggleVis(k: keyof typeof vis) {
    const next = { ...vis, [k]: !vis[k] }
    setVis(next)
    try { await contestApi.setVisibility(c.id, next); toast(`Visibility updated`, 'info') } catch (e) { toast(apiError(e), 'err'); setVis(vis) }
  }
  async function del() {
    if (!confirm('Delete this contest permanently?')) return
    try { await contestApi.remove(c.id); toast('Contest deleted'); nav('/app') } catch (e) { toast(apiError(e), 'err') }
  }

  const VIS: [keyof typeof vis, string][] = [
    ['show_leaderboard', 'Public leaderboard'], ['show_participant_count', 'Participant count'],
    ['show_member_list', 'Member list'], ['show_task_list', 'Task list before start'],
    ['show_statistics', 'Statistics & analytics'], ['show_submission_count', 'Submission counts'],
  ]
  return (
    <div className="grid">
      <div className="notice">⚙ Host console — every control maps to a role-guarded API endpoint.</div>
      <div className="glass" style={{ overflow: 'hidden' }}>
       <div
  className="pad row"
  style={{
    justifyContent: 'space-between',
    flexWrap: 'wrap',
    gap: 10,
    borderBottom:
      '1px solid var(--glass-border)',
  }}
>
  <div>
    <div className="label">
      Members & roles
    </div>

    <div
      className="dim"
      style={{
        marginTop: 4,
        fontSize: 12,
      }}
    >
      The host does not consume a moderator slot.
    </div>
  </div>

  <div
    className={
      moderatorCapacityReached
        ? 'moderator-capacity full'
        : 'moderator-capacity'
    }
  >
    <span>Moderators</span>

    <strong>
      {moderatorCount}
      {' / '}
      {moderatorCapacity}
    </strong>
  </div>
</div>{members === null ? <Loader /> : members.map((m) => (
          <div className="member" key={m.user_id}>
            <Avatar name={m.username} size={32} />
            <div className="grow"><b>{m.username}</b><div className="faint" style={{ fontSize: 12 }}>user #{m.user_id}</div></div>
            <Pill className={m.role === 'HOST' ? 'tag-gold' : m.role === 'MODERATOR' ? 'tag-pending' : 'tag-neutral'}>{m.role}</Pill>
            {m.role !== 'HOST' && (
              <div className="row" style={{ gap: 6 }}>
               <RoleSelect
  c={c}
  m={m}
  moderatorCapacityReached={
    moderatorCapacityReached
  }
  onDone={load}
/>
                <button className="btn danger sm" onClick={() => setKicking(m)}>Kick</button>
              </div>
            )}
          </div>
        ))}
      </div>
      <div className="glass pad">
        <div className="label" style={{ marginBottom: 14 }}>Public visibility</div>
        <div className="grid" style={{ gap: 11 }}>
          {VIS.map(([k, l]) => (
            <label key={k} className="row" style={{ justifyContent: 'space-between', cursor: 'pointer' }} onClick={() => toggleVis(k)}>
              <span>{l}</span><span className={`switch ${vis[k] ? 'on' : ''}`}><i /></span>
            </label>
          ))}
        </div>
      </div>
      <div className="glass pad" style={{ borderColor: 'var(--wa-soft)' }}>
        <div className="label" style={{ marginBottom: 8, color: 'var(--wa)' }}>Danger zone</div>
        <button className="btn danger sm" onClick={del}>Delete contest</button>
      </div>
      {kicking && <KickModal c={c} member={kicking} onClose={() => setKicking(null)} onKicked={() => { setKicking(null); load(); onChange() }} />}
    </div>
  )
}
function RoleSelect({
  c,
  m,
  moderatorCapacityReached,
  onDone,
}: {
  c: Contest
  m: Member
  moderatorCapacityReached: boolean
  onDone: () => void
}) {
  const toast = useToast()
  const [pendingRole, setPendingRole] = useState<string | null>(null)
  const alreadyModerator = m.role === 'MODERATOR'

  function requestChange(role: string) {
    if (role === m.role) return

    if (role === 'MODERATOR' && moderatorCapacityReached && !alreadyModerator) {
      toast('Moderator capacity reached', 'err')
      return
    }

    setPendingRole(role)
  }

  async function confirmChange() {
    if (!pendingRole) return

    try {
      await contestApi.setRole(c.id, m.user_id, pendingRole)
      toast(`Role updated to ${pendingRole}`)
      setPendingRole(null)
      onDone()
    } catch (e) {
      toast(apiError(e), 'err')
    }
  }

  return (
    <>
      <select
        aria-label={`Change ${m.username}'s role`}
        style={{ width: 'auto', padding: '6px 8px', fontSize: 12 }}
        value={m.role || 'PARTICIPANT'}
        onChange={(e) => requestChange(e.target.value)}
      >
        <option value="PARTICIPANT">Participant</option>

        <option
          value="MODERATOR"
          disabled={moderatorCapacityReached && !alreadyModerator}
        >
          Moderator
          {moderatorCapacityReached && !alreadyModerator
            ? ' — capacity reached'
            : ''}
        </option>
      </select>

      {pendingRole && (
        <Modal
          title="Confirm role change"
          onClose={() => setPendingRole(null)}
          footer={
            <>
              <button className="btn ghost" onClick={() => setPendingRole(null)}>
                No
              </button>
              <button className="btn primary" onClick={confirmChange}>
                Yes
              </button>
            </>
          }
        >
          <div className="notice">
            Change {m.username}'s role to {pendingRole}?
          </div>
        </Modal>
      )}
    </>
  )
}

function KickModal({ c, member, onClose, onKicked }: { c: Contest; member: Member; onClose: () => void; onKicked: () => void }) {
  const toast = useToast()
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  async function kick() {
    setBusy(true)
    try { await contestApi.kick(c.id, member.user_id, reason.trim() || undefined); toast(`${member.username} removed & banned`); onKicked() }
    catch (e) { toast(apiError(e), 'err'); setBusy(false) }
  }
  return (
    <Modal title={`Remove ${member.username}?`} onClose={onClose}
      footer={
        <>
          <button
            className="btn ghost"
            onClick={onClose}
          >
            No
          </button>

          <button
            className="btn danger"
            onClick={kick}
            disabled={busy}
          >
            {busy ? <Spinner /> : 'Yes'}
          </button>
        </>
      }>    
      
      <div className="notice" style={{ background: 'var(--wa-soft)', color: 'var(--wa)' }}>Permanently bans re-enrolling. Submissions are preserved for record integrity.</div>
      <div className="field" style={{ marginTop: 14 }}><label>Reason (optional, logged)</label><input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. rules violation" /></div>
    </Modal>
  )
}

/* ---------------- Enroll ---------------- */
function EnrollModal({ c, onClose, onEnrolled }: { c: Contest; onClose: () => void; onEnrolled: () => void }) {
  const toast = useToast()
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  async function enroll() {
    setBusy(true)
    try { await contestApi.enroll(c.id, code.trim() || undefined); toast(`Enrolled in ${c.title}`); onEnrolled() }
    catch (e) { toast(apiError(e), 'err'); setBusy(false) }
  }
  return (
    <Modal title={`Enroll in ${c.title}`} onClose={onClose}
      footer={<><button className="btn ghost" onClick={onClose}>Cancel</button><button className="btn primary" onClick={enroll} disabled={busy}>{busy ? <Spinner /> : 'Confirm enrollment'}</button></>}>
      <p className="dim" style={{ marginTop: 0 }}>You'll join as a <b>Participant</b>. Capacity, late-enrollment and invite-code checks run natively in the database.</p>
      {c.requires_invitation_code && <div className="field"><label>Invitation code</label><input value={code} onChange={(e) => setCode(e.target.value)} placeholder="e.g. ICPC-2026" /></div>}
    </Modal>
  )
}
