import os
from pathlib import Path
from dotenv import load_dotenv
import psycopg

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    print("DATABASE_URL is not found!")
    exit(1)

def run_tests():
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            # 1. Test strategy filter
            cur.execute("SELECT id, title, ranking_strategy FROM search_contests_native(NULL, NULL, NULL, 'SUM', NULL);")
            print("SUM Strategy Contests:", cur.fetchall())
            
            # 2. Test search title filter
            cur.execute("SELECT id, title FROM search_contests_native(NULL, 'Math', NULL, NULL, NULL);")
            print("Title containing 'Math':", cur.fetchall())
            
            # 3. Test timeline ONGOING filter
            cur.execute("SELECT id, title, start_time, end_time FROM search_contests_native(NULL, NULL, NULL, NULL, 'ONGOING');")
            print("Ongoing Contests:", cur.fetchall())

if __name__ == "__main__":
    run_tests()
