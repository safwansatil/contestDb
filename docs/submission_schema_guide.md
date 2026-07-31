# Submission Schema Guide

This guide explains the **task submission schema system** in ContestDB — how it works, what format it uses, and how to design schemas for different contest types.

---

## What is a Submission Schema?

Every task in ContestDB has a `submission_schema` column (JSONB, NOT NULL). It describes the expected structure of `submission_data` that participants must provide when submitting to that task.

The schema is validated by the database function `validate_submission_schema_native()` before a submission is accepted into the queue. A submission that fails validation is **hard-rejected** with HTTP 400 — it is never inserted into the database.

---

## Schema Format

```json
{
  "required_keys": ["key1", "key2"],
  "numeric_keys": ["key1"]
}
```

| Field | Type | Description |
|---|---|---|
| `required_keys` | `string[]` | Keys that must be present in `submission_data`. If any is missing → rejected. |
| `numeric_keys` | `string[]` | Keys whose JSON type must be `number`. If type mismatch → rejected. |

Both fields are optional in the schema object. You can use one or both.

---

## DB Function: `validate_submission_schema_native`

```sql
SELECT validate_submission_schema_native(task_id, submission_data::jsonb);
```

**Logic:**
1. Fetches `tasks.submission_schema` for the given `task_id`.
2. If `submission_schema IS NULL` → returns immediately (no-op, backward compatible).
3. Iterates over `required_keys` → `RAISE EXCEPTION` if any key is missing from `submission_data`.
4. Iterates over `numeric_keys` → checks `jsonb_typeof(submission_data -> key) = 'number'`; raises exception if wrong type.

---

## Examples by Contest Type

### 1. Robotics — Line Follower Run (LFR)
**Schema:**
```json
{"required_keys": ["run_time_seconds", "restarts", "track_id"], "numeric_keys": ["run_time_seconds", "restarts"]}
```
**Valid submission:**
```json
{"run_time_seconds": 12.4, "restarts": 0, "track_id": "A3"}
```
**Invalid (missing key):**
```json
{"run_time_seconds": 12.4}
```
→ `missing required key "restarts"`

### 2. Math Quiz
**Schema:**
```json
{"required_keys": ["score", "verdict"], "numeric_keys": ["score"]}
```
**Valid submission:**
```json
{"score": 85.0, "verdict": "ACCEPTED"}
```
**Invalid (wrong type):**
```json
{"score": "eighty-five", "verdict": "ACCEPTED"}
```
→ `key "score" must be a number, got "string"`

### 3. Chess Match
**Schema:**
```json
{"required_keys": ["pgn", "result", "move_count"], "numeric_keys": ["move_count"]}
```
**Valid submission:**
```json
{"pgn": "1.e4 e5 2.Nf3 Nc6", "result": "1-0", "move_count": 32}
```

### 4. Competitive Programming (Code Submission)
**Schema:**
```json
{"required_keys": ["language", "source_code"]}
```
**Valid submission:**
```json
{"language": "python3", "source_code": "print(int(input())**2)"}
```

### 5. Survey / Open Response
**Schema:**
```json
{"required_keys": ["response_text"]}
```
No `numeric_keys` — only presence is checked.

---

## How Hosts Set a Schema

When creating or updating a task via the API, always include `submission_schema`:

```bash
curl -X POST http://127.0.0.1:8000/contests/1/tasks \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <host_token>" \
     -d '{
       "title": "Speed Run Trial",
       "description": "Complete the track as fast as possible.",
       "max_score": 100,
       "submission_schema": {
         "required_keys": ["run_time_seconds", "restarts"],
         "numeric_keys": ["run_time_seconds", "restarts"]
       },
       "submission_cooldown_seconds": 30,
       "task_order": 1
     }'
```

---

## Extending the Schema System

The current schema supports `required_keys` and `numeric_keys`. The system is designed to be extended by modifying `validate_submission_schema_native()` in `database/procedures.sql`. Potential future extensions:

| Extension | Schema key | Description |
|---|---|---|
| String enum validation | `enum_keys` | Only accept specific string values |
| Min/max value checks | `range_keys` | Enforce numeric bounds |
| Array presence | `array_keys` | Require JSONB array type for a key |
| Nested key validation | `nested_keys` | Validate sub-object structures |

All extensions would live in SQL — no application layer changes needed.
