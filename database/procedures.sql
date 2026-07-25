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
    -- 1. If admin is viewing -> see everything (up to contest end_time)
    -- 2. If contest is completed -> see everything (up to contest end_time)
    -- 3. If contest is ongoing and past freeze time -> hide submissions made after freeze_time
    -- 4. If contest is ongoing and before freeze time -> see everything up to current time (which is < freeze_time)
    IF p_as_admin OR NOW() >= v_end_time THEN
        v_effective_freeze := v_end_time;
    ELSE
        v_effective_freeze := v_freeze_time;
    END IF;

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
END;
$$ LANGUAGE plpgsql;
