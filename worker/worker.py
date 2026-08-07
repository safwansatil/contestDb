import os
import time
import json
import logging
from pathlib import Path
from dotenv import load_dotenv
import psycopg

# Resolve project root directory (two parents up from worker/worker.py)
BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

DATABASE_URL = os.getenv("WORKER_DATABASE_URL")
WORKER_ID = os.getenv("WORKER_ID", "worker-default")
LEASE_SECONDS = int(os.getenv("WORKER_LEASE_SECONDS", "60"))
MAX_ATTEMPTS = int(os.getenv("WORKER_MAX_ATTEMPTS", "3"))

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger("worker")

if not DATABASE_URL:
    logger.error("WORKER_DATABASE_URL is not set!")
    exit(1)

def evaluate_submission(payload: dict) -> tuple[float, str]:
    """
    Mock evaluation logic for a general contest platform.
    Processes submission_data and extracts a standardized score and verdict.
    """
    logger.info(f"Evaluating payload: {payload}")

    # Scores and verdicts are trusted outputs produced only by the worker.
    # Participants must never provide them in submission_data.
    forbidden_fields = {"score", "verdict"}
    supplied_forbidden_fields = forbidden_fields.intersection(payload)

    if supplied_forbidden_fields:
        logger.warning(
            "Rejected submission containing trusted fields: %s",
            sorted(supplied_forbidden_fields),
        )
        return 0.0, "INVALID_SUBMISSION"
    # Case 1: LFR (Line Follower Robot) run telemetry
    if "run_time_seconds" in payload:
        run_time = float(payload["run_time_seconds"])
        restarts = int(payload.get("restarts", 0))
        # Deduct 5 points per restart from a starting score of 100
        score = 100.0 - run_time - (restarts * 5.0)
        score = max(0.0, min(100.0, score)) # Clamp between 0 and 100
        verdict = "RUN_SUCCESS" if run_time < 90 else "TIME_LIMIT_EXCEEDED"
        return score, verdict

    # Case 2: Standard Code Run / ICPC
    elif "source_code" in payload:
        code = str(payload["source_code"])
        if len(code.strip()) == 0:
            return 0.0, "COMPILE_ERROR"
        # Dummy pass criteria
        if "print" in code or "cout" in code:
            return 10.0, "ACCEPTED"
        else:
            return 0.0, "WRONG_ANSWER"

    # Case 3: Default fallback
    else:
        return 50.0, "GENERIC_SUCCESS"

def main():
    logger.info(f"Starting ContestDB Mock Worker: {WORKER_ID}")
    
    while True:
        try:
            # Connect directly to Neon Database
            with psycopg.connect(DATABASE_URL) as conn:
                # Enable autocommit so locks are released immediately after each operation
                conn.autocommit = True
                
                with conn.cursor() as cur:
                    # Poll queue by calling the claim_submission stored procedure
                    cur.execute(
                        "SELECT * FROM claim_submission(%s, %s, %s);",
                        (WORKER_ID, LEASE_SECONDS, MAX_ATTEMPTS)
                    )
                    row = cur.fetchone()
                    
                    if row:
                        sub_id, contest_id, user_id, sub_data = row
                        logger.info(f"Locked submission #{sub_id} from contest #{contest_id} by user #{user_id}")
                        
                        try:
                            # Evaluate submission based on JSONB payload
                            score, verdict = evaluate_submission(sub_data)
                            
                            # Write standardized score and verdict back
                            cur.execute(
                                """
                                UPDATE submissions
                                SET status = 'COMPLETED',
                                    score = %s,
                                    verdict = %s,
                                    judged_at = CURRENT_TIMESTAMP,
                                    lease_expires_at = NULL,
                                    last_error = NULL
                                WHERE id = %s
                                  AND status = 'JUDGING'
                                  AND judged_by = %s
                                  AND lease_expires_at > CURRENT_TIMESTAMP;
                                """,
                                (score, verdict, sub_id, WORKER_ID),
                            )

                            logger.info(f"Successfully judged submission #{sub_id}. Result: Score={score}, Verdict={verdict}")
                        
                        except Exception as eval_err:
                            logger.error(
                                f"Error evaluating submission #{sub_id}: {eval_err}"
                            )

                            cur.execute(
                                """
                                UPDATE submissions
                                SET status = CASE
                                        WHEN attempt_count >= %s THEN 'FAILED'
                                        ELSE 'PENDING'
                                    END,
                                    judged_by = NULL,
                                    lease_expires_at = NULL,
                                    last_error = %s
                                WHERE id = %s
                                AND status = 'JUDGING'
                                AND judged_by = %s
                                AND lease_expires_at > CURRENT_TIMESTAMP;
                                """,
                                (
                                    MAX_ATTEMPTS,
                                    str(eval_err),
                                    sub_id,
                                    WORKER_ID,
                                ),
                            )
                        
                        # Process next item immediately without sleeping
                        continue
                        
            # If queue was empty, wait before polling again
            time.sleep(2)

        except psycopg.OperationalError as db_err:
            logger.error(f"Database connection error: {db_err}. Retrying in 5 seconds...")
            time.sleep(5)
        except Exception as e:
            logger.error(f"Unexpected worker error: {e}. Retrying in 5 seconds...")
            time.sleep(5)

if __name__ == "__main__":
    main()
