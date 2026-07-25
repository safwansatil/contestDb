import logging
from pathlib import Path
from typing import Dict, Any
from fastapi import FastAPI, HTTPException, Query, status
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from .database import pool, get_db_connection

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("backend")

app = FastAPI(title="ContestDB API Gateway", description="Thin-tier API gateway for ContestDB")

@app.get("/")
async def get_index():
    """
    Serve the barebones skeleton dashboard UI.
    """
    return FileResponse(Path(__file__).resolve().parent / "static" / "index.html")

# Pydantic Schemas for validation
class SubmissionRequest(BaseModel):
    contest_id: int = Field(..., description="ID of the contest")
    user_id: int = Field(..., description="ID of the user submitting")
    submission_data: Dict[str, Any] = Field(..., description="Arbitrary JSONB data representing the submission details")

# Lifecycle Event Handlers
@app.on_event("startup")
async def startup():
    logger.info("Opening database connection pool...")
    await pool.open()

@app.on_event("shutdown")
async def shutdown():
    logger.info("Closing database connection pool...")
    await pool.close()

# API Endpoints
@app.post("/submissions", status_code=status.HTTP_201_CREATED)
async def create_submission(payload: SubmissionRequest):
    """
    Ingest a new submission. Inserts it in PENDING state into the queue.
    Natively validates enrollment in the database before accepting.
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            # 1. Database-native check: Verify the user is enrolled in this contest
            await cur.execute(
                "SELECT 1 FROM enrollments WHERE contest_id = %s AND user_id = %s",
                (payload.contest_id, payload.user_id)
            )
            enrolled = await cur.fetchone()
            if not enrolled:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"User {payload.user_id} is not enrolled in contest {payload.contest_id}"
                )

            # 2. Ingest the submission into the PostgreSQL queue
            import json
            submission_json = json.dumps(payload.submission_data)
            
            await cur.execute(
                """
                INSERT INTO submissions (contest_id, user_id, submission_data, status)
                VALUES (%s, %s, %s::jsonb, 'PENDING')
                RETURNING id, submitted_at;
                """,
                (payload.contest_id, payload.user_id, submission_json)
            )
            row = await cur.fetchone()
            
            # Commit the transaction block
            await conn.commit()
            
            return {
                "message": "Submission successfully placed in queue",
                "submission_id": row[0],
                "submitted_at": row[1]
            }

@app.get("/contests/{contest_id}/leaderboard")
async def get_contest_leaderboard(
    contest_id: int, 
    as_admin: bool = Query(False, description="Set to true to view the full unfrozen standings")
):
    """
    Fetch the dynamic leaderboard. Honors scoreboard freeze rules if not viewed as admin.
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                # Query the stored procedure
                await cur.execute(
                    "SELECT user_id, username, total_score, rank FROM get_leaderboard(%s, %s)",
                    (contest_id, as_admin)
                )
                rows = await cur.fetchall()
                
                leaderboard = []
                for row in rows:
                    leaderboard.append({
                        "user_id": row[0],
                        "username": row[1],
                        "total_score": float(row[2]) if row[2] is not None else 0.0,
                        "rank": row[3]
                    })
                return {
                    "contest_id": contest_id,
                    "view_mode": "admin" if as_admin else "public",
                    "leaderboard": leaderboard
                }
            except Exception as e:
                # If the contest doesn't exist, get_leaderboard raises an exception
                logger.error(f"Error fetching leaderboard: {e}")
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=str(e)
                )
