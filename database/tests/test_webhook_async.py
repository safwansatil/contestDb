import os
import sys
import psycopg
from datetime import datetime, timezone, timedelta
from pathlib import Path
from dotenv import load_dotenv

# Resolve project root
BASE_DIR = Path(__file__).resolve().parent.parent.parent
load_dotenv(BASE_DIR / ".env")

DATABASE_URL = os.getenv("MIGRATION_DATABASE_URL")
if not DATABASE_URL:
    print("MIGRATION_DATABASE_URL must be set in .env")
    sys.exit(1)

def run_test():
    print("Running Async Webhook Flow Test...")
    with psycopg.connect(DATABASE_URL) as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            # Setup dummy contest and task
            start_time = datetime.now(timezone.utc)
            freeze_time = start_time + timedelta(hours=1)
            end_time = start_time + timedelta(hours=2)
            
            timestamp_suffix = str(int(datetime.now().timestamp() * 1000))
            # Create a user to be the host
            cur.execute(
                "SELECT user_id FROM register_user(%s, %s);",
                (f"webhook_host_{timestamp_suffix}", "password123")
            )
            host_id = cur.fetchone()[0]
            
            # Create contest
            cur.execute(
                "SELECT create_contest_native(%s::varchar, %s::varchar, %s::timestamptz, %s::timestamptz, %s::timestamptz, %s::varchar, %s::text, %s::int, %s::int, %s::boolean);",
                ("Webhook Test Contest", "MAX", start_time, freeze_time, end_time, "joinme", "Desc", host_id, None, True)
            )
            contest_id = cur.fetchone()[0]
            
            # Approve contest
            cur.execute("SELECT approve_contest_native(%s);", (contest_id,))
            
            # Create task with webhook_url
            webhook_url = "http://localhost:8000/dummy-webhook"
            schema = '{"required_keys": ["data"], "numeric_keys": []}'
            cur.execute(
                "SELECT add_task_native(%s, %s, %s, %s, %s, %s::jsonb, %s, %s, %s);",
                (contest_id, host_id, "Webhook Task", "Desc", 100, schema, 0, 1, webhook_url)
            )
            task_id = cur.fetchone()[0]
            
            # Create a user to submit
            cur.execute(
                "SELECT user_id FROM register_user(%s, %s);",
                (f"webhook_participant_{timestamp_suffix}", "password123")
            )
            part_id = cur.fetchone()[0]
            
            cur.execute("INSERT INTO enrollments (contest_id, user_id, role) VALUES (%s, %s, 'PARTICIPANT')", (contest_id, part_id))
            
            # Submit
            submission_data = '{"data": "hello"}'
            cur.execute(
                "SELECT submission_id FROM submit_entry_native(%s, %s, %s, %s::jsonb);",
                (contest_id, part_id, task_id, submission_data)
            )
            sub_id = cur.fetchone()[0]
            print(f"-> Created Submission #{sub_id}")
            
            # Claim submission (simulate Worker)
            cur.execute("SELECT * FROM claim_submission('worker-1', 60, 3);")
            claimed = cur.fetchone()
            if not claimed:
                print("[FAIL] Could not claim submission")
                sys.exit(1)
            
            c_sub_id, c_contest, c_user, c_task_id, c_data, c_webhook, c_contest_type = claimed
            print(f"-> Claimed Submission for task #{c_task_id}. Webhook URL: {c_webhook}")
            
            if c_webhook != webhook_url:
                print(f"[FAIL] Expected webhook URL {webhook_url}, got {c_webhook}")
                sys.exit(1)

            if c_task_id != task_id:
                print(f"[FAIL] Expected task ID {task_id}, got {c_task_id}")
                sys.exit(1)
            
            # Verify status is JUDGING
            cur.execute("SELECT status FROM submissions WHERE id = %s;", (sub_id,))
            status = cur.fetchone()[0]
            if status != 'JUDGING':
                print(f"[FAIL] Expected status JUDGING, got {status}")
                sys.exit(1)
                
            # Simulate API Callback
            print("-> Simulating async webhook callback from external judge...")
            cur.execute(
                "SELECT update_submission_result_native(%s::int, %s::numeric, %s::varchar, %s::varchar);",
                (sub_id, 95.5, "AC", "judge0-external")
            )
            
            # Verify final state
            cur.execute("SELECT status, score, verdict, judged_by, lease_expires_at FROM submissions WHERE id = %s;", (sub_id,))
            final_status, score, verdict, judged_by, lease_expires_at = cur.fetchone()
            
            print(f"-> Final state: Status={final_status}, Score={score}, Verdict={verdict}")
            
            if final_status == 'COMPLETED' and float(score) == 95.5 and verdict == 'AC' and lease_expires_at is None:
                print("[PASS] Async webhook flow verified!")
            else:
                print("[FAIL] Submission state is incorrect.")
                sys.exit(1)

if __name__ == "__main__":
    run_test()
