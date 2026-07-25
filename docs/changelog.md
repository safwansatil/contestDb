# Changelog

All notable changes to the ContestDB project will be documented in this file.

This project adheres to Semantic Versioning and matches commits/tasks with GitHub Issues.

---

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
