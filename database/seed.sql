-- Seed Data for ContestDB Walking Skeleton
-- Database: PostgreSQL (Neon Serverless)

-- Clean up existing seed data (order matters for foreign keys)
TRUNCATE TABLE submissions, tasks, enrollments, contests, users RESTART IDENTITY CASCADE;

-- 1. Insert Users (Using Team Member Names, Sayma and Nondiny on top)
INSERT INTO users (username, password_hash) VALUES 
('sayma', crypt('password123', gen_salt('bf'))),   -- ID 1
('nondiny', crypt('password123', gen_salt('bf'))), -- ID 2
('satil', crypt('password123', gen_salt('bf'))),   -- ID 3
('tabib', crypt('password123', gen_salt('bf')));   -- ID 4

-- 2. Insert Contests (with status, judging description)
-- Contest 1: "Max Speed Run" (Currently Frozen)
-- Start time: 2 hours ago, Freeze time: 1 hour ago, End time: 1 hour from now.
INSERT INTO contests (id, title, ranking_strategy, start_time, freeze_time, end_time, status, judging_description) VALUES 
(1, 'Max Speed Run', 'MAX', NOW() - INTERVAL '2 hours', NOW() - INTERVAL '1 hour', NOW() + INTERVAL '1 hour', 'ACTIVE', 'Max speed run of LFR. Deduct 5 points per restart from starting score of 100.');

-- Contest 2: "Accumulator Math Quiz" (Not Frozen)
-- Start time: 30 minutes ago, Freeze time: 1 hour from now, End time: 2 hours from now.
INSERT INTO contests (id, title, ranking_strategy, start_time, freeze_time, end_time, status, judging_description) VALUES 
(2, 'Accumulator Math Quiz', 'SUM', NOW() - INTERVAL '30 minutes', NOW() + INTERVAL '1 hour', NOW() + INTERVAL '2 hours', 'ACTIVE', 'Quiz submissions. Add all scores obtained by the user across math tasks.');

-- 3. Insert Tasks for Contests
-- Contest 1 Tasks
INSERT INTO tasks (id, contest_id, title, description, max_score) VALUES
(1, 1, 'Speed Run Time Trial', 'Measure the speed run telemetry. Fastest clean run wins.', 100.0);

-- Contest 2 Tasks
INSERT INTO tasks (id, contest_id, title, description, max_score) VALUES
(2, 2, 'Algorithmic Trivia', 'Answer all math accumulator questions.', 100.0);

-- 4. Enroll Users in Contests (With explicit roles)
-- Sayma (1) is HOST, Nondiny (2) is MODERATOR, and Satil (3) is PARTICIPANT in Contest 1 (Max Speed Run)
INSERT INTO enrollments (contest_id, user_id, role) VALUES 
(1, 1, 'HOST'),      -- sayma
(1, 2, 'MODERATOR'), -- nondiny
(1, 3, 'PARTICIPANT'); -- satil

-- Sayma (1) is HOST, Nondiny (2) is PARTICIPANT, and Tabib (4) is PARTICIPANT in Contest 2 (Quiz)
INSERT INTO enrollments (contest_id, user_id, role) VALUES 
(2, 1, 'HOST'),         -- sayma
(2, 2, 'PARTICIPANT'),  -- nondiny
(2, 4, 'PARTICIPANT');  -- tabib

-- 5. Insert Initial Submissions (with task_id mapped)
-- Contest 1 (Max Speed Run) - Task 1:
-- Sayma (1) submitted 1.5 hours ago (Before Freeze) -> Score 75
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES 
(1, 1, 1, '{"run_time_seconds": 12.4, "restarts": 0}'::jsonb, 'COMPLETED', 75, 'RUN_SUCCESS', NOW() - INTERVAL '1 hour 30 minutes', NOW() - INTERVAL '1 hour 29 minutes', 'worker-1');

-- Nondiny (2) submitted 1.2 hours ago (Before Freeze) -> Score 60
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES 
(1, 2, 1, '{"run_time_seconds": 15.1, "restarts": 1}'::jsonb, 'COMPLETED', 60, 'RUN_SUCCESS', NOW() - INTERVAL '1 hour 12 minutes', NOW() - INTERVAL '1 hour 11 minutes', 'worker-1');

-- Sayma (1) submitted 30 minutes ago (After Freeze) -> Score 90 (Will be hidden on public scoreboard)
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES 
(1, 1, 1, '{"run_time_seconds": 9.2, "restarts": 0}'::jsonb, 'COMPLETED', 90, 'RUN_SUCCESS', NOW() - INTERVAL '30 minutes', NOW() - INTERVAL '29 minutes', 'worker-1');

-- Nondiny (2) submitted 15 minutes ago (After Freeze) -> Score 85 (Will be hidden on public scoreboard)
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES 
(1, 2, 1, '{"run_time_seconds": 10.1, "restarts": 0}'::jsonb, 'COMPLETED', 85, 'RUN_SUCCESS', NOW() - INTERVAL '15 minutes', NOW() - INTERVAL '14 minutes', 'worker-1');

-- Additional historical submissions for activity graph and progression tests
-- Satil (3) submissions in Contest 1 (Max Speed Run)
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES 
(1, 3, 1, '{"run_time_seconds": 25.0, "restarts": 2}'::jsonb, 'COMPLETED', 65, 'RUN_SUCCESS', NOW() - INTERVAL '1 hour 45 minutes', NOW() - INTERVAL '1 hour 44 minutes', 'worker-1'),
(1, 3, 1, '{"run_time_seconds": 18.0, "restarts": 0}'::jsonb, 'COMPLETED', 82, 'RUN_SUCCESS', NOW() - INTERVAL '1 hour 5 minutes', NOW() - INTERVAL '1 hour 4 minutes', 'worker-1'),
(1, 3, 1, '{"run_time_seconds": 8.0, "restarts": 0}'::jsonb, 'COMPLETED', 92, 'RUN_SUCCESS', NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '9 minutes', 'worker-1');

-- Contest 2 (Quiz) Submissions:
-- Sayma (1) submissions
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES 
(2, 1, 2, '{"score": 90.0, "verdict": "ACCEPTED"}'::jsonb, 'COMPLETED', 90, 'ACCEPTED', NOW() - INTERVAL '25 minutes', NOW() - INTERVAL '24 minutes', 'worker-2');

-- Nondiny (2) submissions
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES 
(2, 2, 2, '{"score": 45.0, "verdict": "PARTIAL"}'::jsonb, 'COMPLETED', 45, 'PARTIAL', NOW() - INTERVAL '20 minutes', NOW() - INTERVAL '19 minutes', 'worker-2'),
(2, 2, 2, '{"score": 85.0, "verdict": "ACCEPTED"}'::jsonb, 'COMPLETED', 85, 'ACCEPTED', NOW() - INTERVAL '5 minutes', NOW() - INTERVAL '4 minutes', 'worker-2');

-- Tabib (4) submissions
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES 
(2, 4, 2, '{"score": 70.0, "verdict": "ACCEPTED"}'::jsonb, 'COMPLETED', 70, 'ACCEPTED', NOW() - INTERVAL '18 minutes', NOW() - INTERVAL '17 minutes', 'worker-2');

-- Out-of-contest submissions for users (general activity stats)
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES 
(1, 1, 1, '{"score": 50.0}'::jsonb, 'COMPLETED', 50, 'ACCEPTED', NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day', 'worker-default'),
(1, 1, 1, '{"score": 75.0}'::jsonb, 'COMPLETED', 75, 'ACCEPTED', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days', 'worker-default'),
(1, 2, 1, '{"score": 80.0}'::jsonb, 'COMPLETED', 80, 'ACCEPTED', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days', 'worker-default'),
(1, 3, 1, '{"score": 60.0}'::jsonb, 'COMPLETED', 60, 'ACCEPTED', NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days', 'worker-default'),
(1, 3, 1, '{"score": 70.0}'::jsonb, 'COMPLETED', 70, 'ACCEPTED', NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days', 'worker-default'),
(1, 4, 1, '{"score": 90.0}'::jsonb, 'COMPLETED', 90, 'ACCEPTED', NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days', 'worker-default');

-- Sync SERIAL sequences to prevent duplicate key errors on future inserts
SELECT setval('contests_id_seq', COALESCE((SELECT MAX(id) FROM contests), 1));
SELECT setval('users_id_seq', COALESCE((SELECT MAX(id) FROM users), 1));
SELECT setval('tasks_id_seq', COALESCE((SELECT MAX(id) FROM tasks), 1));
SELECT setval('submissions_id_seq', COALESCE((SELECT MAX(id) FROM submissions), 1));
