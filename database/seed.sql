-- Seed Data for ContestDB Walking Skeleton
-- Database: PostgreSQL (Neon Serverless)

-- Clean up existing seed data (order matters for foreign keys)
TRUNCATE TABLE contest_announcements, kick_log, contest_visibility,
               submissions, tasks, enrollments, contests, users
RESTART IDENTITY CASCADE;

-- 1. Insert Users (Team Member Names — Sayma and Nondiny first per convention)
INSERT INTO users (username, password_hash) VALUES
('sayma',   crypt('password123', gen_salt('bf'))),  -- ID 1
('nondiny', crypt('password123', gen_salt('bf'))),  -- ID 2
('satil',   crypt('password123', gen_salt('bf'))),  -- ID 3
('tabib',   crypt('password123', gen_salt('bf')));  -- ID 4

-- 2. Insert Contests
-- Contest 1: "Max Speed Run" — capped at 5 participants, currently frozen
-- Start: 2h ago, Freeze: 1h ago, End: 1h from now
INSERT INTO contests (id, title, ranking_strategy, start_time, freeze_time, end_time, status,
                      judging_description, max_participants, allow_late_enrollment) VALUES
(1, 'Max Speed Run', 'MAX',
 NOW() - INTERVAL '2 hours',
 NOW() - INTERVAL '1 hour',
 NOW() + INTERVAL '1 hour',
 'ACTIVE',
 'Max speed run of LFR. Deduct 5 points per restart from a starting score of 100.',
 5,      -- capped at 5 participants
 TRUE);

-- Contest 2: "Accumulator Math Quiz" — unlimited participants, not yet frozen
-- Start: 30m ago, Freeze: 1h from now, End: 2h from now
INSERT INTO contests (id, title, ranking_strategy, start_time, freeze_time, end_time, status,
                      judging_description, max_participants, allow_late_enrollment) VALUES
(2, 'Accumulator Math Quiz', 'SUM',
 NOW() - INTERVAL '30 minutes',
 NOW() + INTERVAL '1 hour',
 NOW() + INTERVAL '2 hours',
 'ACTIVE',
 'Quiz submissions. Add all scores obtained by the user across math tasks.',
 NULL,   -- unlimited enrollment
 TRUE);

-- 3. Insert Tasks
-- Tasks must include submission_schema (NOT NULL).
-- submission_schema format:
--   required_keys: keys that must be present in submission_data
--   numeric_keys:  keys that must be JSON number type
--
-- Contest 1 — Task 1: Speed Run Time Trial
INSERT INTO tasks (id, contest_id, title, description, max_score,
                   submission_schema, submission_cooldown_seconds, task_order) VALUES
(1, 1, 'Speed Run Time Trial',
 'Measure the speed run telemetry. Fastest clean run wins.',
 100.0,
 '{"required_keys": ["run_time_seconds", "restarts"], "numeric_keys": ["run_time_seconds", "restarts"]}'::jsonb,
 30,   -- 30-second cooldown between submissions to prevent spam
 1);

-- Contest 2 — Task 2: Algorithmic Trivia
INSERT INTO tasks (id, contest_id, title, description, max_score,
                   submission_schema, submission_cooldown_seconds, task_order) VALUES
(2, 2, 'Algorithmic Trivia',
 'Answer all math accumulator questions. Submit your answers in the required format.',
 100.0,
 '{"required_keys": ["score", "verdict"], "numeric_keys": ["score"]}'::jsonb,
 0,    -- no cooldown
 1);

-- 4. Enroll Users in Contests (With explicit roles)
-- Contest 1 (Max Speed Run): sayma=HOST, nondiny=MODERATOR, satil=PARTICIPANT
INSERT INTO enrollments (contest_id, user_id, role) VALUES
(1, 1, 'HOST'),       -- sayma
(1, 2, 'MODERATOR'),  -- nondiny
(1, 3, 'PARTICIPANT'); -- satil

-- Contest 2 (Quiz): sayma=HOST, nondiny=PARTICIPANT, tabib=PARTICIPANT
INSERT INTO enrollments (contest_id, user_id, role) VALUES
(2, 1, 'HOST'),        -- sayma
(2, 2, 'PARTICIPANT'), -- nondiny
(2, 4, 'PARTICIPANT'); -- tabib

-- 5. Insert Contest Visibility Settings (Defaults for both seeded contests)
-- Contest 1: show participant count and leaderboard; keep member list private
INSERT INTO contest_visibility (contest_id, show_participant_count, show_leaderboard,
                                show_member_list, show_task_list, show_statistics, show_submission_count) VALUES
(1, TRUE, TRUE, FALSE, TRUE, TRUE, TRUE);

-- Contest 2: all public including statistics
INSERT INTO contest_visibility (contest_id, show_participant_count, show_leaderboard,
                                show_member_list, show_task_list, show_statistics, show_submission_count) VALUES
(2, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE);

-- 6. Insert Initial Submissions (with task_id, schema-valid payloads)
-- Contest 1, Task 1: Speed Run
-- Sayma (1): Before Freeze → Score 75
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES
(1, 1, 1, '{"run_time_seconds": 12.4, "restarts": 0}'::jsonb, 'COMPLETED', 75, 'RUN_SUCCESS',
 NOW() - INTERVAL '1 hour 30 minutes', NOW() - INTERVAL '1 hour 29 minutes', 'worker-1');

-- Nondiny (2): Before Freeze → Score 60
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES
(1, 2, 1, '{"run_time_seconds": 15.1, "restarts": 1}'::jsonb, 'COMPLETED', 60, 'RUN_SUCCESS',
 NOW() - INTERVAL '1 hour 12 minutes', NOW() - INTERVAL '1 hour 11 minutes', 'worker-1');

-- Sayma (1): After Freeze → Score 90 (hidden on public scoreboard)
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES
(1, 1, 1, '{"run_time_seconds": 9.2, "restarts": 0}'::jsonb, 'COMPLETED', 90, 'RUN_SUCCESS',
 NOW() - INTERVAL '30 minutes', NOW() - INTERVAL '29 minutes', 'worker-1');

-- Nondiny (2): After Freeze → Score 85 (hidden on public scoreboard)
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES
(1, 2, 1, '{"run_time_seconds": 10.1, "restarts": 0}'::jsonb, 'COMPLETED', 85, 'RUN_SUCCESS',
 NOW() - INTERVAL '15 minutes', NOW() - INTERVAL '14 minutes', 'worker-1');

-- Satil (3): Three submissions in Contest 1
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES
(1, 3, 1, '{"run_time_seconds": 25.0, "restarts": 2}'::jsonb, 'COMPLETED', 65, 'RUN_SUCCESS',
 NOW() - INTERVAL '1 hour 45 minutes', NOW() - INTERVAL '1 hour 44 minutes', 'worker-1'),
(1, 3, 1, '{"run_time_seconds": 18.0, "restarts": 0}'::jsonb, 'COMPLETED', 82, 'RUN_SUCCESS',
 NOW() - INTERVAL '1 hour 5 minutes', NOW() - INTERVAL '1 hour 4 minutes', 'worker-1'),
(1, 3, 1, '{"run_time_seconds": 8.0, "restarts": 0}'::jsonb, 'COMPLETED', 92, 'RUN_SUCCESS',
 NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '9 minutes', 'worker-1');

-- Contest 2, Task 2: Quiz
-- Sayma (1)
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES
(2, 1, 2, '{"score": 90.0, "verdict": "ACCEPTED"}'::jsonb, 'COMPLETED', 90, 'ACCEPTED',
 NOW() - INTERVAL '25 minutes', NOW() - INTERVAL '24 minutes', 'worker-2');

-- Nondiny (2): two attempts
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES
(2, 2, 2, '{"score": 45.0, "verdict": "PARTIAL"}'::jsonb, 'COMPLETED', 45, 'PARTIAL',
 NOW() - INTERVAL '20 minutes', NOW() - INTERVAL '19 minutes', 'worker-2'),
(2, 2, 2, '{"score": 85.0, "verdict": "ACCEPTED"}'::jsonb, 'COMPLETED', 85, 'ACCEPTED',
 NOW() - INTERVAL '5 minutes', NOW() - INTERVAL '4 minutes', 'worker-2');

-- Tabib (4)
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES
(2, 4, 2, '{"score": 70.0, "verdict": "ACCEPTED"}'::jsonb, 'COMPLETED', 70, 'ACCEPTED',
 NOW() - INTERVAL '18 minutes', NOW() - INTERVAL '17 minutes', 'worker-2');

-- Historical submissions for user activity graphs and profile stats
INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status, score, verdict, submitted_at, judged_at, judged_by) VALUES
(1, 1, 1, '{"run_time_seconds": 20.0, "restarts": 1}'::jsonb, 'COMPLETED', 50, 'ACCEPTED', NOW() - INTERVAL '1 day',  NOW() - INTERVAL '1 day',  'worker-default'),
(1, 1, 1, '{"run_time_seconds": 14.0, "restarts": 0}'::jsonb, 'COMPLETED', 75, 'ACCEPTED', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days', 'worker-default'),
(1, 2, 1, '{"run_time_seconds": 13.0, "restarts": 0}'::jsonb, 'COMPLETED', 80, 'ACCEPTED', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days', 'worker-default'),
(1, 3, 1, '{"run_time_seconds": 30.0, "restarts": 2}'::jsonb, 'COMPLETED', 60, 'ACCEPTED', NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days', 'worker-default'),
(1, 3, 1, '{"run_time_seconds": 22.0, "restarts": 1}'::jsonb, 'COMPLETED', 70, 'ACCEPTED', NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days', 'worker-default'),
(1, 4, 1, '{"run_time_seconds": 11.0, "restarts": 0}'::jsonb, 'COMPLETED', 90, 'ACCEPTED', NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days', 'worker-default');

-- 7. Seed Sample Announcements for Contest 1
INSERT INTO contest_announcements (contest_id, author_id, title, body, posted_at) VALUES
(1, 1, 'Welcome to Max Speed Run!',
 'Welcome everyone! Please read the judging description carefully. Submissions must include run_time_seconds and restarts fields. Good luck!',
 NOW() - INTERVAL '1 hour 50 minutes'),
(1, 2, 'Scoreboard Freeze Notice',
 'The scoreboard is now frozen. Final standings will be revealed at the end of the contest. Keep submitting — your best run before the freeze counts!',
 NOW() - INTERVAL '1 hour 1 minute');

-- 8. Sync SERIAL sequences to prevent duplicate key errors on future inserts
SELECT setval('contests_id_seq',              COALESCE((SELECT MAX(id) FROM contests), 1));
SELECT setval('users_id_seq',                 COALESCE((SELECT MAX(id) FROM users), 1));
SELECT setval('tasks_id_seq',                 COALESCE((SELECT MAX(id) FROM tasks), 1));
SELECT setval('submissions_id_seq',           COALESCE((SELECT MAX(id) FROM submissions), 1));
SELECT setval('contest_announcements_id_seq', COALESCE((SELECT MAX(id) FROM contest_announcements), 1));
SELECT setval('kick_log_id_seq',              COALESCE((SELECT MAX(id) FROM kick_log), 1));
