# Git workflow (read once, follow always)

## One-time setup (project owner)
1. GitHub → New repository → name `rewind-dba-project` → **Public** (so Claude can clone it for review) → Create.
2. Settings → Collaborators → add Faiza, Mahnoor, Hadiqa, Abdullah.
3. Settings → Branches → Add rule for `main` → tick **Require a pull request before merging** and
   **Require approvals (1)** → nobody can push directly to `main`.
4. In this project folder:
   ```
   git remote add origin https://github.com/<owner>/rewind-dba-project.git
   git push -u origin main
   ```

## Every member
```
git clone https://github.com/<owner>/rewind-dba-project.git
cd rewind-dba-project
git checkout -b feature/<yourname>-<task>        # e.g. feature/hadiqa-restore-inserted
# ... work, then:
git add .
git commit -m "feat(recovery): add restore_inserted procedure"
git push -u origin feature/<yourname>-<task>
```
Then open GitHub → **Compare & pull request** → base `main` ← your branch → fill the template below.

Daily habit: `git fetch origin && git rebase origin/main` before you push.

## Rules
- Work only on **your own branch**; never push to `main`.
- One small task = one pull request. Commit often with clear messages (`feat:`, `fix:`, `docs:`, `test:`).
- Every SQL change must run from a clean database using `run_all.sql` and pass `08_tests.sql`.
- After pushing, send the PR link in the group → review → fix comments → owner merges.

## Pull request template
```
What I did:
Files changed:
How I tested it (paste the SQL*Plus output / screenshot):
Anything I am unsure about:
```

## Getting a review from Claude
- Public repo: send the PR link or branch name. Claude can clone it and run `git diff main...<branch>`.
- Private repo: paste the output of `git diff main...<branch>` (or upload the changed files).
