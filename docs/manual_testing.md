# Manual Testing Guide (Browser-Focused)

This guide details the step-by-step instructions to initialize, run, and manually test the ContestDB system from end-to-end, with a primary focus on using the built-in browser dashboard.

---

## 1. Setup & Running the System

### 1.1 Database Initialization
1. Ensure your `.env` file at the project root has a valid `DATABASE_URL` (or `MIGRATION_DATABASE_URL`).
2. Open a terminal and run the database setup script to migrate and seed the database:
   ```bash
   cd backend
   .\venv\Scripts\Activate.ps1   # or source venv/bin/activate on Linux/Mac
   python ../database/setup_db.py
   ```

### 1.2 Start the Services
You need three terminals running simultaneously.

**Terminal 1: FastAPI Gateway Server (Backend)**
```bash
cd backend
.\venv\Scripts\Activate.ps1
python run_server.py
```
*(Wait for `INFO:backend:Opening database connection pool...`)*

**Terminal 2: Background Evaluation Worker (Worker)**
```bash
cd worker
.\venv\Scripts\Activate.ps1
python worker.py
```
*(Wait for `Starting ContestDB Mock Worker...`)*

**Terminal 3: React Vite Dashboard (Frontend)**
```bash
cd frontend
npm install
npm run dev
```
*(Wait for the Vite server to start, usually on `http://localhost:5173`)*

---

## 2. Browser E2E Workflow Testing

Open your browser and navigate to the frontend dashboard at **`http://localhost:5173`** (or the port Vite gave you). The dashboard starts in **Guest Mode**. 

### 2.1 Authentication & Role Verification
1. Click the **Sign In** tab.
2. Enter the credentials for the seeded user:
   - **Username**: `sayma`
   - **Password**: `password123`
3. Click **Sign In**. The top right should now greet you with "Hello, sayma".

### 2.2 Contest Creation (Host)
1. Locate the **Host a contest** button on the top right.
2. Fill out the form:
   - **Title**: `Browser Testing Contest`
   - **Contest Format**: `ICPC Coding Tournament`
   - **Start/Freeze/End times**: Pick dates/times that make the contest currently active.
   - **Invitation Code**: `testcode`
   - **Judging Logic**: `Testing standard evaluation`
3. Click **Create contest**.
4. The contest will appear in the main list with a red `Pending Approval` badge.

### 2.3 Contest Configuration & Approval (Developer Action)
1. Click **Sign In** and login as the seeded developer: `safwansatil` / `password123`.
2. Notice you have a **Dev Portal** button in the navigation bar instead of "Host a contest".
3. Click **Dev Portal** to open the Developer Dashboard.
4. Locate the `Browser Testing Contest` in the list and click it.
5. In the Developer config modal, you can review the tasks, and configure their `webhook_url` and `submission_schema`.
6. Click **Approve Contest**. 
7. Refresh your browser or go back to Explore. The contest badge should now be green (`Active`).

### 2.4 Task & Member Management
1. Log back in as `sayma` (the Host).
2. Click on `Browser Testing Contest` in the Explore list to view its details.
3. Switch to the **Tasks** tab.
4. Click **Add New Task** and enter:
   - **Task Title**: `Task 1: Basic Math`
   - **Description**: `Add two numbers`
   - **Max Score**: `100`
5. Click **Create task**. It will appear instantly in the Task List.
6. (Optional) The Developer (`safwansatil`) can now go back to the Dev Portal and inject the webhook logic into this new task.

### 2.5 Participant Enrollment & Submission
1. Log out, then log in as a participant: `nondiny` / `password123`.
2. Click on `Browser Testing Contest`. Notice Nondiny is `Unenrolled`.
3. Click **Join Contest**. A modal will appear.
4. Enter the invitation code: `testcode` and submit.
5. In the task submission panel, select `Task 1: Basic Math`.
6. Enter a JSON payload into the submission box (e.g., `{"run_time_seconds": 12, "restarts": 0}`) and submit.
7. Switch to your worker terminal — you should see the worker claim and judge the submission.
8. The browser standings will refresh automatically to reflect the new score.

---

## 3. Verifying Analytics & Profiles (Browser)

ContestDB includes deep analytics and profile modals accessible directly from the UI.

### 3.1 User Profiles
1. In any contest's **Standings** or **Members** list, click on a user's name (e.g., `nondiny`).
2. A **Profile Modal** will open displaying:
   - Total Score, Win Rate, and submission counts.
   - A donut chart showing verdict breakdowns (e.g., % of AC, WA, TLE).
   - A timeline graph showing their activity over the last 30 days.
   - Tabs for their complete **Contest History** and **Submission History**.

### 3.2 Contest Statistics
1. Navigate to a seeded contest (e.g., Contest ID 1).
2. Inside the contest details panel, switch the tab from **Tasks** to **Analytics**.
3. Verify that the analytics dashboard loads:
   - Cards showing Total Participants, Active Participants, and Total Submissions.
   - Task-by-task success rates (averages).
   - An interactive bar chart showing submission activity bucketed by time intervals.

### 3.3 Searching & Filtering
1. **Contest Filter**: Above the contest list, use the search bar to type a keyword (e.g., "Code"). The list will instantly debounce and filter. You can also use the dropdowns to filter by `Timeline` (e.g., ONGOING) or `Strategy` (e.g., ICPC).
2. **User Search**: In the left sidebar, use the **User Directory Search**. Type "sa" to instantly see results for `sayma` and `satil`. Click on their names to open their public profiles.

---

## 4. Advanced API / Terminal Testing

For features not fully exposed in the dashboard, you can use `curl` or automated test scripts.

### 4.1 Async Webhook Execution Delegation
Test that tasks can offload judging to an external webhook:
```bash
cd backend
.\venv\Scripts\Activate.ps1
python ../database/tests/test_webhook_async.py
```
*Expected Output:* Prints step-by-step console logs concluding with `[PASS] Async webhook flow verified!`.

### 4.2 Leaderboard Freeze & Timing Security Constraints
Verify that participants cannot bypass freeze time and cannot submit outside the contest window:
```bash
cd backend
.\venv\Scripts\Activate.ps1
python ../database/test_leaderboard_timing.py
```
*Expected Output:* Runs 6 regression tests. All must report `[PASS]`. Exit code `0`.

### 4.3 Capacity & Cooldown (cURL)
1. Get a token via `/auth/login`.
2. Try submitting to a task with a cooldown twice in rapid succession.
   ```bash
   curl -X POST http://127.0.0.1:8000/submissions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer <token>" \
        -d '{"contest_id": 1, "task_id": 1, "submission_data": {"run_time_seconds": 10.0}}'
   ```
   *Expected Response on 2nd attempt:* `HTTP 429 Too Many Requests: Submission cooldown active: please wait N more second(s)`.
