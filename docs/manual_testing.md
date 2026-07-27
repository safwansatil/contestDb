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
   * Click on the new contest. Note that a purple button **"Approve Contest (Dev Action)"** appears.
   * Click **Approve Contest (Dev Action)**. The status immediately updates to `ACTIVE` (green badge).
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

#### 2. Approve Contest (Developer/Admin Action)
```bash
curl -X POST http://127.0.0.1:8000/contests/<contest_id>/approve \
     -H "Authorization: Bearer <your_access_token>"
```
*Expected Response:* Returns message indicating the contest is active.

#### 3. Add Task to Contest
```bash
curl -X POST http://127.0.0.1:8000/contests/<contest_id>/tasks \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <your_access_token>" \
     -d '{
       "title": "Speed Test",
       "description": "Drive as fast as possible on the track",
       "max_score": 100
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


