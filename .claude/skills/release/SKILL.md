---
name: release
description: Prepare or cut a CORELink release candidate, or explain how to promote one, using the release workflow or scripts/release.sh. Use when asked to release, ship, cut an RC, promote an RC, or package the addon.
---

Releases are a human button press: GitHub -> Actions -> **release** -> **Run workflow** -> pick the branch.
Inputs: `channel` (`rc`, `final`, `site`), `bump` (`auto`, `patch`, `minor`, `major`; rc only), `notes`, `no_rc`.
`notes` is one paragraph shown above the generated changelog. If it was left empty or needs a correction, edit the
release body on GitHub and press the button with `site`: the page's notes follow the GitHub release.
RCs are cut from a `release/*` branch, never from `main`; `final` runs on `main` after that branch is merged.
Nobody edits version numbers. The job takes the version from the branch name (`release/0.2.0` -> `v0.2.0-rcN`) or
computes it from the git tags (`release/<word>`, and `final`), stamps it into the zip (a candidate says
`0.2.0-rcN` in game and is `CORELink-0.2.0-rcN.zip`; the final is rebuilt as `0.2.0`, `CORELink-0.2.0.zip`), tags,
publishes the GitHub (pre-)release with a conventional-changelog section built from the commits since the previous
tag, prepends it to CHANGELOG.md on the download site, and shows it under the channel on the page. `--dry-run`
prints the section so the user can read it first; if commits lack `feat:`/`fix:` types they land under "Other Changes".

What an agent does:
1. Make or update the release branch. New release: `git fetch origin && git switch -c release/<version> origin/main`
   with the version the merged and pending PRs call for (patch, minor or major over the last final tag). Existing
   release: `git switch release/<version> && git pull`. Then `git merge origin/<feature-branch>` for each branch that
   belongs in this release, merged into `main` or not, resolve conflicts, `tests/run.sh`, and push. Merging into a
   release branch is allowed; merging into `main` is not.
2. `scripts/release.sh rc --dry-run` on that branch and show the user the line "branch: ... this: v<ver>-rcN". That
   is the version the button will produce; the next line, "stamped version: ...", is what testers will see in
   `/cl report`. The dry run refuses on `main` or any non-release branch.
3. If the user asked for an RC, an agent may run `scripts/release.sh rc` locally on the pushed release branch, or
   tell the user to press the button with that branch selected and `rc`. Tell them the RC link
   (https://coreguild.github.io/CORELink/rc/CORELink.zip) and the soak test: a day on two clients in two
   different guilds, one `/reload`, one fresh login, one client still on the previous stable to prove protocol
   compatibility.
4. If the RC had problems: fix via normal PRs into `main`, merge the fix branch (or `main`) into the release branch,
   push, `rc` again; it becomes `rcN+1` of the same version.
5. When the RC is good: open a PR from the release branch into `main` (`gh pr create --base main`), say it is ready,
   and stop. A human merges it. Never run `final`. Then tell them to press the button on `main` with `final` (or
   run `scripts/release.sh final` themselves) and give them the stable link
   (https://coreguild.github.io/CORELink/latest/CORELink.zip).
6. If `final` fails with "the addon on main differs from v<ver>-rcN", something touching `CORELink/` was merged
   after the RC: merge `main` into the release branch, cut a new RC, test, merge, then `final`. Do not use `no_rc`
   to get around it.

The job and the script run the tests and the game-version check and stop on any failure. Do not bypass them with
manual `git tag` or `gh release` commands.
