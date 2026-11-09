# Agent guide

CORELink is a World of Warcraft addon (`CORELink/`, fourteen Lua files loaded in TOC order, mapped in
`docs/ARCHITECTURE.md`) that bridges guild chat between co-guilds over a hidden custom chat channel. It targets the WoW: Forever client (Classic-based engine, interface
16001) and tolerates retail 12.x APIs.

What an agent can and cannot do here:

* Can: edit Lua, run `tests/run.sh` (mock WoW API in plain Lua), run `scripts/install-local.sh` to place the
  addon in a local client, package a zip.
* Cannot: launch the game, log in, or observe chat. Anything beyond the harness must be verified by a human
  with two characters in two different guilds. Say so explicitly in your summary.

Read in order: `branching.md`, `testing.md`, `wow-api-gotchas.md`, `feature-requests.md`, `review-checklist.md`.
