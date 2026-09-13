# ContestDB: A Database-Native Contest Platform

**ContestDB** is a database-native backend infrastructure for contest management and participation platforms. Built as a project for the **CSE 4410: Database Management Systems II Lab** course, ContestDB challenges the traditional web development pattern of placing all business logic in application servers. Instead, it utilizes **PostgreSQL** (running on Neon serverless) as both the transactional database and the primary execution engine.

This is a generic contest management platform: it can hold, manage, and track any type of contest (from ICPC to Chess to LFR) without domain-specific code execution in the database.

---

## Quick start — demo in four terminals

Create `.env` from `.env.example`, put in the three database URLs, and create a virtual environment once with `py -m venv .venv`. Then run these from the project root in four PowerShell terminals:

```powershell
# Terminal 1 — rebuild the database and seed Sayma, Nondiny, Safwan, and the three demo contests
.\.venv\Scripts\Activate.ps1
python database\setup_db.py
```

```powershell
cd .\backend\
venv\Scripts\Activate.ps1   
cd ..
python backend/demo_judges.py
python backend/run_server.py
python worker/worker.py
cd frontend
npm run dev
```

```powershell
# Terminal 2 — API
.\.venv\Scripts\Activate.ps1
python backend\run_server.py
```

```powershell
# Terminal 3 — start the demo judge in the background, then the queue worker
.\.venv\Scripts\Activate.ps1
$root = (Get-Location).Path; Start-Job -ArgumentList $root -ScriptBlock { param($root); Set-Location $root; python backend\demo_judges.py }
python worker\worker.py
```

```powershell
# Terminal 4 — React app
cd frontend
npm install
npm run dev
```

Open the Vite URL, then sign in with `sayma`, `nondiny`, or `satil` and password `password123`. Sayma hosts ICPC and participates in Chess/CTF; Nondiny's two format requests await Safwan (`satil`) in the Developer Console.

---

##  Project Architecture & Layout

The project implements a **Thin-Tier Architecture**:
* **Backend API Gateway (`/backend`)**: A lightweight FastAPI application that exposes endpoints to ingest submissions and fetch leaderboards. It does not calculate rankings or scores.
* **Database Engine (`/database`)**: The core brain of the platform. Hosts tables, indices, stored functions (`claim_submission`), and freeze-aware leaderboard views.
* **Judge Worker (`/worker`)**: A background process that polls the database queue, evaluates the flexible JSONB payload, and writes back the standardized score/verdict.

```
contestDb/
├── .agents/
│   └── AGENTS.md           # Guidelines for AI development agents
├── backend/
│   ├── app/
│   │   ├── database.py     # Connection pool loader
│   │   └── main.py         # FastAPI request routers
│   └── requirements.txt
├── database/
│   ├── init.sql            # Table structures & indexes
│   ├── procedures.sql     # PL/pgSQL queue claiming and freeze leaderboards
│   └── seed.sql            # Mock seed data (using team names)
├── docs/
│   ├── changelog.md        # Unified project changelog
│   ├── conventions.md      # Git, commits, PR board conventions
│   ├── developer_workflow.md # Workspace routine guidelines
│   └── manual_testing.md   # Setup, launch, and E2E curl testing guide
├── worker/
│   ├── worker.py           # Polls queue, mock judges JSONB, updates DB
│   └── requirements.txt
├── .env.example            # Global root environment file template
└── README.md
```

---



## Course & Team Details

This project is submitted for:
* **Course**: CSE 4410 (Database Management Systems II Lab)
* **Department**: Department of Software Engineering (SWE)
* **Institution**: Islamic University of Technology (IUT)
* **Team Members**:
  * M Safwan Hasan Khan (satil) (230042117)
  * Tabib Hassan (230042131)
  * Sayma Tasnim (230042139)
  * Ayman Binta Altaf Nondiny (230042141)

* Proposal Slides: [Canva Link](https://canva.link/mb0dipwrpo9ah0u)
