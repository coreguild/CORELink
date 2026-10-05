# Rules for AI agents working in this repository

This file is read by Claude Code, Codex, Cursor and similar tools. Humans: see `CONTRIBUTING.md`.

Start by reading `agents/README.md`, then follow the three documents it links:

* `agents/branching.md`  - how to create branches, commit, and open PRs. Never commit to `main`.
* `agents/testing.md`    - how to test without the game (`tests/run.sh`) and in the game (`scripts/install-local.sh`, `/reload`).
* `agents/wow-api-gotchas.md` - constraints of the WoW Lua environment that have already cost us days. Read before touching chat or networking code.

Procedures you can follow step by step live in `skills/` (`start-feature`, `test-addon`, `install-addon`, `release`).
Before editing anything, run the `start-feature` skill (or its commands) so you are on a `feat/`, `fix/`, `docs/` or `chore/` branch.

Hard rules:

1. Run `tests/run.sh` before claiming a change works. If it fails, fix it or say so.
2. You cannot run the game. Say "not verified in game" for anything the mock harness does not cover.
3. Do not change the wire protocol (`PROTO`, field order, separator) without bumping the version and keeping old versions readable.
4. Do not add dependencies or build steps. The addon is one Lua file plus two TOC files.
5. Keep the addon Lua 5.1 compatible and guard any API that may be missing on this client.
