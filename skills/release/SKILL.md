---
name: release
description: Cut a CORELink release zip from main after bumping the TOC version. Use when asked to release, ship, or package the addon.
---

1. Confirm you are on `main` and up to date: `git switch main && git pull`.
2. Confirm `## Version:` is identical in `CORELink/CORELink.toc` and `CORELink/CORELink_Camelot.toc` and was bumped in the PR being released. If not, open a `chore/bump-<version>` PR first; never commit to `main`.
3. Run `scripts/check-game-version.sh`; if the live client's interface number is not in both TOCs, stop and open an interface-bump PR first.
4. Run `scripts/package.sh`. It runs the tests and writes `dist/CORELink-<version>.zip`.
5. Tag and publish: `git tag v<version> && git push origin v<version>`, then `gh release create v<version> dist/CORELink-<version>.zip --title "CORELink <version>" --notes "<what changed>"`.
6. Remind the user that every linked guild must run the same version, and that protocol changes need the receive-side compatibility promised in `CONTRIBUTING.md`.
