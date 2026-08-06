# Manual Testing Guide

This guide details the step-by-step instructions to initialize, run, and manually test the ContestDB Walking Skeleton end-to-end flow.

---

## 1. Initialization

1. **Setup Global `.env`**:
   At the project root directory, create a `.env` file using [.env.example](.env.example) as a template. Paste your connection URL into `DATABASE_URL`.

---

## 2. Running the System
Open two terminals on your machine:

### Terminal 1: Start the FastAPI Server
1. Navigate to backend: `cd backend`
2. Initialize virtual environment: `python -m venv venv`
3. Activate virtual environment:
   * **Windows (PowerShell)**: `.\venv\Scripts\Activate.ps1`
   * **Linux/macOS**: `source venv/bin/activate`
4. Install requirements: `pip install -r requirements.txt`
5. Start server:
   * **Windows**: `python run_server.py` (Applies selector event loop policy to prevent psycopg3 connection timeouts)
   * **Linux/macOS**: `uvicorn app.main:app --reload`
6. Confirm the console prints: `INFO:backend:Opening database connection pool...`

### Terminal 2: Start the Judge Worker
1. Navigate to worker: `cd worker`
2. Initialize virtual environment: `python -m venv venv`
3. Activate virtual environment:
   * **Windows (PowerShell)**: `.\venv\Scripts\Activate.ps1`
   * **Linux/macOS**: `source venv/bin/activate`
4. Install requirements: `pip install -r requirements.txt`
5. Start worker: `python worker.py`
6. Confirm the console prints: `Starting ContestDB Mock Worker...`

---

## 3. Step-by-Step Test Scenarios

### Option A: Testing via the Frontend Dashboard (Recommended)
FastAPI serves the premium contest dashboard at the root URL.
1. Open your browser and navigate to `http://127.0.0.1:8000`.
2. **Access State**: The dashboard starts in **Guest Mode**. You can see the scoreboard standings but cannot submit payloads or modify anything.
3. **Log In**: 
   * In the Sign In tab, enter seeded user credentials:
     * Username: `sayma`
     * Password: `password123`
   * Click **Sign In**.
   * Note the header updates to show "Hello, sayma".
4. **Test Contest Creation & Approval Workflow**:
   * On the left panel under "Host New Contest", fill in:
     * Title: `LFR Speed Run 2026`
     * Strategy: `MAX`
     * Start/Freeze/End times (e.g. set Start/Freeze/End to today's date/times).
     * Invitation Code: `joinlfr`
     * Judging Logic: `Speed run of line follower. Deduct 2 points per restart from base 100.`
   * Click **Create & Submit for Approval**.
   * Note in the contest list, the new contest appears with a yellow `PENDING_APPROVAL` badge.
   * The contest card shows an info notice: **"Awaiting Developer Approval"** — no button is shown.
   * To activate the contest, a developer must connect to the database directly in a terminal and run:
     ```sql
     SELECT approve_contest_native(<contest_id>);
     ```
   * After running the SQL, refresh the page. The status updates to `ACTIVE` (green badge).
5. **Test Task Management**:
   * Since Sayma is the creator, she is enrolled as the `HOST` of `LFR Speed Run 2026`.
   * The **"Add Task to Contest"** form is now visible.
   * Add a new task:
     * Title: `Problem A: Line Follower Obstacle Avoidance`
     * Description: `Follow the line while avoiding obstacles. Time limit: 120 seconds.`
     * Max Score: `100.0`
   * Click **Add Task**. It will appear instantly under the contest's task list.
6. **Test Role Management & Invitation Codes**:
   * Log out from Sayma, and sign in as `nondiny` / `password123`.
   * Click on the new contest `LFR Speed Run 2026` from the list. Note that Nondiny is listed as `Unenrolled`.
   * Click **Join Contest**. A modal pops up asking for the invitation code.
   * Enter an incorrect code first and submit -> an error is logged in the feed.
   * Enter the correct code `joinlfr` and submit -> registration succeeds, and Nondiny is enrolled as a `PARTICIPANT`.
   * Switch the dropdown in the submission panel to the new task `Problem A: Line Follower Obstacle Avoidance` and submit telemetry: `{"run_time_seconds": 45.0, "restarts": 1}`.
   * In the worker terminal, you will see the worker successfully claim and judge this submission. Standings will refresh with the new score.
   * Switch back to `sayma` / `password123` (who is the `HOST`).
   * Scroll to the **Contest Role Manager** card. Select `nondiny` from the dropdown and promote her to `MODERATOR`.
   * Click **Update Role**. Check the "Current Members" list to verify that Nondiny is now a `MODERATOR`.

---

### Option B: Testing via Terminal (Curl)

#### 1. Create Contest (Starts as PENDING_APPROVAL)
Log in as `sayma` to get the access token, then:
```bash
curl -X POST http://127.0.0.1:8000/contests \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <your_access_token>" \
     -d '{
       "title": "Robotics Challenge",
       "ranking_strategy": "SUM",
       "start_time": "2026-07-27T15:00:00Z",
       "freeze_time": "2026-07-27T17:00:00Z",
       "end_time": "2026-07-27T18:00:00Z",
       "invitation_code": "secretcode",
       "judging_description": "Score is points sum"
     }'
```
*Expected Response:* Returns `contest_id` and a pending approval message.

#### 2. Approve Contest (Developer/Admin Terminal Action)

> **This is intentionally NOT an API endpoint.** Approval must be done directly in the database.
> The `/contests/{id}/approve` HTTP route has been removed by design.

Connect to your PostgreSQL instance (e.g. via `psql` or the Neon console) and run:
```sql
-- Option A: via stored function
SELECT approve_contest_native(<contest_id>);

-- Option B: direct update
UPDATE contests SET status = 'ACTIVE' WHERE id = <contest_id>;
```
*Expected:* The contest row's `status` changes to `ACTIVE`. The next `GET /contests` call will reflect the change.

#### 3. Add Task to Contest
```bash
curl -X POST http://127.0.0.1:8000/contests/<contest_id>/tasks \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <your_access_token>" \
     -d '{
       "title": "Speed Test",
       "description": "Drive as fast as possible on the track",
       "max_score": 100,
       "submission_schema": {
         "required_keys": ["run_time_seconds", "restarts"],
         "numeric_keys": ["run_time_seconds", "restarts"]
       },
       "submission_cooldown_seconds": 0,
       "task_order": 1
     }'
```
*Expected Response:* Returns `task_id` and success message.

#### 4. Enroll in Contest with Invitation Code
Log in as another user (e.g. `satil` / `password123`) to get a token, then join:
```bash
curl -X POST http://127.0.0.1:8000/contests/<contest_id>/enroll \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <satil_access_token>" \
     -d '{"invitation_code": "secretcode"}'
```
*Expected Response:* Returns enrollment success.

#### 5. Promote Participant to Moderator (Host Action)
Log back in as `sayma` and update Satil's role:
```bash
curl -X POST http://127.0.0.1:8000/contests/<contest_id>/members/role \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <sayma_access_token>" \
     -d '{
       "target_user_id": 3,
       "new_role": "MODERATOR"
     }'
```
*Expected Response:* Role updated success.

---

### 4. Profiles & Statistics APIs Verification (New Features)

#### A. Fetch User Profile Statistics & Activity Graph
Verify user statistics and activity dates:
```bash
curl -X GET http://127.0.0.1:8000/users/1/profile \
     -H "Authorization: Bearer <sayma_access_token>"
```
*Expected Response:* Returns `user_id`, `username`, user metadata, consolidated statistics (contests, submissions, solved tasks count, averages, dynamic verdict breakdown), and activity dates list.

#### B. Fetch User Histories
Retrieve contest history and submission logs:
```bash
curl -X GET http://127.0.0.1:8000/users/1/history \
     -H "Authorization: Bearer <sayma_access_token>"
```
*Expected Response:* Returns `contest_history` (with roles, score, and rank) and a list of the last 20 submissions.

#### C. Fetch Contest Analytics & Timeline
Get contest metrics:
```bash
curl -X GET http://127.0.0.1:8000/contests/1/statistics \
     -H "Authorization: Bearer <sayma_access_token>"
```
*Expected Response:* Returns total participants, active participants count, total submissions, task-by-task averages, and the dynamic `date_bin` activity timeline buckets.

#### D. Fetch Participant Score Growth Timeline
Fetch score progression for a user in a contest:
```bash
curl -X GET http://127.0.0.1:8000/contests/1/progress/3 \
     -H "Authorization: Bearer <sayma_access_token>"
```
*Expected Response:* Returns a chronological list of cumulative score growth after each submission during the contest.

---

## 5. v0.5.0 Feature Verification (New Features)

> **Before testing**: Run `python database/setup_db.py` to apply all schema changes and re-seed the database.

### A. Enrollment Capacity Check
Contest 1 has `max_participants = 5` and currently has sayma + nondiny + satil (3 participants). Try enrolling tabib (not yet in Contest 1):
```bash
# Login as tabib first
curl -X POST http://127.0.0.1:8000/auth/login -H "Content-Type: application/json" -d '{"username": "tabib", "password": "password123"}'
# Then enroll in Contest 1
curl -X POST http://127.0.0.1:8000/contests/1/enroll \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <tabib_token>" \
     -d '{}'
```
*Expected:* Enrollment succeeds (2 spots remain). Then add 2 more users and try again — expect HTTP 400 with `This contest is full`.

### B. Enrollment Info
```bash
curl http://127.0.0.1:8000/contests/1/enrollment-info
```
*Expected:* `{"max_participants": 5, "current_participants": 3, "spots_remaining": 2, "allow_late_enrollment": true, "total_kicked": 0}`

### C. Submission Schema Validation — Missing Key
Login as satil (enrolled in Contest 1), submit to Task 1 with a wrong payload:
```bash
curl -X POST http://127.0.0.1:8000/submissions \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <satil_token>" \
     -d '{"contest_id": 1, "task_id": 1, "submission_data": {"wrong_key": 99}}'
```
*Expected:* HTTP 400 — `Submission schema validation failed: missing required key "run_time_seconds"`

### D. Submission Schema Validation — Wrong Type
```bash
curl -X POST http://127.0.0.1:8000/submissions \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <satil_token>" \
     -d '{"contest_id": 1, "task_id": 1, "submission_data": {"run_time_seconds": "fast", "restarts": 0}}'
```
*Expected:* HTTP 400 — `Submission schema validation failed: key "run_time_seconds" must be a number`

### E. Submission Cooldown
Task 1 has `submission_cooldown_seconds = 30`. Submit twice within 30 seconds:
```bash
# First submit (succeeds)
curl -X POST http://127.0.0.1:8000/submissions \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <satil_token>" \
     -d '{"contest_id": 1, "task_id": 1, "submission_data": {"run_time_seconds": 10.0, "restarts": 0}}'
# Second submit immediately (should be blocked)
curl -X POST http://127.0.0.1:8000/submissions \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <satil_token>" \
     -d '{"contest_id": 1, "task_id": 1, "submission_data": {"run_time_seconds": 9.0, "restarts": 0}}'
```
*Expected:* Second call returns HTTP 429 — `Submission cooldown active: please wait N more second(s)`

### F. Kick Participant
Login as sayma (HOST of Contest 1), kick satil:
```bash
curl -X DELETE http://127.0.0.1:8000/contests/1/members/3 \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <sayma_token>" \
     -d '{"reason": "Violated contest rules"}'
```
*Expected:* `{"message": "Participant (ID 3) successfully removed from contest"}`

Now try re-enrolling as satil:
```bash
curl -X POST http://127.0.0.1:8000/contests/1/enroll \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <satil_token>" \
     -d '{}'
```
*Expected:* HTTP 400 — `You have been removed from this contest and cannot re-enroll`

### G. Kick Log
```bash
curl http://127.0.0.1:8000/contests/1/kick-log \
     -H "Authorization: Bearer <sayma_token>"
```
*Expected:* List containing satil's kick record with reason, kicked_by, and kicked_at.

### H. Contest Visibility
Fetch current visibility:
```bash
curl http://127.0.0.1:8000/contests/1/visibility
```
*Expected:* Returns all 6 boolean flags.

Update visibility (hide leaderboard from public):
```bash
curl -X PUT http://127.0.0.1:8000/contests/1/visibility \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <sayma_token>" \
     -d '{"show_participant_count": true, "show_leaderboard": false, "show_member_list": false, "show_task_list": true, "show_statistics": false, "show_submission_count": false}'
```
*Expected:* `{"message": "Contest visibility settings updated successfully"}`

### I. Announcements
Post an announcement as sayma:
```bash
curl -X POST http://127.0.0.1:8000/contests/1/announcements \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <sayma_token>" \
     -d '{"title": "Important Update", "body": "Please check the revised scoring rules."}'
```
*Expected:* Returns `announcement_id`.

Fetch all announcements (public):
```bash
curl http://127.0.0.1:8000/contests/1/announcements
```
*Expected:* List of announcements (including 2 seeded ones + the one just posted).

### J. Contest Profile Aggregator
```bash
curl http://127.0.0.1:8000/contests/1/profile
```
*Expected:* Full profile including title, status, task_count (1), announcement_count (2+), capacity info (if show_participant_count=TRUE), viewer_role (null if unauthenticated), and visibility flags.

Repeat with sayma's token:
```bash
curl http://127.0.0.1:8000/contests/1/profile \
     -H "Authorization: Bearer <sayma_token>"
```
*Expected:* Same but also includes `invitation_code`, `total_kicked`, and `spots_remaining` since sayma is HOST.

### K. Synchronized Database Time
Fetch the current database server timestamp:
```bash
curl http://127.0.0.1:8000/time
```
*Expected:* `{"server_time": "2026-08-06T18:35:00+06:00"}` (with actual database time).

### L. User Search
Search for a user natively via substring (public):
```bash
curl http://127.0.0.1:8000/users/search?q=sayma
```
*Expected:* A JSON array containing matching users:
```json
[
  {
    "id": 1,
    "username": "sayma",
    "created_at": "2026-08-06T12:00:00+00:00"
  }
]
```

Try search with a partial query:
```bash
curl http://127.0.0.1:8000/users/search?q=sa
```
*Expected:* Users with username matching "sa" (e.g. sayma, satil).

### M. Contest Search & Filtering
Search for contests containing a keyword:
```bash
curl http://127.0.0.1:8000/contests?q=code
```
*Expected:* List of contests containing the string "code" in their title.

Filter contests by timeline status (ONGOING):
```bash
curl http://127.0.0.1:8000/contests?timeline=ONGOING
```
*Expected:* List of contests where `start_time <= NOW()` and `end_time >= NOW()`.

Filter contests by ranking strategy (ICPC):
```bash
curl http://127.0.0.1:8000/contests?strategy=ICPC
```
*Expected:* List of contests with the ICPC ranking strategy.


