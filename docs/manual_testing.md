# Manual Testing Guide

This guide details the step-by-step instructions to initialize, run, and manually test the ContestDB Walking Skeleton end-to-end flow.

---

## 1. Database Setup & Initialization
Since we are using **Neon Serverless PostgreSQL** as our database engine, follow these steps to initialize your schema:

1. **Get Connection String**:
   Log in to your Neon console, create or select your project, and copy your connection string (e.g., `postgresql://user:pass@ep-cool-snowflake-123456.neon.tech/neondb?sslmode=require`).
2. **Setup Global `.env`**:
   At the project root directory, create a `.env` file using [.env.example](.env.example) as a template. Paste your connection URL into `DATABASE_URL`.
3. **Execute SQL scripts on Neon**:
   Instead of copy-pasting code into Neon's online interface, you can run our automated script from the root directory:
   ```bash
   python database/setup_db.py
   ```
   *This script reads your database URL and automatically runs the database files in the correct sequence:*
   * [database/init.sql](database/init.sql) (creates tables and indexes).
   * [database/procedures.sql](database/procedures.sql) (creates queue lock & dynamic leaderboard logic).
   * [database/seed.sql](database/seed.sql) (populates initial contests, users, and submissions).

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
5. Start server: `uvicorn app.main:app --reload`
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
FastAPI serves a static barebones dashboard at the root URL.
1. Open your browser and navigate to `http://127.0.0.1:8000`.
2. **Select a Contest**: Choose **Contest 2** ("Accumulator Math Quiz", which uses the `SUM` strategy).
3. **Inspect Initial State**: You will see users Sayma, Nondiny, and Tabib listed with scores of `0.0`.
4. **Submit a Payload**:
   * Select User: **sayma (ID: 1)**
   * Keep the default JSON payload: `{"score": 95.0, "verdict": "ROUND_2_SUCCESS"}`
   * Click **Submit to Queue**.
5. **Watch the Loop in Real-time**:
   * Look at your **Worker Terminal** (Terminal 2). You will instantly see the worker lock the submission, evaluate the payload, and write back the scores to Neon.
   * Look at the browser log feed. After a 3-second delay, the dashboard will refresh.
   * Sayma will now rank 1st with a total score of `95.0` on the standings table!
6. **Test Scoreboard Freeze**:
   * Switch the Contest dropdown to **Contest 1** ("Max Speed Run" - Currently Frozen).
   * Note the rankings: Sayma has `75.0` and Nondiny has `60.0`.
   * Check the checkbox **"View Standings as Admin (Bypass Scoreboard Freeze)"**.
   * Note that the scoreboard updates instantly to show the true scores including post-freeze runs: Sayma has `90.0` and Nondiny has `85.0`.

---

### Option B: Testing via Terminal (Curl)

#### Scenario A: Testing Live Leaderboard & Submissions (POINTS_SUM)
We use Contest 2 (Quiz, active and unfrozen):
1. **Verify Initial Standings**:
   ```bash
   curl http://127.0.0.1:8000/contests/2/leaderboard
   ```
2. **Submit a Result**:
   Submit LFR telemetry for Sayma (user ID 1):
   ```bash
   curl -X POST http://127.0.0.1:8000/submissions \
        -H "Content-Type: application/json" \
        -d '{"contest_id": 2, "user_id": 1, "submission_data": {"run_time_seconds": 45.0, "restarts": 1}}'
   ```
3. **Verify Standings Update**:
   ```bash
   curl http://127.0.0.1:8000/contests/2/leaderboard
   ```
   *Expected Response:* Sayma shows a score of `50.0` in Rank 1.
4. **Test Enrollment Control**:
   Attempt to submit for Safwan/Satil (user ID 3) in Contest 2 (not enrolled):
   ```bash
   curl -X POST http://127.0.0.1:8000/submissions \
        -H "Content-Type: application/json" \
        -d '{"contest_id": 2, "user_id": 3, "submission_data": {"score": 100}}'
   ```
   *Expected Response:* HTTP 403 Forbidden.

#### Scenario B: Testing Scoreboard Freeze & Admin Override (MAX)
We use Contest 1 (Max Speed Run, currently frozen):
1. **Check Public (Frozen) Leaderboard**:
   ```bash
   curl http://127.0.0.1:8000/contests/1/leaderboard
   ```
   *Expected Response:* Shows scores before freeze (Sayma: 75.0, Nondiny: 60.0).
2. **Check Admin (Unfrozen) Leaderboard**:
   ```bash
   curl "http://127.0.0.1:8000/contests/1/leaderboard?as_admin=true"
   ```
   *Expected Response:* Shows true post-freeze scores (Sayma: 90.0, Nondiny: 85.0).
