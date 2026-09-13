-- Seed Data for ContestDB Walking Skeleton
-- Database: PostgreSQL (Neon Serverless)

-- Clean up existing seed data
TRUNCATE TABLE contest_type_requests, contest_announcements, kick_log, contest_visibility,
               submissions, tasks, enrollments, contests, users
RESTART IDENTITY CASCADE;

-- 1. Insert Users (Team Member Names) - Seeding Order from RULES: sayma, nondiny, satil, tabib
INSERT INTO users (username, password_hash, is_developer) VALUES
('sayma',   crypt('password123', gen_salt('bf')), FALSE),  -- ID 1
('nondiny', crypt('password123', gen_salt('bf')), FALSE),  -- ID 2
('satil',   crypt('password123', gen_salt('bf')), TRUE),   -- ID 3 (Developer)
('tabib',   crypt('password123', gen_salt('bf')), FALSE);  -- ID 4

-- 2. Insert MVP Contests
INSERT INTO contests (id, title, ranking_strategy, start_time, freeze_time, end_time, status,
                      judging_description, max_participants, allow_late_enrollment, contest_type, judge_webhook_url) VALUES
(1, 'ICPC Algorithm Contest', 'SUM', NOW() - INTERVAL '30 minutes', NOW() + INTERVAL '2 hours', NOW() + INTERVAL '3 hours',
 'ACTIVE', 'ICPC style algorithmic contest', NULL, TRUE, 'icpc', 'http://127.0.0.1:8001/judge/icpc'),
(2, 'Chess Checkmate Puzzles', 'MAX', NOW() - INTERVAL '1 hour', NOW() + INTERVAL '2 hours', NOW() + INTERVAL '3 hours',
 'ACTIVE', 'Find the forced checkmates', NULL, TRUE, 'chess', 'http://127.0.0.1:8001/judge/chess'),
(3, 'CTFDB: First Signals', 'SUM', NOW() - INTERVAL '1 hour', NOW() + INTERVAL '2 hours', NOW() + INTERVAL '3 hours',
 'ACTIVE', 'A safe, self-contained beginner CTF. Read each brief, inspect the supplied evidence, and submit flags in CTFDB{...} format.', NULL, TRUE, 'ctf', 'http://127.0.0.1:8001/judge/ctf');

-- 3. Insert Tasks
-- ICPC Tasks — ten familiar algorithm topics for the host demo.
INSERT INTO tasks (id, contest_id, title, description, max_score, submission_schema, task_order) VALUES
(1, 1, 'A. Pair Target', 'Find two array values that add to a target. Topic: hashing.', 100.0, '{"required_keys": ["source_code", "language"]}'::jsonb, 1),
(2, 1, 'B. Greedy Intervals', 'Choose the maximum number of non-overlapping intervals.', 100.0, '{"required_keys": ["source_code", "language"]}'::jsonb, 2),
(3, 1, 'C. Binary Search Factory', 'Find the minimum production time. Topic: binary search on answer.', 100.0, '{"required_keys": ["source_code", "language"]}'::jsonb, 3),
(4, 1, 'D. Prefix Signal', 'Answer range-sum queries on a sequence.', 100.0, '{"required_keys": ["source_code", "language"]}'::jsonb, 4),
(5, 1, 'E. Island Walk', 'Count connected islands in a grid. Topic: DFS.', 100.0, '{"required_keys": ["source_code", "language"]}'::jsonb, 5),
(6, 1, 'F. Shortest Relay', 'Find the shortest unweighted route. Topic: BFS.', 100.0, '{"required_keys": ["source_code", "language"]}'::jsonb, 6),
(7, 1, 'G. Weighted Routes', 'Compute shortest paths with non-negative costs. Topic: Dijkstra.', 100.0, '{"required_keys": ["source_code", "language"]}'::jsonb, 7),
(8, 1, 'H. Backpack', 'Maximize value within a capacity. Topic: dynamic programming.', 100.0, '{"required_keys": ["source_code", "language"]}'::jsonb, 8),
(9, 1, 'I. Inversion Count', 'Count inversions efficiently. Topic: divide and conquer.', 100.0, '{"required_keys": ["source_code", "language"]}'::jsonb, 9),
(10, 1, 'J. Random Area', 'Estimate an area using sampling. Topic: Monte Carlo.', 100.0, '{"required_keys": ["source_code", "language"]}'::jsonb, 10);

-- Chess Tasks
INSERT INTO tasks (id, contest_id, title, description, max_score, submission_schema, task_order) VALUES
(11, 2, 'Level 1: Mate in One', 'Use the board to find a forced checkmate in one move.', 100.0, '{"required_keys": ["moves", "fen"]}'::jsonb, 1),
(12, 2, 'Level 2: Back Rank', 'Spot the back-rank pattern and finish the game.', 150.0, '{"required_keys": ["moves", "fen"]}'::jsonb, 2),
(13, 2, 'Level 3: Queen Net', 'Calculate the final move of a queen-and-king mating net.', 200.0, '{"required_keys": ["moves", "fen"]}'::jsonb, 3);

-- CTF Tasks — deliberately safe, self-contained introductory challenges.
-- The UI provides the evidence panels; flags are validated per task by demo_judges.py.
INSERT INTO tasks (id, contest_id, title, description, max_score, submission_schema, submission_cooldown_seconds, task_order) VALUES
(14, 3, 'View from the Source', 'Web · Easy · 100 points. Learn where a webpage can keep its author notes. Inspect the supplied page fragment; no external website is involved.', 100.0, '{"required_keys": ["flag"]}'::jsonb, 20, 1),
(15, 3, 'Beacon in Transit', 'Crypto · Easy · 150 points. A short transmission was encoded for safe transport. Identify the encoding and recover the original flag.', 150.0, '{"required_keys": ["flag"]}'::jsonb, 20, 2),
(16, 3, 'Case File 03', 'Forensics · Easy · 200 points. Read a tiny evidence manifest and use its metadata convention to reconstruct the flag.', 200.0, '{"required_keys": ["flag"]}'::jsonb, 20, 3);

-- 4. Enroll Users in Contests (With explicit roles)
INSERT INTO enrollments (contest_id, user_id, role) VALUES
(1, 1, 'HOST'),        -- sayma
(1, 3, 'MODERATOR'),   -- satil
(1, 2, 'PARTICIPANT'), -- nondiny
(1, 4, 'PARTICIPANT'), -- tabib
(2, 2, 'HOST'),        -- nondiny
(2, 3, 'MODERATOR'),   -- satil
(2, 1, 'PARTICIPANT'), -- sayma
(2, 4, 'PARTICIPANT'), -- tabib
(3, 4, 'HOST'),        -- tabib
(3, 3, 'MODERATOR'),   -- satil
(3, 1, 'PARTICIPANT'), -- sayma
(3, 2, 'PARTICIPANT'); -- nondiny

-- 5. Insert Contest Visibility Settings
INSERT INTO contest_visibility (contest_id, show_participant_count, show_leaderboard, show_member_list, show_task_list, show_statistics, show_submission_count) VALUES
(1, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE),
(2, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE),
(3, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE);

-- 6. Insert Initial Submissions
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES
(1, 2, 1, '{"source_code": "print(1)", "language": "python"}'::jsonb, 'COMPLETED', 100, 'AC', NOW() - INTERVAL '15 minutes', NOW() - INTERVAL '14 minutes', 'worker-1'),
(3, 1, 14, '{"flag": "CTFDB{view_source_first}"}'::jsonb, 'COMPLETED', 100, 'CORRECT', NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '9 minutes', 'worker-1');

-- 7. Seed Sample Announcements
INSERT INTO contest_announcements (contest_id, author_id, title, body, posted_at) VALUES
(1, 1, 'Welcome to ICPC Demo!', 'Submit your code on time!', NOW() - INTERVAL '1 hour');

-- Nondiny's two requests give Safwan a ready-to-demo developer review queue.
INSERT INTO contest_type_requests (requester_id, requested_type, title, rules_description, requested_tasks) VALUES
(2, 'chess_variant', 'Endgame Studies: Mate in Two', 'Reuse the chess puzzle flow but allow host-provided FEN positions and mate-in-two levels.', 'Three custom endgame positions with increasing difficulty.'),
(2, 'biology_olympiad', 'BioSprint Olympiad', 'A biology Olympiad with multiple-choice and short-answer rounds, reviewed by a human rubric.', 'Cell biology, genetics, and ecology rounds.');

-- 8. Sync SERIAL sequences
SELECT setval('contests_id_seq', COALESCE((SELECT MAX(id) FROM contests), 1));
SELECT setval('users_id_seq', COALESCE((SELECT MAX(id) FROM users), 1));
SELECT setval('tasks_id_seq', COALESCE((SELECT MAX(id) FROM tasks), 1));
SELECT setval('submissions_id_seq', COALESCE((SELECT MAX(id) FROM submissions), 1));
SELECT setval('contest_announcements_id_seq', COALESCE((SELECT MAX(id) FROM contest_announcements), 1));
SELECT setval('kick_log_id_seq', COALESCE((SELECT MAX(id) FROM kick_log), 1));
SELECT setval('contest_type_requests_id_seq', COALESCE((SELECT MAX(id) FROM contest_type_requests), 1));
