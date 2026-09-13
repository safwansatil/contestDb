import {
  useEffect,
  useMemo,
  useState,
} from 'react'

import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'

import {
  contestApi,
  formatRequestApi,
  apiError,
  type Contest,
  type ContestTypeRequest,
} from '../lib/api'

import {
  fmtRel,
  timelineStatus,
} from '../lib/format'

import { useAuth } from '../lib/auth'
import { useToast } from '../lib/toast'

const TIMELINES = [
  'ALL',
  'ONGOING',
  'UPCOMING',
  'COMPLETED',
]

export function Dashboard() {
  const [contests, setContests] =
    useState<Contest[] | null>(null)

  const [query, setQuery] = useState('')
  const [timeline, setTimeline] =
    useState('ALL')

  const [requests, setRequests] =
    useState<ContestTypeRequest[]>([])

  const toast = useToast()
  const { user } = useAuth()
  const navigate = useNavigate()

  async function loadContests() {
    try {
      const params: Record<string, string> = {}

      if (query.trim()) {
        params.q = query.trim()
      }

      if (timeline !== 'ALL') {
        params.timeline = timeline
      }

      const result = await contestApi.list(params)
      setContests(result)
    } catch (error) {
      toast(apiError(error), 'err')
      setContests([])
    }
  }

  useEffect(() => {
    const delay = window.setTimeout(() => {
      void loadContests()
    }, 220)

    return () => {
      window.clearTimeout(delay)
    }
  }, [query, timeline])

  useEffect(() => {
    formatRequestApi
      .mine()
      .then(setRequests)
      .catch(() => setRequests([]))
  }, [])

  const visibleContests = useMemo(
    () =>
      (contests ?? []).filter(
        (contest) =>
          (contest.status !== 'PENDING_APPROVAL' && contest.status !== 'REJECTED')
          || contest.user_role === 'HOST'
          || contest.user_role === 'MODERATOR',
      ),
    [contests],
  )

  function resetFilters() {
    setQuery('')
    setTimeline('ALL')
  }

  return (
    <main className="editorial-page">
      <header className="page-heading">
        <div>
          <span className="index">
            01 / Field notes
          </span>

          <h1>
            Explore
            <br />
            <em>contests.</em>
          </h1>

          <p>
            Choose a room, read its rules, and take
            your place on the board.
          </p>
        </div>

        {!user?.is_developer && (
          <button
            type="button"
            className="btn primary"
            onClick={() =>
              navigate('/contests/new')
            }
          >
            + Host a contest
          </button>
        )}
      </header>

      <section className="explore-controls">
        <input
          value={query}
          placeholder="Search the index…"
          aria-label="Search contests"
          onChange={(event) =>
            setQuery(event.target.value)
          }
        />

        <div className="timeline-filter">
          {TIMELINES.map((item) => (
            <button
              key={item}
              type="button"
              className={
                timeline === item ? 'on' : ''
              }
              onClick={() => setTimeline(item)}
            >
              {item.toLowerCase()}
            </button>
          ))}
        </div>
      </section>

      {contests === null ? (
        <div className="empty">
          Loading the index…
        </div>
      ) : visibleContests.length === 0 ? (
        <div className="empty">
          <p>No contests match this edition.</p>

          <button
            type="button"
            className="btn"
            onClick={resetFilters}
          >
            Reset filters
          </button>
        </div>
      ) : (
        <motion.section
          className="contest-editorial-grid"
          initial="hidden"
          animate="show"
          variants={{
            show: {
              transition: {
                staggerChildren: 0.05,
              },
            },
          }}
        >
          {visibleContests.map(
            (contest, index) => (
              <ContestCard
                key={contest.id}
                contest={contest}
                index={index + 1}
                onClick={() =>
                  navigate(
                    `/contests/${contest.id}`,
                  )
                }
              />
            ),
          )}
        </motion.section>
      )}

      {requests.length > 0 && (
        <section style={{ marginTop: 70 }}>
          <div
            className="page-heading"
            style={{ paddingTop: 0 }}
          >
            <div>
              <span className="index">
                Your desk
              </span>

              <h2 style={{ fontSize: 40 }}>
                Format requests
              </h2>
            </div>
          </div>

          <div className="request-grid">
            {requests.map((request) => (
              <article
                className="request-note"
                key={request.id}
              >
                <span className="label">
                  {request.status}
                </span>

                <h3
                  style={{
                    fontSize: 24,
                    margin: '12px 0 8px',
                  }}
                >
                  {request.title}
                </h3>

                <p className="dim">
                  {request.requested_type.replace(
                    '_',
                    ' ',
                  )}
                  {' · '}
                  {request.rules_description}
                </p>

                {request.developer_note && (
                  <p
                    className="mono"
                    style={{ fontSize: 11 }}
                  >
                    Editor’s note:{' '}
                    {request.developer_note}
                  </p>
                )}
              </article>
            ))}
          </div>
        </section>
      )}
    </main>
  )
}

interface ContestCardProps {
  contest: Contest
  index: number
  onClick: () => void
}

function ContestCard({
  contest,
  index,
  onClick,
}: ContestCardProps) {
  const status = timelineStatus(contest)

  const statusLabel =
    status === 'ONGOING'
      ? '● LIVE'
      : status === 'UPCOMING'
        ? '○ UPCOMING'
        : '— ARCHIVED'

  const relevantTime =
    status === 'UPCOMING'
      ? contest.start_time
      : contest.end_time

  const timeLabel =
    status === 'COMPLETED'
      ? 'Ended'
      : status === 'UPCOMING'
        ? 'Starts'
        : 'Ends'

  const contestType =
  contest.contest_type === 'leetcode'
    ? 'Algorithms'
    : contest.contest_type ?? 'Contest'

  return (
    <motion.button
      type="button"
      className="contest-editorial-card"
      onClick={onClick}
      variants={{
        hidden: {
          opacity: 0,
          y: 16,
        },
        show: {
          opacity: 1,
          y: 0,
        },
      }}
    >
      <span className="card-no">
        #{String(index).padStart(2, '0')}
        {' · '}
        {statusLabel}
      </span>

      <h3>{contest.title}</h3>

      <p className="dim">
        {contest.judging_description
          || 'Rules and scoring information inside.'}
      </p>

      <div className="card-meta">
        <span>
          {contestType || 'Contest'}
        </span>

        <span>
          {timeLabel}{' '}
          {fmtRel(relevantTime)}
        </span>
      </div>
    </motion.button>
  )
}
