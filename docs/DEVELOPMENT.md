# Development

New here? Start with [ONBOARDING.md](../ONBOARDING.md). Branch and commit rules are in
[CONTRIBUTING.md](../CONTRIBUTING.md); how the code is organised is in [ARCHITECTURE.md](ARCHITECTURE.md).
AI agents (and people using one) read [AGENTS.md](../AGENTS.md) and `agents/`.

## Repository layout

| Path | What it is |
|---|---|
| `CORELink/` | The addon: fourteen Lua files and two TOCs. This folder is what goes into `Interface/AddOns/`. |
| `tests/` | `run.sh` runs everything below without the game. `harness.lua` is the mock WoW API, `size.sh` the size limits, `site-render.sh` the download page test. |
| `scripts/install-local.sh` | Symlinks the addon into your WoW client so edits are live after `/reload`. |
| `scripts/package.sh` | Builds `dist/CORELink-<version>.zip`, stamping the version into the TOCs, after running tests. |
| `scripts/release.sh` | `rc` / `final` / `site`: tags, GitHub pre-release or release, and the download page on `gh-pages`. Run by the **release** workflow button, or locally. |
| `scripts/render-site.sh` | Renders `site/index.template.html` with the current channel versions and notes. |
| `scripts/check-game-version.sh` | Compares the TOC `## Interface:` numbers with the live client version. CI runs it on every PR and every 6 hours. |
| `site/` | Template and stylesheet for the download page. Never edited on `gh-pages` by hand. |
| `docs/` | This folder: commands, troubleshooting, architecture, development. |
| `agents/`, `skills/` | Rules and step-by-step procedures for AI agents: branching, testing, gotchas, review, release. |

## Everyday commands

```
scripts/install-local.sh            # link CORELink/ into the Forever client (macOS default path), then /reload in game
tests/run.sh                        # everything CI runs: syntax, luacheck, size limits, mock harness, site render
scripts/package.sh                  # tests + dist/CORELink-<version>.zip
scripts/release.sh rc --dry-run     # what the next release-candidate press would produce
```

Needs a Lua interpreter and luacheck: macOS `brew install lua luacheck`; Windows `winget install DEVCOM.Lua`;
Linux `apt install lua5.4 lua-check`.

## Tests

`tests/run.sh` is the single gate, locally and in CI:

1. `luac -p` on every addon file.
2. `luacheck` with the WoW globals listed in `.luacheckrc`. Undefined globals, typos in API names, unused
   variables and lines over 120 characters fail it. The harness is checked too, without the line limit.
3. `tests/size.sh`: no file over 400 lines, no function over 40 lines.
4. `tests/harness.lua`: a mock of the WoW API in plain Lua that loads the real addon files in TOC order and
   drives them through login, Guild Info parsing, channel join, the text relay out and in, the courier path and
   fan-out, the community mirror, echo, filters, nicknames and commands. Every
   check prints `PASS` or `FAIL` with a sentence saying what it claims, and the script exits non-zero on any
   failure.
5. `tests/site-render.sh`: the download page renders with awkward release notes.

When you change behaviour, add a `check(...)` to the harness that fails without the change. Mock only what the
addon calls, in the harness, never in the addon. If you use a WoW API that is not in `.luacheckrc`, add it to
`read_globals` in the same PR and guard the call with `if X then`.

The harness cannot know what the game server does. Anything that depends on it (delivery across realms, what
`/who` returns, what a community hands back) is "not verified in game" until a person tries it. See
[TROUBLESHOOTING.md](TROUBLESHOOTING.md) for the in-game test steps.

## How a change gets to players

Branch, pull request, CI, then a release branch and two buttons: release candidate from the release branch,
release from `main` once the branch is merged. Nobody edits a version number or a changelog; the release button
computes the version from the branch name or the existing tags and builds the notes from the commits since the
last tag.

```
feat/x ──┐
feat/y ──┴─merge──▶ release/0.2.0 ──[release: rc]──▶ v0.2.0-rc1 (pre-release, rc/CORELink.zip)
                        │                                │ testers run it for a day; fixes merge in, rc again
                        └──PR──▶ main ──[release: final]─┴──▶ v0.2.0 (latest, latest/CORELink.zip)
```

1. **Branch.** `git switch -c feat/<name> main` (`fix/`, `docs/`, `chore/` for other kinds). One change per
   branch, under about 200 lines of diff. Commit subjects use Conventional Commits (`feat(scope): ...`,
   `fix: ...`); the changelog is generated from them.

2. **Pull request into `main`.** The template asks for feature notes (player-facing behaviour, commands, Guild
   Info and wire-protocol impact) and how it was tested. CI runs two required checks: `tests` (`tests/run.sh`
   plus a check that the TOCs still carry `@project-version@` and that a build stamps a version) and
   `game-version` (`scripts/check-game-version.sh` against Blizzard's version server). The `protect-main`
   ruleset blocks merging until both are green and the branch is up to date with `main`. The gameplay-impact
   review in `agents/review-checklist.md` is posted as a comment.

3. **Merge.** A person clicks the button; agents never merge. Merge commits only, so the branch's history lands
   on `main`; the branch is deleted automatically.

4. **Release branch and candidate.** Create `release/<version>` from `main` and merge in the feature branches
   that belong to that release, merged into `main` or not. Push it. Then GitHub -> Actions -> **release** ->
   **Run workflow**, pick the release branch, `rc`. The job re-runs the checks, takes the version from the branch
   name (`release/0.2.0` -> `v0.2.0-rcN`, N counting up), stamps it into the TOCs inside the zip, creates the
   tag, publishes a GitHub pre-release with the changelog section for that tag, and pushes `rc/CORELink.zip`,
   `v/CORELink-<ver>.zip`, the notes, `CHANGELOG.md` and the re-rendered page to `gh-pages`. Testers run the RC
   for a day on two clients in two guilds, with one client left on the previous stable to prove the protocol
   still interoperates. Fixes go through normal PRs, are merged into the release branch too, and `rc` again
   gives `rcN+1`. `rc` is refused on `main`.

   Both `rc` and `final` also upload the zip to CurseForge, as a beta or a release file, when the repository has
   the `CURSEFORGE_API_KEY` secret and the `CURSEFORGE_PROJECT_ID` variable (Settings -> Secrets and variables ->
   Actions). Game versions come from the TOC interface numbers; `CURSEFORGE_GAME_VERSIONS` overrides them with
   the names CurseForge uses. Without the secret the step says it skipped and the release is unaffected.
   The **curseforge-check** button (Actions -> curseforge-check -> Run workflow) proves the key and the version
   names without releasing anything; `scripts/curseforge-upload.sh --dry-run` shows what a release would send.
   Give that button a tag (`v0.2.0`) and it uploads that existing GitHub release instead, for a release that
   shipped before CurseForge was set up or whose upload step failed. One press per tag: CurseForge keeps every
   upload.

5. **Release.** Open a PR from the release branch into `main` and merge it, then the same button on `main` with
   `final`. It finds the newest unreleased rc tag merged into `main` and refuses unless the addon files on
   `main` are identical to that rc, so what ships is what was tested (`no_rc` exists for a small hotfix that
   touches neither the relay path nor the protocol). It tags `v<ver>`, publishes the GitHub release as latest,
   and updates `latest/CORELink.zip` and the page. Everyone in every linked guild should run the same version.

Permanent download URLs: `latest/CORELink.zip` (stable), `rc/CORELink.zip` (candidate), `v/CORELink-<ver>.zip`
(every build), `channels.json` (`{"stable","rc","updated"}` for bots). Only the release job writes to
`gh-pages`. GitHub Pages serves that branch publicly even though the source is private.
