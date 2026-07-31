-- DDL for ContestDB Walking Skeleton
-- Database: PostgreSQL (Neon Serverless)

-- Create extension if needed for future plagiarism/trigram checking
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Users Table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Fallback to add password_hash if users table already existed
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);

-- 2. Contests Table
--    max_participants: NULL means unlimited enrollment cap.
--    allow_late_enrollment: If FALSE, enrollment is rejected after start_time has passed.
CREATE TABLE IF NOT EXISTS contests (
    id SERIAL PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    ranking_strategy VARCHAR(30) NOT NULL,         -- e.g., 'SUM', 'MAX', 'ICPC', 'Custom'
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    freeze_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE NOT NULL,
    status VARCHAR(30) DEFAULT 'PENDING_APPROVAL' NOT NULL,
    judging_description TEXT,
    invitation_code VARCHAR(50),
    max_participants INT,                           -- NULL = unlimited; > 0 enforced by CHECK
    allow_late_enrollment BOOLEAN DEFAULT TRUE NOT NULL,
    CONSTRAINT chk_contest_times CHECK (freeze_time >= start_time AND end_time >= freeze_time),
    CONSTRAINT chk_contest_status CHECK (status IN ('PENDING_APPROVAL', 'ACTIVE', 'COMPLETED')),
    CONSTRAINT chk_max_participants CHECK (max_participants IS NULL OR max_participants > 0)
);

-- Fallbacks if table already existed
ALTER TABLE contests ADD COLUMN IF NOT EXISTS status VARCHAR(30) DEFAULT 'PENDING_APPROVAL' NOT NULL;
ALTER TABLE contests ADD COLUMN IF NOT EXISTS judging_description TEXT;
ALTER TABLE contests ADD COLUMN IF NOT EXISTS invitation_code VARCHAR(50);
ALTER TABLE contests ADD COLUMN IF NOT EXISTS max_participants INT;
ALTER TABLE contests ADD COLUMN IF NOT EXISTS allow_late_enrollment BOOLEAN DEFAULT TRUE NOT NULL;
ALTER TABLE contests DROP CONSTRAINT IF EXISTS chk_contest_status;
ALTER TABLE contests ADD CONSTRAINT chk_contest_status CHECK (status IN ('PENDING_APPROVAL', 'ACTIVE', 'COMPLETED'));
ALTER TABLE contests DROP CONSTRAINT IF EXISTS chk_max_participants;
ALTER TABLE contests ADD CONSTRAINT chk_max_participants CHECK (max_participants IS NULL OR max_participants > 0);

-- 3. Enrollments Table (Maps users to contests they participate in and their roles)
CREATE TABLE IF NOT EXISTS enrollments (
    contest_id INT REFERENCES contests(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    role VARCHAR(20) DEFAULT 'PARTICIPANT' NOT NULL,
    PRIMARY KEY (contest_id, user_id),
    CONSTRAINT chk_enrollment_role CHECK (role IN ('HOST', 'MODERATOR', 'PARTICIPANT'))
);

-- Fallbacks if table already existed
ALTER TABLE enrollments ADD COLUMN IF NOT EXISTS role VARCHAR(20) DEFAULT 'PARTICIPANT' NOT NULL;
ALTER TABLE enrollments DROP CONSTRAINT IF EXISTS chk_enrollment_role;
ALTER TABLE enrollments ADD CONSTRAINT chk_enrollment_role CHECK (role IN ('HOST', 'MODERATOR', 'PARTICIPANT'));

-- 3b. Tasks Table
--     submission_schema: Mandatory JSONB descriptor for the expected shape of submission_data.
--       Example: {"required_keys": ["run_time_seconds", "restarts"], "numeric_keys": ["run_time_seconds"]}
--       The DB function validate_submission_schema_native enforces this before a submission is queued.
--     submission_cooldown_seconds: Minimum seconds a user must wait between submissions on this task.
--       0 means no cooldown enforced. Enforced by check_submission_cooldown_native.
--     task_order: Display ordering index within the contest. Lower = shown first.
CREATE TABLE IF NOT EXISTS tasks (
    id SERIAL PRIMARY KEY,
    contest_id INT REFERENCES contests(id) ON DELETE CASCADE,
    title VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    max_score NUMERIC DEFAULT 100 NOT NULL,
    submission_schema JSONB NOT NULL,               -- Mandatory: every task must declare its payload schema
    submission_cooldown_seconds INT DEFAULT 0 NOT NULL,
    task_order INT DEFAULT 0 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_task_cooldown CHECK (submission_cooldown_seconds >= 0),
    CONSTRAINT chk_task_order CHECK (task_order >= 0)
);

-- Fallbacks if table already existed
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS submission_schema JSONB;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS submission_cooldown_seconds INT DEFAULT 0 NOT NULL;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS task_order INT DEFAULT 0 NOT NULL;
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS chk_task_cooldown;
ALTER TABLE tasks ADD CONSTRAINT chk_task_cooldown CHECK (submission_cooldown_seconds >= 0);
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS chk_task_order;
ALTER TABLE tasks ADD CONSTRAINT chk_task_order CHECK (task_order >= 0);

-- 4. Submissions Table (Flexible payload via JSONB, standardized scoring)
CREATE TABLE IF NOT EXISTS submissions (
    id SERIAL PRIMARY KEY,
    contest_id INT REFERENCES contests(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    task_id INT REFERENCES tasks(id) ON DELETE CASCADE,
    submission_data JSONB NOT NULL,                -- Arbitrary payload; validated against task's submission_schema
    status VARCHAR(20) DEFAULT 'PENDING' NOT NULL, -- 'PENDING', 'JUDGING', 'COMPLETED', 'FAILED'
    score NUMERIC DEFAULT 0 NOT NULL,              -- Standardized evaluation output written by judge worker
    verdict VARCHAR(50),                           -- Standardized evaluation description (e.g. 'AC', 'WA', 'RUN_SUCCESS')
    submitted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    judged_at TIMESTAMP WITH TIME ZONE,
    judged_by VARCHAR(50),                         -- Identifies the judging worker instance
    CONSTRAINT chk_submission_status CHECK (status IN ('PENDING', 'JUDGING', 'COMPLETED', 'FAILED'))
);

-- Fallbacks if table already existed
ALTER TABLE submissions ADD COLUMN IF NOT EXISTS task_id INT REFERENCES tasks(id) ON DELETE CASCADE;

-- 5. Contest Visibility Table
--    Per-contest, host-configurable flags that control which fields are exposed to public viewers.
--    A row is automatically created with defaults when a contest is created via create_contest_native.
--    Only HOST and MODERATOR can modify these via update_contest_visibility().
CREATE TABLE IF NOT EXISTS contest_visibility (
    contest_id              INT PRIMARY KEY REFERENCES contests(id) ON DELETE CASCADE,
    show_participant_count  BOOLEAN DEFAULT TRUE  NOT NULL, -- Whether public can see enrollment numbers
    show_leaderboard        BOOLEAN DEFAULT TRUE  NOT NULL, -- Whether public leaderboard is shown
    show_member_list        BOOLEAN DEFAULT FALSE NOT NULL, -- Whether participant list is public
    show_task_list          BOOLEAN DEFAULT TRUE  NOT NULL, -- Whether tasks are visible before contest start
    show_statistics         BOOLEAN DEFAULT FALSE NOT NULL, -- Whether contest analytics are public
    show_submission_count   BOOLEAN DEFAULT FALSE NOT NULL, -- Whether total submission count is shown
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 6. Kick Log Table
--    Immutable audit trail of participants removed by the HOST.
--    Also acts as a ban list: kicked users cannot re-enroll in the same contest.
--    Submissions made before the kick are preserved for record integrity.
CREATE TABLE IF NOT EXISTS kick_log (
    id             SERIAL PRIMARY KEY,
    contest_id     INT NOT NULL REFERENCES contests(id) ON DELETE CASCADE,
    kicked_user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kicked_by      INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason         TEXT,
    kicked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 7. Contest Announcements Table
--    HOST and MODERATOR can broadcast messages inside a contest.
--    Public viewers see announcements if show_task_list is TRUE (announcements are part of the contest page).
CREATE TABLE IF NOT EXISTS contest_announcements (
    id         SERIAL PRIMARY KEY,
    contest_id INT NOT NULL REFERENCES contests(id) ON DELETE CASCADE,
    author_id  INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title      VARCHAR(150) NOT NULL,
    body       TEXT NOT NULL,
    posted_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Indices for faster lookups and queuing
CREATE INDEX IF NOT EXISTS idx_submissions_queue       ON submissions(submitted_at ASC) WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_submissions_contest     ON submissions(contest_id);
CREATE INDEX IF NOT EXISTS idx_submissions_user        ON submissions(user_id);
CREATE INDEX IF NOT EXISTS idx_submissions_task        ON submissions(task_id);
CREATE INDEX IF NOT EXISTS idx_submissions_user_time   ON submissions(user_id, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_submissions_contest_time ON submissions(contest_id, submitted_at DESC);

-- New indices for v0.5.0
CREATE INDEX IF NOT EXISTS idx_tasks_order             ON tasks(contest_id, task_order ASC);
CREATE INDEX IF NOT EXISTS idx_kick_log_contest        ON kick_log(contest_id, kicked_user_id);
CREATE INDEX IF NOT EXISTS idx_announcements_contest   ON contest_announcements(contest_id, posted_at DESC);
