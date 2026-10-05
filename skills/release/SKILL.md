---
name: release
description: Cut a CORELink release candidate or final release from main with scripts/release.sh, publishing GitHub releases and the public download page. Use when asked to release, ship, cut an RC, promote an RC, or package the addon.
---

Two channels, one script, run from an up-to-date `main` with a clean tree:

- `scripts/release.sh rc`    -> tag `v<ver>-rcN`, GitHub pre-release, RC download link updated.
- `scripts/release.sh final` -> tag `v<ver>`, GitHub latest release, stable download link updated.
  Refuses unless an rc tag points at the same commit; `--no-rc` is allowed only for a small hotfix that touches
  neither the relay path nor the protocol, and the user must say so.
- `scripts/release.sh site`  -> re-render the download page without releasing.

`<ver>` is read from `## Version:` in `CORELink/CORELink.toc`. It never contains "rc".

Steps:
1. `git switch main && git pull`. Confirm `## Version:` is identical in both TOCs and is the version being released;
   if it still shows the previous release, stop: a version bump PR is needed first. Never commit to `main`.
2. Confirm `CHANGELOG.md` has a section for this version. Pass its text with `--notes "..."`.
3. For a new version: `scripts/release.sh rc`. Tell the user the RC link
   (`https://core-wow-community.github.io/CORELink/rc/CORELink.zip`) and that it needs a day of play on two clients in
   two different guilds, including one `/reload` and one fresh login, and one client still on the previous stable
   to prove protocol compatibility.
4. After the user confirms the RC is good: `scripts/release.sh final`. Give them the stable link
   (`https://core-wow-community.github.io/CORELink/latest/CORELink.zip`) and the CHANGELOG text to announce.
5. If the RC had problems: fix via normal PRs, then `scripts/release.sh rc` again; it picks the next rc number.

The script runs the tests and the game-version check itself and stops on any failure. Do not bypass it with manual
`git tag` or `gh release` commands.
