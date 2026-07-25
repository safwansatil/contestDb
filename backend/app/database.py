import os
from contextlib import asynccontextmanager
from pathlib import Path
from dotenv import load_dotenv
from psycopg_pool import AsyncConnectionPool

# Resolve project root directory (three parents up from backend/app/database.py)
BASE_DIR = Path(__file__).resolve().parent.parent.parent
load_dotenv(BASE_DIR / ".env")

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise ValueError("DATABASE_URL environment variable is not set in the root '.env' file!")

# Initialize the asynchronous connection pool
# Note: min_size=1, max_size=10 is safe for Neon serverless limits
pool = AsyncConnectionPool(
    conninfo=DATABASE_URL,
    min_size=1,
    max_size=10,
    open=False, # Do not open immediately on import, wait for startup
)

@asynccontextmanager
async def get_db_connection():
    """
    Context manager to acquire a connection from the pool and return it.
    Ensures the connection is released back to the pool after use.
    """
    async with pool.connection() as conn:
        yield conn
