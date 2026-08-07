# ContestDB — Frontend Plan & Build Brief

> **Purpose of this document.** It is a self-contained brief for building the ContestDB
> web frontend. It explains what the project is, reverse-engineers the complete workflow
> from the existing backend, and specifies the screens, components, states, and design
> system to build. It is written so that another engineer **or an AI agent** can implement
> the frontend without needing to re-read the backend source.
>
> A clickable, non-production prototype of everything below was built as a single-file
> HTML artifact (`contestdb-demo.html`) — use it as the visual reference. This document is
> the source of truth for behavior and data contracts.

---

## 1. What ContestDB is

ContestDB is a **database-native contest management platform**. It can host, run, and rank
*any* kind of contest — competitive programming (ICPC), robotics (Line Follower Robots),
chess, quizzes — without contest-type-specific logic living in the application layer.

The defining architectural choice: **PostgreSQL is the execution engine, not just storage.**
Business rules — ranking, scoreboard freeze, enrollment caps, cooldowns, schema validation,
role checks — are implemented as PL/pgSQL stored functions. The API is a *thin gateway*.

```
┌────────────┐    HTTP/JSON     ┌─────────────────┐   SQL functions   ┌──────────────┐
│  Frontend  │ ───────────────► │ FastAPI gateway │ ────────────────► │  PostgreSQL  │
│ (to build) │ ◄─────────────── │  (thin tier)    │ ◄──────────────── │ (the engine) │
└────────────┘                  └─────────────────┘                   └──────┬───────┘
                                                                             │ polls queue
                                                                      ┌──────┴───────┐
                                                                      │ Judge Worker │
                                                                      │ (async judge)│
                                                                      └──────────────┘
```

**Implication for the frontend:** the frontend is a *pure client of the API*. It should hold
almost no business logic. Ranking, freeze rules, and permission checks are already enforced
server-side; the UI's job is to present state and reflect the role-scoped data the API returns.

### The central concepts

| Concept | What it means |
|---|---|
| **User** | An account (username + password). Authenticated via JWT (24h expiry). |
| **Contest** | A competition with a schedule and a ranking strategy. Lifecycle: `PENDING_APPROVAL → ACTIVE → COMPLETED`. |
| **Role (per contest)** | `HOST`, `MODERATOR`, or `PARTICIPANT`. A user's role is *scoped to each contest*, not global. Non-enrolled/guest = no role. |
| **Task** | A problem inside a contest. Declares a `submission_schema` (which JSONB keys a submission must contain) and an optional per-user cooldown. |
| **Submission** | A JSONB payload against a task. Enters a queue as `PENDING`, is picked up by the worker (`JUDGING`), and ends `COMPLETED`/`FAILED` with a standardized `score` + `verdict`. |
| **Ranking strategy** | How scores aggregate into standings: `SUM`, `MAX`, `ICPC`, `Custom`. |
| **Scoreboard freeze** | Between `freeze_time` and `end_time`, public/participant viewers see standings **frozen** at the freeze moment. Hosts/moderators always see live standings. Classic ICPC mechanic. |
| **Visibility settings** | Per-contest host-controlled flags governing what the public can see (leaderboard, member list, stats, etc.). |

### The three timestamps every contest has
`start_time ≤ freeze_time ≤ end_time` (enforced by a DB CHECK constraint).
- Before `start_time`: **UPCOMING** — no submissions accepted.
- `start_time … freeze_time`: **ONGOING, live board.**
- `freeze_time … end_time`: **ONGOING, board frozen** for non-admins.
- After `end_time`: **COMPLETED** — full results revealed to everyone.

> Contest **approval** (`PENDING_APPROVAL → ACTIVE`) is intentionally **not** an API endpoint.
> It's a developer-only terminal action (`SELECT approve_contest_native(<id>);`). The frontend
> should show newly created contests as "pending developer approval" and never attempt to approve.

### Team / course context
Built for **CSE 4410 (Database Management Systems II Lab)** at IUT, Department of Software
Engineering. Team: M Safwan Hasan Khan (satil), Tabib Hassan, Sayma Tasnim, Ayman Binta Altaf Nondiny.

---

## 2. Backend status & the complete API surface

The backend (`/backend`, FastAPI), database (`/database`, PostgreSQL), and worker (`/worker`)
are **built and working**. No frontend exists yet. Base URL in dev is the FastAPI server root.

### Auth model
- `Authorization: Bearer <jwt>` header on authenticated requests.
- Many read endpoints take an **optional** token: pass it if signed in to unlock role-scoped
  fields (e.g. invitation codes, admin leaderboard, your own role), omit it to get the public view.
- Store the JWT (e.g. `localStorage`); attach it via an axios/fetch interceptor.

### Endpoint reference (grouped by feature)

**Auth**
| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/auth/signup` | — | `{username, password}` → `{access_token, user}`. Username lowercased; `^[a-zA-Z0-9_-]+$`, 3–50 chars; password ≥6. |
| POST | `/auth/login` | — | `{username, password}` → `{access_token, user}`. 401 on bad creds. |
| GET | `/auth/me` | ✔ | Returns `{id, username}`; use to validate a stored token on app load. |

**Contests**
| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/contests` | optional | Query: `q`, `status`, `strategy`, `timeline` (`UPCOMING\|ONGOING\|COMPLETED`). Returns array with per-viewer `user_role`, `visibility`, capacity, and `invitation_code` (only for HOST/MOD). |
| GET | `/contests/{id}` | optional | Single contest, same shape. |
| GET | `/contests/{id}/profile` | optional | **Aggregator** — one call returns metadata + capacity + visibility + task/announcement counts + viewer's enrollment status. Prefer this for the contest page header. |
| POST | `/contests` | ✔ | Create. Body: `title, ranking_strategy, start_time, freeze_time, end_time, invitation_code?, judging_description, max_participants?, allow_late_enrollment`. Creator becomes HOST. New contest = `PENDING_APPROVAL`. |
| PUT | `/contests/{id}` | ✔ (HOST/MOD) | Update; same body. |
| DELETE | `/contests/{id}` | ✔ (HOST) | Delete. |

**Tasks**
| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/contests/{id}/tasks` | optional | Ordered by `task_order`. Each: `title, description, max_score, submission_schema, submission_cooldown_seconds, task_order`. |
| POST | `/contests/{id}/tasks` | ✔ (HOST/MOD) | Create task. `submission_schema` is **required** JSONB: `{required_keys:[...], numeric_keys:[...]}`. |
| PUT | `/tasks/{id}` | ✔ (HOST/MOD) | Update task. |
| DELETE | `/tasks/{id}` | ✔ (HOST/MOD) | Delete task. |

**Enrollment & members**
| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/contests/{id}/enroll` | ✔ | Body `{invitation_code?}`. DB enforces capacity, late-enrollment rule, invite code, and ban list. |
| GET | `/contests/{id}/enrollment-info` | optional | `max_participants, current_participants, spots_remaining, allow_late_enrollment, total_kicked`. |
| GET | `/contests/{id}/members` | ✔ (HOST/MOD) | `[{user_id, username, role}]`. |
| POST | `/contests/{id}/members/role` | ✔ (HOST) | `{target_user_id, new_role}` — role ∈ HOST/MODERATOR/PARTICIPANT. |
| DELETE | `/contests/{id}/members/{target_user_id}` | ✔ (HOST) | Kick + permanently ban from re-enrolling. Body `{reason?}`. Submissions preserved. |
| GET | `/contests/{id}/kick-log` | ✔ (HOST/MOD) | Audit trail of removals. |

**Submissions & leaderboard**
| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/submissions` | ✔ | Body `{contest_id, task_id?, submission_data}`. Server checks: enrolled, contest ACTIVE + within window, task belongs to contest, **cooldown**, and **schema validation** — then queues as PENDING. Returns `{submission_id, submitted_at}`. |
| GET | `/contests/{id}/leaderboard` | optional | Returns `{view_mode: "admin"\|"public", leaderboard:[{user_id, username, total_score, rank}]}`. **Freeze is applied server-side** by role. |

**Statistics & progress**
| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/contests/{id}/statistics` | optional | `total_participants, active_participants, total_submissions, task_statistics, submission_timeline`. Admins bypass freeze. |
| GET | `/contests/{id}/progress/{user_id}` | ✔ | Cumulative score progression (for a line chart). |

**Visibility**
| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/contests/{id}/visibility` | optional | The 6 boolean flags. |
| PUT | `/contests/{id}/visibility` | ✔ (HOST/MOD) | Update flags: `show_participant_count, show_leaderboard, show_member_list, show_task_list, show_statistics, show_submission_count`. |

**Announcements**
| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/contests/{id}/announcements` | optional | Newest first: `{id, title, body, author, posted_at}`. |
| POST | `/contests/{id}/announcements` | ✔ (HOST/MOD) | `{title, body}`. |
| DELETE | `/announcements/{id}` | ✔ (HOST/MOD) | Delete. |

**Users & profile**
| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/users/search?q=` | — | Trigram username search. |
| GET | `/users` | ✔ | All users (for role assignment pickers). |
| GET | `/users/{id}/profile` | optional | `stats` (submissions, contests, avg/max score, `verdict_breakdown`) + `activity_graph` (date→count, for a heatmap). |
| GET | `/users/{id}/history` | optional | `contest_history` + recent `submissions_history`. |
| GET | `/time` | — | Server/DB timestamp — **use to sync the client clock** for countdowns & freeze, don't trust local time. |

### The submission lifecycle (critical to model in the UI)
```
User submits payload ──► POST /submissions
   DB validates: enrolled? active+in-window? task in contest? cooldown ok? schema ok?
        │ fail → 4xx with human message (show inline)
        ▼ pass
   Row inserted: status = PENDING  ────────────────┐
                                                    │ worker polls claim_submission()
   status = JUDGING (worker locked it)  ◄───────────┘
        │ evaluate_submission(payload)  (mock judge — see worker.py)
        ▼
   status = COMPLETED, score + verdict written back
```
The judge is **asynchronous**. The UI must not expect a score in the POST response — it must
**poll** (or optimistically show "PENDING → JUDGING → judged") until the submission completes.
Poll `/users/{id}/history` or a submission-status view. Typical verdicts the mock worker emits:
`RUN_SUCCESS`, `TIME_LIMIT_EXCEEDED`, `ACCEPTED`, `WRONG_ANSWER`, `COMPILE_ERROR`, `PARTIAL`, `GRADED`, `GENERIC_SUCCESS`.

### `submission_schema` drives dynamic forms
Each task carries `{required_keys:[...], numeric_keys:[...]}`. **Build the submission form
dynamically from this** — one field per required key, `type="number"` for numeric keys, a
textarea for a key literally named `source_code`. Example schemas seen in seed data:
- LFR: `{required_keys:["run_time_seconds","restarts"], numeric_keys:["run_time_seconds","restarts"]}`
- Quiz: `{required_keys:["score","verdict"], numeric_keys:["score"]}`
- ICPC: `{required_keys:["source_code","language"], numeric_keys:[]}`

---

## 3. Roles & what each viewer sees

The same screen renders differently by role. Enforce this in the UI (server enforces it too).

| Capability | Guest | Participant | Moderator | Host |
|---|:--:|:--:|:--:|:--:|
| Browse / search contests | ✔ | ✔ | ✔ | ✔ |
| View public leaderboard (freeze-aware) | ✔ | ✔ | ✔ | ✔ |
| See **live** (unfrozen) leaderboard | — | — | ✔ | ✔ |
| Enroll / submit | — | ✔ | — | — |
| See invitation code | — | — | ✔ | ✔ |
| Post/delete announcements | — | — | ✔ | ✔ |
| Add/edit/delete tasks | — | — | ✔ | ✔ |
| View member list & kick log | — | — | ✔ | ✔ |
| Kick/ban, change roles, edit/delete contest, visibility | — | — | — | ✔ |
| Approve contest | — | — | — | **DB-only, never in UI** |

> **Prototype convenience:** the demo has a Guest/Participant/Host **role switcher** in the top
> bar. That is a *demo affordance only* — in production, role comes from the JWT + the contest's
> enrollment record. Keep it out of the real build (or gate behind a dev flag).

---

## 4. Information architecture & screens

```
/                         → Explore (contest discovery)
/login  /signup           → Auth
/contests/:id             → Contest detail (tabbed)
     ?tab=overview|tasks|leaderboard|stats|announcements|manage
/contests/new             → Create/host a contest
/users/:id                → User profile
```

### Screen 1 — Explore / Discovery
- Search bar (`q`) + timeline filter segments (All / Ongoing / Upcoming / Completed).
  Optionally expose `strategy` and `status` filters too.
- Responsive grid of **contest cards**. Card shows: status pill (color-coded), ranking-strategy
  mono tag, title, your role (if any), invite-only lock, truncated judging description, a
  starts/ends relative time, and a capacity bar (only if `show_participant_count`).
- `PENDING_APPROVAL` contests appear **only** to their host/moderators.
- Signed-in users get a "Host a contest" CTA.

### Screen 2 — Auth (login / signup)
- Single card, toggle between modes. Client-validate username regex & password length before POST.
- On success store JWT, hydrate user, redirect to Explore. Show server's error message on 401/400.

### Screen 3 — Contest detail (the core screen — tabbed)
Fed primarily by `/contests/:id/profile`. A hero with: status pill, strategy, your role,
title, judging description, a **live countdown** (to start or end), a **Start→Freeze→End
timeline** with a "now" marker, and a **primary action button** that is role/state-aware:
- Host/Mod → "Manage contest" (jumps to Manage tab)
- Enrolled participant, ongoing → "Submit solution"
- Not enrolled, joinable → "Enroll" / "Enroll with code"
- Guest → "Sign in to join"; ended → disabled "Contest ended"; late-locked → "Enrollment closed"

Tabs (each tab hidden if visibility flag says so, unless viewer is admin):
1. **Overview** — judging & rules, latest announcement, top-3 standings preview, schedule side
   panel, enrollment count, invitation code (admins only).
2. **Tasks** — ordered task list; each shows description, its `submission_schema` as chips
   (numeric keys highlighted), cooldown, max score, and a **Submit** button (enrolled+ongoing)
   or **Edit** (admins). Admins get "Add task".
3. **Leaderboard** — freeze-aware table with gold/silver/bronze rank badges, your row
   highlighted. Show a **freeze banner**: participants see "board frozen as of …"; admins see
   "Admin view — live standings; participants see it frozen".
4. **Statistics** — KPI tiles (participants, active, submissions, avg score), submission-timeline
   bar chart, verdict-breakdown bars. (Requires `show_statistics` or admin.)
5. **Announcements** — list newest-first; admins can post/delete.
6. **Manage** (admins only) — members & roles table (change role, kick), public-visibility
   toggles, invitation code, and a danger zone (edit / delete contest). Kick opens a modal with
   an optional reason and a permanent-ban warning.

### Screen 4 — Submission flow (modal)
Task picker → **dynamically generated fields from `submission_schema`** → submit. On submit,
model the async lifecycle: toast "queued · PENDING" → "claimed by worker · JUDGING" → a result
card with the score and a color-coded verdict pill. In production this is polling, not a timer.
Surface server rejections (cooldown = 429, schema/enrollment/window = 400) as inline errors.

### Screen 5 — Create / host a contest
Form: title, ranking strategy, judging description, the three datetimes (validate
start ≤ freeze ≤ end), max participants (blank = unlimited), invitation code (optional),
allow-late-enrollment toggle. On success show "pending developer approval" and route to the
new contest. (A future enhancement: a stepper that also adds tasks in step 2.)

### Screen 6 — User profile
Header with avatar, join date, and stat tiles (avg score, best, contests, submissions).
A **GitHub-style activity heatmap** from `activity_graph`. Contest history (clickable rows with
rank badges) and a verdict-breakdown panel.

---

## 5. Component inventory (build these as reusable primitives)

- **StatusPill** — contest status / timeline, color-mapped.
- **VerdictPill** — maps verdict string → semantic color (AC-family green, WA-family red,
  TLE/PARTIAL amber, PENDING/JUDGING blue, else neutral). Centralize this map.
- **RankBadge** — gold/silver/bronze for ranks 1–3, plain mono for the rest.
- **StrategyTag**, **RoleTag**, **SchemaChip** (numeric variant highlighted).
- **CountdownTimer** (ticks every second; clamps at 0) and **ContestTimeline** (Start/Freeze/End).
- **CapacityBar**, **KpiTile**, **BarChart** (timeline), **HBarBreakdown** (verdicts), **Heatmap**.
- **LeaderboardTable** (freeze banner + highlighted "you" row).
- **Modal**, **Toast/Toaster**, **Tabs**, **SegmentedControl**, **Toggle**, **EmptyState**.
- **DynamicSubmissionForm** (renders from `submission_schema`).
- **RoleGate** helper — conditionally render by `viewer_role`.

---

## 6. Design system

The prototype's identity: **"judge's terminal meets clean product UI."** Cool-slate neutrals
(deliberately hue-biased, not flat grey) with a single **warm gold accent** — evoking medals,
podiums, first place. Semantic verdict colors are kept *separate* from the accent. Monospace
does real work for all competitive data (scores, ranks, verdicts, codes, schema keys).

Aesthetic references: **shadcn/ui** (subtle borders, restrained radii, neutral base, quiet
surfaces) and **Radix** primitives for accessible behavior. Avoid heavy gradients and glassy
chrome; let type hierarchy and spacing carry the page.

### Tokens (both themes — support light & dark)
```css
/* DARK */                         /* LIGHT */
--bg:#0d1017;                      --bg:#f4f5f7;
--surface:#161b23;                 --surface:#ffffff;
--surface-2:#1c222c;               --surface-2:#eceef1;
--border:#28303c;                  --border:#dde1e7;
--text:#e9edf3;                    --text:#141821;
--text-muted:#94a0b0;              --text-muted:#5a636f;
--accent:#e8b04b;   /* gold */     --accent:#a86610;   /* deep gold */
/* semantic verdict colors (tune per theme) */
--ac:#34d17f / #1f9d55;      /* ACCEPTED / RUN_SUCCESS */
--wa:#f0665f / #d1443b;      /* WRONG_ANSWER / COMPILE_ERROR / FAILED */
--tle:#f0a53a / #c26a17;     /* TLE / PARTIAL */
--pending:#5b9cf0 / #3b74d1; /* PENDING / JUDGING */
--gold/silver/bronze         /* rank badges */
```
- **Type:** heavy system grotesque for headings (tight tracking); system sans for body
  (~65ch line length); a **monospace** stack (`ui-monospace, "SF Mono", "JetBrains Mono"…`)
  with `tabular-nums` for every number, score, rank, verdict, code, and schema key.
- **Shape/spacing:** radius ~8–12px, 1px borders, soft shadows, generous card padding, grid/flex
  `gap` for spacing (not per-element margins).
- **Motion:** subtle only — view fade-in, hover lift on cards, modal pop; honor
  `prefers-reduced-motion`.
- **Accessibility:** visible focus rings, keyboard-navigable tabs/modals (Radix helps),
  color never the sole signal (pair verdict color with its text label).

---

## 7. Recommended stack & structure

- **React + TypeScript + Vite.** **Tailwind CSS** with the tokens above mapped to CSS variables,
  and **shadcn/ui** components on **Radix** primitives. (daisyUI is a fine alternative if you
  prefer a component-class approach over copy-in components.)
- **TanStack Query** for all server state — it makes the submission **polling** and cache
  invalidation clean. **React Router** for routing. A thin **axios** client with a JWT
  interceptor. **Recharts** (or lightweight custom SVG) for the timeline/progression charts.
- **Zod** types mirroring the API responses in §2.

```
src/
  api/            # axios client + typed endpoint fns + zod schemas
  auth/           # JWT store, useAuth, ProtectedRoute
  components/ui/  # shadcn primitives
  components/     # StatusPill, VerdictPill, RankBadge, LeaderboardTable, DynamicSubmissionForm, ...
  features/
    explore/  contest/  submission/  profile/  manage/
  lib/            # verdict color map, time/format helpers, useServerClock
  routes/
```

### Cross-cutting rules for the implementer
1. **Server owns the logic.** Don't re-implement ranking/freeze/permissions client-side — render
   what the API returns and gate UI by `viewer_role`/`visibility`.
2. **Clock from the server.** Drive countdowns/freeze from `/time` offset, not the device clock.
3. **Submissions are async.** POST returns only an id; poll for the verdict.
4. **Forms are data-driven.** Generate submission fields from `submission_schema`; show the
   server's validation/cooldown messages verbatim.
5. **Approval is invisible.** Never expose contest approval; show "pending developer approval".
6. **Optional-auth reads:** send the token when present to unlock role-scoped fields.

---

## 8. Suggested build order (milestones)
1. **Foundation** — Vite/TS/Tailwind, tokens, theme toggle, API client, auth (login/signup, JWT, `/auth/me`).
2. **Discovery** — Explore grid + search/filters; contest card.
3. **Contest read path** — detail hero + timeline + Overview/Tasks/Leaderboard/Announcements tabs (read-only), freeze-aware leaderboard.
4. **Participation** — enroll modal; dynamic submission form + async verdict polling.
5. **Host tooling** — create contest; Manage tab (members/roles, kick + log, visibility, announcements, task CRUD).
6. **Analytics & profile** — statistics tab (charts), user profile + activity heatmap + history.
7. **Polish** — empty/loading/error states, accessibility pass, responsive/mobile, motion.

---

*Companion artifact:* `contestdb-demo.html` — an interactive prototype demonstrating all of the
above with mock data and a role switcher. Treat it as the visual spec; treat this file as the
behavioral + data-contract spec.
