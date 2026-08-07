-- PL/pgSQL Stored Procedures and Views for ContestDB
-- Database: PostgreSQL (Neon Serverless)

-- ============================================================
-- 1. Function to Claim Submissions from Queue (FOR UPDATE SKIP LOCKED)
-- ============================================================
DROP FUNCTION IF EXISTS claim_submission(VARCHAR);
CREATE OR REPLACE FUNCTION claim_submission(
    p_worker_id VARCHAR,
    p_lease_seconds INT DEFAULT 60,
    p_max_attempts INT DEFAULT 3
)
RETURNS TABLE (
    submission_id INT,
    contest_id INT,
    user_id INT,
    submission_data JSONB
) AS $$
DECLARE
    v_sub_id INT;
BEGIN
    IF p_lease_seconds <= 0 THEN
        RAISE EXCEPTION 'Lease duration must be greater than zero';
    END IF;

    IF p_max_attempts <= 0 THEN
        RAISE EXCEPTION 'Maximum attempts must be greater than zero';
    END IF;

    -- Permanently fail expired jobs that already reached the retry limit.
    UPDATE submissions
    SET status = 'FAILED',
        judged_by = NULL,
        lease_expires_at = NULL,
        last_error = COALESCE(
            last_error,
            'Worker lease expired after maximum retry attempts'
        )
    WHERE status = 'JUDGING'
      AND lease_expires_at <= CURRENT_TIMESTAMP
      AND attempt_count >= p_max_attempts;

    -- Recover expired jobs that still have retries remaining.
    UPDATE submissions
    SET status = 'PENDING',
        judged_by = NULL,
        lease_expires_at = NULL,
        last_error = 'Previous worker lease expired'
    WHERE status = 'JUDGING'
      AND lease_expires_at <= CURRENT_TIMESTAMP
      AND attempt_count < p_max_attempts;

    -- Lock and claim the oldest eligible pending submission.
    SELECT s.id
    INTO v_sub_id
    FROM submissions s
    WHERE s.status = 'PENDING'
      AND s.attempt_count < p_max_attempts
    ORDER BY s.submitted_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT 1;

    IF v_sub_id IS NOT NULL THEN
        UPDATE submissions
        SET status = 'JUDGING',
            judged_by = p_worker_id,
            attempt_count = attempt_count + 1,
            lease_expires_at =
                CURRENT_TIMESTAMP + make_interval(secs => p_lease_seconds),
            last_error = NULL
        WHERE id = v_sub_id;

        RETURN QUERY
        SELECT s.id, s.contest_id, s.user_id, s.submission_data
        FROM submissions s
        WHERE s.id = v_sub_id;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 2. Function to Get Dynamic Time-Aware Leaderboard
-- Strategies:
--   'SUM': Score is the SUM of the user's best scores across all tasks.
--   'MAX': Score is the single MAX score achieved across all submissions.
--   Scoreboard freeze logic applies: public viewers see standings frozen at freeze_time.
-- ============================================================
CREATE OR REPLACE FUNCTION get_leaderboard(p_contest_id INT, p_viewer_id INT DEFAULT NULL)
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
    v_is_admin BOOLEAN := FALSE;
BEGIN
    -- Fetch contest settings
    SELECT start_time, freeze_time, end_time, ranking_strategy
      INTO v_start_time, v_freeze_time, v_end_time, v_strategy
    FROM contests
    WHERE id = p_contest_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contest with ID % not found', p_contest_id;
    END IF;

    -- Check if the viewer is HOST or MODERATOR
    -- NOTE: columns are qualified with the table alias because this function's
    -- RETURNS TABLE declares an output column named `user_id`, which would otherwise
    -- make the bare `user_id` reference ambiguous and raise an error at runtime.
    IF p_viewer_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1
            FROM enrollments e
            WHERE e.contest_id = p_contest_id
              AND e.user_id = p_viewer_id
              AND e.role IN ('HOST', 'MODERATOR')
        ) INTO v_is_admin;
    END IF;

    -- Determine freeze boundary:
    IF v_is_admin THEN
        -- Admins see everything up to the current moment, capped at contest end
        v_effective_freeze := LEAST(NOW(), v_end_time);
    ELSE
        IF NOW() >= v_end_time THEN
            -- After contest ends, everyone sees the final standings
            v_effective_freeze := v_end_time;
        ELSE
            -- During the contest, regular users see standings up to NOW() capped at freeze_time (defaulting to end_time if null)
            v_effective_freeze := LEAST(NOW(), COALESCE(v_freeze_time, v_end_time));
        END IF;
    END IF;

    -- Check if contest has tasks
    SELECT EXISTS(SELECT 1 FROM tasks WHERE contest_id = p_contest_id) INTO v_has_tasks;

    IF v_has_tasks THEN
        IF v_strategy = 'MAX' THEN
            -- MAX strategy with tasks: highest single score achieved across all tasks
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
            -- SUM strategy with tasks: sum of the user's best score on each task
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
        -- Fallback to old behavior if no tasks exist (task-less contests)
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

        ELSE -- Default strategy: 'SUM'
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

-- ============================================================
-- Post-contest rating calculation
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_contest_ratings_native(
    p_contest_id INT,
    p_user_id INT
) RETURNS INT AS $$
DECLARE
    v_end_time TIMESTAMP WITH TIME ZONE;
    v_participant_count INT;
    v_rows_inserted INT;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM enrollments
        WHERE contest_id = p_contest_id
        AND user_id = p_user_id
        AND role IN ('HOST', 'MODERATOR')
    ) THEN
        RAISE EXCEPTION 'Unauthorized: Only Host or Moderator can calculate ratings';
    END IF;

    SELECT end_time
    INTO v_end_time
    FROM contests
    WHERE id = p_contest_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contest not found';
    END IF;

    IF CURRENT_TIMESTAMP < v_end_time THEN
        RAISE EXCEPTION 'Contest has not ended yet';
    END IF;

    -- Prevent applying ratings twice.
    IF EXISTS (
        SELECT 1
        FROM contest_rating_history
        WHERE contest_id = p_contest_id
    ) THEN
        RETURN 0;
    END IF;

    SELECT COUNT(*)
    INTO v_participant_count
    FROM enrollments
    WHERE contest_id = p_contest_id
      AND role = 'PARTICIPANT';

    IF v_participant_count = 0 THEN
        RETURN 0;
    END IF;

    WITH participants AS MATERIALIZED (
        SELECT
            ranked.user_id,
            DENSE_RANK() OVER (
                ORDER BY ranked.total_score DESC
            )::INT AS final_rank,
            ranked.old_rating
        FROM (
            SELECT
                l.user_id,
                l.total_score,
                u.current_rating AS old_rating
            FROM get_leaderboard(p_contest_id, NULL) l
            JOIN enrollments e
            ON e.contest_id = p_contest_id
            AND e.user_id = l.user_id
            AND e.role = 'PARTICIPANT'
            JOIN users u
            ON u.id = l.user_id
        ) ranked
    ),
    calculated AS (
        SELECT
            p.user_id,
            p.final_rank,
            p.old_rating,

            CASE
                WHEN v_participant_count = 1 THEN 0.5
                ELSE
                    (v_participant_count - p.final_rank)::NUMERIC
                    / (v_participant_count - 1)
            END AS actual_score,

            CASE
                WHEN v_participant_count = 1 THEN 0.5
                ELSE (
                    SELECT AVG(
                        1.0 / (
                            1.0 +
                            POWER(
                                10.0,
                                (op.old_rating - p.old_rating)::NUMERIC / 400.0
                            )
                        )
                    )
                    FROM participants op
                    WHERE op.user_id <> p.user_id
                )
            END AS expected_score
        FROM participants p
    ),
    rating_changes AS (
        SELECT
            user_id,
            final_rank,
            old_rating,
            ROUND(
                32 * (actual_score - expected_score)
            )::INT AS rating_change
        FROM calculated
    ),
    inserted AS (
        INSERT INTO contest_rating_history (
            contest_id,
            user_id,
            old_rating,
            rating_change,
            new_rating,
            final_rank
        )
        SELECT
            p_contest_id,
            rc.user_id,
            rc.old_rating,
            rc.rating_change,
            rc.old_rating + rc.rating_change,
            rc.final_rank
        FROM rating_changes rc
        ON CONFLICT (contest_id, user_id) DO NOTHING
        RETURNING user_id, new_rating
    )
    UPDATE users u
    SET current_rating = i.new_rating
    FROM inserted i
    WHERE u.id = i.user_id;

    GET DIAGNOSTICS v_rows_inserted = ROW_COUNT;

    UPDATE contests
    SET status = 'COMPLETED'
    WHERE id = p_contest_id;

    RETURN v_rows_inserted;
END;
$$ LANGUAGE plpgsql;

ALTER FUNCTION calculate_contest_ratings_native(INT, INT)
    SECURITY DEFINER;

ALTER FUNCTION calculate_contest_ratings_native(INT, INT)
    SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION get_user_rating_history_native(
    p_user_id INT
)
RETURNS TABLE (
    contest_id INT,
    contest_title VARCHAR,
    old_rating INT,
    rating_change INT,
    new_rating INT,
    final_rank INT,
    calculated_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        h.contest_id,
        c.title,
        h.old_rating,
        h.rating_change,
        h.new_rating,
        h.final_rank,
        h.calculated_at
    FROM contest_rating_history h
    JOIN contests c ON c.id = h.contest_id
    WHERE h.user_id = p_user_id
    ORDER BY h.calculated_at DESC, h.contest_id DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 3. Function to Register a New User Natively (pgcrypto bcrypt)
-- ============================================================
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

-- ============================================================
-- 4. Function to Verify User Credentials Natively
-- ============================================================
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

-- ============================================================
-- 5. Contest CRUD Functions
-- ============================================================

-- A. Create Contest
--    Contest starts as PENDING_APPROVAL. Creator is auto-enrolled as HOST.
--    A default contest_visibility row is inserted automatically.
CREATE OR REPLACE FUNCTION create_contest_native(
    p_title VARCHAR,
    p_ranking_strategy VARCHAR,
    p_start_time TIMESTAMP WITH TIME ZONE,
    p_freeze_time TIMESTAMP WITH TIME ZONE,
    p_end_time TIMESTAMP WITH TIME ZONE,
    p_invitation_code VARCHAR,
    p_judging_description TEXT,
    p_creator_id INT,
    p_max_participants INT DEFAULT NULL,
    p_allow_late_enrollment BOOLEAN DEFAULT TRUE
) RETURNS INT AS $$
DECLARE
    v_contest_id INT;
BEGIN
    INSERT INTO contests (title, ranking_strategy, start_time, freeze_time, end_time,
                          invitation_code, judging_description, status,
                          max_participants, allow_late_enrollment)
    VALUES (p_title, p_ranking_strategy, p_start_time, p_freeze_time, p_end_time,
            p_invitation_code, p_judging_description, 'PENDING_APPROVAL',
            p_max_participants, p_allow_late_enrollment)
    RETURNING id INTO v_contest_id;

    -- Creator is automatically enrolled as HOST
    INSERT INTO enrollments (contest_id, user_id, role)
    VALUES (v_contest_id, p_creator_id, 'HOST');

    -- Auto-create default visibility config for this contest
    INSERT INTO contest_visibility (contest_id)
    VALUES (v_contest_id);

    RETURN v_contest_id;
END;
$$ LANGUAGE plpgsql;

-- B. Approve Contest (Developer/Admin operation)
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
    p_judging_description TEXT,
    p_max_participants INT DEFAULT NULL,
    p_allow_late_enrollment BOOLEAN DEFAULT TRUE
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
        judging_description = p_judging_description,
        max_participants = p_max_participants,
        allow_late_enrollment = p_allow_late_enrollment
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

-- ============================================================
-- 6. Task CRUD Functions
-- ============================================================

-- E. Add Task (Only Hosts & Moderators)
--    submission_schema is REQUIRED — every task must declare the expected payload structure.
--    submission_cooldown_seconds: 0 = no cooldown enforced. > 0 = cooldown active.
--    task_order: display ordering index within the contest.
CREATE OR REPLACE FUNCTION add_task_native(
    p_contest_id INT,
    p_user_id INT,
    p_title VARCHAR,
    p_description TEXT,
    p_max_score NUMERIC,
    p_submission_schema JSONB,
    p_submission_cooldown_seconds INT DEFAULT 0,
    p_task_order INT DEFAULT 0
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

    INSERT INTO tasks (contest_id, title, description, max_score,
                       submission_schema, submission_cooldown_seconds, task_order)
    VALUES (p_contest_id, p_title, p_description, p_max_score,
            p_submission_schema, p_submission_cooldown_seconds, p_task_order)
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
    p_max_score NUMERIC,
    p_submission_schema JSONB,
    p_submission_cooldown_seconds INT DEFAULT 0,
    p_task_order INT DEFAULT 0
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
        max_score = p_max_score,
        submission_schema = p_submission_schema,
        submission_cooldown_seconds = p_submission_cooldown_seconds,
        task_order = p_task_order
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

-- Normalize and replace all tags assigned to a task
CREATE OR REPLACE FUNCTION set_task_tags_native(
    p_task_id INT,
    p_user_id INT,
    p_tags TEXT[]
) RETURNS VOID AS $$
DECLARE
    v_contest_id INT;
    v_role VARCHAR;
    v_tag TEXT;
    v_normalized_tag TEXT;
    v_tag_id INT;
BEGIN
    SELECT contest_id INTO v_contest_id
    FROM tasks
    WHERE id = p_task_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task not found';
    END IF;

    SELECT role INTO v_role
    FROM enrollments
    WHERE contest_id = v_contest_id
      AND user_id = p_user_id;

    IF v_role IS NULL OR v_role NOT IN ('HOST', 'MODERATOR') THEN
        RAISE EXCEPTION 'Unauthorized: Only Host or Moderator can update task tags';
    END IF;

    DELETE FROM task_tags
    WHERE task_id = p_task_id;

    FOREACH v_tag IN ARRAY COALESCE(p_tags, ARRAY[]::TEXT[])
    LOOP
        v_normalized_tag := LOWER(TRIM(v_tag));

        IF v_normalized_tag <> '' THEN
            INSERT INTO tags (name, normalized_name)
            VALUES (TRIM(v_tag), v_normalized_tag)
            ON CONFLICT (normalized_name)
            DO UPDATE SET normalized_name = EXCLUDED.normalized_name
            RETURNING id INTO v_tag_id;

            INSERT INTO task_tags (task_id, tag_id)
            VALUES (p_task_id, v_tag_id)
            ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

ALTER FUNCTION set_task_tags_native(INT, INT, TEXT[])
    SECURITY DEFINER;

ALTER FUNCTION set_task_tags_native(INT, INT, TEXT[])
    SET search_path = public, pg_temp;

-- GIN-backed task search with optional normalized tag filtering
CREATE OR REPLACE FUNCTION search_tasks_native(
    p_query TEXT DEFAULT NULL,
    p_tags TEXT[] DEFAULT NULL,
    p_contest_id INT DEFAULT NULL
)
RETURNS TABLE (
    id INT,
    contest_id INT,
    title VARCHAR,
    description TEXT,
    max_score NUMERIC,
    task_order INT,
    tags TEXT[]
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.id,
        t.contest_id,
        t.title,
        t.description,
        t.max_score,
        t.task_order,
        COALESCE(
            (
                ARRAY_AGG(DISTINCT tg.name)
                    FILTER (WHERE tg.id IS NOT NULL)
            )::TEXT[],
            ARRAY[]::TEXT[]
        ) AS tags
    FROM tasks t
    LEFT JOIN task_tags tt ON tt.task_id = t.id
    LEFT JOIN tags tg ON tg.id = tt.tag_id
    WHERE
        (
            p_query IS NULL
            OR TRIM(p_query) = ''
            OR to_tsvector(
                'simple',
                COALESCE(t.title, '') || ' ' || COALESCE(t.description, '')
            ) @@ websearch_to_tsquery('simple', p_query)
        )
        AND (
            p_contest_id IS NULL
            OR t.contest_id = p_contest_id
        )
        AND (
            p_tags IS NULL
            OR CARDINALITY(p_tags) = 0
            OR NOT EXISTS (
                SELECT 1
                FROM UNNEST(p_tags) requested_tag
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM task_tags requested_tt
                    JOIN tags requested_tg
                      ON requested_tg.id = requested_tt.tag_id
                    WHERE requested_tt.task_id = t.id
                      AND requested_tg.normalized_name =
                          LOWER(TRIM(requested_tag))
                )
            )
        )
    GROUP BY
        t.id,
        t.contest_id,
        t.title,
        t.description,
        t.max_score,
        t.task_order
    ORDER BY t.contest_id, t.task_order, t.id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 7. Enrollment Functions
-- ============================================================

-- H. Enroll in Contest
--    Checks (all database-native, in this order):
--      1. Already enrolled → silent no-op (idempotent).
--      2. Contest existence.
--      3. Contest is PENDING_APPROVAL → blocked.
--      4. Late enrollment disabled and contest already started → blocked.
--      5. User was previously kicked (ban check via kick_log) → blocked.
--      6. Invitation code validation.
--      7. Enrollment cap: uses FOR UPDATE lock on contests row to prevent race conditions.
CREATE OR REPLACE FUNCTION enroll_in_contest(
    p_contest_id INT,
    p_user_id INT,
    p_code VARCHAR DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
    v_expected_code         VARCHAR;
    v_status                VARCHAR;
    v_is_enrolled           BOOLEAN;
    v_is_banned             BOOLEAN;
    v_max_participants      INT;
    v_allow_late            BOOLEAN;
    v_start_time            TIMESTAMP WITH TIME ZONE;
    v_current_participants  INT;
BEGIN
    -- 1. Check if already enrolled (idempotent)
    SELECT EXISTS(
        SELECT 1 FROM enrollments
        WHERE contest_id = p_contest_id AND user_id = p_user_id
    ) INTO v_is_enrolled;

    IF v_is_enrolled THEN
        RETURN;
    END IF;

    -- 2. Lock the contest row to prevent concurrent enrollment races, and fetch settings
    SELECT status, invitation_code, max_participants, allow_late_enrollment, start_time
      INTO v_status, v_expected_code, v_max_participants, v_allow_late, v_start_time
    FROM contests
    WHERE id = p_contest_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contest not found';
    END IF;

    -- 3. Block enrollment in unapproved contests
    IF v_status = 'PENDING_APPROVAL' THEN
        RAISE EXCEPTION 'This contest is pending developer approval';
    END IF;

    -- 4. Block late enrollment if disabled and contest has already started
    IF NOT v_allow_late AND NOW() > v_start_time THEN
        RAISE EXCEPTION 'Late enrollment is disabled for this contest — it has already started';
    END IF;

    -- 5. Ban check: if the user was previously kicked, they cannot re-enroll
    SELECT EXISTS(
        SELECT 1 FROM kick_log
        WHERE contest_id = p_contest_id AND kicked_user_id = p_user_id
    ) INTO v_is_banned;

    IF v_is_banned THEN
        RAISE EXCEPTION 'You have been removed from this contest and cannot re-enroll';
    END IF;

    -- 6. Validate invitation code if one is set on the contest
    IF v_expected_code IS NOT NULL AND v_expected_code <> '' THEN
        IF p_code IS NULL OR p_code <> v_expected_code THEN
            RAISE EXCEPTION 'Invalid invitation code';
        END IF;
    END IF;

    -- 7. Capacity check (only if max_participants is set)
    IF v_max_participants IS NOT NULL THEN
        SELECT COUNT(*)::INT INTO v_current_participants
        FROM enrollments
        WHERE contest_id = p_contest_id AND role = 'PARTICIPANT';

        IF v_current_participants >= v_max_participants THEN
            RAISE EXCEPTION 'This contest is full (% / % participants)', v_current_participants, v_max_participants;
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

-- ============================================================
-- 8. Submission Validation Functions (DB-Native Schema & Cooldown)
-- ============================================================

-- J. Validate Submission Schema (Hard-Reject)
--    Called before inserting any submission into the queue.
--    Fetches the task's submission_schema JSONB and validates p_submission_data against it.
--
--    Schema format supported:
--      {
--        "required_keys": ["key1", "key2"],   -- all these keys must be present in submission_data
--        "numeric_keys": ["key1"]              -- these keys must be JSON number type
--      }
--
--    Raises EXCEPTION (HTTP 400 from API layer) on any validation failure.
--    No-op if task has no schema (NULL) — backward compatible with task-less submissions.
CREATE OR REPLACE FUNCTION validate_submission_schema_native(
    p_task_id INT,
    p_submission_data JSONB
) RETURNS VOID AS $$
DECLARE
    v_schema        JSONB;
    v_required_keys TEXT[];
    v_numeric_keys  TEXT[];
    v_key           TEXT;
BEGIN
    -- Fetch the task's submission schema
    SELECT submission_schema INTO v_schema
    FROM tasks
    WHERE id = p_task_id;

    -- If schema is NULL, no validation needed (e.g. task was created before this feature)
    IF v_schema IS NULL THEN
        RETURN;
    END IF;

    -- Extract required_keys array from schema
    IF v_schema ? 'required_keys' THEN
        SELECT ARRAY(
            SELECT jsonb_array_elements_text(v_schema -> 'required_keys')
        ) INTO v_required_keys;

        FOREACH v_key IN ARRAY v_required_keys LOOP
            IF NOT (p_submission_data ? v_key) THEN
                RAISE EXCEPTION 'Submission schema validation failed: missing required key "%"', v_key;
            END IF;
        END LOOP;
    END IF;

    -- Extract numeric_keys array from schema and verify JSON type
    IF v_schema ? 'numeric_keys' THEN
        SELECT ARRAY(
            SELECT jsonb_array_elements_text(v_schema -> 'numeric_keys')
        ) INTO v_numeric_keys;

        FOREACH v_key IN ARRAY v_numeric_keys LOOP
            IF NOT (p_submission_data ? v_key) THEN
                RAISE EXCEPTION 'Submission schema validation failed: numeric key "%" is missing', v_key;
            END IF;
            IF jsonb_typeof(p_submission_data -> v_key) <> 'number' THEN
                RAISE EXCEPTION 'Submission schema validation failed: key "%" must be a number, got "%"',
                    v_key, jsonb_typeof(p_submission_data -> v_key);
            END IF;
        END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- K. Check Submission Cooldown (DB-Native Rate Limiting)
--    Only enforced if the task's submission_cooldown_seconds > 0.
--    Queries the user's most recent submission to this task and checks elapsed time.
--    Raises EXCEPTION with seconds remaining if the cooldown has not expired.
CREATE OR REPLACE FUNCTION check_submission_cooldown_native(
    p_task_id INT,
    p_user_id INT
) RETURNS VOID AS $$
DECLARE
    v_cooldown      INT;
    v_last_sub_at   TIMESTAMP WITH TIME ZONE;
    v_elapsed_secs  NUMERIC;
    v_remaining     NUMERIC;
BEGIN
    -- Fetch the cooldown setting for this task
    SELECT submission_cooldown_seconds INTO v_cooldown
    FROM tasks
    WHERE id = p_task_id;

    -- If cooldown is 0 or not set, no rate limiting needed
    IF v_cooldown IS NULL OR v_cooldown = 0 THEN
        RETURN;
    END IF;

    -- Find the most recent submission by this user to this task
    SELECT MAX(submitted_at) INTO v_last_sub_at
    FROM submissions
    WHERE task_id = p_task_id AND user_id = p_user_id;

    -- If no previous submission, cooldown is not applicable
    IF v_last_sub_at IS NULL THEN
        RETURN;
    END IF;

    v_elapsed_secs := EXTRACT(EPOCH FROM (NOW() - v_last_sub_at));

    IF v_elapsed_secs < v_cooldown THEN
        v_remaining := CEIL(v_cooldown - v_elapsed_secs);
        RAISE EXCEPTION 'Submission cooldown active: please wait % more second(s) before submitting to this task again', v_remaining::INT;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- L. Submit Entry Atomically
--    Performs all validation and inserts the submission in one transaction.
CREATE OR REPLACE FUNCTION submit_entry_native(
    p_contest_id INT,
    p_user_id INT,
    p_task_id INT,
    p_submission_data JSONB
)
RETURNS TABLE (
    submission_id INT,
    submitted_at TIMESTAMP WITH TIME ZONE
) AS $$
DECLARE
    v_contest_status VARCHAR;
    v_start_time TIMESTAMP WITH TIME ZONE;
    v_end_time TIMESTAMP WITH TIME ZONE;
    v_submission_id INT;
    v_submitted_at TIMESTAMP WITH TIME ZONE;
BEGIN
    IF p_submission_data IS NULL
       OR jsonb_typeof(p_submission_data) <> 'object' THEN
        RAISE EXCEPTION 'Submission data must be a JSON object';
    END IF;

    -- Score and verdict are trusted worker outputs.
    IF p_submission_data ?| ARRAY['score', 'verdict'] THEN
        RAISE EXCEPTION
            'Submission data cannot contain trusted result fields: score or verdict';
    END IF;

    SELECT status, start_time, end_time
    INTO v_contest_status, v_start_time, v_end_time
    FROM contests
    WHERE id = p_contest_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contest not found';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM enrollments
        WHERE contest_id = p_contest_id
          AND user_id = p_user_id
    ) THEN
        RAISE EXCEPTION
            'User is not enrolled in contest %',
            p_contest_id;
    END IF;

    IF v_contest_status <> 'ACTIVE' THEN
        RAISE EXCEPTION
            'Submissions are only allowed for ACTIVE contests';
    END IF;

    IF CURRENT_TIMESTAMP < v_start_time THEN
        RAISE EXCEPTION
            'Submissions are not allowed yet. The contest has not started';
    END IF;

    IF CURRENT_TIMESTAMP > v_end_time THEN
        RAISE EXCEPTION
            'Submissions are closed. The contest has ended';
    END IF;

    IF p_task_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM tasks
            WHERE id = p_task_id
              AND contest_id = p_contest_id
        ) THEN
            RAISE EXCEPTION
                'Task % does not belong to contest %',
                p_task_id,
                p_contest_id;
        END IF;

        -- Prevent concurrent requests from bypassing the cooldown.
        PERFORM pg_advisory_xact_lock(p_user_id, p_task_id);

        PERFORM check_submission_cooldown_native(
            p_task_id,
            p_user_id
        );

        PERFORM validate_submission_schema_native(
            p_task_id,
            p_submission_data
        );
    END IF;

    INSERT INTO submissions (
        contest_id,
        user_id,
        task_id,
        submission_data,
        status
    )
    VALUES (
        p_contest_id,
        p_user_id,
        p_task_id,
        p_submission_data,
        'PENDING'
    )
    RETURNING id, submissions.submitted_at
    INTO v_submission_id, v_submitted_at;

    RETURN QUERY
    SELECT v_submission_id, v_submitted_at;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 9. Participant Kick & Ban Functions
-- ============================================================

-- L. Kick Participant (HOST only)
--    Removes the participant from enrollments and records the action in kick_log.
--    The kicked user cannot re-enroll (enforced by enroll_in_contest ban check).
--    The participant's submission history is preserved for record integrity.
CREATE OR REPLACE FUNCTION kick_participant_native(
    p_contest_id           INT,
    p_requesting_user_id   INT,
    p_target_user_id       INT,
    p_reason               TEXT DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
    v_req_role      VARCHAR;
    v_target_role   VARCHAR;
BEGIN
    -- Only HOST can kick participants
    SELECT role INTO v_req_role
    FROM enrollments
    WHERE contest_id = p_contest_id AND user_id = p_requesting_user_id;

    IF v_req_role IS NULL OR v_req_role <> 'HOST' THEN
        RAISE EXCEPTION 'Unauthorized: Only the Host can remove participants';
    END IF;

    -- Verify the target is enrolled
    SELECT role INTO v_target_role
    FROM enrollments
    WHERE contest_id = p_contest_id AND user_id = p_target_user_id;

    IF v_target_role IS NULL THEN
        RAISE EXCEPTION 'Target user is not enrolled in this contest';
    END IF;

    -- A HOST cannot kick themselves
    IF p_target_user_id = p_requesting_user_id THEN
        RAISE EXCEPTION 'A Host cannot remove themselves from the contest';
    END IF;

    -- Another HOST cannot be kicked (only MODERATOR or PARTICIPANT)
    IF v_target_role = 'HOST' THEN
        RAISE EXCEPTION 'Cannot remove another Host from the contest';
    END IF;

    -- Record the kick in the audit log (acts as permanent ban for this contest)
    INSERT INTO kick_log (contest_id, kicked_user_id, kicked_by, reason)
    VALUES (p_contest_id, p_target_user_id, p_requesting_user_id, p_reason);

    -- Remove the enrollment
    DELETE FROM enrollments
    WHERE contest_id = p_contest_id AND user_id = p_target_user_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 10. Contest Visibility Functions
-- ============================================================

-- M. Update Contest Visibility Settings (HOST or MODERATOR)
--    Allows fine-grained control over what public viewers can see on the contest page.
CREATE OR REPLACE FUNCTION update_contest_visibility(
    p_contest_id            INT,
    p_user_id               INT,
    p_show_participant_count BOOLEAN,
    p_show_leaderboard       BOOLEAN,
    p_show_member_list       BOOLEAN,
    p_show_task_list         BOOLEAN,
    p_show_statistics        BOOLEAN,
    p_show_submission_count  BOOLEAN
) RETURNS VOID AS $$
DECLARE
    v_role VARCHAR;
BEGIN
    SELECT role INTO v_role
    FROM enrollments
    WHERE contest_id = p_contest_id AND user_id = p_user_id;

    IF v_role IS NULL OR v_role NOT IN ('HOST', 'MODERATOR') THEN
        RAISE EXCEPTION 'Unauthorized: Only Host or Moderator can update visibility settings';
    END IF;

    INSERT INTO contest_visibility (
        contest_id, show_participant_count, show_leaderboard,
        show_member_list, show_task_list, show_statistics,
        show_submission_count, updated_at
    )
    VALUES (
        p_contest_id, p_show_participant_count, p_show_leaderboard,
        p_show_member_list, p_show_task_list, p_show_statistics,
        p_show_submission_count, NOW()
    )
    ON CONFLICT (contest_id) DO UPDATE SET
        show_participant_count = EXCLUDED.show_participant_count,
        show_leaderboard       = EXCLUDED.show_leaderboard,
        show_member_list       = EXCLUDED.show_member_list,
        show_task_list         = EXCLUDED.show_task_list,
        show_statistics        = EXCLUDED.show_statistics,
        show_submission_count  = EXCLUDED.show_submission_count,
        updated_at             = NOW();
END;
$$ LANGUAGE plpgsql;

-- N. Get Contest Visibility Settings
CREATE OR REPLACE FUNCTION get_contest_visibility(p_contest_id INT)
RETURNS TABLE (
    show_participant_count  BOOLEAN,
    show_leaderboard        BOOLEAN,
    show_member_list        BOOLEAN,
    show_task_list          BOOLEAN,
    show_statistics         BOOLEAN,
    show_submission_count   BOOLEAN,
    updated_at              TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        cv.show_participant_count,
        cv.show_leaderboard,
        cv.show_member_list,
        cv.show_task_list,
        cv.show_statistics,
        cv.show_submission_count,
        cv.updated_at
    FROM contest_visibility cv
    WHERE cv.contest_id = p_contest_id;

    -- If no visibility row exists yet (e.g. created before this feature), return defaults
    IF NOT FOUND THEN
        RETURN QUERY SELECT TRUE, TRUE, FALSE, TRUE, FALSE, FALSE, NULL::TIMESTAMP WITH TIME ZONE;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 11. Contest Enrollment Info Function
-- ============================================================

-- O. Get Contest Enrollment Info
--    Returns enrollment capacity, current participant count, remaining spots, and ban count.
--    Used by the API to expose contest capacity status to the frontend.
CREATE OR REPLACE FUNCTION get_contest_enrollment_info(p_contest_id INT)
RETURNS TABLE (
    max_participants        INT,
    current_participants    INT,
    spots_remaining         INT,
    allow_late_enrollment   BOOLEAN,
    total_kicked            INT
) AS $$
DECLARE
    v_max INT;
    v_allow_late BOOLEAN;
    v_current INT;
    v_kicked INT;
BEGIN
    SELECT c.max_participants, c.allow_late_enrollment
      INTO v_max, v_allow_late
    FROM contests c
    WHERE c.id = p_contest_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contest with ID % not found', p_contest_id;
    END IF;

    SELECT COUNT(*)::INT INTO v_current
    FROM enrollments
    WHERE contest_id = p_contest_id AND role = 'PARTICIPANT';

    SELECT COUNT(*)::INT INTO v_kicked
    FROM kick_log
    WHERE contest_id = p_contest_id;

    RETURN QUERY SELECT
        v_max,
        v_current,
        CASE WHEN v_max IS NULL THEN NULL ELSE GREATEST(0, v_max - v_current) END,
        v_allow_late,
        v_kicked;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 12. Contest Announcements Functions
-- ============================================================

-- P. Post Announcement (HOST or MODERATOR)
CREATE OR REPLACE FUNCTION post_announcement_native(
    p_contest_id    INT,
    p_author_id     INT,
    p_title         VARCHAR,
    p_body          TEXT
) RETURNS INT AS $$
DECLARE
    v_role          VARCHAR;
    v_ann_id        INT;
BEGIN
    SELECT role INTO v_role
    FROM enrollments
    WHERE contest_id = p_contest_id AND user_id = p_author_id;

    IF v_role IS NULL OR v_role NOT IN ('HOST', 'MODERATOR') THEN
        RAISE EXCEPTION 'Unauthorized: Only Host or Moderator can post announcements';
    END IF;

    INSERT INTO contest_announcements (contest_id, author_id, title, body)
    VALUES (p_contest_id, p_author_id, p_title, p_body)
    RETURNING id INTO v_ann_id;

    RETURN v_ann_id;
END;
$$ LANGUAGE plpgsql;

-- Q. Delete Announcement (HOST or MODERATOR of the same contest)
CREATE OR REPLACE FUNCTION delete_announcement_native(
    p_announcement_id   INT,
    p_user_id           INT
) RETURNS VOID AS $$
DECLARE
    v_contest_id    INT;
    v_role          VARCHAR;
BEGIN
    SELECT contest_id INTO v_contest_id
    FROM contest_announcements
    WHERE id = p_announcement_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Announcement not found';
    END IF;

    SELECT role INTO v_role
    FROM enrollments
    WHERE contest_id = v_contest_id AND user_id = p_user_id;

    IF v_role IS NULL OR v_role NOT IN ('HOST', 'MODERATOR') THEN
        RAISE EXCEPTION 'Unauthorized: Only Host or Moderator can delete announcements';
    END IF;

    DELETE FROM contest_announcements WHERE id = p_announcement_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 13. Contest Profile Aggregator
-- ============================================================

-- R. Get Contest Profile
--    Returns a full profile snapshot for a contest including metadata, capacity info,
--    visibility config, announcement count, and whether the viewer is enrolled.
--    This is the "single query" profile endpoint — all aggregation happens in the DB.
CREATE OR REPLACE FUNCTION get_contest_profile(
    p_contest_id        INT,
    p_viewer_user_id    INT DEFAULT NULL
) RETURNS TABLE (
    contest_id              INT,
    title                   VARCHAR,
    ranking_strategy        VARCHAR,
    start_time              TIMESTAMP WITH TIME ZONE,
    freeze_time             TIMESTAMP WITH TIME ZONE,
    end_time                TIMESTAMP WITH TIME ZONE,
    status                  VARCHAR,
    judging_description     TEXT,
    invitation_code         VARCHAR,
    max_participants        INT,
    allow_late_enrollment   BOOLEAN,
    current_participants    INT,
    spots_remaining         INT,
    total_kicked            INT,
    task_count              INT,
    announcement_count      INT,
    latest_announcement_title VARCHAR,
    show_participant_count  BOOLEAN,
    show_leaderboard        BOOLEAN,
    show_member_list        BOOLEAN,
    show_task_list          BOOLEAN,
    show_statistics         BOOLEAN,
    show_submission_count   BOOLEAN,
    viewer_role             VARCHAR,
    viewer_is_enrolled      BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    WITH enroll_info AS (
        SELECT
            e.contest_id,
            COUNT(*) FILTER (WHERE e.role = 'PARTICIPANT')::INT AS participant_count
        FROM enrollments e
        WHERE e.contest_id = p_contest_id
        GROUP BY e.contest_id
    ),
    kick_info AS (
        SELECT COUNT(*)::INT AS kicked_count
        FROM kick_log
        WHERE contest_id = p_contest_id
    ),
    task_info AS (
        SELECT COUNT(*)::INT AS task_count
        FROM tasks
        WHERE contest_id = p_contest_id
    ),
    ann_info AS (
        SELECT
            COUNT(*)::INT AS ann_count,
            (SELECT ca2.title FROM contest_announcements ca2
             WHERE ca2.contest_id = p_contest_id
             ORDER BY ca2.posted_at DESC LIMIT 1) AS latest_title
        FROM contest_announcements ca
        WHERE ca.contest_id = p_contest_id
    ),
    viewer_info AS (
        SELECT e.role AS v_role
        FROM enrollments e
        WHERE e.contest_id = p_contest_id AND e.user_id = p_viewer_user_id
    )
    SELECT
        c.id,
        c.title,
        c.ranking_strategy,
        c.start_time,
        c.freeze_time,
        c.end_time,
        c.status,
        c.judging_description,
        CASE WHEN COALESCE(vi.v_role, '') IN ('HOST', 'MODERATOR') THEN c.invitation_code ELSE NULL END,
        c.max_participants,
        c.allow_late_enrollment,
        COALESCE(ei.participant_count, 0),
        CASE WHEN c.max_participants IS NULL THEN NULL
             ELSE GREATEST(0, c.max_participants - COALESCE(ei.participant_count, 0)) END,
        COALESCE(ki.kicked_count, 0),
        COALESCE(ti.task_count, 0),
        COALESCE(ai.ann_count, 0),
        ai.latest_title,
        COALESCE(cv.show_participant_count, TRUE),
        COALESCE(cv.show_leaderboard, TRUE),
        COALESCE(cv.show_member_list, FALSE),
        COALESCE(cv.show_task_list, TRUE),
        COALESCE(cv.show_statistics, FALSE),
        COALESCE(cv.show_submission_count, FALSE),
        vi.v_role,
        (vi.v_role IS NOT NULL)
    FROM contests c
    LEFT JOIN enroll_info ei       ON TRUE
    LEFT JOIN kick_info ki         ON TRUE
    LEFT JOIN task_info ti         ON TRUE
    LEFT JOIN ann_info ai          ON TRUE
    LEFT JOIN contest_visibility cv ON cv.contest_id = c.id
    LEFT JOIN viewer_info vi       ON TRUE
    WHERE c.id = p_contest_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 14. User Profile & Statistics Functions (Unchanged from v0.4.0)
-- ============================================================

-- S. Fetch User Profile Statistics
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
    SELECT COUNT(*)::INT INTO v_total_subs FROM submissions WHERE user_id = p_user_id;
    SELECT COUNT(DISTINCT contest_id)::INT INTO v_total_contests FROM enrollments WHERE user_id = p_user_id;
    SELECT COUNT(DISTINCT task_id)::INT INTO v_tasks_attempted FROM submissions WHERE user_id = p_user_id AND task_id IS NOT NULL;

    SELECT COUNT(DISTINCT s.task_id)::INT INTO v_completed_tasks
    FROM submissions s
    JOIN tasks t ON s.task_id = t.id
    WHERE s.user_id = p_user_id AND s.score >= t.max_score AND s.status = 'COMPLETED';

    SELECT COALESCE(AVG(score), 0)::NUMERIC(10,2) INTO v_avg_score FROM submissions WHERE user_id = p_user_id AND status = 'COMPLETED';
    SELECT COALESCE(MAX(score), 0)::NUMERIC(10,2) INTO v_max_score FROM submissions WHERE user_id = p_user_id AND status = 'COMPLETED';

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

-- T. Fetch User Activity Graph (Submissions Count by Date)
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

-- U. Fetch User Contest Participation History
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
        -- NOTE: Pass NULL as viewer_id so leaderboard uses public/frozen visibility for all
        -- history calls. Passing TRUE here was a bug — PostgreSQL casts TRUE to int 1,
        -- which would accidentally grant admin-level (live) leaderboard access to every
        -- contest history lookup by making the function think user ID 1 is always the viewer.
        -- Closes #15 (privilege escalation via type coercion in get_user_contest_history).
        CROSS JOIN LATERAL get_leaderboard(ec.contest_id, NULL) l
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

-- V. Fetch User Submission History
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

-- W. Fetch Contest-Wide Statistics
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

    SELECT COUNT(*)::INT INTO v_total_parts
    FROM enrollments
    WHERE contest_id = p_contest_id AND role = 'PARTICIPANT';

    SELECT COUNT(DISTINCT user_id)::INT INTO v_active_parts
    FROM submissions
    WHERE contest_id = p_contest_id
      AND submitted_at >= v_start_time
      AND submitted_at < v_effective_freeze;

    SELECT COUNT(*)::INT INTO v_total_subs
    FROM submissions
    WHERE contest_id = p_contest_id
      AND submitted_at >= v_start_time
      AND submitted_at < v_effective_freeze;

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
        ORDER BY t.task_order ASC, t.id ASC
    ) t_row;

    RETURN QUERY SELECT v_total_parts, v_active_parts, v_total_subs, v_task_stats;
END;
$$ LANGUAGE plpgsql;

-- X. Fetch Contest Submission Timeline Chart Data
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

-- Y. Fetch Participant Score Cumulative Progression
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
        ELSE -- 'SUM' strategy
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

-- ============================================================
-- Function to Search Users Natively
-- ============================================================
CREATE OR REPLACE FUNCTION search_users_native(p_query VARCHAR)
RETURNS TABLE (
    id INT,
    username VARCHAR,
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT u.id, u.username, u.created_at
    FROM users u
    WHERE u.username ILIKE '%' || p_query || '%'
    ORDER BY u.username ASC
    LIMIT 50;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Function to Search & Filter Contests Natively
-- ============================================================
CREATE OR REPLACE FUNCTION search_contests_native(
    p_viewer_id INT,
    p_query VARCHAR DEFAULT NULL,
    p_status VARCHAR DEFAULT NULL,
    p_strategy VARCHAR DEFAULT NULL,
    p_timeline VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    id INT,
    title VARCHAR,
    ranking_strategy VARCHAR,
    start_time TIMESTAMP WITH TIME ZONE,
    freeze_time TIMESTAMP WITH TIME ZONE,
    end_time TIMESTAMP WITH TIME ZONE,
    status VARCHAR,
    judging_description TEXT,
    invitation_code VARCHAR,
    user_role VARCHAR,
    max_participants INT,
    allow_late_enrollment BOOLEAN,
    show_participant_count BOOLEAN,
    show_leaderboard BOOLEAN,
    show_member_list BOOLEAN,
    show_task_list BOOLEAN,
    show_statistics BOOLEAN,
    show_submission_count BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT c.id, c.title, c.ranking_strategy, c.start_time, c.freeze_time, c.end_time,
           c.status, c.judging_description, c.invitation_code, e.role::VARCHAR AS user_role,
           c.max_participants, c.allow_late_enrollment,
           cv.show_participant_count, cv.show_leaderboard, cv.show_member_list,
           cv.show_task_list, cv.show_statistics, cv.show_submission_count
    FROM contests c
    LEFT JOIN enrollments e ON c.id = e.contest_id AND e.user_id = p_viewer_id
    LEFT JOIN contest_visibility cv ON c.id = cv.contest_id
    WHERE 
        (p_query IS NULL OR p_query = '' OR c.title ILIKE '%' || p_query || '%')
        AND (p_status IS NULL OR p_status = '' OR c.status = p_status)
        AND (p_strategy IS NULL OR p_strategy = '' OR c.ranking_strategy = p_strategy)
        AND (
            p_timeline IS NULL OR p_timeline = '' 
            OR (p_timeline = 'UPCOMING' AND c.start_time > CURRENT_TIMESTAMP)
            OR (p_timeline = 'ONGOING' AND c.start_time <= CURRENT_TIMESTAMP AND c.end_time >= CURRENT_TIMESTAMP)
            OR (p_timeline = 'COMPLETED' AND c.end_time < CURRENT_TIMESTAMP)
        )
    ORDER BY c.id DESC;
END;
$$ LANGUAGE plpgsql;
