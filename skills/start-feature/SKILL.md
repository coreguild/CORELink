---
name: start-feature
description: Create a correctly named branch from the latest main before changing CORELink. Use at the start of any feature, fix, or docs change, before editing files.
---

Arguments: a short description of the change, e.g. `officer chat bridging` or `fix utf8 trim`.

1. Decide the type: `feat` for new behaviour, `fix` for a bug, `docs` for documentation only, `chore` for tooling or housekeeping.
2. Make a short kebab-case name from the description, 2-4 words: `officer-chat`, `utf8-trim`.
3. Make sure the tree is clean (`git status --short`). If there are uncommitted changes, stop and ask whether to stash or commit them; never start a branch with someone else's half-done work in it.
4. Run:
   ```
   git fetch origin
   git switch -c <type>/<name> origin/main
   ```
5. Confirm with `git status -sb` that you are on the new branch tracking nothing yet, then start the work.
6. When the work is done: `tests/run.sh`, commit with an imperative subject and a `Co-Authored-By:` trailer naming the agent, `git push -u origin <type>/<name>`, and open a pull request into `main` with `gh pr create --fill` (edit the body to say how it was tested, or "not verified in game").

Never: commit on `main`, reuse a merged branch, or put two unrelated changes on one branch.
