"""
Integration tests for GitHub Issue #47:
Database-native Moderator Dashboard.

Run from the project root while FastAPI is running:

    python database/tests/test_moderator_dashboard.py

Requirements:
    1. get_moderator_dashboard() has been applied to Neon.
    2. FastAPI is running at http://127.0.0.1:8000.
    3. The database contains the seeded users.
"""

import sys
import unittest

from test_manager_dashboard import login, request


class ModeratorDashboardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Seeded moderator for at least one contest.
        cls.moderator_token = login("nondiny")

        # A second valid account used to verify that results are
        # dynamically restricted to the authenticated user's roles.
        cls.secondary_token = login("satil")

    def test_01_authentication_is_required(self):
        status_code, body = request(
            "GET",
            "/dashboards/moderator"
        )

        self.assertEqual(
            status_code,
            401,
            "Request without JWT should return HTTP 401"
        )

        self.assertIsInstance(body, dict)
        self.assertIn("detail", body)

    def test_02_response_structure(self):
        status_code, dashboard = request(
            "GET",
            "/dashboards/moderator",
            token=self.moderator_token
        )

        self.assertEqual(status_code, 200)
        self.assertIsInstance(dashboard, dict)

        self.assertEqual(
            set(dashboard.keys()),
            {
                "summary",
                "ongoing_contests",
                "upcoming_contests",
                "recent_submissions"
            }
        )

        summary = dashboard["summary"]

        self.assertIsInstance(summary, dict)

        self.assertEqual(
            set(summary.keys()),
            {
                "assigned_contests",
                "live_contests",
                "total_participants",
                "total_submissions"
            }
        )

        for field in (
            "assigned_contests",
            "live_contests",
            "total_participants",
            "total_submissions"
        ):
            self.assertIsInstance(
                summary[field],
                int,
                f"{field} should be an integer"
            )

            self.assertGreaterEqual(
                summary[field],
                0,
                f"{field} should not be negative"
            )

        for section in (
            "ongoing_contests",
            "upcoming_contests",
            "recent_submissions"
        ):
            self.assertIsInstance(
                dashboard[section],
                list,
                f"{section} should be an array"
            )

    def test_03_only_moderated_contests_are_returned(self):
        status_code, dashboard = request(
            "GET",
            "/dashboards/moderator",
            token=self.moderator_token
        )
        self.assertEqual(status_code, 200)

        status_code, contests = request(
            "GET",
            "/contests",
            token=self.moderator_token
        )
        self.assertEqual(status_code, 200)
        self.assertIsInstance(contests, list)

        moderated_ids = {
            contest["id"]
            for contest in contests
            if contest.get("user_role") == "MODERATOR"
        }

        dashboard_contest_ids = {
            contest["contest_id"]
            for contest in (
                dashboard["ongoing_contests"]
                + dashboard["upcoming_contests"]
            )
        }

        submission_contest_ids = {
            submission["contest_id"]
            for submission in dashboard["recent_submissions"]
        }

        self.assertTrue(
            dashboard_contest_ids.issubset(moderated_ids),
            "Dashboard returned a contest that the user "
            "does not moderate"
        )

        self.assertTrue(
            submission_contest_ids.issubset(moderated_ids),
            "Dashboard returned a submission from a contest "
            "that the user does not moderate"
        )

        self.assertEqual(
            dashboard["summary"]["assigned_contests"],
            len(moderated_ids)
        )

    def test_04_dashboard_matches_secondary_user_roles(self):
        status_code, dashboard = request(
            "GET",
            "/dashboards/moderator",
            token=self.secondary_token
        )
        self.assertEqual(status_code, 200)

        status_code, contests = request(
            "GET",
            "/contests",
            token=self.secondary_token
        )
        self.assertEqual(status_code, 200)
        self.assertIsInstance(contests, list)

        moderated_ids = {
            contest["id"]
            for contest in contests
            if contest.get("user_role") == "MODERATOR"
        }

        self.assertEqual(
            dashboard["summary"]["assigned_contests"],
            len(moderated_ids)
        )

        dashboard_contest_ids = {
            contest["contest_id"]
            for contest in (
                dashboard["ongoing_contests"]
                + dashboard["upcoming_contests"]
            )
        }

        submission_contest_ids = {
            submission["contest_id"]
            for submission in dashboard["recent_submissions"]
        }

        self.assertTrue(
            dashboard_contest_ids.issubset(moderated_ids)
        )

        self.assertTrue(
            submission_contest_ids.issubset(moderated_ids)
        )

        if not moderated_ids:
            self.assertEqual(
                dashboard["summary"],
                {
                    "assigned_contests": 0,
                    "live_contests": 0,
                    "total_participants": 0,
                    "total_submissions": 0
                }
            )

            self.assertEqual(
                dashboard["ongoing_contests"],
                []
            )
            self.assertEqual(
                dashboard["upcoming_contests"],
                []
            )
            self.assertEqual(
                dashboard["recent_submissions"],
                []
            )

    def test_05_recent_submissions_limit_and_order(self):
        status_code, dashboard = request(
            "GET",
            "/dashboards/moderator",
            token=self.moderator_token
        )

        self.assertEqual(status_code, 200)

        recent = dashboard["recent_submissions"]

        self.assertLessEqual(
            len(recent),
            10,
            "Dashboard should return at most ten submissions"
        )

        submitted_times = [
            submission["submitted_at"]
            for submission in recent
        ]

        self.assertEqual(
            submitted_times,
            sorted(submitted_times, reverse=True),
            "Recent submissions should be newest first"
        )

    def test_06_ongoing_contests_have_monitoring_fields(self):
        status_code, dashboard = request(
            "GET",
            "/dashboards/moderator",
            token=self.moderator_token
        )

        self.assertEqual(status_code, 200)

        required_fields = {
            "contest_id",
            "title",
            "status",
            "ranking_strategy",
            "start_time",
            "freeze_time",
            "end_time",
            "leaderboard_frozen",
            "max_participants",
            "participant_count",
            "submission_count",
            "task_count"
        }

        for contest in dashboard["ongoing_contests"]:
            self.assertTrue(
                required_fields.issubset(contest.keys())
            )

            self.assertIsInstance(
                contest["leaderboard_frozen"],
                bool
            )


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(
        ModeratorDashboardTests
    )

    result = unittest.TextTestRunner(
        verbosity=2
    ).run(suite)

    sys.exit(
        0 if result.wasSuccessful() else 1
    )