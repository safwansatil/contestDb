-- ContestDB runtime permission groups.
-- These are NOLOGIN roles. Actual Neon login users are granted membership separately.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'contestdb_api') THEN
        CREATE ROLE contestdb_api NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'contestdb_worker') THEN
        CREATE ROLE contestdb_worker NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'contestdb_migration') THEN
        CREATE ROLE contestdb_migration NOLOGIN;
    END IF;
END
$$;

-- Remove implicit access.
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;

-- All application roles must be able to resolve objects in public.
GRANT USAGE ON SCHEMA public
TO contestdb_api, contestdb_worker, contestdb_migration;

-- ============================================================
-- API permissions
-- ============================================================

-- The current FastAPI implementation directly reads these tables.
GRANT SELECT ON
    users,
    contests,
    enrollments,
    tasks,
    submissions,
    contest_visibility,
    kick_log,
    contest_announcements
TO contestdb_api;

-- Existing functions execute with caller permissions, so the API needs
-- the corresponding DML rights used inside those functions.
-- Users are created through register_user().
GRANT INSERT ON users
TO contestdb_api;

-- Contest-management functions require these permissions.
GRANT INSERT, UPDATE, DELETE ON
    contests,
    enrollments,
    tasks,
    contest_visibility,
    kick_log,
    contest_announcements
TO contestdb_api;

-- The API may queue submissions, but it must never modify judge results.
GRANT INSERT ON submissions
TO contestdb_api;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public
TO contestdb_api;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public
TO contestdb_api;

-- Queue claiming belongs exclusively to workers.
REVOKE EXECUTE ON FUNCTION claim_submission(VARCHAR, INT, INT)
FROM contestdb_api;

-- ============================================================
-- Worker permissions
-- ============================================================

GRANT SELECT, UPDATE ON submissions
TO contestdb_worker;

GRANT EXECUTE ON FUNCTION claim_submission(VARCHAR, INT, INT)
TO contestdb_worker;

-- ============================================================
-- Migration permissions
-- ============================================================

GRANT ALL PRIVILEGES ON SCHEMA public
TO contestdb_migration;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public
TO contestdb_migration;

GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public
TO contestdb_migration;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public
TO contestdb_migration;

-- Apply equivalent privileges to objects created later by the role
-- executing this script.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL PRIVILEGES ON TABLES TO contestdb_migration;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL PRIVILEGES ON SEQUENCES TO contestdb_migration;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO contestdb_migration;




