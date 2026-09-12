"""
Integration tests for GitHub Issue #46:
Database-native Manager Dashboard.

Run from the project root while FastAPI is running:

    python database/tests/test_manager_dashboard.py
"""

import json
import sys
import unittest
import urllib.error
import urllib.request
from typing import Any


BASE_URL = "http://127.0.0.1:8000"


def request(
    method: str,
    path: str,
    payload: dict | None = None,
    token: str | None = None
) -> tuple[int, Any]:
    data = None

    if payload is not None:
        data = json.dumps(payload).encode()

    req = urllib.request.Request(
        f"{BASE_URL}{path}",
        data=data,
        method=method
    )

    if payload is not None:
        req.add_header("Content-Type", "application/json")

    if token:
        req.add_header("Authorization", f"Bearer {token}")

    try:
        with urllib.request.urlopen(req) as response:
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
        raise RuntimeError(
            f"Cannot connect to {BASE_URL}. "
            "Make sure FastAPI is running."
        ) from error


def login(username: str) -> str:
    status_code, body = request(
        "POST",
        "/auth/login",
        {
            "username": username,
            "password": "password123"
        }
    )

    if status_code != 200:
        raise RuntimeError(
            f"Login failed for {username}: "
            f"HTTP {status_code} — {body}"
        )

    token = body.get("access_token")

    if not token:
        raise RuntimeError(
            f"Login response for {username} has no access_token"
        )

    return token


class ManagerDashboardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manager_token = login("sayma")
        cls.participant_token = login("satil")

    def test_01_authentication_is_required(self):
        status_code, body = request(
            "GET",
            "/dashboards/manager"
        )

        self.assertEqual(status_code, 401)
        self.assertIsInstance(body, dict)
        self.assertIn("detail", body)

    def test_02_response_structure(self):
        status_code, dashboard = request(
            "GET",
            "/dashboards/manager",
            token=self.manager_token
        )

        self.assertEqual(status_code, 200)
        self.assertIsInstance(dashboard, dict)

        self.assertEqual(
            set(dashboard.keys()),
            {
                "summary",
                "ongoing_contests",
                "upcoming_contests",
                "recent_contests"
            }
        )

        summary = dashboard["summary"]

        self.assertEqual(
            set(summary.keys()),
            {
                "live_contests",
                "total_participants",
                "total_submissions",
                "completed_contests"
            }
        )

        for value in summary.values():
            self.assertIsInstance(value, int)
            self.assertGreaterEqual(value, 0)

        for section in (
            "ongoing_contests",
            "upcoming_contests",
            "recent_contests"
        ):
            self.assertIsInstance(dashboard[section], list)

    def test_03_only_host_contests_are_returned(self):
        status_code, dashboard = request(
            "GET",
            "/dashboards/manager",
            token=self.manager_token
        )
        self.assertEqual(status_code, 200)

        status_code, contests = request(
            "GET",
            "/contests",
            token=self.manager_token
        )
        self.assertEqual(status_code, 200)

        hosted_ids = {
            contest["id"]
            for contest in contests
            if contest.get("user_role") == "HOST"
        }

        dashboard_ids = {
            contest["contest_id"]
            for contest in (
                dashboard["ongoing_contests"]
                + dashboard["upcoming_contests"]
                + dashboard["recent_contests"]
            )
        }

        self.assertTrue(
            dashboard_ids.issubset(hosted_ids),
            "Manager dashboard returned a contest "
            "not hosted by the authenticated user"
        )

    def test_04_user_without_hosted_contests_gets_empty_state(self):
        status_code, dashboard = request(
            "GET",
            "/dashboards/manager",
            token=self.participant_token
        )

        self.assertEqual(status_code, 200)

        self.assertEqual(
            dashboard["summary"],
            {
                "live_contests": 0,
                "total_participants": 0,
                "total_submissions": 0,
                "completed_contests": 0
            }
        )

        self.assertEqual(dashboard["ongoing_contests"], [])
        self.assertEqual(dashboard["upcoming_contests"], [])
        self.assertEqual(dashboard["recent_contests"], [])

    def test_05_recent_contests_limit_and_order(self):
        status_code, dashboard = request(
            "GET",
            "/dashboards/manager",
            token=self.manager_token
        )

        self.assertEqual(status_code, 200)

        recent = dashboard["recent_contests"]
        self.assertLessEqual(len(recent), 5)

        contest_ids = [
            contest["contest_id"]
            for contest in recent
        ]

        self.assertEqual(
            contest_ids,
            sorted(contest_ids, reverse=True)
        )


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(
        ManagerDashboardTests
    )
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)