-- Seed Data for ContestDB Walking Skeleton
-- Database: PostgreSQL (Neon Serverless)

-- Clean up existing seed data (order matters for foreign keys)
TRUNCATE TABLE contest_announcements, kick_log, contest_visibility,
               submissions, tasks, enrollments, contests, users
RESTART IDENTITY CASCADE;

-- 1. Insert Users (Team Member Names)
INSERT INTO users (username, password_hash, is_developer) VALUES
('sayma',   crypt('password123', gen_salt('bf')), FALSE),  -- ID 1
('nondiny', crypt('password123', gen_salt('bf')), FALSE),  -- ID 2
('satil',   crypt('password123', gen_salt('bf')), FALSE),  -- ID 3
('tabib',   crypt('password123', gen_salt('bf')), FALSE),  -- ID 4
('safwansatil', crypt('password123', gen_salt('bf')), TRUE);   -- ID 5 (Developer)

-- 2. Insert MVP Contests
-- Contest 1: "MVP LeetCode Contest" (Competitive Programming)
INSERT INTO contests (id, title, ranking_strategy, start_time, freeze_time, end_time, status,
                      judging_description, max_participants, allow_late_enrollment, contest_type, judge_webhook_url) VALUES
(1, 'MVP LeetCode Contest', 'SUM',
 NOW() - INTERVAL '30 minutes',
 NOW() + INTERVAL '2 hours',
 NOW() + INTERVAL '3 hours',
 'ACTIVE',
 'Algorithmic coding contest. Judged via built-in MVP webhook.',
 NULL,
 TRUE, 'leetcode', 'http://127.0.0.1:8000/api/v1/judges/leetcode');

-- Contest 2: "MVP Chess Match"
INSERT INTO contests (id, title, ranking_strategy, start_time, freeze_time, end_time, status,
                      judging_description, max_participants, allow_late_enrollment, contest_type, judge_webhook_url) VALUES
(2, 'MVP Chess Match', 'MAX',
 NOW() - INTERVAL '1 hour',
 NOW() + INTERVAL '2 hours',
 NOW() + INTERVAL '3 hours',
 'ACTIVE',
 'Standard chess match. Judged via built-in MVP webhook.',
 2,
 TRUE, 'chess', 'http://127.0.0.1:8000/api/v1/judges/chess');


-- 3. Insert Tasks
-- Contest 1 — Task 1: Two Sum
INSERT INTO tasks (id, contest_id, title, description, max_score,
                   submission_schema, submission_cooldown_seconds, task_order) VALUES
(1, 1, 'Two Sum',
 'Given an array of integers nums and an integer target, return indices of the two numbers such that they add up to target.',
 100.0,
 '{"required_keys": [], "numeric_keys": []}'::jsonb,
 10,   
 1);

-- Contest 2 — Task 2: Standard Game
INSERT INTO tasks (id, contest_id, title, description, max_score,
                   submission_schema, submission_cooldown_seconds, task_order) VALUES
(2, 2, 'Play a Game',
 'Make your best moves on the board.',
 100.0,
 '{"required_keys": [], "numeric_keys": []}'::jsonb,
 5,    
 1);

-- 4. Enroll Users in Contests (With explicit roles)
-- Contest 1 (Leetcode): sayma=HOST, satil=MODERATOR, nondiny=PARTICIPANT, tabib=PARTICIPANT
INSERT INTO enrollments (contest_id, user_id, role) VALUES
(1, 1, 'HOST'),        -- sayma
(1, 3, 'MODERATOR'),   -- satil
(1, 2, 'PARTICIPANT'), -- nondiny
(1, 4, 'PARTICIPANT'); -- tabib

-- Contest 2 (Chess): tabib=HOST, sayma=MODERATOR, nondiny=PARTICIPANT, satil=PARTICIPANT
INSERT INTO enrollments (contest_id, user_id, role) VALUES
(2, 4, 'HOST'),        -- tabib
(2, 1, 'MODERATOR'),   -- sayma
(2, 2, 'PARTICIPANT'), -- nondiny
(2, 3, 'PARTICIPANT'); -- satil

-- 5. Insert Contest Visibility Settings (Defaults for both seeded contests)
INSERT INTO contest_visibility (contest_id, show_participant_count, show_leaderboard,
                                show_member_list, show_task_list, show_statistics, show_submission_count) VALUES
(1, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE),
(2, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE);

-- 6. Insert Initial Submissions
-- Contest 1, Task 1: LeetCode
-- Nondiny (2) -> Score 100
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES
(1, 2, 1, '{"source_code": "def solve():\n    return", "language_id": "python"}'::jsonb, 'COMPLETED', 100, 'ACCEPTED',
 NOW() - INTERVAL '15 minutes', NOW() - INTERVAL '14 minutes', 'worker-1');

-- Tabib (4) -> Score 0
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES
(1, 4, 1, '{"source_code": "def solve():\n    pass", "language_id": "python"}'::jsonb, 'COMPLETED', 0, 'WRONG_ANSWER',
 NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '9 minutes', 'worker-1');

-- Contest 2, Task 2: Chess
-- Satil (3) -> Score 50
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES
(2, 3, 2, '{"pgn": "1. e4", "fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", "move": "e4"}'::jsonb, 'COMPLETED', 50, 'ACCEPTED',
 NOW() - INTERVAL '5 minutes', NOW() - INTERVAL '4 minutes', 'worker-1');

-- 7. Seed Sample Announcements
INSERT INTO contest_announcements (contest_id, author_id, title, body, posted_at) VALUES
(1, 1, 'Welcome to MVP LeetCode!',
 'Welcome everyone! Submissions are routed to the mock webhook judge.',
 NOW() - INTERVAL '1 hour 50 minutes');

-- 8. Sync SERIAL sequences to prevent duplicate key errors on future inserts
SELECT setval('contests_id_seq',              COALESCE((SELECT MAX(id) FROM contests), 1));
SELECT setval('users_id_seq',                 COALESCE((SELECT MAX(id) FROM users), 1));
SELECT setval('tasks_id_seq',                 COALESCE((SELECT MAX(id) FROM tasks), 1));
SELECT setval('submissions_id_seq',           COALESCE((SELECT MAX(id) FROM submissions), 1));
SELECT setval('contest_announcements_id_seq', COALESCE((SELECT MAX(id) FROM contest_announcements), 1));
SELECT setval('kick_log_id_seq',              COALESCE((SELECT MAX(id) FROM kick_log), 1));
