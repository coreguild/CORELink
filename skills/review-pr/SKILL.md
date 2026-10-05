---
name: review-pr
description: Review a CORELink pull request for gameplay impact before merge, using agents/review-checklist.md. Use when asked to review, check, or approve a PR, or before merging anything.
---

Argument: a PR number or branch name. Default: the current branch's open PR.

1. `gh pr view <n> --json title,body,files` and `gh pr diff <n>`. Read the whole diff, not just the Lua.
2. Check the PR body against `.github/pull_request_template.md`: feature notes filled in, tests checklist
   honest, open questions answered. If the notes are vague, ask the author the specific missing question
   instead of guessing; that is a "needs changes".
3. Walk `agents/review-checklist.md` top to bottom against the diff. For every blocker, find the exact line.
4. Run `gh pr checks <n>`; both `tests` and `game-version` must be green. If `game-version` is red, the game
   patched: the fix is an interface bump PR, not a merge.
5. Check out the branch and run `tests/run.sh` yourself. Read the harness diff: a new feature with no new
   `check(...)` is "needs changes".
6. Post the review with `gh pr review <n> --comment --body ...` (or `--approve` when clean) in the report format
   from the checklist. Never merge; say the PR is ready to merge and let a human click it.
