-- PL/pgSQL Stored Procedures and Views for ContestDB
-- Database: PostgreSQL (Neon Serverless)

-- 1. Function to Claim Submissions from Queue (FOR UPDATE SKIP LOCKED)
CREATE OR REPLACE FUNCTION claim_submission(p_worker_id VARCHAR)
RETURNS TABLE (
    submission_id INT,
    contest_id INT,
    user_id INT,
    submission_data JSONB
) AS $$
DECLARE
    v_sub_id INT;
BEGIN
    -- Select the oldest pending submission, lock the row, and skip any already locked
    SELECT id INTO v_sub_id
    FROM submissions
    WHERE status = 'PENDING'
    ORDER BY submitted_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT 1;

    -- If a submission was successfully locked, update its status and return its details
    IF v_sub_id IS NOT NULL THEN
        UPDATE submissions
        SET status = 'JUDGING', 
            judged_by = p_worker_id
        WHERE id = v_sub_id;

        RETURN QUERY 
        SELECT id, s.contest_id, s.user_id, s.submission_data
        FROM submissions s
        WHERE id = v_sub_id;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 2. Function to Get Dynamic Time-Aware Leaderboard
-- Strategies: 
--   'SUM': Score is the SUM of all submissions.
--   'MAX': Score is the MAX score of any submission.
--   With tasks, 'SUM' strategy sums the user's best scores across all tasks.
CREATE OR REPLACE FUNCTION get_leaderboard(p_contest_id INT, p_as_admin BOOLEAN DEFAULT FALSE)
RETURNS TABLE (
    user_id INT,
    username VARCHAR,
    total_score NUMERIC,
    rank INT
) AS $$
DECLARE
    v_start_time TIMESTAMP WITH TIME ZONE;
    v_freeze_time TIMESTAMP WITH TIME ZONE;
    v_end_time TIMESTAMP WITH TIME ZONE;
    v_strategy VARCHAR(30);
    v_effective_freeze TIMESTAMP WITH TIME ZONE;
    v_has_tasks BOOLEAN;
BEGIN
    -- Fetch contest settings
    SELECT start_time, freeze_time, end_time, ranking_strategy 
      INTO v_start_time, v_freeze_time, v_end_time, v_strategy
    FROM contests
    WHERE id = p_contest_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contest with ID % not found', p_contest_id;
    END IF;

    -- Determine freeze boundary:
    IF p_as_admin OR NOW() >= v_end_time THEN
        v_effective_freeze := v_end_time;
    ELSE
        v_effective_freeze := v_freeze_time;
    END IF;

    -- Check if contest has tasks
    SELECT EXISTS(SELECT 1 FROM tasks WHERE contest_id = p_contest_id) INTO v_has_tasks;

    IF v_has_tasks THEN
        IF v_strategy = 'MAX' THEN
            -- With tasks, MAX strategy is the maximum score achieved across all tasks in the contest
            RETURN QUERY
            WITH user_best_scores AS (
                SELECT 
                    s.user_id,
                    MAX(s.score) AS best_score
                FROM submissions s
                WHERE s.contest_id = p_contest_id
                  AND s.status = 'COMPLETED'
                  AND s.submitted_at >= v_start_time
                  AND s.submitted_at < v_effective_freeze
                GROUP BY s.user_id
            )
            SELECT 
                u.id AS user_id,
                u.username,
                COALESCE(ubs.best_score, 0)::NUMERIC AS total_score,
                DENSE_RANK() OVER (ORDER BY COALESCE(ubs.best_score, 0) DESC)::INT AS rank
            FROM enrollments e
            JOIN users u ON e.user_id = u.id
            LEFT JOIN user_best_scores ubs ON e.user_id = ubs.user_id
            WHERE e.contest_id = p_contest_id;
        ELSE
            -- With tasks, SUM strategy is the sum of maximum score achieved on each task
            RETURN QUERY
            WITH user_task_scores AS (
                SELECT 
                    s.user_id,
                    s.task_id,
                    MAX(s.score) AS best_score
                FROM submissions s
                WHERE s.contest_id = p_contest_id
                  AND s.status = 'COMPLETED'
                  AND s.submitted_at >= v_start_time
                  AND s.submitted_at < v_effective_freeze
                GROUP BY s.user_id, s.task_id
            ),
            user_sum_scores AS (
                SELECT 
                    uts.user_id,
                    SUM(uts.best_score) AS sum_score
                FROM user_task_scores uts
                GROUP BY uts.user_id
            )
            SELECT 
                u.id AS user_id,
                u.username,
                COALESCE(uss.sum_score, 0)::NUMERIC AS total_score,
                DENSE_RANK() OVER (ORDER BY COALESCE(uss.sum_score, 0) DESC)::INT AS rank
            FROM enrollments e
            JOIN users u ON e.user_id = u.id
            LEFT JOIN user_sum_scores uss ON e.user_id = uss.user_id
            WHERE e.contest_id = p_contest_id;
        END IF;
    ELSE
        -- Fallback to old behavior if no tasks exist
        IF v_strategy = 'MAX' THEN
            RETURN QUERY
            WITH user_best_scores AS (
                SELECT 
                    s.user_id,
                    MAX(s.score) AS best_score
                FROM submissions s
                WHERE s.contest_id = p_contest_id
                  AND s.status = 'COMPLETED'
                  AND s.submitted_at >= v_start_time
                  AND s.submitted_at < v_effective_freeze
                GROUP BY s.user_id
            )
            SELECT 
                u.id AS user_id,
                u.username,
                COALESCE(ubs.best_score, 0)::NUMERIC AS total_score,
                DENSE_RANK() OVER (ORDER BY COALESCE(ubs.best_score, 0) DESC)::INT AS rank
            FROM enrollments e
            JOIN users u ON e.user_id = u.id
            LEFT JOIN user_best_scores ubs ON e.user_id = ubs.user_id
            WHERE e.contest_id = p_contest_id;

        ELSE -- Default strategy: 'SUM' (Accumulative score)
            RETURN QUERY
            WITH user_sum_scores AS (
                SELECT 
                    s.user_id,
                    SUM(s.score) AS sum_score
                FROM submissions s
                WHERE s.contest_id = p_contest_id
                  AND s.status = 'COMPLETED'
                  AND s.submitted_at >= v_start_time
                  AND s.submitted_at < v_effective_freeze
                GROUP BY s.user_id
            )
            SELECT 
                u.id AS user_id,
                u.username,
                COALESCE(uss.sum_score, 0)::NUMERIC AS total_score,
                DENSE_RANK() OVER (ORDER BY COALESCE(uss.sum_score, 0) DESC)::INT AS rank
            FROM enrollments e
            JOIN users u ON e.user_id = u.id
            LEFT JOIN user_sum_scores uss ON e.user_id = uss.user_id
            WHERE e.contest_id = p_contest_id;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 3. Function to Register a New User Natively
CREATE OR REPLACE FUNCTION register_user(p_username VARCHAR, p_password VARCHAR)
RETURNS TABLE (
    user_id INT,
    username VARCHAR,
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    INSERT INTO users (username, password_hash)
    VALUES (p_username, crypt(p_password, gen_salt('bf')))
    RETURNING id, users.username, users.created_at;
END;
$$ LANGUAGE plpgsql;

-- 4. Function to Verify User Credentials Natively
CREATE OR REPLACE FUNCTION verify_user_credentials(p_username VARCHAR, p_password VARCHAR)
RETURNS TABLE (
    user_id INT,
    username VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT id, users.username
    FROM users
    WHERE users.username = p_username 
      AND users.password_hash = crypt(p_password, users.password_hash);
END;
$$ LANGUAGE plpgsql;

-- 5. Stored Procedures for Contest CRUD, Tasks, and Roles

-- A. Create Contest (Starts as PENDING_APPROVAL, Creator becomes HOST)
CREATE OR REPLACE FUNCTION create_contest_native(
    p_title VARCHAR,
    p_ranking_strategy VARCHAR,
    p_start_time TIMESTAMP WITH TIME ZONE,
    p_freeze_time TIMESTAMP WITH TIME ZONE,
    p_end_time TIMESTAMP WITH TIME ZONE,
    p_invitation_code VARCHAR,
    p_judging_description TEXT,
    p_creator_id INT
) RETURNS INT AS $$
DECLARE
    v_contest_id INT;
BEGIN
    INSERT INTO contests (title, ranking_strategy, start_time, freeze_time, end_time, invitation_code, judging_description, status)
    VALUES (p_title, p_ranking_strategy, p_start_time, p_freeze_time, p_end_time, p_invitation_code, p_judging_description, 'PENDING_APPROVAL')
    RETURNING id INTO v_contest_id;

    -- Creator is automatically enrolled as HOST
    INSERT INTO enrollments (contest_id, user_id, role)
    VALUES (v_contest_id, p_creator_id, 'HOST');

    RETURN v_contest_id;
END;
$$ LANGUAGE plpgsql;

-- B. Approve Contest (Developer/Admin operation to make it ACTIVE)
CREATE OR REPLACE FUNCTION approve_contest_native(p_contest_id INT)
RETURNS VOID AS $$
BEGIN
    UPDATE contests
    SET status = 'ACTIVE'
    WHERE id = p_contest_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contest not found';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- C. Update Contest (Only Hosts & Moderators)
CREATE OR REPLACE FUNCTION update_contest_native(
    p_contest_id INT,
    p_user_id INT,
    p_title VARCHAR,
    p_ranking_strategy VARCHAR,
    p_start_time TIMESTAMP WITH TIME ZONE,
    p_freeze_time TIMESTAMP WITH TIME ZONE,
    p_end_time TIMESTAMP WITH TIME ZONE,
    p_invitation_code VARCHAR,
    p_judging_description TEXT
) RETURNS VOID AS $$
DECLARE
    v_role VARCHAR;
BEGIN
    SELECT role INTO v_role
    FROM enrollments
    WHERE contest_id = p_contest_id AND user_id = p_user_id;

    IF v_role IS NULL OR v_role NOT IN ('HOST', 'MODERATOR') THEN
        RAISE EXCEPTION 'Unauthorized: Only Host or Moderator can update this contest';
    END IF;

    UPDATE contests
    SET title = p_title,
        ranking_strategy = p_ranking_strategy,
        start_time = p_start_time,
        freeze_time = p_freeze_time,
        end_time = p_end_time,
        invitation_code = p_invitation_code,
        judging_description = p_judging_description
    WHERE id = p_contest_id;
END;
$$ LANGUAGE plpgsql;

-- D. Delete Contest (Only Hosts)
CREATE OR REPLACE FUNCTION delete_contest_native(
    p_contest_id INT,
    p_user_id INT
) RETURNS VOID AS $$
DECLARE
    v_role VARCHAR;
BEGIN
    SELECT role INTO v_role
    FROM enrollments
    WHERE contest_id = p_contest_id AND user_id = p_user_id;

    IF v_role IS NULL OR v_role <> 'HOST' THEN
        RAISE EXCEPTION 'Unauthorized: Only Host can delete this contest';
    END IF;

    DELETE FROM contests WHERE id = p_contest_id;
END;
$$ LANGUAGE plpgsql;

-- E. Add Task (Only Hosts & Moderators)
CREATE OR REPLACE FUNCTION add_task_native(
    p_contest_id INT,
    p_user_id INT,
    p_title VARCHAR,
    p_description TEXT,
    p_max_score NUMERIC
) RETURNS INT AS $$
DECLARE
    v_role VARCHAR;
    v_task_id INT;
BEGIN
    SELECT role INTO v_role
    FROM enrollments
    WHERE contest_id = p_contest_id AND user_id = p_user_id;

    IF v_role IS NULL OR v_role NOT IN ('HOST', 'MODERATOR') THEN
        RAISE EXCEPTION 'Unauthorized: Only Host or Moderator can add tasks';
    END IF;

    INSERT INTO tasks (contest_id, title, description, max_score)
    VALUES (p_contest_id, p_title, p_description, p_max_score)
    RETURNING id INTO v_task_id;

    RETURN v_task_id;
END;
$$ LANGUAGE plpgsql;

-- F. Update Task (Only Hosts & Moderators)
CREATE OR REPLACE FUNCTION update_task_native(
    p_task_id INT,
    p_user_id INT,
    p_title VARCHAR,
    p_description TEXT,
    p_max_score NUMERIC
) RETURNS VOID AS $$
DECLARE
    v_contest_id INT;
    v_role VARCHAR;
BEGIN
    SELECT contest_id INTO v_contest_id
    FROM tasks
    WHERE id = p_task_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task not found';
    END IF;

    SELECT role INTO v_role
    FROM enrollments
    WHERE contest_id = v_contest_id AND user_id = p_user_id;

    IF v_role IS NULL OR v_role NOT IN ('HOST', 'MODERATOR') THEN
        RAISE EXCEPTION 'Unauthorized: Only Host or Moderator can update tasks';
    END IF;

    UPDATE tasks
    SET title = p_title,
        description = p_description,
        max_score = p_max_score
    WHERE id = p_task_id;
END;
$$ LANGUAGE plpgsql;

-- G. Delete Task (Only Hosts & Moderators)
CREATE OR REPLACE FUNCTION delete_task_native(
    p_task_id INT,
    p_user_id INT
) RETURNS VOID AS $$
DECLARE
    v_contest_id INT;
    v_role VARCHAR;
BEGIN
    SELECT contest_id INTO v_contest_id
    FROM tasks
    WHERE id = p_task_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task not found';
    END IF;

    SELECT role INTO v_role
    FROM enrollments
    WHERE contest_id = v_contest_id AND user_id = p_user_id;

    IF v_role IS NULL OR v_role NOT IN ('HOST', 'MODERATOR') THEN
        RAISE EXCEPTION 'Unauthorized: Only Host or Moderator can delete tasks';
    END IF;

    DELETE FROM tasks WHERE id = p_task_id;
END;
$$ LANGUAGE plpgsql;

-- H. Enroll in Contest (Invitation Code Checked Natively)
CREATE OR REPLACE FUNCTION enroll_in_contest(
    p_contest_id INT,
    p_user_id INT,
    p_code VARCHAR DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
    v_expected_code VARCHAR;
    v_status VARCHAR;
    v_is_enrolled BOOLEAN;
BEGIN
    -- Check if already enrolled
    SELECT EXISTS(
        SELECT 1 FROM enrollments 
        WHERE contest_id = p_contest_id AND user_id = p_user_id
    ) INTO v_is_enrolled;

    IF v_is_enrolled THEN
        RETURN;
    END IF;

    -- Fetch contest settings
    SELECT status, invitation_code INTO v_status, v_expected_code
    FROM contests
    WHERE id = p_contest_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contest not found';
    END IF;

    -- Cannot enroll in unapproved contests (unless host/creator who is already enrolled)
    IF v_status = 'PENDING_APPROVAL' THEN
        RAISE EXCEPTION 'This contest is pending developer approval';
    END IF;

    -- Validate invitation code if it is set
    IF v_expected_code IS NOT NULL AND v_expected_code <> '' THEN
        IF p_code IS NULL OR p_code <> v_expected_code THEN
            RAISE EXCEPTION 'Invalid invitation code';
        END IF;
    END IF;

    INSERT INTO enrollments (contest_id, user_id, role)
    VALUES (p_contest_id, p_user_id, 'PARTICIPANT');
END;
$$ LANGUAGE plpgsql;

-- I. Update Member Role (Only Hosts)
CREATE OR REPLACE FUNCTION update_contest_member_role(
    p_contest_id INT,
    p_requesting_user_id INT,
    p_target_user_id INT,
    p_new_role VARCHAR
) RETURNS VOID AS $$
DECLARE
    v_req_role VARCHAR;
BEGIN
    -- Only HOST can modify roles
    SELECT role INTO v_req_role
    FROM enrollments
    WHERE contest_id = p_contest_id AND user_id = p_requesting_user_id;

    IF v_req_role IS NULL OR v_req_role <> 'HOST' THEN
        RAISE EXCEPTION 'Unauthorized: Only the Host can manage roles';
    END IF;

    IF p_new_role NOT IN ('HOST', 'MODERATOR', 'PARTICIPANT') THEN
        RAISE EXCEPTION 'Invalid role specified';
    END IF;

    INSERT INTO enrollments (contest_id, user_id, role)
    VALUES (p_contest_id, p_target_user_id, p_new_role)
    ON CONFLICT (contest_id, user_id)
    DO UPDATE SET role = EXCLUDED.role;
END;
$$ LANGUAGE plpgsql;

-- J. Fetch User Profile Statistics (Database-Native)
CREATE OR REPLACE FUNCTION get_user_profile_stats(p_user_id INT)
RETURNS TABLE (
    total_submissions INT,
    total_contests_joined INT,
    unique_tasks_attempted INT,
    fully_completed_tasks INT,
    average_score NUMERIC,
    max_score_single NUMERIC,
    verdict_breakdown JSONB
) AS $$
DECLARE
    v_total_subs INT;
    v_total_contests INT;
    v_tasks_attempted INT;
    v_completed_tasks INT;
    v_avg_score NUMERIC;
    v_max_score NUMERIC;
    v_verdicts JSONB;
BEGIN
    -- Total submissions
    SELECT COUNT(*)::INT INTO v_total_subs FROM submissions WHERE user_id = p_user_id;

    -- Total contests joined
    SELECT COUNT(DISTINCT contest_id)::INT INTO v_total_contests FROM enrollments WHERE user_id = p_user_id;

    -- Unique tasks attempted
    SELECT COUNT(DISTINCT task_id)::INT INTO v_tasks_attempted FROM submissions WHERE user_id = p_user_id AND task_id IS NOT NULL;

    -- Fully completed tasks (where score >= task's max_score)
    SELECT COUNT(DISTINCT s.task_id)::INT INTO v_completed_tasks
    FROM submissions s
    JOIN tasks t ON s.task_id = t.id
    WHERE s.user_id = p_user_id AND s.score >= t.max_score AND s.status = 'COMPLETED';

    -- Average score
    SELECT COALESCE(AVG(score), 0)::NUMERIC(10,2) INTO v_avg_score FROM submissions WHERE user_id = p_user_id AND status = 'COMPLETED';

    -- Max score
    SELECT COALESCE(MAX(score), 0)::NUMERIC(10,2) INTO v_max_score FROM submissions WHERE user_id = p_user_id AND status = 'COMPLETED';

    -- Verdict breakdown as JSONB
    SELECT COALESCE(jsonb_object_agg(COALESCE(verdict, 'UNKNOWN'), cnt), '{}'::jsonb)
    INTO v_verdicts
    FROM (
        SELECT verdict, COUNT(*)::INT as cnt
        FROM submissions
        WHERE user_id = p_user_id AND status = 'COMPLETED'
        GROUP BY verdict
    ) q;

    RETURN QUERY SELECT v_total_subs, v_total_contests, v_tasks_attempted, v_completed_tasks, v_avg_score, v_max_score, v_verdicts;
END;
$$ LANGUAGE plpgsql;

-- K. Fetch User Activity Graph (Submissions Count by Date)
CREATE OR REPLACE FUNCTION get_user_activity_graph(p_user_id INT)
RETURNS TABLE (
    activity_date DATE,
    submission_count INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT DATE(submitted_at AT TIME ZONE 'UTC') AS act_date, COUNT(*)::INT
    FROM submissions
    WHERE user_id = p_user_id
    GROUP BY act_date
    ORDER BY act_date ASC;
END;
$$ LANGUAGE plpgsql;

-- L. Fetch User Contest Participation History
CREATE OR REPLACE FUNCTION get_user_contest_history(p_user_id INT)
RETURNS TABLE (
    contest_id INT,
    contest_title VARCHAR,
    role VARCHAR,
    registered_at TIMESTAMP WITH TIME ZONE,
    total_score NUMERIC,
    rank INT
) AS $$
BEGIN
    RETURN QUERY
    WITH enrolled_contests AS (
        SELECT e.contest_id, c.title, e.role, e.registered_at
        FROM enrollments e
        JOIN contests c ON e.contest_id = c.id
        WHERE e.user_id = p_user_id
    ),
    contest_standings AS (
        SELECT 
            ec.contest_id,
            l.user_id,
            l.total_score,
            l.rank
        FROM enrolled_contests ec
        CROSS JOIN LATERAL get_leaderboard(ec.contest_id, TRUE) l
    )
    SELECT 
        ec.contest_id,
        ec.title AS contest_title,
        ec.role,
        ec.registered_at,
        CASE WHEN ec.role = 'PARTICIPANT' THEN cs.total_score ELSE NULL END AS total_score,
        CASE WHEN ec.role = 'PARTICIPANT' THEN cs.rank ELSE NULL END AS rank
    FROM enrolled_contests ec
    LEFT JOIN contest_standings cs ON ec.contest_id = cs.contest_id AND cs.user_id = p_user_id
    ORDER BY ec.registered_at DESC;
END;
$$ LANGUAGE plpgsql;

-- M. Fetch User Submission History
CREATE OR REPLACE FUNCTION get_user_submission_history(p_user_id INT, p_limit INT DEFAULT 20)
RETURNS TABLE (
    submission_id INT,
    contest_id INT,
    contest_title VARCHAR,
    task_id INT,
    task_title VARCHAR,
    score NUMERIC,
    verdict VARCHAR,
    submitted_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.id,
        s.contest_id,
        c.title AS contest_title,
        s.task_id,
        t.title AS task_title,
        s.score,
        s.verdict,
        s.submitted_at
    FROM submissions s
    LEFT JOIN contests c ON s.contest_id = c.id
    LEFT JOIN tasks t ON s.task_id = t.id
    WHERE s.user_id = p_user_id
    ORDER BY s.submitted_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- N. Fetch Contest-Wide Statistics (With scoreboard freeze rules)
CREATE OR REPLACE FUNCTION get_contest_statistics(p_contest_id INT, p_as_admin BOOLEAN DEFAULT FALSE)
RETURNS TABLE (
    total_participants INT,
    active_participants INT,
    total_submissions INT,
    task_stats JSONB
) AS $$
DECLARE
    v_start_time TIMESTAMP WITH TIME ZONE;
    v_freeze_time TIMESTAMP WITH TIME ZONE;
    v_end_time TIMESTAMP WITH TIME ZONE;
    v_effective_freeze TIMESTAMP WITH TIME ZONE;
    v_total_parts INT;
    v_active_parts INT;
    v_total_subs INT;
    v_task_stats JSONB;
BEGIN
    SELECT start_time, freeze_time, end_time INTO v_start_time, v_freeze_time, v_end_time
    FROM contests WHERE id = p_contest_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contest with ID % not found', p_contest_id;
    END IF;

    IF p_as_admin OR NOW() >= v_end_time THEN
        v_effective_freeze := v_end_time;
    ELSE
        v_effective_freeze := v_freeze_time;
    END IF;

    -- Total participants (enrolled with role = 'PARTICIPANT')
    SELECT COUNT(*)::INT INTO v_total_parts 
    FROM enrollments 
    WHERE contest_id = p_contest_id AND role = 'PARTICIPANT';

    -- Active participants (submitted at least once before freeze)
    SELECT COUNT(DISTINCT user_id)::INT INTO v_active_parts
    FROM submissions
    WHERE contest_id = p_contest_id 
      AND submitted_at >= v_start_time 
      AND submitted_at < v_effective_freeze;

    -- Total submissions before freeze
    SELECT COUNT(*)::INT INTO v_total_subs
    FROM submissions
    WHERE contest_id = p_contest_id
      AND submitted_at >= v_start_time
      AND submitted_at < v_effective_freeze;

    -- Task-by-task statistics
    SELECT COALESCE(jsonb_agg(t_row), '[]'::jsonb) INTO v_task_stats
    FROM (
        SELECT 
            t.id AS task_id,
            t.title AS task_title,
            t.max_score,
            COALESCE(AVG(s.score), 0)::NUMERIC(10,2) AS avg_score,
            COALESCE(MAX(s.score), 0)::NUMERIC(10,2) AS max_score_achieved,
            COUNT(s.id)::INT AS total_attempts,
            COUNT(DISTINCT CASE WHEN s.score >= t.max_score THEN s.user_id END)::INT AS solved_users
        FROM tasks t
        LEFT JOIN submissions s ON t.id = s.task_id 
          AND s.submitted_at >= v_start_time 
          AND s.submitted_at < v_effective_freeze
          AND s.status = 'COMPLETED'
        WHERE t.contest_id = p_contest_id
        GROUP BY t.id, t.title, t.max_score
        ORDER BY t.id ASC
    ) t_row;

    RETURN QUERY SELECT v_total_parts, v_active_parts, v_total_subs, v_task_stats;
END;
$$ LANGUAGE plpgsql;

-- O. Fetch Contest Submission Timeline Chart Data
CREATE OR REPLACE FUNCTION get_contest_submission_timeline(p_contest_id INT, p_as_admin BOOLEAN DEFAULT FALSE)
RETURNS TABLE (
    bucket_start TIMESTAMP WITH TIME ZONE,
    submission_count INT
) AS $$
DECLARE
    v_start TIMESTAMP WITH TIME ZONE;
    v_end TIMESTAMP WITH TIME ZONE;
    v_freeze TIMESTAMP WITH TIME ZONE;
    v_effective_freeze TIMESTAMP WITH TIME ZONE;
    v_duration_hours NUMERIC;
    v_stride INTERVAL;
BEGIN
    SELECT start_time, freeze_time, end_time INTO v_start, v_freeze, v_end
    FROM contests WHERE id = p_contest_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contest not found';
    END IF;

    IF p_as_admin OR NOW() >= v_end THEN
        v_effective_freeze := v_end;
    ELSE
        v_effective_freeze := v_freeze;
    END IF;

    v_duration_hours := EXTRACT(EPOCH FROM (v_end - v_start)) / 3600;

    IF v_duration_hours <= 6 THEN
        v_stride := INTERVAL '10 minutes';
    ELSIF v_duration_hours <= 24 THEN
        v_stride := INTERVAL '30 minutes';
    ELSIF v_duration_hours <= 168 THEN -- 7 days
        v_stride := INTERVAL '3 hours';
    ELSE
        v_stride := INTERVAL '1 day';
    END IF;

    RETURN QUERY
    SELECT 
        date_bin(v_stride, submitted_at, v_start) AS b_start,
        COUNT(*)::INT
    FROM submissions
    WHERE contest_id = p_contest_id
      AND submitted_at >= v_start
      AND submitted_at < v_effective_freeze
    GROUP BY b_start
    ORDER BY b_start ASC;
END;
$$ LANGUAGE plpgsql;

-- P. Fetch Participant Score Cumulative Progression
CREATE OR REPLACE FUNCTION get_participant_score_progression(p_contest_id INT, p_user_id INT)
RETURNS TABLE (
    submitted_at TIMESTAMP WITH TIME ZONE,
    running_score NUMERIC
) AS $$
DECLARE
    v_strategy VARCHAR(30);
    v_has_tasks BOOLEAN;
BEGIN
    SELECT ranking_strategy INTO v_strategy FROM contests WHERE id = p_contest_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contest not found';
    END IF;

    SELECT EXISTS(SELECT 1 FROM tasks WHERE contest_id = p_contest_id) INTO v_has_tasks;

    IF v_has_tasks THEN
        IF v_strategy = 'MAX' THEN
            RETURN QUERY
            SELECT 
                s.submitted_at,
                (
                    SELECT COALESCE(MAX(sub.score), 0)
                    FROM submissions sub
                    WHERE sub.contest_id = p_contest_id
                      AND sub.user_id = p_user_id
                      AND sub.status = 'COMPLETED'
                      AND sub.submitted_at <= s.submitted_at
                )::NUMERIC AS running_score
            FROM submissions s
            WHERE s.contest_id = p_contest_id
              AND s.user_id = p_user_id
              AND s.status = 'COMPLETED'
            ORDER BY s.submitted_at ASC;
        ELSE -- 'SUM' strategy: Sum of best score on each task up to that submission time
            RETURN QUERY
            SELECT 
                s.submitted_at,
                (
                    SELECT COALESCE(SUM(best.max_score), 0)
                    FROM (
                        SELECT sub.task_id, MAX(sub.score) AS max_score
                        FROM submissions sub
                        WHERE sub.contest_id = p_contest_id
                          AND sub.user_id = p_user_id
                          AND sub.status = 'COMPLETED'
                          AND sub.submitted_at <= s.submitted_at
                        GROUP BY sub.task_id
                    ) best
                )::NUMERIC AS running_score
            FROM submissions s
            WHERE s.contest_id = p_contest_id
              AND s.user_id = p_user_id
              AND s.status = 'COMPLETED'
            ORDER BY s.submitted_at ASC;
        END IF;
    ELSE
        -- Fallback if no tasks exist
        IF v_strategy = 'MAX' THEN
            RETURN QUERY
            SELECT 
                s.submitted_at,
                (
                    SELECT COALESCE(MAX(sub.score), 0)
                    FROM submissions sub
                    WHERE sub.contest_id = p_contest_id
                      AND sub.user_id = p_user_id
                      AND sub.status = 'COMPLETED'
                      AND sub.submitted_at <= s.submitted_at
                )::NUMERIC AS running_score
            FROM submissions s
            WHERE s.contest_id = p_contest_id
              AND s.user_id = p_user_id
              AND s.status = 'COMPLETED'
            ORDER BY s.submitted_at ASC;
        ELSE
            RETURN QUERY
            SELECT 
                s.submitted_at,
                (
                    SELECT COALESCE(SUM(sub.score), 0)
                    FROM submissions sub
                    WHERE sub.contest_id = p_contest_id
                      AND sub.user_id = p_user_id
                      AND sub.status = 'COMPLETED'
                      AND sub.submitted_at <= s.submitted_at
                )::NUMERIC AS running_score
            FROM submissions s
            WHERE s.contest_id = p_contest_id
              AND s.user_id = p_user_id
              AND s.status = 'COMPLETED'
            ORDER BY s.submitted_at ASC;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;
