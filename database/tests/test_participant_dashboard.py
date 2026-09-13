"""
Integration tests for GitHub Issue #42:
Database-native Participant Dashboard.

Run from the project root:

    python database/tests/test_participant_dashboard.py

Requirements:
    1. get_participant_dashboard() has been applied to Neon.
    2. FastAPI is running at http://127.0.0.1:8000.
    3. The database contains the seeded users.
"""

import json
import sys
import urllib.error
import urllib.request
from typing import Any


BASE_URL = "http://127.0.0.1:8000"

PASS = "\033[92m[PASS]\033[0m"
FAIL = "\033[91m[FAIL]\033[0m"
INFO = "\033[94m[INFO]\033[0m"

failures = 0


# ============================================================
# HTTP helpers
# ============================================================

def api_get(
    path: str,
    token: str | None = None
) -> tuple[int, Any]:
    request = urllib.request.Request(
        f"{BASE_URL}{path}",
        method="GET"
    )

    if token:
        request.add_header(
            "Authorization",
            f"Bearer {token}"
        )

    try:
        with urllib.request.urlopen(request) as response:
            body = json.loads(response.read().decode())
            return response.status, body

    except urllib.error.HTTPError as error:
        raw_body = error.read().decode()

        try:
            body = json.loads(raw_body)
        except json.JSONDecodeError:
            body = {"detail": raw_body}

        return error.code, body

    except urllib.error.URLError as error:
        print(
            f"{FAIL} Could not connect to {BASE_URL}. "
            "Make sure FastAPI is running."
        )
        print(f"Reason: {error.reason}")
        sys.exit(1)


def api_post(
    path: str,
    payload: dict,
    token: str | None = None
) -> tuple[int, Any]:
    request = urllib.request.Request(
        f"{BASE_URL}{path}",
        data=json.dumps(payload).encode(),
        method="POST"
    )

    request.add_header("Content-Type", "application/json")

    if token:
        request.add_header(
            "Authorization",
            f"Bearer {token}"
        )

    try:
        with urllib.request.urlopen(request) as response:
            body = json.loads(response.read().decode())
            return response.status, body

    except urllib.error.HTTPError as error:
        raw_body = error.read().decode()

        try:
            body = json.loads(raw_body)
        except json.JSONDecodeError:
            body = {"detail": raw_body}

        return error.code, body

    except urllib.error.URLError as error:
        print(
            f"{FAIL} Could not connect to {BASE_URL}. "
            "Make sure FastAPI is running."
        )
        print(f"Reason: {error.reason}")
        sys.exit(1)


def login(
    username: str,
    password: str = "password123"
) -> tuple[str | None, int | None]:
    status_code, body = api_post(
        "/auth/login",
        {
            "username": username,
            "password": password
        }
    )

    if status_code != 200:
        print(
            f"{FAIL} Login failed for {username!r}: "
            f"HTTP {status_code} — {body}"
        )
        return None, None

    token = body.get("access_token")
    user_id = body.get("user", {}).get("id")

    if not token or not user_id:
        print(
            f"{FAIL} Login response did not contain "
            "access_token and user.id"
        )
        return None, None

    return token, user_id


# ============================================================
# Assertion helpers
# ============================================================

def assert_equal(label: str, actual: Any, expected: Any):
    global failures

    if actual == expected:
        print(f"  {PASS} {label}")
    else:
        print(
            f"  {FAIL} {label}: "
            f"expected {expected!r}, got {actual!r}"
        )
        failures += 1


def assert_true(label: str, condition: bool):
    global failures

    if condition:
        print(f"  {PASS} {label}")
    else:
        print(f"  {FAIL} {label}")
        failures += 1


def assert_has_keys(
    label: str,
    value: dict,
    expected_keys: set[str]
):
    global failures

    missing_keys = expected_keys - set(value.keys())

    if not missing_keys:
        print(f"  {PASS} {label}")
    else:
        print(
            f"  {FAIL} {label}: "
            f"missing keys {sorted(missing_keys)}"
        )
        failures += 1


# ============================================================
# Test 1: Authentication is mandatory
# ============================================================

def test_authentication_required():
    print("\n=== Test 1: Dashboard requires authentication ===")

    status_code, body = api_get(
        "/dashboards/participant"
    )

    assert_equal(
        "Request without JWT returns HTTP 401",
        status_code,
        401
    )

    assert_true(
        "Unauthorized response contains detail",
        isinstance(body, dict) and "detail" in body
    )


# ============================================================
# Test 2: Response structure
# ============================================================

def test_dashboard_response_structure(
    token: str
) -> dict | None:
    print("\n=== Test 2: Dashboard response structure ===")

    status_code, body = api_get(
        "/dashboards/participant",
        token
    )

    assert_equal(
        "Authenticated request returns HTTP 200",
        status_code,
        200
    )

    if status_code != 200 or not isinstance(body, dict):
        print(f"  {FAIL} Cannot continue structure checks: {body}")
        return None

    assert_has_keys(
        "Dashboard contains all four sections",
        body,
        {
            "summary",
            "ongoing_contests",
            "upcoming_contests",
            "recent_submissions"
        }
    )

    summary = body.get("summary", {})

    assert_true(
        "summary is an object",
        isinstance(summary, dict)
    )

    if isinstance(summary, dict):
        assert_has_keys(
            "Summary contains all required statistics",
            summary,
            {
                "active_contests",
                "completed_contests",
                "total_submissions",
                "tasks_completed"
            }
        )

        for field in (
            "active_contests",
            "completed_contests",
            "total_submissions",
            "tasks_completed"
        ):
            assert_true(
                f"{field} is a non-negative integer",
                isinstance(summary.get(field), int)
                and summary.get(field) >= 0
            )

    for section in (
        "ongoing_contests",
        "upcoming_contests",
        "recent_submissions"
    ):
        assert_true(
            f"{section} is an array",
            isinstance(body.get(section), list)
        )

    return body


# ============================================================
# Test 3: Only participant-enrolled contests are returned
# ============================================================

def test_contest_isolation(
    token: str,
    dashboard: dict
):
    print(
        "\n=== Test 3: Dashboard contains only "
        "participant-enrolled contests ==="
    )

    status_code, contests = api_get(
        "/contests",
        token
    )

    assert_equal(
        "Contest directory request returns HTTP 200",
        status_code,
        200
    )

    if status_code != 200 or not isinstance(contests, list):
        return

    participant_contest_ids = {
        contest["id"]
        for contest in contests
        if contest.get("user_role") == "PARTICIPANT"
    }

    dashboard_contest_ids = {
        contest.get("contest_id")
        for contest in (
            dashboard.get("ongoing_contests", [])
            + dashboard.get("upcoming_contests", [])
        )
    }

    assert_true(
        "Every dashboard contest has PARTICIPANT role",
        dashboard_contest_ids.issubset(
            participant_contest_ids
        )
    )


# ============================================================
# Test 4: Recent submissions belong to logged-in user
# ============================================================

def test_submission_isolation(
    token: str,
    user_id: int,
    dashboard: dict
):
    print(
        "\n=== Test 4: Recent submissions belong "
        "to the authenticated user ==="
    )

    status_code, history = api_get(
        f"/users/{user_id}/history",
        token
    )

    assert_equal(
        "User history request returns HTTP 200",
        status_code,
        200
    )

    if status_code != 200 or not isinstance(history, dict):
        return

    own_submission_ids = {
        submission.get("submission_id")
        for submission in history.get(
            "submissions_history",
            []
        )
    }

    dashboard_submissions = dashboard.get(
        "recent_submissions",
        []
    )

    dashboard_submission_ids = {
        submission.get("submission_id")
        for submission in dashboard_submissions
    }

    assert_true(
        "Dashboard returns no more than five submissions",
        len(dashboard_submissions) <= 5
    )

    assert_true(
        "Every dashboard submission belongs to logged-in user",
        dashboard_submission_ids.issubset(
            own_submission_ids
        )
    )

    submitted_times = [
        submission.get("submitted_at")
        for submission in dashboard_submissions
        if submission.get("submitted_at") is not None
    ]

    assert_true(
        "Recent submissions are ordered newest first",
        submitted_times == sorted(
            submitted_times,
            reverse=True
        )
    )


# ============================================================
# Test runner
# ============================================================

def run_all_tests():
    print("=" * 65)
    print("ContestDB Participant Dashboard Tests — Issue #42")
    print("=" * 65)

    test_authentication_required()

    # satil is seeded as PARTICIPANT in Contest 1.
    token, user_id = login("satil")

    if not token or not user_id:
        sys.exit(1)

    dashboard = test_dashboard_response_structure(token)

    if dashboard is not None:
        test_contest_isolation(token, dashboard)
        test_submission_isolation(
            token,
            user_id,
            dashboard
        )

    print("\n" + "=" * 65)

    if failures == 0:
        print(f"{PASS} All participant-dashboard tests passed.")
    else:
        print(
            f"{FAIL} {failures} participant-dashboard "
            "test(s) failed."
        )

    print("=" * 65)

    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    run_all_tests()