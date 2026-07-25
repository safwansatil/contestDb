# ContestDB: AI Agent Guidelines

You are an AI developer assisting Team 4 (satil, Tabib, Sayma, Nondiny) in building **ContestDB**, a database-native contest platform. To maintain project consistency and prevent regressions, you must adhere strictly to these engineering guidelines.

---

## 1. Architectural Mandate: Database-Native (Thin-Tier)
* **Application Layer (FastAPI)**: Serves only as a lightweight router, validator (Pydantic), and gateway. It must NOT contain business logic, score calculations, rating adjustments, or ranking computations.
* **Database Layer (PostgreSQL)**: The core brain. All calculation, ranking, queue management, and transaction-safety logic must live in SQL/PL/pgSQL (functions, triggers, procedures, views, and CTEs).
* **Driver (psycopg3)**: Use asynchronous pooling and execution. Prefer binary parameters and pipeline mode where appropriate for high-throughput batching.
* **Separation of Concerns**: The platform is contest-agnostic. The database stores submission inputs in a flexible `submission_data JSONB` column and expects external judge processes to write back standardized results (`verdict` and `score`). Do not embed domain-specific judging logic inside the database.

---

## 2. SQL & Schema Management
* All schema definitions must reside in `/database/init.sql` (DDL) and `/database/procedures.sql` (PL/pgSQL).
* Do not apply ad-hoc schema changes using raw SQL commands in the terminal. Always modify the source SQL files and, if needed, write incremental migration scripts.
* Ensure all tables use appropriate constraints (foreign keys, CHECK constraints, NOT NULL, defaults) to enforce database-level validation.

---

## 3. Concurrency & Queue Rules
* The submission queue must be driven by PostgreSQL.
* The claim loop must use a stored function with `FOR UPDATE SKIP LOCKED` to lock and return the next pending submission to prevent double-judging.
* Always release locks immediately by committing or rolling back transaction blocks as quickly as possible.

---

## 4. Environment Configuration
* **Single Global Config**: The project strictly uses a single `.env` file at the root directory of the workspace. Do NOT create local `.env` files in `backend/` or `worker/`.
* **Path Resolution**: Resolve the root `.env` path programmatically relative to the source code file:
  * For `backend`: `Path(__file__).resolve().parent.parent.parent / ".env"`
  * For `worker`: `Path(__file__).resolve().parent.parent / ".env"`

---

## 5. Changelog, Walkthrough, & Documentation Maintenance
* **Mandatory Logs**: Every time you modify or add features to this codebase, you must append an entry to `docs/changelog.md` outlining the changed files and summarizing the additions.
* **Verification Alignment**: If any schemas, APIs, or mock evaluations are modified, you must immediately update `docs/manual_testing.md` to keep the E2E verification steps and curl examples completely aligned.
* **Active Task Lists**: Maintain complete alignment with the active task list in `task.md`.
* **CRITICAL FOR AI AGENTS**: Any AI agent operating in this workspace must NOT proceed to make updates without validating that all of these files are kept synchronized. Failure to update the changelog and manual testing documentation upon schema or code changes constitutes a violation of repository guidelines.

---

## 6. Git, Branching, & Links
* Never push code directly to `main`.
* Ensure every code modification is aligned with a specific feature branch and references the active GitHub Issue ID.
* Use conventional commit headers: `feat(db):`, `feat(api):`, `fix(worker):`, `docs(team):`, `chore:`.
* **Portable Markdown Links**: All links inside repository markdown files (such as `README.md` or files under `docs/`) must use relative repository paths (`[title](path/to/file)`). Never write absolute local file URLs (`file:///...`) into repository files.

---

## 7. Conventions & Incremental Progression
* **No Destructive Modifying**: AI agents must not delete existing instructions, design choices, or files unless explicitly requested. Always add/append/extend features in an additive, backward-compatible manner.
* **Seeding Order**: When seeding users, always place `sayma` (ID 1) and `nondiny` (ID 2) at the top of the insertion list, followed by `satil` (ID 3) and `tabib` (ID 4). Use this order for manual testing curls.
