# Developer Workflow &  Routine

This guide defines the exact step-by-step workflow that any team member must follow when sitting down to work on ContestDB. This system ensures git histories, issue trackers, and the Kanban board are aligned.

---

## Step 1: Claiming Work (GitHub Project Board)
Before writing any code:
1. Open the **GitHub Project Board** for the repository.
2. Review the **To Do** column. Find a task that is unassigned or assigned to you.
3. If unassigned, assign it to yourself.
4. Drag the issue card from **To Do** to **In Progress**.

---

## Step 2: Preparing Your Environment
Always branch off the latest codebase:
1. Open your terminal in the project directory.
2. Switch to main: `git checkout main`
3. Fetch the latest updates: `git pull origin main`
4. Create your feature branch: `git checkout -b feat/issue-<number>-<short-description>`
   * *Example:* `git checkout -b feat/issue-4-db-schema`

---

## Step 3: Coding and Verification
Write code in your feature branch.
1. If you are using an AI assistant, it will read `.agents/AGENTS.md` automatically. Ensure it writes code conforming to those rules (e.g. business logic in PostgreSQL, routers in FastAPI).
2. Test your changes locally (run database seeds, execute local server tests, verify database state).

---

## Step 4: Committing Code
Keep commits concise and meaningful:
1. Stage your changes: `git add .`
2. Commit with Conventional Commits structure and reference the issue:
   * *Example:* `git commit -m "feat(db): add submissions table schema #4"`

---

## Step 5: Pushing and Creating a Pull Request (PR)
1. Push your branch to the remote repository:
   * *Example:* `git push origin feat/issue-4-db-schema`
2. Go to your GitHub repository in the browser.
3. Click **Compare & pull request**.
4. In the PR description, include the magic keyword:
   ```markdown
   Closes #4
   ```
5. Assign at least one team member as a **Reviewer**.

---

## Step 6: Review, Merge, and Automation
Once the PR is created, the system triggers the following automation:
1. The GitHub Project card for the issue moves automatically to **In Review**.
2. The assigned reviewer inspects your code. If changes are requested, commit them directly to your branch.
3. Once approved, the reviewer or author clicks **Squash and Merge** (to keep history clean).
4. GitHub automatically:
   * Closes Issue `#4`.
   * Moves the issue card to **Done**.
   * Merges your code into `main`.
5. Locally, clean up your workspace:
   * `git checkout main`
   * `git pull origin main`
   * `git branch -d feat/issue-4-db-schema` (deletes local branch)
