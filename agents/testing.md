# Testing

## Without the game (always)

```
tests/run.sh
```

Runs `luac -p` on the addon, then `luacheck` (undefined globals, typos in API names, unused variables, accidental
globals; configuration and the list of allowed WoW globals in `.luacheckrc`), then `tests/size.sh` (file and function length limits), then `tests/harness.lua`, a mock of the WoW API that
loads the real addon files in TOC order and drives them through login, Guild Info parsing, channel join, outgoing relay, incoming packets (all protocol
versions), filters, nicknames, GM-only commands and UTF-8 trimming. Exit code is non-zero on any failure.

Then `tests/compat.sh` loads the oldest supported release from its tag next to the working copy and makes the two
talk to each other (`tests/compat.lua`; "Frozen formats" in `docs/ARCHITECTURE.md`). If the tag is missing it says
how to fetch it, skips locally and fails in CI. It has its own small fake client; when the addon calls a new game
API, add it there too.

When you add behaviour, add a `check(...)` to `tests/harness.lua`. Mock only what the addon calls; keep mocks
in the harness, never in the addon.

If you use a WoW API that is not in `.luacheckrc`, add it to `read_globals` in the same PR and guard the call with
`if X then`. Do not silence a warning with an inline comment unless the comment says why.

Needs a Lua interpreter and luacheck: macOS `brew install lua luacheck`; Windows `winget install DEVCOM.Lua`; Linux `apt install lua5.4`.

## In the game (humans)

```
scripts/install-local.sh ["/path/to/World of Warcraft/_forever_"]
```

Symlinks `CORELink/` into `Interface/AddOns/`, so every save is picked up by `/reload`. On Windows without
symlink rights it copies instead; re-run after each change.

Minimum manual test for any chat/relay change, two characters in two different guilds, both with the Guild Info
line:

1. `/cl` on both: configured, channel joined.
2. Type a guild message on A. B sees `[TAGA] [A]: ...`. Check `/cl` on A shows `last send result: 0`.
3. Type on B; A sees it. Then `/cl guilds` lists both tags.
4. `/reload` on both and confirm it still works (tests the auto-join path).

Record exactly this in the PR. If you only ran the harness, write "not verified in game".

When a player reports a problem, ask for the output of `/cl report`. It contains the version, channel id, last send
result and the last 20 debug events, which is usually enough to locate the fault without a back-and-forth.
