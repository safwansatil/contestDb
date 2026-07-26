# Changelog

All notable changes to the ContestDB project will be documented in this file.

This project adheres to Semantic Versioning and matches commits/tasks with GitHub Issues.

---

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
