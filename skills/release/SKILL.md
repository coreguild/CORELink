---
name: release
description: Prepare or cut a CORELink release candidate, or explain how to promote one, using the release workflow or scripts/release.sh. Use when asked to release, ship, cut an RC, promote an RC, or package the addon.
---

Releases are a human button press: GitHub -> Actions -> **release** -> **Run workflow**.
Inputs: `channel` (`rc`, `final`, `site`), `bump` (`auto`, `patch`, `minor`, `major`; rc only), `notes`, `no_rc`.
Nobody edits version numbers. The job computes the next version from the git tags, stamps it into the zip, tags,
publishes the GitHub (pre-)release with notes generated from merged PR titles, and updates the public download page.

What an agent does:
1. `git switch main && git pull`, then `scripts/release.sh rc --dry-run` (add `--bump minor|major` if the merged
   PRs say so) and show the user the line "last final ... this: v<ver>-rcN". That is the version the button will produce.
2. If the user asked for an RC, an agent may run `scripts/release.sh rc` locally or tell the user to press the button
   with `rc`. Tell them the RC link (https://core-wow-community.github.io/CORELink/rc/CORELink.zip) and the soak
   test: a day on two clients in two different guilds, one `/reload`, one fresh login, one client still on the
   previous stable to prove protocol compatibility.
3. Never run `final`. When the user says the RC is good, tell them to press the button with `final` (or run
   `scripts/release.sh final` themselves) and give them the stable link
   (https://core-wow-community.github.io/CORELink/latest/CORELink.zip).
4. If the RC had problems: fix via normal PRs, then `rc` again; it becomes `rcN+1` of the same version.
5. If `final` fails with "no v*-rc* tag points at this commit", a PR was merged after the RC: cut a new RC, do not
   use `no_rc` to get around it.

The job and the script run the tests and the game-version check and stop on any failure. Do not bypass them with
manual `git tag` or `gh release` commands.
