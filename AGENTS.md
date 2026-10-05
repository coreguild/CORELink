# Rules for AI agents working in this repository

This file is read by Claude Code, Codex, Cursor and similar tools. Humans: see `CONTRIBUTING.md`.

Start by reading `agents/README.md`, then follow the three documents it links:

* `agents/branching.md`  - how to create branches, commit, and open PRs. Never commit to `main`.
* `agents/testing.md`    - how to test without the game (`tests/run.sh`) and in the game (`scripts/install-local.sh`, `/reload`).
* `agents/wow-api-gotchas.md` - constraints of the WoW Lua environment that have already cost us days. Read before touching chat or networking code.
* `agents/feature-requests.md` - how to turn a feature request into a clear note, questions, tests, and a PR.
* `agents/review-checklist.md` - the pre-merge review for gameplay impact. Every PR gets this review before merge.

Procedures you can follow step by step live in `skills/` (`start-feature`, `test-addon`, `install-addon`, `release`).
Before editing anything, run the `start-feature` skill (or its commands) so you are on a `feat/`, `fix/`, `docs/` or `chore/` branch.

Hard rules:

1. Run `tests/run.sh` before claiming a change works. If it fails, fix it or say so.
   Every new or changed behaviour needs a `check(...)` in `tests/harness.lua` that fails without the change.
   CI runs the same script on every pull request and `main` will not accept a PR whose tests fail.
2. For a feature request, restate it, ask about anything ambiguous, and fill in the PR template's
   "Feature notes" section completely (see `agents/feature-requests.md`). Add a CHANGELOG line.
3. You cannot run the game. Say "not verified in game" for anything the mock harness does not cover.
4. Do not change the wire protocol (`PROTO`, field order, separator) without bumping the version and keeping old versions readable.
5. Do not add dependencies or build steps. The addon is one Lua file plus two TOC files.
6. Keep the addon Lua 5.1 compatible and guard any API that may be missing on this client.
7. Before anything is merged, run the `review-pr` skill (or walk `agents/review-checklist.md`) and post the result
   on the PR. CI also fails the PR when the TOC interface number no longer matches the live game client.
8. **Agents never merge.** Do not run `gh pr merge`, click merge, enable auto-merge, or push to `main` by any other
   route, even when asked to "finish it" or "get it in". Say the PR is ready and stop. Merging is a human button
   press. The same applies to `scripts/release.sh final`: run it only when a human explicitly asks for that release.
