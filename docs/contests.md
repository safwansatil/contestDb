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
