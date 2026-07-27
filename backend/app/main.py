import os
import sys
import asyncio
import logging
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime, timedelta, timezone
import json
import jwt

# Fix psycopg3 connection pool warning and error on Windows
if sys.platform == 'win32':
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

from fastapi import FastAPI, HTTPException, Query, status, Depends
from fastapi.responses import FileResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field, field_validator
from .database import pool, get_db_connection

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("backend")

app = FastAPI(title="ContestDB API Gateway", description="Thin-tier API gateway for ContestDB with Authentication")

# Auth Configuration
JWT_SECRET = os.getenv("JWT_SECRET", "contestdb_jwt_secret_key_change_me_in_production")
JWT_ALGORITHM = "HS256"
TOKEN_EXPIRE_MINUTES = 1440  # 24 Hours

security = HTTPBearer(auto_error=False)

def create_access_token(user_id: int, username: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=TOKEN_EXPIRE_MINUTES)
    to_encode = {
        "sub": str(user_id),
        "username": username,
        "exp": expire
    }
    return jwt.encode(to_encode, JWT_SECRET, algorithm=JWT_ALGORITHM)

async def get_current_user(credentials: Optional[HTTPAuthorizationCredentials] = Depends(security)) -> Dict[str, Any]:
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization credentials missing"
        )
    token = credentials.credentials
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        user_id = int(payload.get("sub"))
        username = payload.get("username")
        if not user_id or not username:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token payload"
            )
        return {"user_id": user_id, "username": username}
    except jwt.PyJWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Could not validate credentials: {str(e)}"
        )

async def get_optional_user(credentials: Optional[HTTPAuthorizationCredentials] = Depends(security)) -> Optional[Dict[str, Any]]:
    if not credentials:
        return None
    try:
        payload = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return {"user_id": int(payload.get("sub")), "username": payload.get("username")}
    except jwt.PyJWTError:
        return None

# Pydantic Schemas for validation
class AuthRequest(BaseModel):
    username: str = Field(..., min_length=3, max_length=50, description="Username (alphanumeric, underscores, hyphens)")
    password: str = Field(..., min_length=6, max_length=100, description="Password (min 6 characters)")

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str) -> str:
        import re
        if not re.match(r"^[a-zA-Z0-9_-]+$", v):
            raise ValueError("Username can only contain letters, numbers, underscores, and hyphens")
        return v

class SubmissionRequest(BaseModel):
    contest_id: int = Field(..., description="ID of the contest")
    task_id: Optional[int] = Field(None, description="ID of the task")
    user_id: Optional[int] = Field(None, description="Deprecated, user ID is resolved from authenticated token")
    submission_data: Dict[str, Any] = Field(..., description="Arbitrary JSONB data representing the submission details")

class ContestCreateRequest(BaseModel):
    title: str = Field(..., min_length=3, max_length=100)
    ranking_strategy: str = Field(..., max_length=30, description="Strategy, e.g., SUM, MAX, ICPC, or Custom")
    start_time: datetime
    freeze_time: datetime
    end_time: datetime
    invitation_code: Optional[str] = Field(None, max_length=50)
    judging_description: str = Field(..., min_length=5)

class TaskCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=100)
    description: str = Field(..., min_length=1)
    max_score: float = Field(100.0, ge=0.0)

class EnrollRequest(BaseModel):
    invitation_code: Optional[str] = None

class RoleUpdateRequest(BaseModel):
    target_user_id: int
    new_role: str

    @field_validator("new_role")
    @classmethod
    def validate_role(cls, v: str) -> str:
        if v not in ("HOST", "MODERATOR", "PARTICIPANT"):
            raise ValueError("Role must be HOST, MODERATOR, or PARTICIPANT")
        return v

# Lifecycle Event Handlers
@app.on_event("startup")
async def startup():
    logger.info("Opening database connection pool...")
    await pool.open()

@app.on_event("shutdown")
async def shutdown():
    logger.info("Closing database connection pool...")
    await pool.close()

# HTML Serving
@app.get("/")
async def get_index():
    """
    Serve the dashboard UI.
    """
    return FileResponse(Path(__file__).resolve().parent / "static" / "index.html")

# Authentication Endpoints
@app.post("/auth/signup", status_code=status.HTTP_201_CREATED)
async def signup(payload: AuthRequest):
    """
    Register a new user natively in the database.
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    "SELECT user_id, username, created_at FROM register_user(%s, %s)",
                    (payload.username.lower(), payload.password)
                )
                row = await cur.fetchone()
                if not row:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Registration failed"
                    )
                user_id, username, created_at = row
                await conn.commit()
                
                token = create_access_token(user_id, username)
                return {
                    "access_token": token,
                    "token_type": "bearer",
                    "user": {
                        "id": user_id,
                        "username": username,
                        "created_at": created_at
                    }
                }
            except Exception as e:
                await conn.rollback()
                logger.error(f"Signup error: {e}")
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Username already exists or registration failed"
                )

@app.post("/auth/login")
async def login(payload: AuthRequest):
    """
    Authenticate user natively in the database and return JWT.
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT user_id, username FROM verify_user_credentials(%s, %s)",
                (payload.username.lower(), payload.password)
            )
            row = await cur.fetchone()
            if not row:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid username or password"
                )
            
            user_id, username = row
            token = create_access_token(user_id, username)
            return {
                "access_token": token,
                "token_type": "bearer",
                "user": {
                    "id": user_id,
                    "username": username
                }
            }

@app.get("/auth/me")
async def get_me(current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    Verify access token and return user profile details.
    """
    return {
        "id": current_user["user_id"],
        "username": current_user["username"]
    }

# Contest Endpoints
@app.get("/contests")
async def get_contests(current_user: Optional[Dict[str, Any]] = Depends(get_optional_user)):
    """
    Fetch all contests. If authenticated, return the user's role.
    Only return invitation codes to HOST or MODERATOR users.
    """
    user_id = current_user["user_id"] if current_user else None
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT c.id, c.title, c.ranking_strategy, c.start_time, c.freeze_time, c.end_time, 
                       c.status, c.judging_description, c.invitation_code, e.role
                FROM contests c
                LEFT JOIN enrollments e ON c.id = e.contest_id AND e.user_id = %s
                ORDER BY c.id DESC;
                """,
                (user_id,)
            )
            rows = await cur.fetchall()
            contests = []
            for row in rows:
                c_id, title, ranking, start, freeze, end, status, judging_desc, inv_code, role = row
                has_code = inv_code is not None and inv_code != ""
                show_code = role in ("HOST", "MODERATOR")
                
                contests.append({
                    "id": c_id,
                    "title": title,
                    "ranking_strategy": ranking,
                    "start_time": start,
                    "freeze_time": freeze,
                    "end_time": end,
                    "status": status,
                    "judging_description": judging_desc,
                    "requires_invitation_code": has_code,
                    "invitation_code": inv_code if show_code else None,
                    "user_role": role
                })
            return contests

@app.get("/contests/{contest_id}")
async def get_contest(contest_id: int, current_user: Optional[Dict[str, Any]] = Depends(get_optional_user)):
    """
    Fetch single contest details.
    """
    user_id = current_user["user_id"] if current_user else None
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT c.id, c.title, c.ranking_strategy, c.start_time, c.freeze_time, c.end_time, 
                       c.status, c.judging_description, c.invitation_code, e.role
                FROM contests c
                LEFT JOIN enrollments e ON c.id = e.contest_id AND e.user_id = %s
                WHERE c.id = %s;
                """,
                (user_id, contest_id)
            )
            row = await cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Contest not found")
            
            c_id, title, ranking, start, freeze, end, status, judging_desc, inv_code, role = row
            has_code = inv_code is not None and inv_code != ""
            show_code = role in ("HOST", "MODERATOR")
            
            return {
                "id": c_id,
                "title": title,
                "ranking_strategy": ranking,
                "start_time": start,
                "freeze_time": freeze,
                "end_time": end,
                "status": status,
                "judging_description": judging_desc,
                "requires_invitation_code": has_code,
                "invitation_code": inv_code if show_code else None,
                "user_role": role
            }

@app.post("/contests", status_code=status.HTTP_201_CREATED)
async def create_contest(payload: ContestCreateRequest, current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    Create a new contest natively in the database.
    """
    creator_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    "SELECT create_contest_native(%s, %s, %s, %s, %s, %s, %s, %s);",
                    (
                        payload.title,
                        payload.ranking_strategy,
                        payload.start_time,
                        payload.freeze_time,
                        payload.end_time,
                        payload.invitation_code,
                        payload.judging_description,
                        creator_id
                    )
                )
                row = await cur.fetchone()
                await conn.commit()
                return {"message": "Contest successfully created and pending developer approval", "contest_id": row[0]}
            except Exception as e:
                await conn.rollback()
                logger.error(f"Error creating contest: {e}")
                raise HTTPException(status_code=400, detail=str(e))

@app.post("/contests/{contest_id}/approve")
async def approve_contest(contest_id: int, current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    Developer/Admin action to approve a contest and make it live.
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute("SELECT approve_contest_native(%s);", (contest_id,))
                await conn.commit()
                return {"message": "Contest successfully approved and is now active"}
            except Exception as e:
                await conn.rollback()
                logger.error(f"Error approving contest: {e}")
                raise HTTPException(status_code=400, detail=str(e))

@app.put("/contests/{contest_id}")
async def update_contest(contest_id: int, payload: ContestCreateRequest, current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    Update contest parameters. Natively checks for Host/Moderator role.
    """
    user_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    "SELECT update_contest_native(%s, %s, %s, %s, %s, %s, %s, %s, %s);",
                    (
                        contest_id,
                        user_id,
                        payload.title,
                        payload.ranking_strategy,
                        payload.start_time,
                        payload.freeze_time,
                        payload.end_time,
                        payload.invitation_code,
                        payload.judging_description
                    )
                )
                await conn.commit()
                return {"message": "Contest successfully updated"}
            except Exception as e:
                await conn.rollback()
                logger.error(f"Error updating contest: {e}")
                raise HTTPException(status_code=400, detail=str(e))

@app.delete("/contests/{contest_id}")
async def delete_contest(contest_id: int, current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    Delete a contest. Natively checks for Host role.
    """
    user_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute("SELECT delete_contest_native(%s, %s);", (contest_id, user_id))
                await conn.commit()
                return {"message": "Contest successfully deleted"}
            except Exception as e:
                await conn.rollback()
                logger.error(f"Error deleting contest: {e}")
                raise HTTPException(status_code=400, detail=str(e))

# Task Endpoints
@app.get("/contests/{contest_id}/tasks")
async def get_contest_tasks(contest_id: int, current_user: Optional[Dict[str, Any]] = Depends(get_optional_user)):
    """
    Fetch all tasks for a contest.
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT id, title, description, max_score
                FROM tasks
                WHERE contest_id = %s
                ORDER BY id ASC;
                """,
                (contest_id,)
            )
            rows = await cur.fetchall()
            tasks = []
            for row in rows:
                tasks.append({
                    "id": row[0],
                    "title": row[1],
                    "description": row[2],
                    "max_score": float(row[3])
                })
            return tasks

@app.post("/contests/{contest_id}/tasks", status_code=status.HTTP_201_CREATED)
async def create_task(contest_id: int, payload: TaskCreateRequest, current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    Add a task to a contest. Natively validates Host/Moderator role.
    """
    user_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    "SELECT add_task_native(%s, %s, %s, %s, %s);",
                    (contest_id, user_id, payload.title, payload.description, payload.max_score)
                )
                row = await cur.fetchone()
                await conn.commit()
                return {"message": "Task successfully created", "task_id": row[0]}
            except Exception as e:
                await conn.rollback()
                logger.error(f"Error adding task: {e}")
                raise HTTPException(status_code=400, detail=str(e))

@app.put("/tasks/{task_id}")
async def update_task(task_id: int, payload: TaskCreateRequest, current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    Update task details. Natively validates Host/Moderator role.
    """
    user_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    "SELECT update_task_native(%s, %s, %s, %s, %s);",
                    (task_id, user_id, payload.title, payload.description, payload.max_score)
                )
                await conn.commit()
                return {"message": "Task successfully updated"}
            except Exception as e:
                await conn.rollback()
                logger.error(f"Error updating task: {e}")
                raise HTTPException(status_code=400, detail=str(e))

@app.delete("/tasks/{task_id}")
async def delete_task(task_id: int, current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    Delete task. Natively validates Host/Moderator role.
    """
    user_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute("SELECT delete_task_native(%s, %s);", (task_id, user_id))
                await conn.commit()
                return {"message": "Task successfully deleted"}
            except Exception as e:
                await conn.rollback()
                logger.error(f"Error deleting task: {e}")
                raise HTTPException(status_code=400, detail=str(e))

# Enrollment & Role Management Endpoints
@app.post("/contests/{contest_id}/enroll")
async def enroll_contest(contest_id: int, payload: EnrollRequest, current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    Enroll in a contest. Natively validates invitation code if required.
    """
    user_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    "SELECT enroll_in_contest(%s, %s, %s);",
                    (contest_id, user_id, payload.invitation_code)
                )
                await conn.commit()
                return {"message": "Successfully enrolled in contest"}
            except Exception as e:
                await conn.rollback()
                logger.error(f"Error enrolling in contest: {e}")
                raise HTTPException(status_code=400, detail=str(e))

@app.post("/contests/{contest_id}/members/role")
async def update_member_role(contest_id: int, payload: RoleUpdateRequest, current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    Update member role in a contest. Natively validates Host role.
    """
    user_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    "SELECT update_contest_member_role(%s, %s, %s, %s);",
                    (contest_id, user_id, payload.target_user_id, payload.new_role)
                )
                await conn.commit()
                return {"message": f"Successfully updated user's role to {payload.new_role}"}
            except Exception as e:
                await conn.rollback()
                logger.error(f"Error updating member role: {e}")
                raise HTTPException(status_code=400, detail=str(e))

@app.get("/contests/{contest_id}/members")
async def get_contest_members(contest_id: int, current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    List members and roles for a contest. Requires Host/Moderator role.
    """
    user_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT role FROM enrollments WHERE contest_id = %s AND user_id = %s",
                (contest_id, user_id)
            )
            row = await cur.fetchone()
            if not row or row[0] not in ("HOST", "MODERATOR"):
                raise HTTPException(status_code=403, detail="Unauthorized: Only hosts or moderators can view members")
            
            await cur.execute(
                """
                SELECT u.id, u.username, e.role
                FROM enrollments e
                JOIN users u ON e.user_id = u.id
                WHERE e.contest_id = %s
                ORDER BY u.username ASC;
                """,
                (contest_id,)
            )
            rows = await cur.fetchall()
            return [{"user_id": r[0], "username": r[1], "role": r[2]} for r in rows]

@app.get("/users")
async def list_users(current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    Fetch all users in the system (useful for assigning roles).
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute("SELECT id, username FROM users ORDER BY username ASC;")
            rows = await cur.fetchall()
            return [{"id": r[0], "username": r[1]} for r in rows]

# Submission Endpoints
@app.post("/submissions", status_code=status.HTTP_201_CREATED)
async def create_submission(
    payload: SubmissionRequest, 
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """
    Ingest a new submission. Inserts it in PENDING state into the queue.
    Resolves submitting user natively from JWT authentication.
    Natively validates enrollment in the database before accepting.
    """
    user_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            # 1. Database-native check: Verify the user is enrolled in this contest
            await cur.execute(
                "SELECT role FROM enrollments WHERE contest_id = %s AND user_id = %s",
                (payload.contest_id, user_id)
            )
            enrolled = await cur.fetchone()
            if not enrolled:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"User '{current_user['username']}' (ID {user_id}) is not enrolled in contest {payload.contest_id}"
                )

            # 1a. Verify contest is active
            await cur.execute(
                "SELECT status FROM contests WHERE id = %s",
                (payload.contest_id,)
            )
            contest_status_row = await cur.fetchone()
            if not contest_status_row or contest_status_row[0] != 'ACTIVE':
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Submissions are only allowed for ACTIVE contests"
                )

            # 1b. Verify task belongs to contest if task_id is provided
            if payload.task_id:
                await cur.execute(
                    "SELECT 1 FROM tasks WHERE id = %s AND contest_id = %s",
                    (payload.task_id, payload.contest_id)
                )
                task_belongs = await cur.fetchone()
                if not task_belongs:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"Task {payload.task_id} does not belong to contest {payload.contest_id}"
                    )

            # 2. Ingest the submission into the PostgreSQL queue
            submission_json = json.dumps(payload.submission_data)
            
            await cur.execute(
                """
                INSERT INTO submissions (contest_id, user_id, task_id, submission_data, status)
                VALUES (%s, %s, %s, %s::jsonb, 'PENDING')
                RETURNING id, submitted_at;
                """,
                (payload.contest_id, user_id, payload.task_id, submission_json)
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

# User Profile & Activity Statistics Endpoints
@app.get("/users/{user_id}/profile")
async def get_user_profile(user_id: int, current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    Fetch user stats and activity graph data.
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            # 1. Fetch user metadata
            await cur.execute("SELECT username, created_at FROM users WHERE id = %s;", (user_id,))
            user_row = await cur.fetchone()
            if not user_row:
                raise HTTPException(status_code=404, detail="User not found")
            username, created_at = user_row

            # 2. Fetch user stats
            await cur.execute(
                """
                SELECT total_submissions, total_contests_joined, unique_tasks_attempted, 
                       fully_completed_tasks, average_score, max_score_single, verdict_breakdown 
                FROM get_user_profile_stats(%s);
                """,
                (user_id,)
            )
            stats_row = await cur.fetchone()
            
            stats = {}
            if stats_row:
                stats = {
                    "total_submissions": stats_row[0],
                    "total_contests_joined": stats_row[1],
                    "unique_tasks_attempted": stats_row[2],
                    "fully_completed_tasks": stats_row[3],
                    "average_score": float(stats_row[4]) if stats_row[4] is not None else 0.0,
                    "max_score_single": float(stats_row[5]) if stats_row[5] is not None else 0.0,
                    "verdict_breakdown": stats_row[6]
                }

            # 3. Fetch activity graph
            await cur.execute("SELECT activity_date, submission_count FROM get_user_activity_graph(%s);", (user_id,))
            activity_rows = await cur.fetchall()
            activity_graph = [{"date": str(r[0]), "count": r[1]} for r in activity_rows]

            return {
                "user_id": user_id,
                "username": username,
                "created_at": created_at,
                "stats": stats,
                "activity_graph": activity_graph
            }

@app.get("/users/{user_id}/history")
async def get_user_history(user_id: int, current_user: Dict[str, Any] = Depends(get_current_user)):
    """
    Fetch user contest history and recent submission history.
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            # 1. Verify user exists
            await cur.execute("SELECT 1 FROM users WHERE id = %s;", (user_id,))
            if not await cur.fetchone():
                raise HTTPException(status_code=404, detail="User not found")

            # 2. Fetch contest history
            await cur.execute(
                """
                SELECT contest_id, contest_title, role, registered_at, total_score, rank 
                FROM get_user_contest_history(%s);
                """, 
                (user_id,)
            )
            contest_rows = await cur.fetchall()
            contest_history = []
            for r in contest_rows:
                contest_history.append({
                    "contest_id": r[0],
                    "contest_title": r[1],
                    "role": r[2],
                    "registered_at": r[3],
                    "total_score": float(r[4]) if r[4] is not None else None,
                    "rank": r[5]
                })

            # 3. Fetch recent submissions
            await cur.execute(
                """
                SELECT submission_id, contest_id, contest_title, task_id, task_title, score, verdict, submitted_at 
                FROM get_user_submission_history(%s);
                """, 
                (user_id,)
            )
            sub_rows = await cur.fetchall()
            submissions_history = []
            for r in sub_rows:
                submissions_history.append({
                    "submission_id": r[0],
                    "contest_id": r[1],
                    "contest_title": r[2],
                    "task_id": r[3],
                    "task_title": r[4],
                    "score": float(r[5]) if r[5] is not None else 0.0,
                    "verdict": r[6],
                    "submitted_at": r[7]
                })

            return {
                "contest_history": contest_history,
                "submissions_history": submissions_history
            }

# Contest Statistics & Timeline Endpoints
@app.get("/contests/{contest_id}/statistics")
async def get_contest_stats_api(
    contest_id: int, 
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_user)
):
    """
    Fetch contest-wide aggregated statistics, task stats, and timeline.
    Bypasses freeze if viewed by a HOST or MODERATOR of that contest.
    """
    user_id = current_user["user_id"] if current_user else None
    
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            # Determine if user is host or moderator of this contest
            as_admin = False
            if user_id:
                await cur.execute(
                    "SELECT role FROM enrollments WHERE contest_id = %s AND user_id = %s;",
                    (contest_id, user_id)
                )
                role_row = await cur.fetchone()
                if role_row and role_row[0] in ("HOST", "MODERATOR"):
                    as_admin = True

            try:
                # 1. Fetch contest stats
                await cur.execute(
                    "SELECT total_participants, active_participants, total_submissions, task_stats FROM get_contest_statistics(%s, %s);",
                    (contest_id, as_admin)
                )
                stats_row = await cur.fetchone()
                if not stats_row:
                    raise HTTPException(status_code=404, detail="Contest statistics not available")
                
                # 2. Fetch timeline
                await cur.execute(
                    "SELECT bucket_start, submission_count FROM get_contest_submission_timeline(%s, %s);",
                    (contest_id, as_admin)
                )
                timeline_rows = await cur.fetchall()
                timeline = [{"bucket_start": str(r[0]), "count": r[1]} for r in timeline_rows]

                return {
                    "contest_id": contest_id,
                    "as_admin": as_admin,
                    "total_participants": stats_row[0],
                    "active_participants": stats_row[1],
                    "total_submissions": stats_row[2],
                    "task_statistics": stats_row[3],
                    "submission_timeline": timeline
                }
            except Exception as e:
                logger.error(f"Error fetching contest statistics: {e}")
                raise HTTPException(status_code=400, detail=str(e))

@app.get("/contests/{contest_id}/progress/{user_id}")
async def get_participant_progress(
    contest_id: int, 
    user_id: int, 
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """
    Fetch the cumulative score progression of a participant during a contest.
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            # Verify participant is enrolled
            await cur.execute(
                "SELECT role FROM enrollments WHERE contest_id = %s AND user_id = %s;",
                (contest_id, user_id)
            )
            enrolled = await cur.fetchone()
            if not enrolled:
                raise HTTPException(status_code=404, detail="User is not enrolled in this contest")

            await cur.execute(
                "SELECT submitted_at, running_score FROM get_participant_score_progression(%s, %s);",
                (contest_id, user_id)
            )
            rows = await cur.fetchall()
            progress = [{"submitted_at": r[0], "running_score": float(r[1])} for r in rows]
            
            return {
                "contest_id": contest_id,
                "user_id": user_id,
                "progress": progress
            }
