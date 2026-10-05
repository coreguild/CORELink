---
name: install-addon
description: Put the working copy of CORELink into a local World of Warcraft client for manual testing with /reload.
---

1. Run `scripts/install-local.sh`. It links `CORELink/` into `_classic_beta_/Interface/AddOns/CORELink` (macOS default path). Pass the flavor folder as the first argument for another location, e.g. `_classic_` or a Windows path.
2. If the script moved an existing folder aside (`CORELink.bak.*`), tell the user; it holds whatever version they had installed.
3. Tell the user to type `/reload` in game, then `/cl` to confirm the version loaded (the status line shows config and `last send result`).
4. Never edit files under `Interface/AddOns` directly; edit the repo and `/reload`.
