import os
import logging
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime, timedelta, timezone
import json
import jwt
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

security = HTTPBearer()

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
    user_id: Optional[int] = Field(None, description="Deprecated, user ID is resolved from authenticated token")
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

# API Endpoints
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
                "SELECT 1 FROM enrollments WHERE contest_id = %s AND user_id = %s",
                (payload.contest_id, user_id)
            )
            enrolled = await cur.fetchone()
            if not enrolled:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"User '{current_user['username']}' (ID {user_id}) is not enrolled in contest {payload.contest_id}"
                )

            # 2. Ingest the submission into the PostgreSQL queue
            submission_json = json.dumps(payload.submission_data)
            
            await cur.execute(
                """
                INSERT INTO submissions (contest_id, user_id, submission_data, status)
                VALUES (%s, %s, %s::jsonb, 'PENDING')
                RETURNING id, submitted_at;
                """,
                (payload.contest_id, user_id, submission_json)
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
