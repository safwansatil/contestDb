import { Link } from 'react-router-dom'
import { ThemeSwitcher } from '../components/Nav'

const notes = [
  ['01', 'One source of truth', 'Scoring, standings and the freeze live in PostgreSQL, where every result can be traced.'],
  ['02', 'Any format', 'Algorithms, chess, CTFs, quizzes and custom formats share one durable contest model.'],
  ['03', 'Built for the board', 'Read the brief, ship your submission, then watch the live record change.'],
  ['04', 'Freeze aware', 'When the seal drops, competitors see exactly the standings they should see.'],
]
export function Landing() {
  return <main className="landing">
    <header className="landing-top"><Link to="/" className="wordmark"><b>Contest</b><i>DB</i><small>ISSUE 01 / 2026</small></Link><div className="nav-actions"><ThemeSwitcher /><Link to="/login">Sign in</Link><Link className="nav-join" to="/signup">Join the board</Link></div></header>
    <section className="editorial-cover"><div className="cover-copy"><div><p className="cover-kicker">A database-native competition journal</p><h1 className="cover-title">MAKE<br/>YOUR<br/><em>MOVE.</em></h1></div><div><p className="cover-lead">ContestDB is a contest platform for people who care about the rules. Host a room, enter a bracket, submit the work, and let the database keep the score.</p><div className="cover-cta"><Link className="btn primary lg" to="/signup">Enter the index →</Link><Link className="btn lg" to="/login">I have a pass</Link></div></div></div><aside className="cover-index"><div><span className="cover-kicker">This edition</span><h2>THE<br/>COMPETITION<br/>ISSUE</h2></div><div className="cover-number">01</div><p className="cover-rules">RUN / RANK / FREEZE<br/>A contest system for IUT DBMS II<br/>Built around the record, not the hype.</p></aside></section>
    <section className="editorial-strip">{notes.map(([n,title,text]) => <article key={n}><span className="label">{n} / Index</span><h3>{title}</h3><p>{text}</p></article>)}</section>
    <section className="landing-cta"><h2>There is a seat<br/><em>on the board.</em></h2><aside><Link className="btn primary lg" to="/signup">Create your account →</Link></aside></section>
  </main>
}
