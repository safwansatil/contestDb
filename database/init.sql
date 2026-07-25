-- DDL for ContestDB Walking Skeleton
-- Database: PostgreSQL (Neon Serverless)

-- Create extension if needed for future plagiarism/trigram checking
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 1. Users Table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 2. Contests Table
CREATE TABLE IF NOT EXISTS contests (
    id SERIAL PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    ranking_strategy VARCHAR(30) NOT NULL, -- e.g., 'POINTS_SUM', 'HIGHEST_SCORE', 'Custom'
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    freeze_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT chk_contest_times CHECK (freeze_time >= start_time AND end_time >= freeze_time)
);

-- 3. Enrollments Table (Maps users to contests they participate in)
CREATE TABLE IF NOT EXISTS enrollments (
    contest_id INT REFERENCES contests(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (contest_id, user_id)
);

-- 4. Submissions Table (Flexible payload via JSONB, standardized scoring)
CREATE TABLE IF NOT EXISTS submissions (
    id SERIAL PRIMARY KEY,
    contest_id INT REFERENCES contests(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    submission_data JSONB NOT NULL, -- Arbitrary payload containing the contest submission details
    status VARCHAR(20) DEFAULT 'PENDING' NOT NULL, -- 'PENDING', 'JUDGING', 'COMPLETED', 'FAILED'
    score NUMERIC DEFAULT 0 NOT NULL, -- Standardized evaluation output
    verdict VARCHAR(50), -- Standardized evaluation description (e.g. 'AC', 'WA', 'RUN_SUCCESS')
    submitted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    judged_at TIMESTAMP WITH TIME ZONE,
    judged_by VARCHAR(50), -- Identifies the judging worker instance
    CONSTRAINT chk_submission_status CHECK (status IN ('PENDING', 'JUDGING', 'COMPLETED', 'FAILED'))
);

-- Indices for faster lookups and queuing
CREATE INDEX IF NOT EXISTS idx_submissions_queue ON submissions(submitted_at ASC) WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_submissions_contest ON submissions(contest_id);
CREATE INDEX IF NOT EXISTS idx_submissions_user ON submissions(user_id);
