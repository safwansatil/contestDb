# Changelog

All notable changes to the ContestDB project will be documented in this file.

This project adheres to Semantic Versioning and matches commits/tasks with GitHub Issues.

---

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
