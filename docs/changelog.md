# Changelog

All notable changes to the ContestDB project will be documented in this file.

This project adheres to Semantic Versioning and matches commits/tasks with GitHub Issues.

---

## [0.8.0] - 2026-08-06 (Participant Dashboard)

### Added

- **[#42] Database-Native Participant Dashboard** — Added `get_participant_dashboard(p_user_id)` to `database/procedures.sql`. It returns summary statistics, ongoing contests, upcoming contests, leaderboard ranks and scores, and the five most recent participant submissions as one JSONB object.
- **Authenticated Dashboard Endpoint** — Added `GET /dashboards/participant` to `backend/app/main.py`. The endpoint obtains `user_id` exclusively from the authenticated JWT and does not accept a client-selected user ID.
- **Participant Dashboard Integration Tests** — Added `database/tests/test_participant_dashboard.py` covering authentication, response structure, participant-role filtering, recent-submission ownership, and the five-submission limit.
- **Documentation** — Updated `docs/manual_testing.md` and `docs/architecture_and_erd.md` with the endpoint verification procedure and database-native request flow.

## [0.7.1] - 2026-08-06 (Security Hardening: Leaderboard Freeze & Submission Timing)
### Fixed
* **[#15] Privilege Escalation via Type Coercion in `get_user_contest_history`** — The `get_user_contest_history` PL/pgSQL function in [procedures.sql](database/procedures.sql) called `get_leaderboard(ec.contest_id, TRUE)` with a literal boolean `TRUE` as the viewer ID. PostgreSQL silently casts `TRUE` to integer `1`, making every call to `/users/{id}/history` treat user ID 1 (sayma) as the viewer — thereby granting admin-level (unfreeze-bypassing) leaderboard access to every user's contest history. Fixed by changing `TRUE` to `NULL`, which instructs `get_leaderboard` to use the public/frozen visibility path for all history lookups. This is correct: contest history always shows final public standings.
* **[#15] Confirmed: `GET /contests/{id}/leaderboard` is already server-authoritative** — No client-controllable `as_admin` parameter exists on this endpoint. The `view_mode` ("admin" or "public") is determined entirely by the server: the JWT is decoded to extract `user_id`, which is passed to the database function `get_leaderboard`, which queries the `enrollments` table to confirm HOST/MODERATOR status. The client cannot influence this decision.
* **[#29] Confirmed: Submission timing constraints already enforced** — The `POST /submissions` endpoint in [main.py](backend/app/main.py) checks (1) `status = 'ACTIVE'`, (2) `db_now >= start_time`, and (3) `db_now <= end_time` using the database clock (`CURRENT_TIMESTAMP`), rejecting submissions outside the valid window with HTTP 400.

### Tests
* **Extended `database/test_leaderboard_timing.py`** — Replaced the minimal existing test with a comprehensive 6-test regression suite covering:
  * HOST receives `view_mode: "admin"`, participant receives `view_mode: "public"`.
  * A participant token cannot self-elevate to admin view (privilege is DB-resolved).
  * `/users/{id}/history` endpoint remains functional after the `TRUE→NULL` fix.
  * Submission to a not-yet-running contest returns HTTP 400/403.
  * Submission to an active, running contest is accepted.
  * Leaderboard response contains all required fields (`user_id`, `username`, `total_score`, `rank`).

---

## [0.7.0] - 2026-08-06 (Contest Search & Filtering System)
### Added
* **Trigram Index for Contests** — Added `idx_contests_title_trgm` GIN index on `contests(title)` in [init.sql](database/init.sql) using `pg_trgm` to optimize substring search speed.
* **Database-Native Contest Search Function** — Created `search_contests_native(...)` PL/pgSQL function in [procedures.sql](database/procedures.sql) that returns filtered contest rows based on search queries, statuses, strategies, and timelines, resolved with visitor enrollment roles.
* **Advanced Query Parameters** — Updated the `GET /contests` endpoint in [main.py](backend/app/main.py) to support query-filtering parameters: `q`, `status`, `strategy`, and `timeline`.
* **Sidebar Filter GUI Controls** — Integrated an input text search, timeline dropdown, and ranking strategy dropdown inside the Contests List card in [index.html](backend/app/static/index.html) to filter dynamically with debounced key entry.

---

## [0.6.0] - 2026-08-06 (User Search & Database-Synchronized UTC Clock)
### Added
* **Trigram Index for User Search** — Added `idx_users_username_trgm` index on `users(username)` in [init.sql](database/init.sql) using `pg_trgm` to optimize case-insensitive substring searches.
* **Database-Native User Search Function** — Created `search_users_native(p_query)` PL/pgSQL function in [procedures.sql](database/procedures.sql) that queries database users matching the query substring, ordered alphabetically.
* **Server Time Synchronizer** — Exposes `/time` endpoint in [main.py](backend/app/main.py) returning database server timestamp (`CURRENT_TIMESTAMP`) for high-precision frontend time synchronization.
* **Search API Endpoint** — Exposes public `/users/search` endpoint in [main.py](backend/app/main.py) wrapping the native search function.
* **User Search UI Card** — Added a sidebar card in [index.html](backend/app/static/index.html) allowing visitors to search users by username and click through to view their profiles.
* **Global Sync UTC Timer** — Displays a live-updating clock in the top-bar header of [index.html](backend/app/static/index.html) that synchronizes with the database time on initialization via calculated time offset.

### Changed
* Made `/users/{user_id}/profile` and `/users/{user_id}/history` API endpoints login-optional (`get_optional_user`) so guest users can view profiles.
* Modified the frontend profile modal trigger to dynamically request authorization headers only if the client is logged in, allowing visitors to inspect stats.

---

## [0.5.1] - 2026-07-31 (Remove Contest Approval from API & GUI)
### Removed
* **`POST /contests/{id}/approve` endpoint** — removed from [main.py](backend/app/main.py) entirely. Contest approval is now a developer-only terminal action. Calling this endpoint will return 404. To approve a contest, connect to the database directly and run `SELECT approve_contest_native(<id>);` or `UPDATE contests SET status = 'ACTIVE' WHERE id = <id>;`.
* **Approve Contest button** — removed from [index.html](backend/app/static/index.html). The `approveContest()` JS function has been deleted. PENDING_APPROVAL contests now display a styled info notice explaining how to approve via the terminal.

### Changed
* Updated [docs/manual_testing.md](docs/manual_testing.md) Section 1 (GUI) and Section 2 (curl) to reflect that approval is a terminal-only SQL operation.

---

## [0.5.0] - 2026-07-31 (Contest Enhancements: Schemas, Capacity, Visibility, Kick & Announcements)
### Added
* **Task Submission Schemas** — Added mandatory `submission_schema JSONB NOT NULL` column to the `tasks` table in [init.sql](database/init.sql). Every task must declare a schema describing the expected shape of `submission_data`. Created new DB function `validate_submission_schema_native(task_id, submission_data)` in [procedures.sql](database/procedures.sql) that hard-rejects (RAISE EXCEPTION) submissions failing schema validation. API calls this before inserting into the queue.
* **Per-Task Submission Cooldowns** — Added `submission_cooldown_seconds INT DEFAULT 0` to `tasks`. Created `check_submission_cooldown_native(task_id, user_id)` that enforces minimum wait time between submissions. No-op when cooldown = 0. Returns HTTP 429 on cooldown violation.
* **Enrollment Capacity** — Added `max_participants INT` (nullable = unlimited) and `allow_late_enrollment BOOLEAN DEFAULT TRUE` to `contests` table. Extended `enroll_in_contest()` with a `FOR UPDATE` lock on the contest row to prevent concurrent enrollment race conditions, a capacity count check, a late-enrollment block, and a ban-list check.
* **Participant Kick & Ban** — New `kick_log` table as immutable audit trail. New `kick_participant_native()` function (HOST only): inserts kick record, deletes enrollment. Kicked users cannot re-enroll (checked in `enroll_in_contest`). Submission history is preserved.
* **Contest Visibility System** — New `contest_visibility` table with 6 configurable boolean flags per contest. Auto-created with defaults by `create_contest_native()`. Updated by `update_contest_visibility()` (HOST/MOD). Applied by API when returning contest data to public viewers.
* **Contest Announcements** — New `contest_announcements` table. Functions `post_announcement_native()` and `delete_announcement_native()` (HOST/MOD only). Public `GET /contests/{id}/announcements` endpoint.
* **Contest Profile Aggregator** — New `get_contest_profile(contest_id, viewer_id)` PL/pgSQL function joining 6 tables in a single query. Exposed via `GET /contests/{id}/profile`.
* **New API Endpoints** — `GET/PUT /contests/{id}/visibility`, `GET /contests/{id}/enrollment-info`, `DELETE /contests/{id}/members/{uid}`, `GET /contests/{id}/kick-log`, `POST/GET /contests/{id}/announcements`, `DELETE /announcements/{id}`, `GET /contests/{id}/profile`.
* **Documentation** — New file [docs/submission_schema_guide.md](docs/submission_schema_guide.md). Expanded [docs/contests.md](docs/contests.md) with sections 4–10. Updated [docs/architecture_and_erd.md](docs/architecture_and_erd.md) with new ERD and function catalogue. Updated [docs/manual_testing.md](docs/manual_testing.md) with Section 5 curl verification scenarios.
* **Task Ordering** — Added `task_order INT DEFAULT 0` to `tasks`. Tasks are now returned ordered by `task_order ASC, id ASC`.

### Changed
* Updated `create_contest_native` and `update_contest_native` to accept `max_participants` and `allow_late_enrollment`.
* Updated `add_task_native` and `update_task_native` to accept `submission_schema`, `submission_cooldown_seconds`, `task_order`.
* Updated `GET /contests`, `GET /contests/{id}` to return `max_participants`, `allow_late_enrollment`, and a `visibility` object.
* Updated `GET /contests/{id}/tasks` to return `submission_schema`, `submission_cooldown_seconds`, `task_order`, ordered by `task_order`.
* Updated [seed.sql](database/seed.sql) with `max_participants`, `allow_late_enrollment`, `submission_schema`, `submission_cooldown_seconds`, `task_order`; added `contest_visibility` rows and sample announcements; updated TRUNCATE order and sequence syncs.
* Updated [architecture_and_erd.md](docs/architecture_and_erd.md) ERD to version `v0.5.0` with all new tables and columns.

## [0.4.0] - 2026-07-27 (User Profiles, History, Activity Graphs & Contest Insights)
### Added
* Implemented database-native stored PL/pgSQL functions for user statistics, activity graphs, contest history, and cumulative score timelines (`get_user_profile_stats`, `get_user_activity_graph`, `get_user_contest_history`, `get_user_submission_history`, `get_contest_statistics`, `get_contest_submission_timeline`, `get_participant_score_progression`).
* Created backend API endpoints in [main.py](backend/app/main.py) to fetch profile metrics, participation histories, contest statistics, and user progression logs.
* Added a new documentation file [docs/profiles_and_statistics.md](docs/profiles_and_statistics.md) detailing the profile/statistics database logic and implementation details.
* Upgraded the frontend interface in [index.html](backend/app/static/index.html) to render user profiles inside a modal (with stats cards, activity timeline, verdict counts, and tables for contest/submission history).
* Added click triggers to Standings ranks and Members lists to open profile modals.
* Created a sub-tabs container inside contest details to toggle between Task lists and Contest Analytics summaries (total participants, active participants count, task success rates, and `date_bin` activity charts).
* Added composite indexes on the `submissions` table inside [init.sql](database/init.sql) to optimize user and contest history lookups.
* Created a server runner wrapper `backend/run_server.py` to configure uvicorn with Windows selector loop policies and bypass psycopg3 async connection failures on Windows.

### Changed
* Updated [seed.sql](database/seed.sql) to seed more realistic historical submissions over multiple days to populate profiles and activity timeline charts.
* Updated [architecture_and_erd.md](docs/architecture_and_erd.md) and [manual_testing.md](docs/manual_testing.md) to align with schema indexes, statistics helper functions, and manual API curl instructions.

## [0.3.1] - 2026-07-27 (Sequence Sync & Custom Strategy Hotfix)
### Added
* Created [docs/contests.md](docs/contests.md) detailing contest workflows, developer actions auditing procedures, seeded user roles mappings, and sequence out-of-sync troubleshooting.

### Fixed
* Fixed sequence out-of-sync error on inserting new contests by appending `setval` sequence synchronizers to the end of [seed.sql](database/seed.sql).
* Relaxed Pydantic validator in [main.py](backend/app/main.py) to allow any custom ranking strategy text.
* Replaced strategy select dropdown with a text input in [index.html](backend/app/static/index.html) to allow hosts to input custom strategies for developer approval.
* Enforced coherent validation in [main.py](backend/app/main.py) to block submissions to contests that are not `'ACTIVE'`.

## [0.3.0] - 2026-07-27 (Contest Systems, Tasks & Roles Release)
### Added
* Implemented native stored procedures inside [procedures.sql](database/procedures.sql) for database-level security checks and role validation (`create_contest_native`, `approve_contest_native`, `update_contest_native`, `delete_contest_native`, `add_task_native`, `update_task_native`, `delete_task_native`, `enroll_in_contest`, `update_contest_member_role`).
* Updated `get_leaderboard` function in [procedures.sql](database/procedures.sql) to calculate task-aware standings (summing max task scores for `'SUM'`, taking max overall for `'MAX'`, with backward-compatible fallback for contests without tasks).
* Created new API gateway endpoints inside [main.py](backend/app/main.py) for contest CRUD/approvals, tasks CRUD, enrollment, role updates, and user directory listings.
* Upgraded the frontend interface in [index.html](backend/app/static/index.html) to render dynamic contests cards, status tags, invitation code modals, task list components, role updates forms, and approval dev triggers.
* Expanded [architecture_and_erd.md](docs/architecture_and_erd.md) and [manual_testing.md](docs/manual_testing.md) to document the new DDL specs, ER diagram relationships, and manual verification instructions.

### Changed
* Altered `contests` table in [init.sql](database/init.sql) to add `status`, `judging_description`, and `invitation_code` fields.
* Altered `enrollments` table in [init.sql](database/init.sql) to add the `role` column (`'HOST'`, `'MODERATOR'`, `'PARTICIPANT'`) with native check constraints.
* Created the `tasks` table and added `task_id` reference to `submissions` in [init.sql](database/init.sql).
* Updated seed scripts in [seed.sql](database/seed.sql) to seed default tasks, mapped roles, and submissions referencing specific tasks.

## [0.2.0] - 2026-07-26 (Authentication & Registration Release)
### Added
* Created [docs/auth_architecture.md](docs/auth_architecture.md) detailing security trade-offs, PostgreSQL `pgcrypto` hashing, and JWT token management best practices.
* Implemented native user registration and verification stored procedures `register_user` and `verify_user_credentials` inside `database/procedures.sql`.
* Implemented endpoints `/auth/signup`, `/auth/login`, and `/auth/me` inside the API gateway at `backend/app/main.py`.
* Added token verification, bearer authorization headers, and registration/login widgets inside `backend/app/static/index.html`.

### Changed
* Enabled `pgcrypto` extension and added `password_hash` column to the `users` table inside `database/init.sql`.
* Updated seed scripts inside `database/seed.sql` to encrypt seed users (`sayma`, `nondiny`, `satil`, `tabib`) passwords natively using Bcrypt (`password123`).
* Updated telemetry ingestion `/submissions` to extract identity natively from validated JWT bearer token instead of using the request payload body user ID.
* Upgraded backend dependencies inside `backend/requirements.txt` to include `PyJWT`.
* Revised manual verification scenarios and E2E curl requests inside [docs/manual_testing.md](docs/manual_testing.md).
* Updated system architecture summaries and ERD flowcharts inside [docs/architecture_and_erd.md](docs/architecture_and_erd.md).

## [0.1.4] - 2026-07-26 (System Architecture & ERD Documentation)
### Added
* Created [docs/architecture_and_erd.md](docs/architecture_and_erd.md) containing the full Mermaid system flow architecture diagram and Entity Relationship Diagram (ERD) mapping users, contests, enrollments, and submissions.
* Added mandatory documentation sync rules in [.agents/AGENTS.md](.agents/AGENTS.md) that require AI agents to update `docs/architecture_and_erd.md` whenever table schemas, database scripts, or system flows are updated.

## [0.1.3] - 2026-07-25 (Documentation Rigor & Dashboard Testing)
### Added
* Expanded [docs/manual_testing.md](docs/manual_testing.md) to include a step-by-step walkthrough for evaluating the dynamic leaderboards and freeze logic using the barebones browser dashboard.
* Enforced strict rules in [.agents/AGENTS.md](.agents/AGENTS.md) that mandate synchronized documentation, walkthroughs, and manual testing guide updates for all AI agents.

## [0.1.2] - 2026-07-25 (Developer Utilities & Skeleton Dashboard)
### Added
* Created Python database migration script `database/setup_db.py` to automate running init/procedures/seed SQL files sequentially.
* Created a barebones HTML/JS dashboard at `backend/app/static/index.html` to visualize live scoreboard updates and test queue submission payloads directly in the browser.
* Configured FastAPI gateway to serve the static dashboard at `GET /`.
* Expanded Python `.gitignore` to include standard build, caching, virtual environments (`venv`), IDE, and OS ignore patterns.

### Changed
* Replaced `safwan` with `satil` in database seeds, team lists, and code examples.
* Configured `.agents/AGENTS.md` to require non-destructive AI edits, team user priorities (`sayma` and `nondiny` first), and synchronization rules for `docs/manual_testing.md`.

## [0.1.1] - 2026-07-25 (Seed Ordering & Portability Fix)
### Changed
* Prioritized `sayma` (ID 1) and `nondiny` (ID 2) at the top of database seed insertions and manual testing examples.
* Converted all absolute file links (`file:///...`) in repository markdown files (`README.md`, `docs/manual_testing.md`) to portable relative links for GitHub.
* Updated `.agents/AGENTS.md` to enforce relative link compliance and team seed ordering rules.

## [0.1.0] - 2026-07-25 (Skeleton Setup)
### Added
* Created project development rules `.agents/AGENTS.md`.
* Created `docs/conventions.md` (Git, issues, and board automation).
* Created `docs/developer_workflow.md` (Workspace routine guidelines).
* Created `docs/manual_testing.md` (Manual E2E verification guide).
* Created `docs/changelog.md` (This file).
