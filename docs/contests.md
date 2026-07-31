# Contest Systems, Tasks, and Roles Documentation

This document explains the features, implementation details, and issues encountered during the development of the Contest Systems, Tasks, and Roles modules in **ContestDB**.

---

## 1. Feature Specifications & System Workflows

### Contest Approval Workflow
To prevent uncoordinated contests from going live without proper database aggregation rules or API logic, the system uses a two-step validation workflow:
1. **Contest Hosting**: When a user creates a new contest, they provide details including title, times, invitation code, a custom **Ranking Strategy** string, and a **Judging Logic Description**. The contest is stored with the status `'PENDING_APPROVAL'`.
2. **Developer Approval**: A system developer/administrator reviews the custom judging description and strategy. Once they hook up any necessary code or database rules, they approve the contest, shifting its status to `'ACTIVE'`. Only `'ACTIVE'` contests accept enrollments and submissions.

### Tasks CRUD
Each contest holds individual tasks (problems or challenges). Hosts and Moderators of a contest can dynamically create, edit, or delete tasks. Submissions from participants are mapped directly to a specific task (`task_id`) within the contest.

### Contest-Specific Roles
Each user enrolled in a contest has one of the following contest-specific roles:
* **`HOST`**: Full administrative privileges (edit/delete contest, manage user roles, CRUD tasks, and view Standings bypassing freeze).
* **`MODERATOR`**: Operational privileges (edit contest parameters, CRUD tasks, and view Standings bypassing freeze).
* **`PARTICIPANT`**: Contestant privileges (enroll in the contest, view tasks, submit solutions, and view Standings respecting scoreboard freeze).

### Seeded User Roles (Quick Reference)
The default database seeds [database/seed.sql](database/seed.sql) map users to roles as follows:
* **Contest 1 (Max Speed Run)**:
  * `sayma` (ID 1): **`HOST`** (Creator)
  * `nondiny` (ID 2): **`MODERATOR`**
  * `satil` (ID 3): **`PARTICIPANT`**
  * `tabib` (ID 4): *Unenrolled*
* **Contest 2 (Accumulator Math Quiz)**:
  * `sayma` (ID 1): **`HOST`** (Creator)
  * `nondiny` (ID 2): **`PARTICIPANT`**
  * `tabib` (ID 4): **`PARTICIPANT`**
  * `satil` (ID 3): *Unenrolled*

### Enrollment & Invitation Codes
* Public contests (without an invitation code) allow any registered user to join as a `PARTICIPANT`.
* Private contests (configured with an `invitation_code`) require users to provide the correct code during enrollment. Only hosts and moderators can view the code via the API; other users only see that a code is required.

---

## 2. Technical Decisions & Rationale

### What Counts as "Developer Action"?
When a contest is created, it goes into the main `contests` table with the status `'PENDING_APPROVAL'`. The **Developer Action** workflow is as follows:
1. **Developer Audit**: The developer (who has direct database access and acts as the system admin) inspects the requested contest parameters inside the `contests` table:
   ```sql
   SELECT id, title, ranking_strategy, judging_description FROM contests WHERE status = 'PENDING_APPROVAL';
   ```
2. **Code Implementation**: The developer reviews the requested `judging_description` and `ranking_strategy` (e.g. they might need to write a new stored function in `database/procedures.sql` to support a new score calculation formula, or extend the worker python code).
3. **Approve / Release**: Once the developer implements and deploys the necessary features for the contest, they run the approval command (or invoke the frontend "Approve" button, which calls `POST /contests/{contest_id}/approve` and runs `approve_contest_native` natively):
   ```sql
   SELECT approve_contest_native(contest_id);
   ```
   This shifts the status to `'ACTIVE'`, making the contest live and open for enrollment.

### Coherent Logic: Blocking Submissions for Draft Contests
To ensure a contest cannot accept submissions before the developer approves the logic and database support is complete:
* The `/submissions` endpoint in [main.py](backend/app/main.py) natively validates the contest's status.
* Submissions made to contests with a status of `'PENDING_APPROVAL'` are blocked with an HTTP 400 Bad Request error.
* Participants can only submit to `'ACTIVE'` contests.

### Why is Ranking Strategy a Text Field?
Initially, the ranking strategy was limited to a dropdown select with `"SUM"` and `"MAX"` options. However, because ContestDB is designed to be **contest-agnostic** and thin-tier:
* The platform does not pre-impose strict judging algorithms.
* By making **Ranking Strategy** a flexible text field (e.g., accepting `SUM`, `MAX`, `ICPC`, `IOI`, `Custom LFR`), hosts can propose any judging structure they need.
* System developers can then review these draft strategies and implement custom SQL/PL/pgSQL functions or backend APIs for them before approving the contest.

---

## 3. Troubleshooting: Sequence Synchronization Error

### What Happened
During contest creation, the following error occurred:
```
Creation failed: duplicate key value violates unique constraint "contests_pkey"
DETAIL: Key (id)=(1) already exists.
```

### Why it Happened
In PostgreSQL, a table using a `SERIAL` (or `IDENTITY`) column relies on an implicit sequence generator (e.g., `contests_id_seq`) to automatically assign unique IDs to new rows.
* When our database seed script [database/seed.sql](database/seed.sql) populated the initial database using explicit IDs (e.g., `INSERT INTO contests (id, ...) VALUES (1, ...)`), it bypassed the sequence generator.
* Consequently, the sequence counter remained at `1`.
* When the application tried to insert a new contest natively without providing an ID (expecting the sequence to generate the next number), PostgreSQL attempted to assign `1`. Because `1` was already seeded, a unique key constraint violation was thrown.

### How it was Resolved
We appended sequence synchronization commands to the bottom of the seed script [database/seed.sql](database/seed.sql) to automatically align the sequence counters with the highest existing IDs after seeding:
```sql
SELECT setval('contests_id_seq', COALESCE((SELECT MAX(id) FROM contests), 1));
SELECT setval('users_id_seq', COALESCE((SELECT MAX(id) FROM users), 1));
SELECT setval('tasks_id_seq', COALESCE((SELECT MAX(id) FROM tasks), 1));
SELECT setval('submissions_id_seq', COALESCE((SELECT MAX(id) FROM submissions), 1));
```
Running the setup script [database/setup_db.py](database/setup_db.py) now completely resolves this issue, ensuring future inserts generate the correct unique IDs.

---

## 4. Enrollment Capacity & Late Enrollment

### `max_participants` — Enrollment Cap
The `contests` table has a nullable `max_participants INT` column. When set to `NULL` (the default), enrollment is unlimited. When set to a positive integer, the contest has a hard cap on participant count.

The capacity check is enforced inside `enroll_in_contest()` using a `SELECT ... FOR UPDATE` lock on the `contests` row. This prevents race conditions where two users simultaneously enroll when only one spot remains — the lock serializes the two transactions so only one succeeds.

The check compares `COUNT(*) FROM enrollments WHERE role = 'PARTICIPANT'` against `max_participants` and raises an exception if full.

### `allow_late_enrollment` — Time-Based Enrollment Gate
When set to `FALSE`, enrollment is rejected if `NOW() > start_time`. This is enforced inside `enroll_in_contest()` after the cap check. When `TRUE` (default), participants can join at any time while the contest is ACTIVE.

---

## 5. Task Submission Schemas

### Why Submission Schemas?
Every task in ContestDB has a `submission_schema JSONB NOT NULL` column. This is mandatory — a task cannot be created without a schema. The schema declares what shape a valid `submission_data` payload must have.

This keeps the submission contract explicit and enforced entirely inside PostgreSQL via `validate_submission_schema_native()`.

### Schema Format
```json
{
  "required_keys": ["key1", "key2"],
  "numeric_keys": ["key1"]
}
```
- `required_keys`: All listed keys must exist in `submission_data`.
- `numeric_keys`: All listed keys must have JSON number type (`jsonb_typeof(...) = 'number'`).

### Validation Flow
1. Participant submits via `POST /submissions`.
2. API calls `SELECT validate_submission_schema_native(task_id, submission_data::jsonb)`.
3. DB function fetches the task's schema, iterates over `required_keys` and `numeric_keys`.
4. If any key is missing or wrong type, `RAISE EXCEPTION` is thrown → API returns HTTP 400 with the DB error message.
5. If all checks pass, submission is inserted into the queue as `PENDING`.

### Example: Speed Run Task
```json
{"required_keys": ["run_time_seconds", "restarts"], "numeric_keys": ["run_time_seconds", "restarts"]}
```

### Example: Math Quiz Task
```json
{"required_keys": ["score", "verdict"], "numeric_keys": ["score"]}
```

---

## 6. Submission Cooldowns (Per-Task)

The `tasks.submission_cooldown_seconds INT` column (default `0`) sets a per-task minimum wait time between submissions from the same user.

- `0` = no cooldown enforced (the DB function returns immediately — zero overhead).
- `> 0` = cooldown active. The function queries `MAX(submitted_at)` from `submissions WHERE task_id AND user_id`, computes elapsed seconds, and raises an exception with seconds remaining if the cooldown has not expired.

This is enforced inside PostgreSQL via `check_submission_cooldown_native(task_id, user_id)`, called by the API before schema validation. If triggered, the API returns HTTP 429.

---

## 7. Participant Kick & Ban System

### How Kicking Works
A contest HOST can remove any PARTICIPANT or MODERATOR from a contest via `DELETE /contests/{id}/members/{uid}`. This calls `kick_participant_native()` which:
1. Verifies the requester is HOST.
2. Verifies the target is not another HOST or the requester themselves.
3. Inserts a row into `kick_log` with timestamp and optional reason.
4. Deletes the enrollment row.

### Permanent Ban
The `kick_log` table acts as a ban list. `enroll_in_contest()` checks `kick_log` before allowing re-enrollment — kicked users receive an exception if they try to join again.

### Submission Preservation
A kicked participant's submissions are **not deleted**. They remain in the `submissions` table for historical accuracy and leaderboard record integrity. Only the enrollment row is removed.

### Kick Log
The full audit trail is available to HOST/MODERATOR via `GET /contests/{id}/kick-log`. Each record shows who was kicked, by whom, when, and the reason.

---

## 8. Contest Profile & Visibility System

### `contest_visibility` Table
Every contest has exactly one row in `contest_visibility`, auto-created with defaults when `create_contest_native()` is called. The table controls which fields public viewers can see on the contest page.

| Flag | Default | Description |
|---|---|---|
| `show_participant_count` | `TRUE` | Whether enrollment numbers are visible |
| `show_leaderboard` | `TRUE` | Whether the leaderboard is public |
| `show_member_list` | `FALSE` | Whether the participant list is public |
| `show_task_list` | `TRUE` | Whether tasks are visible before contest ends |
| `show_statistics` | `FALSE` | Whether contest analytics are public |
| `show_submission_count` | `FALSE` | Whether total submission count is shown |

### Updating Visibility
HOST or MODERATOR can change any flag via `PUT /contests/{id}/visibility`. The update is an upsert (`ON CONFLICT DO UPDATE`) into `contest_visibility`. All logic is in `update_contest_visibility()` (PL/pgSQL).

### How the API Applies Visibility
- `GET /contests/{id}` and `GET /contests` return a `visibility` object with all flags.
- `GET /contests/{id}/profile` (the full profile aggregator) conditionally includes fields like `current_participants` only if `show_participant_count = TRUE` OR the viewer is HOST/MODERATOR.
- Viewers with HOST or MODERATOR role always see everything regardless of visibility flags.

---

## 9. Contest Announcements

HOSTs and MODERATORs can post broadcast messages to a contest via `POST /contests/{id}/announcements`. Announcements are stored in `contest_announcements` and are visible to all viewers via `GET /contests/{id}/announcements` (public endpoint, no auth required).

Deletion is available to HOST/MOD via `DELETE /announcements/{id}`.

Announcement count and the title of the latest announcement are included in the contest profile aggregator (`GET /contests/{id}/profile`).

---

## 10. Contest Profile Aggregator

The `GET /contests/{id}/profile` endpoint calls `get_contest_profile(contest_id, viewer_user_id)` — a single PL/pgSQL function that joins:
- `contests` metadata
- `enrollments` for participant count
- `kick_log` for ban count
- `tasks` for task count
- `contest_announcements` for announcement count and latest title preview
- `contest_visibility` for visibility flags
- `enrollments` again for the viewer's role

All in one SQL query using CTEs and LEFT JOINs. The API layer then applies visibility gating to decide which fields to expose.
