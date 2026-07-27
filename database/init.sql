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
CREATE TABLE IF NOT EXISTS contests (
    id SERIAL PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    ranking_strategy VARCHAR(30) NOT NULL, -- e.g., 'POINTS_SUM', 'HIGHEST_SCORE', 'Custom'
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    freeze_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE NOT NULL,
    status VARCHAR(30) DEFAULT 'PENDING_APPROVAL' NOT NULL,
    judging_description TEXT,
    invitation_code VARCHAR(50),
    CONSTRAINT chk_contest_times CHECK (freeze_time >= start_time AND end_time >= freeze_time),
    CONSTRAINT chk_contest_status CHECK (status IN ('PENDING_APPROVAL', 'ACTIVE', 'COMPLETED'))
);

-- Fallbacks if table already existed
ALTER TABLE contests ADD COLUMN IF NOT EXISTS status VARCHAR(30) DEFAULT 'PENDING_APPROVAL' NOT NULL;
ALTER TABLE contests ADD COLUMN IF NOT EXISTS judging_description TEXT;
ALTER TABLE contests ADD COLUMN IF NOT EXISTS invitation_code VARCHAR(50);
ALTER TABLE contests DROP CONSTRAINT IF EXISTS chk_contest_status;
ALTER TABLE contests ADD CONSTRAINT chk_contest_status CHECK (status IN ('PENDING_APPROVAL', 'ACTIVE', 'COMPLETED'));

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
CREATE TABLE IF NOT EXISTS tasks (
    id SERIAL PRIMARY KEY,
    contest_id INT REFERENCES contests(id) ON DELETE CASCADE,
    title VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    max_score NUMERIC DEFAULT 100 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 4. Submissions Table (Flexible payload via JSONB, standardized scoring)
CREATE TABLE IF NOT EXISTS submissions (
    id SERIAL PRIMARY KEY,
    contest_id INT REFERENCES contests(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    task_id INT REFERENCES tasks(id) ON DELETE CASCADE,
    submission_data JSONB NOT NULL, -- Arbitrary payload containing the contest submission details
    status VARCHAR(20) DEFAULT 'PENDING' NOT NULL, -- 'PENDING', 'JUDGING', 'COMPLETED', 'FAILED'
    score NUMERIC DEFAULT 0 NOT NULL, -- Standardized evaluation output
    verdict VARCHAR(50), -- Standardized evaluation description (e.g. 'AC', 'WA', 'RUN_SUCCESS')
    submitted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    judged_at TIMESTAMP WITH TIME ZONE,
    judged_by VARCHAR(50), -- Identifies the judging worker instance
    CONSTRAINT chk_submission_status CHECK (status IN ('PENDING', 'JUDGING', 'COMPLETED', 'FAILED'))
);

-- Fallbacks if table already existed
ALTER TABLE submissions ADD COLUMN IF NOT EXISTS task_id INT REFERENCES tasks(id) ON DELETE CASCADE;

-- Indices for faster lookups and queuing
CREATE INDEX IF NOT EXISTS idx_submissions_queue ON submissions(submitted_at ASC) WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_submissions_contest ON submissions(contest_id);
CREATE INDEX IF NOT EXISTS idx_submissions_user ON submissions(user_id);
CREATE INDEX IF NOT EXISTS idx_submissions_task ON submissions(task_id);
