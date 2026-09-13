BEGIN;

ALTER TABLE contests
    ADD COLUMN IF NOT EXISTS
    max_moderators INT DEFAULT 0 NOT NULL;

ALTER TABLE contests
    DROP CONSTRAINT IF EXISTS chk_max_moderators;

ALTER TABLE contests
    ADD CONSTRAINT chk_max_moderators
    CHECK (max_moderators >= 0);

DROP FUNCTION IF EXISTS create_contest_native(
    VARCHAR,
    VARCHAR,
    TIMESTAMP WITH TIME ZONE,
    TIMESTAMP WITH TIME ZONE,
    TIMESTAMP WITH TIME ZONE,
    VARCHAR,
    TEXT,
    INT,
    INT,
    BOOLEAN
);

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
    p_max_moderators INT DEFAULT 0,
    p_allow_late_enrollment BOOLEAN DEFAULT TRUE
) RETURNS INT AS $$
DECLARE
    v_contest_id INT;
BEGIN
    IF p_max_moderators < 0 THEN
        RAISE EXCEPTION
            'Moderator capacity cannot be negative';
    END IF;

    INSERT INTO contests (
        title,
        ranking_strategy,
        start_time,
        freeze_time,
        end_time,
        invitation_code,
        judging_description,
        status,
        max_participants,
        max_moderators,
        allow_late_enrollment
    )
    VALUES (
        p_title,
        p_ranking_strategy,
        p_start_time,
        p_freeze_time,
        p_end_time,
        NULLIF(TRIM(p_invitation_code), ''),
        p_judging_description,
        'PENDING_APPROVAL',
        p_max_participants,
        p_max_moderators,
        p_allow_late_enrollment
    )
    RETURNING id INTO v_contest_id;

    INSERT INTO enrollments (
        contest_id,
        user_id,
        role
    )
    VALUES (
        v_contest_id,
        p_creator_id,
        'HOST'
    );

    INSERT INTO contest_visibility (contest_id)
    VALUES (v_contest_id);

    RETURN v_contest_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_contest_member_role(
    p_contest_id INT,
    p_requesting_user_id INT,
    p_target_user_id INT,
    p_new_role VARCHAR
) RETURNS VOID AS $$
DECLARE
    v_requesting_role VARCHAR;
    v_target_role VARCHAR;
    v_normalized_role VARCHAR;
    v_max_moderators INT;
    v_current_moderators INT;
BEGIN
    v_normalized_role := UPPER(TRIM(p_new_role));

    SELECT max_moderators
    INTO v_max_moderators
    FROM contests
    WHERE id = p_contest_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contest not found';
    END IF;

    SELECT role
    INTO v_requesting_role
    FROM enrollments
    WHERE contest_id = p_contest_id
      AND user_id = p_requesting_user_id;

    IF v_requesting_role IS DISTINCT FROM 'HOST' THEN
        RAISE EXCEPTION
            'Unauthorized: Only the Host can manage roles';
    END IF;

    IF p_requesting_user_id = p_target_user_id THEN
        RAISE EXCEPTION
            'The Host cannot change their own role';
    END IF;

    IF v_normalized_role NOT IN (
        'MODERATOR',
        'PARTICIPANT'
    ) THEN
        RAISE EXCEPTION
            'Role must be MODERATOR or PARTICIPANT';
    END IF;

    SELECT role
    INTO v_target_role
    FROM enrollments
    WHERE contest_id = p_contest_id
      AND user_id = p_target_user_id;

    IF v_target_role = 'HOST' THEN
        RAISE EXCEPTION
            'The contest creator role cannot be changed';
    END IF;

    IF v_normalized_role = 'MODERATOR'
       AND v_target_role IS DISTINCT FROM 'MODERATOR' THEN

        SELECT COUNT(*)::INT
        INTO v_current_moderators
        FROM enrollments
        WHERE contest_id = p_contest_id
          AND role = 'MODERATOR';

        IF v_current_moderators >= v_max_moderators THEN
            RAISE EXCEPTION
                'Moderator capacity reached (% / %)',
                v_current_moderators,
                v_max_moderators;
        END IF;
    END IF;

    INSERT INTO enrollments (
        contest_id,
        user_id,
        role
    )
    VALUES (
        p_contest_id,
        p_target_user_id,
        v_normalized_role
    )
    ON CONFLICT (contest_id, user_id)
    DO UPDATE SET role = EXCLUDED.role;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION create_contest_native(
    VARCHAR,
    VARCHAR,
    TIMESTAMP WITH TIME ZONE,
    TIMESTAMP WITH TIME ZONE,
    TIMESTAMP WITH TIME ZONE,
    VARCHAR,
    TEXT,
    INT,
    INT,
    INT,
    BOOLEAN
) TO contestdb_api;

GRANT EXECUTE ON FUNCTION update_contest_member_role(
    INT,
    INT,
    INT,
    VARCHAR
) TO contestdb_api;

COMMIT;