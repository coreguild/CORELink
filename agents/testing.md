# Testing

## Without the game (always)

```
tests/run.sh
```

Runs `luac -p` on the addon and then `tests/harness.lua`, a mock of the WoW API that loads the real addon file
and drives it through login, Guild Info parsing, channel join, outgoing relay, incoming packets (all protocol
versions), filters, nicknames, GM-only commands and UTF-8 trimming. Exit code is non-zero on any failure.

When you add behaviour, add a `check(...)` to `tests/harness.lua`. Mock only what the addon calls; keep mocks
in the harness, never in the addon.

Needs a Lua interpreter: macOS `brew install lua`; Windows `winget install DEVCOM.Lua`; Linux `apt install lua5.4`.

## In the game (humans)

```
scripts/install-local.sh ["/path/to/World of Warcraft/_classic_beta_"]
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
