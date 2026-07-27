# Profiles and Statistics Subsystem Documentation

This document explains the technical design and database-native implementation of User Profiles, Activity Graphs, Score Progressions, and Contest Analytics in **ContestDB**.

---

## 1. Design Philosophy: Thin-Tier (Database-Native)
In alignment with the ContestDB architectural mandate, the Python API gateway performs no business logic or statistical aggregates. Instead:
- All queries group, slice, filter, and calculate metrics inside PostgreSQL.
- Time-series buckets are calculated natively in SQL using the `date_bin` command.
- Standing recalculations are computed inside SQL using Window functions and LATERAL joints.
- Scoring rules (such as max-score thresholds or verdict aggregations) are resolved inside stored PL/pgSQL functions.

---

## 2. Database Objects & Calculation Logic

### A. User Profile Statistics (`get_user_profile_stats`)
This function aggregates a user's entire submission history:
- **Total Submissions**: Count of all submissions.
- **Total Contests Joined**: Count of contests user is enrolled in.
- **Unique Tasks Attempted**: Count of distinct tasks user has made submissions for.
- **Fully Completed Tasks**: Count of tasks where user's maximum score matches or exceeds the task's maximum possible score (`score >= max_score`).
- **Average & Max Score**: Statistical aggregates of `score` for completed runs.
- **Verdict Breakdown**: Dynamic grouping of verdict strings and their counts returned as a single `JSONB` object (e.g. `{"ACCEPTED": 4, "WRONG_ANSWER": 2}`).

```sql
CREATE OR REPLACE FUNCTION get_user_profile_stats(p_user_id INT)
RETURNS TABLE (
    total_submissions INT,
    total_contests_joined INT,
    unique_tasks_attempted INT,
    fully_completed_tasks INT,
    average_score NUMERIC,
    max_score_single NUMERIC,
    verdict_breakdown JSONB
)
```

### B. User Activity Graph (`get_user_activity_graph`)
Aggregates submission counts per calendar date across the user's entire history, adjusted to UTC:
```sql
SELECT DATE(submitted_at AT TIME ZONE 'UTC') AS act_date, COUNT(*)::INT
FROM submissions
WHERE user_id = p_user_id
GROUP BY act_date;
```

### C. Contest Standing History (`get_user_contest_history`)
Returns all contests a user enrolled in. For contests where the user was a `PARTICIPANT`, it joins with the dynamic time-aware leaderboard standings using a `LATERAL` function call to retrieve their rank and score. For `HOST` or `MODERATOR` enrollments, it returns `NULL` for rank/score.

### D. Contest Submission Timeline (`get_contest_submission_timeline`)
To draw an activity timeline chart, we bin submissions during the contest duration. The time stride (granularity) of the chart is automatically chosen based on the contest's duration:
- Duration $\le$ 6 hours $\implies$ 10-minute stride
- Duration $\le$ 24 hours $\implies$ 30-minute stride
- Duration $\le$ 7 days $\implies$ 3-hour stride
- Duration > 7 days $\implies$ 1-day stride

Bins are aligned to the contest start time using PostgreSQL's `date_bin` function:
```sql
date_bin(v_stride, submitted_at, v_start) AS b_start
```

### E. Participant Cumulative Score Progression (`get_participant_score_progression`)
Calculates the growth of a user's total score over the duration of the contest. For each of the user's submissions, a subquery calculates the cumulative contest score at that exact timestamp:
- For `SUM` contests, it sums the user's best score for each task up to that timestamp.
- For `MAX` contests, it selects the maximum score achieved on any submission up to that timestamp.

---

## 3. Scoreboard Freeze Rules
To prevent public leakage of standing statistics during a scoreboard freeze, the functions:
- `get_contest_statistics`
- `get_contest_submission_timeline`

Honor the `freeze_time` boundary:
- If called with `p_as_admin = FALSE` and the current time is before the contest end time, they only include submissions where `submitted_at < freeze_time`.
- If called with `p_as_admin = TRUE` or if the contest has already ended, they calculate statistics using all submissions.
- The API gateway resolves this automatically by checking the user's role in the `enrollments` table before calling the database procedures.
