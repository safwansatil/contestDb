import { useEffect, useRef } from 'react'
import { Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import gsap from 'gsap'
import { ThemeSwitcher } from '../components/Nav'
import { IconLedger, IconPalette, IconSeal, IconBolt, EmblemGuild } from '../components/icons'

const FEATURES = [
  { Icon: IconLedger, title: 'Ledger-native engine', text: 'Ranking, freeze rules and scoring run as PostgreSQL stored functions — not scattered across app code.' },
  { Icon: IconPalette, title: 'Any contest, any craft', text: 'ICPC, robotics time-trials, chess, quizzes. A flexible JSONB payload adapts to every judging style.' },
  { Icon: IconSeal, title: 'The Seal — scoreboard freeze', text: 'Standings lock at freeze time for the crowd, while hosts keep watching the live board.' },
  { Icon: IconBolt, title: 'Async judge queue', text: 'Submissions flow through a real PENDING → JUDGING → COMPLETED pipeline with standardized verdicts.' },
]
const VERDICTS = [
  { v: 'ACCEPTED', c: 'tag-ac' }, { v: 'WRONG_ANSWER', c: 'tag-wa' },
  { v: 'TLE', c: 'tag-tle' }, { v: 'RUN_SUCCESS', c: 'tag-ac' }, { v: 'PENDING', c: 'tag-pending' },
]

export function Landing() {
  const root = useRef<HTMLDivElement>(null)

  useEffect(() => {
    // Explicit fromTo (not from) so the visible end-state is always defined —
    // this survives React StrictMode's double-invoke without leaving nodes at opacity 0.
    let safety = 0
    const ctx = gsap.context(() => {
      const tl = gsap.timeline({ defaults: { ease: 'power3.out' } })
      const rise = (sel: string, opts: gsap.TweenVars = {}, at?: string) =>
        tl.fromTo(sel, { y: 26, opacity: 0, ...(opts.from as object) }, { y: 0, opacity: 1, duration: 0.6, ...opts }, at)
      rise('.hero-badge', { duration: 0.5 })
      rise('.hero-line', { duration: 0.7, stagger: 0.12, y: 40 }, '-=0.2')
      rise('.hero-sub', { duration: 0.6 }, '-=0.35')
      rise('.hero-cta', { duration: 0.5, stagger: 0.1 }, '-=0.3')
      tl.fromTo('.hero-panel', { y: 60, opacity: 0, scale: 0.96 }, { y: 0, opacity: 1, scale: 1, duration: 0.9, ease: 'power4.out' }, '-=0.5')
      tl.fromTo('.lb-row', { x: 24, opacity: 0 }, { x: 0, opacity: 1, duration: 0.4, stagger: 0.08 }, '-=0.5')
      // gentle idle float on the preview panel
      gsap.to('.hero-panel', { y: '+=12', duration: 3, repeat: -1, yoyo: true, ease: 'sine.inOut', delay: 2 })

      // Safety: if requestAnimationFrame is throttled (e.g. a backgrounded tab),
      // snap the intro to its final, fully-visible state so content never gets stuck hidden.
      safety = window.setTimeout(() => { if (tl.progress() < 1) tl.progress(1) }, tl.duration() * 1000 + 600)
    }, root)
    return () => { window.clearTimeout(safety); ctx.revert() }
  }, [])

  return (
    <div ref={root}>
      {/* Top bar (minimal, landing-only) */}
      <div className="row" style={{ padding: '20px 26px', maxWidth: 1200, margin: '0 auto' }}>
        <Link to="/" className="brand"><span className="mark"><EmblemGuild size={19} /></span>ContestDB</Link>
        <div className="grow" />
        <ThemeSwitcher />
        <Link to="/login" className="btn ghost sm" style={{ marginLeft: 4 }}>Sign in</Link>
        <Link to="/signup" className="btn primary sm" style={{ marginLeft: 8 }}>Get started</Link>
      </div>

      {/* Hero */}
      <section style={{ maxWidth: 1200, margin: '0 auto', padding: '40px 26px 80px', display: 'grid', gridTemplateColumns: '1.05fr 1fr', gap: 50, alignItems: 'center' }} className="hero-grid">
        <div>
          <span className="hero-badge pill tag-gold" style={{ marginBottom: 22, display: 'inline-flex', gap: 6 }}><EmblemGuild size={13} /> Ledger-native contest platform</span>
          <h1 style={{ fontSize: 54, lineHeight: 1.08, letterSpacing: '-0.04em' }}>
            <div className="hero-line">Run any contest.</div>
            <div className="hero-line" style={{ paddingBottom: '0.08em', background: 'linear-gradient(120deg,var(--gold-2),var(--gold-deep))', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>Ranked in the database.</div>
          </h1>
          <p className="hero-sub dim" style={{ fontSize: 17, maxWidth: 480, marginTop: 28 }}>
            ContestDB hosts, judges and ranks competitions of any kind — with the scoring engine living
            inside PostgreSQL itself. Host a contest, enroll, submit, and climb a freeze-aware leaderboard.
          </p>
          <div className="row hero-cta-wrap" style={{ gap: 12, marginTop: 30 }}>
            <Link to="/signup" className="hero-cta btn primary lg">Start competing →</Link>
            <Link to="/login" className="hero-cta btn lg">I have an account</Link>
          </div>
          <div className="row hero-cta" style={{ gap: 8, marginTop: 26, flexWrap: 'wrap' }}>
            {VERDICTS.map((v) => <span key={v.v} className={`pill ${v.c}`}>{v.v}</span>)}
          </div>
        </div>

        {/* Live-looking leaderboard preview panel */}
        <div className="hero-panel glass pad-lg" style={{ borderRadius: 22 }}>
          <div className="row" style={{ justifyContent: 'space-between', marginBottom: 4 }}>
            <div><div className="label">Live leaderboard</div><h3 style={{ fontSize: 18, marginTop: 4 }}>Max Speed Run</h3></div>
            <span className="strat">MAX</span>
          </div>
          <div className="freeze-banner" style={{ margin: '14px 0' }}><span className="ic"><IconSeal size={18} /></span><span style={{ fontSize: 12.5 }} className="dim">Scoreboard sealed · results reveal at end</span></div>
          {[['satil', 82, 1], ['sayma', 75, 2], ['nondiny', 60, 3]].map(([n, s, r]) => (
            <div key={n as string} className="lb-row row" style={{ padding: '11px 0', borderBottom: '1px solid var(--glass-border)' }}>
              <span className={`rk-badge rk${r}`}>{r as number}</span>
              <span className="avatar" style={{ width: 28, height: 28, fontSize: 11, marginLeft: 10 }}>{(n as string).slice(0, 2).toUpperCase()}</span>
              <b style={{ marginLeft: 10 }}>{n}</b><div className="grow" />
              <span className="mono" style={{ fontWeight: 750, fontSize: 16 }}>{s}</span>
            </div>
          ))}
        </div>
      </section>

      {/* Features */}
      <section style={{ maxWidth: 1160, margin: '0 auto', padding: '0 26px 70px' }}>
        <motion.div className="contest-grid" style={{ gridTemplateColumns: 'repeat(auto-fit,minmax(250px,1fr))' }}
          initial="hidden" whileInView="show" viewport={{ once: true, margin: '-80px' }}
          variants={{ show: { transition: { staggerChildren: 0.1 } } }}>
          {FEATURES.map((f) => (
            <motion.div key={f.title} className="glass pad-lg"
              variants={{ hidden: { opacity: 0, y: 30 }, show: { opacity: 1, y: 0, transition: { duration: 0.5 } } }}>
              <div style={{ marginBottom: 14, color: 'var(--primary)' }}><f.Icon size={28} strokeWidth={1.5} /></div>
              <h3 style={{ fontSize: 18, marginBottom: 8 }}>{f.title}</h3>
              <p className="dim" style={{ fontSize: 13.5, margin: 0 }}>{f.text}</p>
            </motion.div>
          ))}
        </motion.div>
      </section>

      {/* CTA */}
      <section style={{ maxWidth: 900, margin: '0 auto 90px', padding: '0 26px' }}>
        <div className="glass glass-strong pad-lg center" style={{ padding: '48px 26px', borderRadius: 22 }}>
          <h2 style={{ fontSize: 30 }}>Ready to host or compete?</h2>
          <p className="dim" style={{ maxWidth: 440, margin: '12px auto 26px' }}>Create an account and you're one click from your first leaderboard.</p>
          <Link to="/signup" className="btn primary lg">Create your account</Link>
        </div>
        <p className="center faint" style={{ fontSize: 12, marginTop: 30 }}>
          CSE 4410 · Database Management Systems II Lab · Islamic University of Technology
        </p>
      </section>

      <style>{`@media(max-width:820px){.hero-grid{grid-template-columns:1fr!important;gap:36px!important}h1{font-size:40px!important}}`}</style>
    </div>
  )
}
