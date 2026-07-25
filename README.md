# ContestDB: A Database-Native Contest Platform

**ContestDB** is a database-native backend infrastructure for contest management and participation platforms. Built as a project for the **CSE 4410: Database Management Systems II Lab** course, ContestDB challenges the traditional web development pattern of placing all business logic in application servers. Instead, it utilizes **PostgreSQL** (running on Neon serverless) as both the transactional database and the primary execution engine.

This is a generic contest management platform: it can hold, manage, and track any type of contest (from ICPC to Chess to LFR) without domain-specific code execution in the database.

---

## 📐 Project Architecture & Layout

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



## 👥 Course & Team Details

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
