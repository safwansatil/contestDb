from fastapi import FastAPI, Request
from pydantic import BaseModel
import uvicorn
import logging

app = FastAPI(title="ContestDB Demo Webhooks Judge")
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("demo_judge")

class JudgeResponse(BaseModel):
    score: float
    status: str

@app.post("/judge/icpc")
async def judge_icpc(request: Request):
    payload = await request.json()
    logger.info(f"Received ICPC submission: {payload}")
    sub_data = payload.get("payload", {})
    code = sub_data.get("source_code", "").lower()
    
    # Mock evaluation for ICPC
    if "print" in code or "cout" in code or "system.out" in code:
        return {"score": 100, "status": "AC"}
    return {"score": 0, "status": "WA"}

@app.post("/judge/chess")
async def judge_chess(request: Request):
    payload = await request.json()
    logger.info(f"Received Chess submission: {payload}")
    sub_data = payload.get("payload", {})
    moves = sub_data.get("moves", [])
    
    # The frontend only sends a chess payload after chess.js reports checkmate.
    # Keep this intentionally deterministic for the demo judge.
    if moves and any("#" in str(move) for move in moves):
        return {"score": 100, "status": "CHECKMATE"}
    return {"score": 0, "status": "INCORRECT"}

@app.post("/judge/ctf")
async def judge_ctf(request: Request):
    payload = await request.json()
    logger.info(f"Received CTF submission: {payload}")
    sub_data = payload.get("payload", {})
    flag = sub_data.get("flag", "")
    
    valid_flags = {
        "CTFDB{view_source_first}",
        "CTFDB{base64_is_encoding}",
        "CTFDB{metadata_matters}",
    }
    if flag in valid_flags:
        return {"score": 100, "status": "CORRECT"}
    return {"score": 0, "status": "WRONG_FLAG"}

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8001)
