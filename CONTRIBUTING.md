# Contributing

## Branching

* `main` is always releasable. Nobody pushes to `main` directly, including the owners.
* One branch per change, from `main`: `feat/<short-name>`, `fix/<short-name>`, `docs/<short-name>`, `chore/<short-name>`.
  Examples: `feat/officer-chat`, `fix/utf8-trim`.
* Open a pull request into `main`. Keep PRs small: one feature or one fix. Describe how you tested it in game.
* Merge with a merge commit (the only method enabled), so every branch keeps its full commit history on `main`.
  The branch is deleted automatically. Merging is always a person clicking the button; AI agents open and update
  PRs but never merge them.

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

* Nobody edits a version number. Both TOCs say `## Version: @project-version@` and CI keeps it that way. The
  release job computes the version from the existing git tags and stamps it into the zip it builds.
* Two channels, two presses of the **release** workflow (Actions tab -> release -> Run workflow). A person presses
  the button; agents never run `final`. `scripts/release.sh` is the same code for local use; `--dry-run` previews.
  * **Release candidate** (`rc`): run on a `release/*` branch, never on `main`. `release/0.2.0` pins the version
    and counts `rcN` up; `release/<word>` continues an open candidate series or `bump`s the last release. Feature
    branches reach it through reviewed PRs, like `main` (release branches share its protection), then press. Publishes a GitHub
    pre-release and updates the RC download link. Guild leads run it for a day on two clients in two guilds, with
    one client left on the previous stable to prove the protocol still interoperates.
  * **Latest release** (`final`): run on `main` after the release branch is merged. Promotes the rc merged into
    `main` to `v<ver>`, refusing if the addon files changed since that rc, publishes it as latest and updates the
    stable link. `no_rc` exists for small hotfixes only.
* Release notes are a changelog section in the conventional-changelog format (Features, Bug Fixes, ... each line
  linking its commit), built from the commits since the previous tag. They go on the GitHub release, on the
  download page under "What's new", and are prepended to the published
  [CHANGELOG.md](https://coreguild.github.io/CORELink/CHANGELOG.md). The copy of `CHANGELOG.md` in this repo
  is frozen; the published one is the real changelog.
* Public download links, no GitHub account needed:
  * stable: https://coreguild.github.io/CORELink/latest/CORELink.zip
  * release candidate: https://coreguild.github.io/CORELink/rc/CORELink.zip
  * landing page with both: https://coreguild.github.io/CORELink/
  Served from the `gh-pages` branch, which only the release job writes to. Older builds stay at `v/CORELink-<version>.zip`.

## Commit messages

Subjects follow [Conventional Commits](https://www.conventionalcommits.org/), because the changelog is generated
from them at release time and grouped by type:

```
feat(relay): queue messages typed before the channel joins      -> Features
fix: debug echo is off at login                                  -> Bug Fixes
perf(roster): cache rank lookups                                 -> Performance Improvements
docs: explain the officer note                                   -> Documentation
chore|ci|build|test|refactor|style: ...                          -> Maintenance
feat(protocol)!: CL5 packets                                     -> also listed under BREAKING CHANGES
```

Scope is optional and should be a player-recognisable area (`relay`, `officer`, `nicknames`, `setup`, `ui`).
A subject without a type still appears, under "Other Changes". Imperative mood, lower case, no trailing period.
Body explains why if it is not obvious.
If an AI agent wrote the change, say so in the commit body, e.g. `Co-Authored-By: <agent name>`.

## Code style

Two-space indent, Lua 5.1 compatible (the game's Lua), no globals except the addon's slash commands and
`CORELinkDB`. Guard every API that may not exist on this client with `if X then`.

The code is written to be read without an editor's help, and `tests/run.sh` enforces the measurable part:

* A file is under 400 lines and owns one concern; `docs/ARCHITECTURE.md` lists them. A new file goes into both
  TOCs in load order and starts with `local _, NS = ...`.
* A function is under 40 lines, does one thing its name states, and is findable by grepping for what triggers
  it: the packet name, the event, the `/cl` command.
* A line is under 120 characters and holds one statement. No `if x then a; b end` on one line.
* Shared state and functions live on `NS` with a comment saying what the key means; see the registries in
  `docs/ARCHITECTURE.md` for adding a command, a packet handler or an event without touching the dispatcher.

## License

CORELink is released under the ISC License (see `LICENSE`). By contributing you agree that your contribution
is licensed the same way.
