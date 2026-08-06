# ContestDB — Frontend Integration Context

This document records the work done to build and wire up the **React frontend** for ContestDB
and to get the **full stack running locally**. It is a running log of tasks completed, plus how
to run everything. (For the higher-level product/feature spec, see `FRONTEND_PLAN.md`.)

Branch: **`frontend-integration`** · Stack: React 19 + TypeScript + Vite, FastAPI, PostgreSQL, judge worker.

---

## 1. What ContestDB is (recap)

A **database-native contest platform**: hosting, judging and ranking of any contest type
(ICPC, robotics, chess, quizzes) with the scoring engine living inside **PostgreSQL** as
stored functions. FastAPI is a thin gateway; a background **worker** judges submissions
asynchronously. See `README.md` for architecture.

---

## 2. Tasks completed

### A. Stood up the full stack locally (was previously DB-less)
- Created a local PostgreSQL 17 database `contestdb` and loaded `database/init.sql`,
  `database/procedures.sql`, and `database/seed.sql` (4 users, 2 contests, tasks, submissions).
- Created a root `.env` pointing the backend/worker at the local database
  (`DATABASE_URL=postgresql://tabib@localhost:5432/contestdb`) plus a dev `JWT_SECRET`.
- Set up a Python venv (`.venv`), installed `backend/requirements.txt` and
  `worker/requirements.txt`, and started:
  - **FastAPI gateway** on `http://127.0.0.1:8000`
  - **Judge worker** (`worker-1`) polling the queue
- Smoke-tested auth, contests, leaderboard, and a live submission end-to-end.

### B. Backend changes (completing what the frontend needed)
1. **CORS enabled** — `backend/app/main.py` now adds `CORSMiddleware` allowing any
   `localhost`/`127.0.0.1` origin, so the browser app can call the API directly.
2. **Fixed a real bug in `get_leaderboard`** (`database/procedures.sql`) — the HOST/MODERATOR
   admin-check subquery used a bare `user_id`, which is **ambiguous** because the function's
   `RETURNS TABLE(user_id …)` declares an output column of the same name. This raised
   *"column reference user_id is ambiguous"* for **every authenticated leaderboard request**,
   i.e. logged-in users could not view any leaderboard. Columns are now qualified
   (`enrollments e … e.user_id = p_viewer_id`). Verified admin vs. participant views both work.

> No other backend module was incomplete — all endpoints the UI needs already existed and work.

### C. Built the React frontend (`/frontend`) — new
Design language: **glassmorphism** — deep "aurora" gradient background with frosted-glass panels,
a warm-gold accent (medals/podium), and monospace for all competitive data. Animation:
**GSAP** (landing hero timeline + idle float), **Framer Motion** (page/list/modal transitions,
toasts), and **Lottie** (`lottie-react`, gold ring loader) per the request.

Structure:
- `src/lib/` — `api.ts` (typed axios client + all endpoint fns + JWT interceptor + error
  normalizer), `auth.tsx` (JWT auth context, validates token via `/auth/me`), `format.ts`
  (time/verdict/freeze helpers), `toast.tsx` (animated toaster).
- `src/components/` — `ui.tsx` (Aurora, Lottie Loader, Modal, Pill, RankBadge, Avatar, Toggle,
  Page/stagger animation primitives), `Nav.tsx`, `CreateContestModal.tsx`, `SubmitModal.tsx`
  (dynamic schema form + async verdict polling), `ErrorBoundary.tsx`.
- `src/pages/` — `Landing.tsx` (guest marketing page, GSAP hero, live-leaderboard preview),
  `Auth.tsx` (login/signup), `Dashboard.tsx` (explore: search + timeline filters + contest
  cards + host-a-contest), `ContestDetail.tsx` (hero + countdown + Start→Freeze→End timeline +
  tabs: Overview / Tasks / Leaderboard / Statistics / Announcements / Manage, plus enroll, kick,
  role-change, visibility, announcements), `Profile.tsx` (stats, activity heatmap, history).
- `src/styles/global.css` — the whole design system (tokens, glass, buttons, leaderboard, etc.).

Behavior wired to the backend:
- **Auth**: signup/login store the JWT in `localStorage`; token validated on boot.
- **Role-aware UI**: the hero action button and visible tabs change by the viewer's contest role
  (guest / participant / moderator / host); pending contests only show to their host/mods.
- **Freeze-aware leaderboard**: participants see the frozen banner + frozen board; hosts see an
  "admin view — live standings" banner. (Freeze is enforced server-side; UI just reflects it.)
- **Submissions**: the form is generated dynamically from each task's `submission_schema`
  (number vs text fields). On submit it POSTs to the queue, then **polls** `/users/{id}/history`
  until the worker writes back a verdict, then shows a score/verdict result card.
- **Host tools**: create contest, post/delete announcements, change roles, kick+ban, toggle the
  six visibility flags, delete contest — all against the role-guarded endpoints.

### D. Verified end-to-end (in-browser, against the live backend)
- Landing → signup/login → dashboard → contest → submit → verdict → leaderboard update.
- Login as `sayma` (HOST of both seeded contests) and `tabib` (participant) to exercise both roles.
- Confirmed a real submission (score 88 / ACCEPTED) was judged by the worker and moved `tabib`
  to rank #2 on the live board.

### Notes / known cosmetic items
- Bundle is ~925 kB (gsap + framer-motion + lottie); fine for a local demo, could be code-split later.
- `lottie-web` triggers a harmless build-time `eval` warning (library internal).
- Task **create/edit** UI is stubbed with a note — the endpoints are wired in `api.ts`
  (`addTask`, etc.); building the task-builder form is a good next step.

---

## 3. How to run the full stack locally

Three processes. From the repo root:

**1) Database (one-time load)** — requires a local PostgreSQL:
```bash
createdb contestdb
psql -d contestdb -f database/init.sql
psql -d contestdb -f database/procedures.sql
psql -d contestdb -f database/seed.sql
```
Ensure the root `.env` has `DATABASE_URL` pointing at it.

**2) Backend + worker** (Python venv):
```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r backend/requirements.txt -r worker/requirements.txt
# terminal 1 — API gateway (http://127.0.0.1:8000)
cd backend && python run_server.py
# terminal 2 — judge worker
cd worker && python worker.py
```

**3) Frontend** (Node):
```bash
cd frontend
npm install
npm run dev     # http://localhost:5173 (or next free port, e.g. 5174)
```
The API base is configured in `frontend/.env` (`VITE_API_BASE=http://127.0.0.1:8000`).

**Seed logins** (all password `password123`): `sayma` (host), `nondiny`, `satil`, `tabib`.

---

## 4. Files added / changed on this branch

- **Added**: entire `frontend/` app; `context.md`; `FRONTEND_PLAN.md`; root `.env` is git-ignored.
- **Changed**: `backend/app/main.py` (CORS); `database/procedures.sql` (`get_leaderboard` fix);
  root `.gitignore` (re-include `frontend/src/lib`, ignore node_modules/dist).
- **Untouched**: `main` branch and all other backend/worker/database logic.
