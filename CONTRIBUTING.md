# Contributing

## Branching

* `main` is always releasable. Nobody pushes to `main` directly, including the owners.
* One branch per change, from `main`: `feat/<short-name>`, `fix/<short-name>`, `docs/<short-name>`, `chore/<short-name>`.
  Examples: `feat/officer-chat`, `fix/utf8-trim`.
* Open a pull request into `main`. Keep PRs small: one feature or one fix. Describe how you tested it in game.
* Squash-merge. Delete the branch after merging.

## Pull requests

The PR template asks for feature notes (player-facing behaviour, commands, config and protocol impact, version) and
a test checklist. Fill it in; an empty template is the most common reason a PR gets sent back. No reviewer approval
is required, but CI (`tests/run.sh`) must pass before the merge button works, and `CHANGELOG.md` gets a line for
every user-visible change.

## Before you push

1. `tests/run.sh` passes (syntax check plus the mock harness).
2. You loaded the addon in the Forever client and tried the change. Note what you did in the PR.
3. If you changed the wire protocol, read `agents/wow-api-gotchas.md` first and bump the `PROTO` version.
   Receivers must keep accepting older protocol versions for at least one release.
4. No `print` left behind; use `/cl` status output for diagnostics.

## Versioning and releases

* Version lives in `## Version:` in both TOC files. Bump it in the PR that ships a user-visible change
  (patch for fixes, minor for features; we are pre-1.0).
* To release: merge to `main`, then `scripts/package.sh`, then upload `dist/CORELink-<version>.zip` as a
  GitHub Release tagged `v<version>`. Everyone in every linked guild should run the same version.

## Commit messages

Short imperative subject (`Fix UTF-8 trim at packet boundary`), body explains why if it is not obvious.
If an AI agent wrote the change, say so in the commit body, e.g. `Co-Authored-By: <agent name>`.

## Code style

Two-space indent, Lua 5.1 compatible (the game's Lua), no globals except the addon's slash commands and
`CORELinkDB`. Guard every API that may not exist on this client with `if X then`.
