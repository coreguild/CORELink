---
name: self-review
description: Review your own branch before calling a PR ready: tests, the mutation check, an independent code review of the diff, fixes for confirmed findings, and the verdict posted on the PR. Use when a change is finished, before opening or updating a pull request, or when asked to self-review.
---

No second person reviews PRs on this project. The ruleset requires green CI, not an approval, so the author's own
review is the review. It has to be independent of the session that wrote the code, bounded, and on the record.

1. `tests/run.sh`, then `tests/mutation.sh origin/main`. If `CORELink/` changed, at least one harness check
   must fail against `main`'s addon files; if none does, the change has no check yet. Fix that first.
2. Independent review of the diff. Run the `code-review` skill at level `high` on the branch: it gives fresh
   reviewers the diff and nothing of your reasoning. Its findings are claims; confirm each against the code before
   acting on it. Then walk `agents/review-checklist.md` against the diff as `.claude/skills/review-pr/SKILL.md` step 3 says.
   If prose changed (README, docs, agent rules, skills, Lua or shell comments, the PR body, commit subjects), read
   `.claude/skills/unslop/SKILL.md` and apply it to the changed lines. It is manual-only, so it is not in the skill
   list; reading the file is how it runs. A prose finding is fixed in place and needs no harness check.
3. For each confirmed finding: fix it, add a harness `check(...)` that fails without the fix, and rerun step 1.
   A finding you decide not to fix goes in the PR body under "Open questions" with the reason. At most two
   rounds; after that, stop and list what is left in the PR body rather than polishing further.
4. Post the verdict as `.claude/skills/review-pr/SKILL.md` step 6 says (`gh pr review <n> --comment`, the checklist's
   report format). This comment is the review record.
5. Say "PR #n is ready to merge: CI green, self-review posted" and stop. Never merge.

Every few weeks, or after editing the checklist, run `tests/review-evals/run.py` to measure the reviewer against
past bugs. A miss means the checklist needs a line, not a longer prompt.
