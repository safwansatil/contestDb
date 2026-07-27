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
