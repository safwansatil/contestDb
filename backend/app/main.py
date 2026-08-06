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
        print("DEBUG get_optional_user: No credentials found")
        return None
    try:
        payload = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        user_info = {"user_id": int(payload.get("sub")), "username": payload.get("username")}
        print(f"DEBUG get_optional_user: Decoded user info: {user_info}")
        import sys
        sys.stdout.flush()
        return user_info
    except jwt.PyJWTError as e:
        print(f"DEBUG get_optional_user: JWT error: {e}")
        import sys
        sys.stdout.flush()
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
    max_participants: Optional[int] = Field(None, ge=1, description="Max participant cap. NULL = unlimited.")
    allow_late_enrollment: bool = Field(True, description="If False, enrollment is blocked after start_time.")

class TaskCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=100)
    description: str = Field(..., min_length=1)
    max_score: float = Field(100.0, ge=0.0)
    submission_schema: Dict[str, Any] = Field(..., description="Required JSONB schema descriptor for submission_data validation (required_keys, numeric_keys).")
    submission_cooldown_seconds: int = Field(0, ge=0, description="Cooldown seconds between submissions per user. 0 = no cooldown.")
    task_order: int = Field(0, ge=0, description="Display order index within the contest. Lower = shown first.")

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

class ContestVisibilityRequest(BaseModel):
    show_participant_count: bool = True
    show_leaderboard: bool = True
    show_member_list: bool = False
    show_task_list: bool = True
    show_statistics: bool = False
    show_submission_count: bool = False

class AnnouncementCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=150)
    body: str = Field(..., min_length=1)

class KickParticipantRequest(BaseModel):
    reason: Optional[str] = None

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
async def get_contests(
    q: Optional[str] = Query(None, description="Search contests by title"),
    status: Optional[str] = Query(None, description="Filter contests by status"),
    strategy: Optional[str] = Query(None, description="Filter contests by ranking strategy"),
    timeline: Optional[str] = Query(None, description="Filter contests by timeline status (UPCOMING, ONGOING, COMPLETED)"),
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_user)
):
    """
    Fetch all contests matching filters. If authenticated, return the user's role.
    Only return invitation codes to HOST or MODERATOR users.
    """
    user_id = current_user["user_id"] if current_user else None
    print(f"DEBUG get_contests: user_id={user_id}, q={q!r}, status={status!r}, strategy={strategy!r}, timeline={timeline!r}")
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT * FROM search_contests_native(%s, %s, %s, %s, %s);",
                (user_id, q, status, strategy, timeline)
            )
            rows = await cur.fetchall()
            contests = []
            for row in rows:
                (c_id, title, ranking, start, freeze, end, status_val, judging_desc, inv_code, role,
                 max_p, allow_late, show_pc, show_lb, show_ml, show_tl, show_st, show_sc) = row
                has_code = inv_code is not None and inv_code != ""
                is_admin = role in ("HOST", "MODERATOR")
                contests.append({
                    "id": c_id,
                    "title": title,
                    "ranking_strategy": ranking,
                    "start_time": start,
                    "freeze_time": freeze,
                    "end_time": end,
                    "status": status_val,
                    "judging_description": judging_desc,
                    "requires_invitation_code": has_code,
                    "invitation_code": inv_code if is_admin else None,
                    "user_role": role,
                    "max_participants": max_p,
                    "allow_late_enrollment": allow_late,
                    "visibility": {
                        "show_participant_count": show_pc if show_pc is not None else True,
                        "show_leaderboard": show_lb if show_lb is not None else True,
                        "show_member_list": show_ml if show_ml is not None else False,
                        "show_task_list": show_tl if show_tl is not None else True,
                        "show_statistics": show_st if show_st is not None else False,
                        "show_submission_count": show_sc if show_sc is not None else False,
                    }
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
                       c.status, c.judging_description, c.invitation_code, e.role,
                       c.max_participants, c.allow_late_enrollment,
                       cv.show_participant_count, cv.show_leaderboard, cv.show_member_list,
                       cv.show_task_list, cv.show_statistics, cv.show_submission_count
                FROM contests c
                LEFT JOIN enrollments e ON c.id = e.contest_id AND e.user_id = %s
                LEFT JOIN contest_visibility cv ON c.id = cv.contest_id
                WHERE c.id = %s;
                """,
                (user_id, contest_id)
            )
            row = await cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Contest not found")

            (c_id, title, ranking, start, freeze, end, status, judging_desc, inv_code, role,
             max_p, allow_late, show_pc, show_lb, show_ml, show_tl, show_st, show_sc) = row
            has_code = inv_code is not None and inv_code != ""
            is_admin = role in ("HOST", "MODERATOR")

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
                "invitation_code": inv_code if is_admin else None,
                "user_role": role,
                "max_participants": max_p,
                "allow_late_enrollment": allow_late,
                "visibility": {
                    "show_participant_count": show_pc if show_pc is not None else True,
                    "show_leaderboard": show_lb if show_lb is not None else True,
                    "show_member_list": show_ml if show_ml is not None else False,
                    "show_task_list": show_tl if show_tl is not None else True,
                    "show_statistics": show_st if show_st is not None else False,
                    "show_submission_count": show_sc if show_sc is not None else False,
                }
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
                    "SELECT create_contest_native(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s);",
                    (
                        payload.title,
                        payload.ranking_strategy,
                        payload.start_time,
                        payload.freeze_time,
                        payload.end_time,
                        payload.invitation_code,
                        payload.judging_description,
                        creator_id,
                        payload.max_participants,
                        payload.allow_late_enrollment
                    )
                )
                row = await cur.fetchone()
                await conn.commit()
                return {"message": "Contest successfully created and pending developer approval", "contest_id": row[0]}
            except Exception as e:
                await conn.rollback()
                logger.error(f"Error creating contest: {e}")
                raise HTTPException(status_code=400, detail=str(e))


# NOTE: Contest approval is intentionally NOT exposed as an API endpoint.
# To approve a pending contest, connect to the database directly and run:
#   SELECT approve_contest_native(<contest_id>);
# or:
#   UPDATE contests SET status = 'ACTIVE' WHERE id = <contest_id>;
# This is a deliberate design choice — approval is a developer/admin terminal action only.

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
                    "SELECT update_contest_native(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);",
                    (
                        contest_id,
                        user_id,
                        payload.title,
                        payload.ranking_strategy,
                        payload.start_time,
                        payload.freeze_time,
                        payload.end_time,
                        payload.invitation_code,
                        payload.judging_description,
                        payload.max_participants,
                        payload.allow_late_enrollment
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
                SELECT id, title, description, max_score,
                       submission_schema, submission_cooldown_seconds, task_order
                FROM tasks
                WHERE contest_id = %s
                ORDER BY task_order ASC, id ASC;
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
                    "max_score": float(row[3]),
                    "submission_schema": row[4],
                    "submission_cooldown_seconds": row[5],
                    "task_order": row[6]
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
                import json as _json
                await cur.execute(
                    "SELECT add_task_native(%s, %s, %s, %s, %s, %s::jsonb, %s, %s);",
                    (
                        contest_id, user_id, payload.title, payload.description, payload.max_score,
                        _json.dumps(payload.submission_schema),
                        payload.submission_cooldown_seconds,
                        payload.task_order
                    )
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
                import json as _json
                await cur.execute(
                    "SELECT update_task_native(%s, %s, %s, %s, %s, %s::jsonb, %s, %s);",
                    (
                        task_id, user_id, payload.title, payload.description, payload.max_score,
                        _json.dumps(payload.submission_schema),
                        payload.submission_cooldown_seconds,
                        payload.task_order
                    )
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

@app.get("/time")
async def get_server_time():
    """
    Fetch the current database server timestamp to synchronize the global UTC clock.
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute("SELECT CURRENT_TIMESTAMP;")
            row = await cur.fetchone()
            return {"server_time": row[0]}

@app.get("/users/search")
async def search_users(q: str = Query("", description="Query prefix/substring to search users")):
    """
    Search users natively in the database by username.
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute("SELECT id, username, created_at FROM search_users_native(%s);", (q.strip(),))
            rows = await cur.fetchall()
            return [{"id": r[0], "username": r[1], "created_at": r[2]} for r in rows]

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
    current_user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Validate and insert a submission atomically through PostgreSQL.
    """
    user_id = current_user["user_id"]

    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    """
                    SELECT submission_id, submitted_at
                    FROM submit_entry_native(
                        %s,
                        %s,
                        %s,
                        %s::jsonb
                    );
                    """,
                    (
                        payload.contest_id,
                        user_id,
                        payload.task_id,
                        json.dumps(payload.submission_data),
                    ),
                )

                row = await cur.fetchone()
                await conn.commit()

                return {
                    "message": "Submission successfully placed in queue",
                    "submission_id": row[0],
                    "submitted_at": row[1],
                }

            except Exception as exc:
                await conn.rollback()

                error_message = str(exc)

                if "cooldown active" in error_message.lower():
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail=error_message,
                    )

                if "not enrolled" in error_message.lower():
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail=error_message,
                    )

                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=error_message,
                )

@app.get("/contests/{contest_id}/leaderboard")
async def get_contest_leaderboard(
    contest_id: int, 
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_user)
):
    """
    Fetch the dynamic leaderboard. Honors scoreboard freeze rules based on the user's role.
    """
    user_id = current_user["user_id"] if current_user else None
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                # Query the stored procedure
                await cur.execute(
                    "SELECT user_id, username, total_score, rank FROM get_leaderboard(%s, %s)",
                    (contest_id, user_id)
                )
                rows = await cur.fetchall()
                
                # Check if this user is a Host/Moderator to return view mode info
                is_admin = False
                if user_id:
                    await cur.execute(
                        "SELECT role FROM enrollments WHERE contest_id = %s AND user_id = %s",
                        (contest_id, user_id)
                    )
                    enrolled = await cur.fetchone()
                    if enrolled and enrolled[0] in ("HOST", "MODERATOR"):
                        is_admin = True

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
                    "view_mode": "admin" if is_admin else "public",
                    "leaderboard": leaderboard
                }
            except Exception as e:
                # If the contest doesn't exist, get_leaderboard raises an exception
                logger.error(f"Error fetching leaderboard: {e}")
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=str(e)
                )


# Participant Dashboard Endpoint
@app.get("/dashboards/participant")
async def get_participant_dashboard_api(
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """
    Return the complete participant dashboard for the authenticated user.
    """
    user_id = current_user["user_id"]

    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT get_participant_dashboard(%s);",
                (user_id,)
            )

            row = await cur.fetchone()

            if not row or row[0] is None:
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Could not generate participant dashboard"
                )

            return row[0]



# User Profile & Activity Statistics Endpoints
@app.get("/users/{user_id}/profile")
async def get_user_profile(user_id: int, current_user: Optional[Dict[str, Any]] = Depends(get_optional_user)):
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
async def get_user_history(user_id: int, current_user: Optional[Dict[str, Any]] = Depends(get_optional_user)):
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

# ============================================================
# Contest Visibility Endpoints
# ============================================================

@app.get("/contests/{contest_id}/visibility")
async def get_contest_visibility(
    contest_id: int,
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_user)
):
    """
    Fetch the visibility configuration for a contest.
    Visibility settings control which fields public viewers can see.
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    """
                    SELECT show_participant_count, show_leaderboard, show_member_list,
                           show_task_list, show_statistics, show_submission_count, updated_at
                    FROM get_contest_visibility(%s);
                    """,
                    (contest_id,)
                )
                row = await cur.fetchone()
                if not row:
                    raise HTTPException(status_code=404, detail="Contest not found")
                return {
                    "contest_id": contest_id,
                    "show_participant_count": row[0],
                    "show_leaderboard": row[1],
                    "show_member_list": row[2],
                    "show_task_list": row[3],
                    "show_statistics": row[4],
                    "show_submission_count": row[5],
                    "updated_at": row[6]
                }
            except Exception as e:
                logger.error(f"Error fetching visibility: {e}")
                raise HTTPException(status_code=400, detail=str(e))

@app.put("/contests/{contest_id}/visibility")
async def update_contest_visibility(
    contest_id: int,
    payload: ContestVisibilityRequest,
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """
    Update contest visibility settings. Only HOST or MODERATOR can call this.
    Controls which fields are exposed to public viewers on the contest profile page.
    """
    user_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    "SELECT update_contest_visibility(%s, %s, %s, %s, %s, %s, %s, %s);",
                    (
                        contest_id, user_id,
                        payload.show_participant_count,
                        payload.show_leaderboard,
                        payload.show_member_list,
                        payload.show_task_list,
                        payload.show_statistics,
                        payload.show_submission_count
                    )
                )
                await conn.commit()
                return {"message": "Contest visibility settings updated successfully"}
            except Exception as e:
                await conn.rollback()
                logger.error(f"Error updating visibility: {e}")
                raise HTTPException(status_code=400, detail=str(e))

# ============================================================
# Enrollment Info Endpoint
# ============================================================

@app.get("/contests/{contest_id}/enrollment-info")
async def get_enrollment_info(
    contest_id: int,
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_user)
):
    """
    Fetch enrollment capacity info for a contest:
    max participants, current count, remaining spots, late-enrollment flag, and kick count.
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    """
                    SELECT max_participants, current_participants, spots_remaining,
                           allow_late_enrollment, total_kicked
                    FROM get_contest_enrollment_info(%s);
                    """,
                    (contest_id,)
                )
                row = await cur.fetchone()
                if not row:
                    raise HTTPException(status_code=404, detail="Contest not found")
                return {
                    "contest_id": contest_id,
                    "max_participants": row[0],
                    "current_participants": row[1],
                    "spots_remaining": row[2],
                    "allow_late_enrollment": row[3],
                    "total_kicked": row[4]
                }
            except Exception as e:
                logger.error(f"Error fetching enrollment info: {e}")
                raise HTTPException(status_code=400, detail=str(e))

# ============================================================
# Participant Kick & Kick Log Endpoints
# ============================================================

@app.delete("/contests/{contest_id}/members/{target_user_id}")
async def kick_participant(
    contest_id: int,
    target_user_id: int,
    payload: KickParticipantRequest,
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """
    Remove (kick) a participant from a contest. HOST only.
    The participant is permanently banned from re-enrolling in the same contest.
    Their submission history is preserved for record integrity.
    The kick is logged in kick_log with an optional reason.
    """
    user_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    "SELECT kick_participant_native(%s, %s, %s, %s);",
                    (contest_id, user_id, target_user_id, payload.reason)
                )
                await conn.commit()
                return {"message": f"Participant (ID {target_user_id}) successfully removed from contest"}
            except Exception as e:
                await conn.rollback()
                logger.error(f"Error kicking participant: {e}")
                raise HTTPException(status_code=400, detail=str(e))

@app.get("/contests/{contest_id}/kick-log")
async def get_kick_log(
    contest_id: int,
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """
    Fetch the full kick/ban audit log for a contest. HOST or MODERATOR only.
    Returns all removed participants with kick reason and timestamp.
    """
    user_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT role FROM enrollments WHERE contest_id = %s AND user_id = %s",
                (contest_id, user_id)
            )
            role_row = await cur.fetchone()
            if not role_row or role_row[0] not in ("HOST", "MODERATOR"):
                raise HTTPException(status_code=403, detail="Unauthorized: Only Host or Moderator can view the kick log")

            await cur.execute(
                """
                SELECT kl.id, u_kicked.id, u_kicked.username, u_by.username,
                       kl.reason, kl.kicked_at
                FROM kick_log kl
                JOIN users u_kicked ON kl.kicked_user_id = u_kicked.id
                JOIN users u_by ON kl.kicked_by = u_by.id
                WHERE kl.contest_id = %s
                ORDER BY kl.kicked_at DESC;
                """,
                (contest_id,)
            )
            rows = await cur.fetchall()
            return [
                {
                    "log_id": r[0],
                    "kicked_user_id": r[1],
                    "kicked_username": r[2],
                    "kicked_by_username": r[3],
                    "reason": r[4],
                    "kicked_at": r[5]
                }
                for r in rows
            ]

# ============================================================
# Contest Announcements Endpoints
# ============================================================

@app.post("/contests/{contest_id}/announcements", status_code=status.HTTP_201_CREATED)
async def post_announcement(
    contest_id: int,
    payload: AnnouncementCreateRequest,
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """
    Post a new announcement to a contest. HOST or MODERATOR only.
    Announcements are visible to all viewers of the contest page.
    """
    user_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    "SELECT post_announcement_native(%s, %s, %s, %s);",
                    (contest_id, user_id, payload.title, payload.body)
                )
                row = await cur.fetchone()
                await conn.commit()
                return {"message": "Announcement posted", "announcement_id": row[0]}
            except Exception as e:
                await conn.rollback()
                logger.error(f"Error posting announcement: {e}")
                raise HTTPException(status_code=400, detail=str(e))

@app.get("/contests/{contest_id}/announcements")
async def get_announcements(
    contest_id: int,
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_user)
):
    """
    Fetch all announcements for a contest, ordered newest first.
    Public endpoint — any viewer can read announcements.
    """
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT ca.id, ca.title, ca.body, u.username, ca.posted_at
                FROM contest_announcements ca
                JOIN users u ON ca.author_id = u.id
                WHERE ca.contest_id = %s
                ORDER BY ca.posted_at DESC;
                """,
                (contest_id,)
            )
            rows = await cur.fetchall()
            return [
                {
                    "id": r[0],
                    "title": r[1],
                    "body": r[2],
                    "author": r[3],
                    "posted_at": r[4]
                }
                for r in rows
            ]

@app.delete("/announcements/{announcement_id}")
async def delete_announcement(
    announcement_id: int,
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """
    Delete an announcement. HOST or MODERATOR of the associated contest only.
    """
    user_id = current_user["user_id"]
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    "SELECT delete_announcement_native(%s, %s);",
                    (announcement_id, user_id)
                )
                await conn.commit()
                return {"message": "Announcement deleted"}
            except Exception as e:
                await conn.rollback()
                logger.error(f"Error deleting announcement: {e}")
                raise HTTPException(status_code=400, detail=str(e))

# ============================================================
# Contest Profile Aggregator Endpoint
# ============================================================

@app.get("/contests/{contest_id}/profile")
async def get_contest_profile(
    contest_id: int,
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_user)
):
    """
    Fetch a full aggregated contest profile in a single database call.
    Returns contest metadata, enrollment capacity info, visibility config,
    announcement summary, task count, and the viewer's enrollment status.
    Fields like invitation_code are redacted based on viewer role and visibility settings.
    """
    viewer_id = current_user["user_id"] if current_user else None
    async with get_db_connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute(
                    """
                    SELECT contest_id, title, ranking_strategy, start_time, freeze_time, end_time,
                           status, judging_description, invitation_code, max_participants,
                           allow_late_enrollment, current_participants, spots_remaining,
                           total_kicked, task_count, announcement_count, latest_announcement_title,
                           show_participant_count, show_leaderboard, show_member_list,
                           show_task_list, show_statistics, show_submission_count,
                           viewer_role, viewer_is_enrolled
                    FROM get_contest_profile(%s, %s);
                    """,
                    (contest_id, viewer_id)
                )
                row = await cur.fetchone()
                if not row:
                    raise HTTPException(status_code=404, detail="Contest not found")

                (
                    c_id, title, ranking, start, freeze, end,
                    c_status, judging_desc, inv_code, max_p,
                    allow_late, current_p, spots, total_kicked,
                    task_count, ann_count, latest_ann_title,
                    show_pc, show_lb, show_ml, show_tl, show_st, show_sc,
                    viewer_role, viewer_enrolled
                ) = row

                is_admin = viewer_role in ("HOST", "MODERATOR")

                profile = {
                    "contest_id": c_id,
                    "title": title,
                    "ranking_strategy": ranking,
                    "start_time": start,
                    "freeze_time": freeze,
                    "end_time": end,
                    "status": c_status,
                    "judging_description": judging_desc,
                    "invitation_code": inv_code if is_admin else None,
                    "max_participants": max_p,
                    "allow_late_enrollment": allow_late,
                    "task_count": task_count,
                    "announcement_count": ann_count,
                    "latest_announcement_title": latest_ann_title,
                    "viewer_role": viewer_role,
                    "viewer_is_enrolled": viewer_enrolled,
                    "visibility": {
                        "show_participant_count": show_pc,
                        "show_leaderboard": show_lb,
                        "show_member_list": show_ml,
                        "show_task_list": show_tl,
                        "show_statistics": show_st,
                        "show_submission_count": show_sc,
                    }
                }

                # Conditionally include visibility-gated fields
                if show_pc or is_admin:
                    profile["current_participants"] = current_p
                    profile["spots_remaining"] = spots

                if is_admin:
                    profile["total_kicked"] = total_kicked

                return profile

            except Exception as e:
                logger.error(f"Error fetching contest profile: {e}")
                raise HTTPException(status_code=400, detail=str(e))
