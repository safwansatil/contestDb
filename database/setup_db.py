import os
import sys
from pathlib import Path
from dotenv import load_dotenv
import psycopg

# 1. Resolve project root and load environment variables
BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

DATABASE_URL = os.getenv("MIGRATION_DATABASE_URL")
if not DATABASE_URL:
    print("Error: MIGRATION_DATABASE_URL not found in root '.env' file!")
    sys.exit(1)

# 2. Files to execute in order
SQL_FILES = [
    "database/init.sql",
    "database/procedures.sql",
    "database/seed.sql"
]

def run_migration():
    print(f"Connecting to Neon Database...")
    try:
        with psycopg.connect(DATABASE_URL) as conn:
            # Enable autocommit for transactional safety across DDL operations
            conn.autocommit = True
            
            with conn.cursor() as cur:
                for file_path in SQL_FILES:
                    full_path = BASE_DIR / file_path
                    if not full_path.exists():
                        print(f"Error: SQL file not found at {full_path}")
                        sys.exit(1)
                    
                    print(f"Executing {file_path}...")
                    with open(full_path, "r", encoding="utf-8") as f:
                        sql_content = f.read()
                    
                    # Execute the SQL scripts
                    cur.execute(sql_content)
                    print(f"Successfully executed {file_path}")
                    
        print("\nNeon database initialization and seeding completed successfully!")
        
    except Exception as e:
        print(f"\nDatabase setup failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    run_migration()
