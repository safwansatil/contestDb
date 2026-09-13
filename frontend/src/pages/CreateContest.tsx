import {
  useState,
  type FormEvent,
} from 'react'

import { useNavigate } from 'react-router-dom'

import {
  contestApi,
  apiError,
} from '../lib/api'

import {
  Page,
  Spinner,
} from '../components/ui'

import { IconArrowLeft } from '../components/icons'
import { useToast } from '../lib/toast'

function localDateTime(offsetHours: number) {
  const date = new Date(
    Date.now() + offsetHours * 3_600_000
  )

  date.setSeconds(0, 0)

  return new Date(
    date.getTime()
      - date.getTimezoneOffset() * 60_000
  )
    .toISOString()
    .slice(0, 16)
}

interface CreateContestForm {
  title: string
  start_time: string
  end_time: string
  max_participants: string
  max_moderators: string
  invitation_code: string
  judging_description: string
}

export function CreateContest() {
  const navigate = useNavigate()
  const toast = useToast()

  const [busy, setBusy] = useState(false)

  const [form, setForm] =
    useState<CreateContestForm>({
      title: '',
      start_time: localDateTime(24),
      end_time: localDateTime(27),
      max_participants: '',
      max_moderators: '1',
      invitation_code: '',
      judging_description: '',
    })

  function update(
    field: keyof CreateContestForm,
    value: string,
  ) {
    setForm((current) => ({
      ...current,
      [field]: value,
    }))
  }

  async function submit(
    event: FormEvent<HTMLFormElement>,
  ) {
    event.preventDefault()

    const title = form.title.trim()
    const description =
      form.judging_description.trim()

    if (title.length < 3) {
      toast(
        'Title must be at least 3 characters',
        'err',
      )
      return
    }

    if (description.length < 5) {
      toast(
        'Description must be at least 5 characters',
        'err',
      )
      return
    }

    const start = new Date(form.start_time)
    const finish = new Date(form.end_time)

    if (
      Number.isNaN(start.getTime())
      || Number.isNaN(finish.getTime())
    ) {
      toast(
        'Enter valid start and finish times',
        'err',
      )
      return
    }

    if (finish <= start) {
      toast(
        'Finish time must be after start time',
        'err',
      )
      return
    }

    const maxParticipants =
      form.max_participants === ''
        ? null
        : Number(form.max_participants)

    const maxModerators =
      Number(form.max_moderators)

    if (
      maxParticipants !== null
      && (
        !Number.isInteger(maxParticipants)
        || maxParticipants < 1
      )
    ) {
      toast(
        'Maximum participants must be at least 1',
        'err',
      )
      return
    }

    if (
      !Number.isInteger(maxModerators)
      || maxModerators < 0
    ) {
      toast(
        'Moderator capacity cannot be negative',
        'err',
      )
      return
    }

    setBusy(true)

    try {
      const result = await contestApi.create({
        title,
        ranking_strategy: 'SUM',
        start_time: start.toISOString(),

        // No separate public freeze field yet.
        // The contest freezes when it finishes.
        freeze_time: finish.toISOString(),

        end_time: finish.toISOString(),
        max_participants: maxParticipants,
        max_moderators: maxModerators,
        invitation_code:
          form.invitation_code.trim() || null,
        judging_description: description,
        allow_late_enrollment: true,
      })

      toast(
        'Contest created and awaiting approval',
        'info',
      )

      navigate(`/contests/${result.contest_id}`)
    } catch (error) {
      toast(apiError(error), 'err')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Page>
      <main className="create-contest-page">
        <button
          type="button"
          className="btn ghost sm"
          onClick={() => navigate('/app')}
        >
          <IconArrowLeft size={15} />
          Explore
        </button>

        <header className="create-contest-heading">
          <div>
            <p className="label">
              New competition
            </p>

            <h1>Host a contest.</h1>

            <p>
              Establish the schedule, capacity and
              rules. Moderator accounts can be
              assigned after creation.
            </p>
          </div>

          <div className="create-contest-status">
            Pending approval
          </div>
        </header>

        <form
          className="create-contest-form"
          onSubmit={submit}
        >
          <section className="create-form-section">
            <div className="create-section-number">
              01
            </div>

            <div className="create-section-content">
              <h2>Contest identity</h2>

              <div className="field">
                <label htmlFor="contest-title">
                  Title
                </label>

                <input
                  id="contest-title"
                  value={form.title}
                  maxLength={100}
                  placeholder="e.g. Spring Algorithm Contest"
                  onChange={(event) =>
                    update(
                      'title',
                      event.target.value,
                    )
                  }
                />
              </div>

              <div className="field">
                <label htmlFor="contest-description">
                  Contest description
                </label>

                <textarea
                  id="contest-description"
                  value={form.judging_description}
                  placeholder="Describe the contest and how submissions are scored."
                  onChange={(event) =>
                    update(
                      'judging_description',
                      event.target.value,
                    )
                  }
                />
              </div>
            </div>
          </section>

          <section className="create-form-section">
            <div className="create-section-number">
              02
            </div>

            <div className="create-section-content">
              <h2>Schedule</h2>

              <div className="create-form-grid">
                <div className="field">
                  <label htmlFor="contest-start">
                    Start time
                  </label>

                  <input
                    id="contest-start"
                    type="datetime-local"
                    value={form.start_time}
                    onChange={(event) =>
                      update(
                        'start_time',
                        event.target.value,
                      )
                    }
                  />
                </div>

                <div className="field">
                  <label htmlFor="contest-finish">
                    Finish time
                  </label>

                  <input
                    id="contest-finish"
                    type="datetime-local"
                    value={form.end_time}
                    onChange={(event) =>
                      update(
                        'end_time',
                        event.target.value,
                      )
                    }
                  />
                </div>
              </div>
            </div>
          </section>

          <section className="create-form-section">
            <div className="create-section-number">
              03
            </div>

            <div className="create-section-content">
              <h2>Access and capacity</h2>

              <div className="create-form-grid">
                <div className="field">
                  <label htmlFor="max-participants">
                    Maximum participants
                  </label>

                  <input
                    id="max-participants"
                    type="number"
                    min="1"
                    step="1"
                    value={form.max_participants}
                    placeholder="Blank means unlimited"
                    onChange={(event) =>
                      update(
                        'max_participants',
                        event.target.value,
                      )
                    }
                  />
                </div>

                <div className="field">
                  <label htmlFor="max-moderators">
                    Moderator capacity
                  </label>

                  <input
                    id="max-moderators"
                    type="number"
                    min="0"
                    max="100"
                    step="1"
                    required
                    value={form.max_moderators}
                    onChange={(event) =>
                      update(
                        'max_moderators',
                        event.target.value,
                      )
                    }
                  />

                  <small className="create-field-help">
                    The host is not included. Assign
                    actual moderators after creation.
                  </small>
                </div>
              </div>

              <div className="field">
                <label htmlFor="invitation-code">
                  Invitation code
                </label>

                <input
                  id="invitation-code"
                  value={form.invitation_code}
                  maxLength={50}
                  autoComplete="off"
                  placeholder="Optional"
                  onChange={(event) =>
                    update(
                      'invitation_code',
                      event.target.value,
                    )
                  }
                />
              </div>
            </div>
          </section>

          <footer className="create-form-actions">
            <button
              type="button"
              className="btn"
              disabled={busy}
              onClick={() => navigate('/app')}
            >
              Cancel
            </button>

            <button
              type="submit"
              className="btn primary"
              disabled={busy}
            >
              {busy
                ? <Spinner />
                : 'Create contest →'}
            </button>
          </footer>
        </form>
      </main>
    </Page>
  )
}