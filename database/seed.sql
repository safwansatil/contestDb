-- Seed Data for ContestDB Walking Skeleton
-- Database: PostgreSQL (Neon Serverless)

-- Clean up existing seed data (order matters for foreign keys)
TRUNCATE TABLE submissions, enrollments, contests, users RESTART IDENTITY CASCADE;

-- 1. Insert Users (Using Team Member Names, Sayma and Nondiny on top)
INSERT INTO users (username, password_hash) VALUES 
('sayma', crypt('password123', gen_salt('bf'))),   -- ID 1
('nondiny', crypt('password123', gen_salt('bf'))), -- ID 2
('satil', crypt('password123', gen_salt('bf'))),   -- ID 3
('tabib', crypt('password123', gen_salt('bf')));   -- ID 4

-- 2. Insert Contests
-- Contest 1: "Max Speed Run" (Currently Frozen)
-- Start time: 2 hours ago, Freeze time: 1 hour ago, End time: 1 hour from now.
INSERT INTO contests (id, title, ranking_strategy, start_time, freeze_time, end_time) VALUES 
(1, 'Max Speed Run', 'MAX', NOW() - INTERVAL '2 hours', NOW() - INTERVAL '1 hour', NOW() + INTERVAL '1 hour');

-- Contest 2: "Accumulator Math Quiz" (Not Frozen)
-- Start time: 30 minutes ago, Freeze time: 1 hour from now, End time: 2 hours from now.
INSERT INTO contests (id, title, ranking_strategy, start_time, freeze_time, end_time) VALUES 
(2, 'Accumulator Math Quiz', 'SUM', NOW() - INTERVAL '30 minutes', NOW() + INTERVAL '1 hour', NOW() + INTERVAL '2 hours');

-- 3. Enroll Users in Contests
-- Sayma (1), Nondiny (2), and Satil (3) participate in Contest 1 (Max Speed Run)
INSERT INTO enrollments (contest_id, user_id) VALUES 
(1, 1), -- sayma
(1, 2), -- nondiny
(1, 3); -- satil

-- Sayma (1), Nondiny (2), and Tabib (4) participate in Contest 2 (Quiz)
INSERT INTO enrollments (contest_id, user_id) VALUES 
(2, 1), -- sayma
(2, 2), -- nondiny
(2, 4); -- tabib

-- 4. Insert Initial Submissions
-- We insert some submissions to simulate contest history before the skeleton is run.

-- Contest 1 (Max Speed Run):
-- Sayma (1) submitted 1.5 hours ago (Before Freeze) -> Score 75
INSERT INTO submissions (contest_id, user_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES 
(1, 1, '{"run_time_seconds": 12.4, "restarts": 0}'::jsonb, 'COMPLETED', 75, 'RUN_SUCCESS', NOW() - INTERVAL '1 hour 30 minutes', NOW() - INTERVAL '1 hour 29 minutes', 'worker-1');

-- Nondiny (2) submitted 1.2 hours ago (Before Freeze) -> Score 60
INSERT INTO submissions (contest_id, user_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES 
(1, 2, '{"run_time_seconds": 15.1, "restarts": 1}'::jsonb, 'COMPLETED', 60, 'RUN_SUCCESS', NOW() - INTERVAL '1 hour 12 minutes', NOW() - INTERVAL '1 hour 11 minutes', 'worker-1');

-- Sayma (1) submitted 30 minutes ago (After Freeze) -> Score 90 (Will be hidden on public scoreboard)
INSERT INTO submissions (contest_id, user_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES 
(1, 1, '{"run_time_seconds": 9.2, "restarts": 0}'::jsonb, 'COMPLETED', 90, 'RUN_SUCCESS', NOW() - INTERVAL '30 minutes', NOW() - INTERVAL '29 minutes', 'worker-1');

-- Nondiny (2) submitted 15 minutes ago (After Freeze) -> Score 85 (Will be hidden on public scoreboard)
INSERT INTO submissions (contest_id, user_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES 
(1, 2, '{"run_time_seconds": 10.1, "restarts": 0}'::jsonb, 'COMPLETED', 85, 'RUN_SUCCESS', NOW() - INTERVAL '15 minutes', NOW() - INTERVAL '14 minutes', 'worker-1');
