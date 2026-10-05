# Contributing

## Branching

* `main` is always releasable. Nobody pushes to `main` directly, including the owners.
* One branch per change, from `main`: `feat/<short-name>`, `fix/<short-name>`, `docs/<short-name>`, `chore/<short-name>`.
  Examples: `feat/officer-chat`, `fix/utf8-trim`.
* Open a pull request into `main`. Keep PRs small: one feature or one fix. Describe how you tested it in game.
* Squash-merge. Delete the branch after merging. Merging is always a person clicking the button; AI agents open
  and update PRs but never merge them.

## Pull requests

The PR template asks for feature notes (player-facing behaviour, commands, config and protocol impact, version) and
a test checklist. Fill it in; an empty template is the most common reason a PR gets sent back. No reviewer approval
is required, but CI must pass before the merge button works (`tests/run.sh`, and the TOC interface number must match
the live game client), every PR gets the gameplay-impact review in `agents/review-checklist.md`, and `CHANGELOG.md` gets a line for
every user-visible change.

## Before you push

1. `tests/run.sh` passes (syntax check, luacheck, and the mock harness).
2. You loaded the addon in the Forever client and tried the change. Note what you did in the PR.
3. If you changed the wire protocol, read `agents/wow-api-gotchas.md` first and bump the `PROTO` version.
   Receivers must keep accepting older protocol versions for at least one release.
4. No `print` left behind; use `/cl` status output for diagnostics.

## Versioning and releases

* Version lives in `## Version:` in both TOC files. Bump it in the PR that ships the first user-visible change of
  the next version (patch for fixes, minor for features; we are pre-1.0), and start that version's CHANGELOG section.
  The TOC never carries an "rc" suffix; the same zip that passed RC is the one that ships.
* Two channels, driven by `scripts/release.sh` from an up-to-date `main`:
  * **Release candidate**: `scripts/release.sh rc` tags `v<ver>-rcN` (next free N), publishes a GitHub pre-release,
    and updates the RC download link. Guild leads run it for a day on two clients in two guilds, with one client left
    on the previous stable to prove the protocol still interoperates. Problems -> normal fix PRs -> `rc` again.
  * **Latest release**: `scripts/release.sh final` tags `v<ver>` on the same commit as the RC, publishes the GitHub
    release as latest, and updates the stable download link. `--no-rc` exists for small hotfixes only.
* Public download links, no GitHub account needed:
  * stable: https://core-wow-community.github.io/CORELink/latest/CORELink.zip
  * release candidate: https://core-wow-community.github.io/CORELink/rc/CORELink.zip
  * landing page with both: https://core-wow-community.github.io/CORELink/
  These are served from the `gh-pages` branch, which only `scripts/release.sh` writes to. Older builds stay at
  `v/CORELink-<version>.zip`.

## Commit messages

Short imperative subject (`Fix UTF-8 trim at packet boundary`), body explains why if it is not obvious.
If an AI agent wrote the change, say so in the commit body, e.g. `Co-Authored-By: <agent name>`.

## Code style

Two-space indent, Lua 5.1 compatible (the game's Lua), no globals except the addon's slash commands and
`CORELinkDB`. Guard every API that may not exist on this client with `if X then`.
