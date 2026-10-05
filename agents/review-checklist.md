# Pre-merge review: will this hurt someone's gameplay?

Run this review on every PR before it is merged, whether a human or an agent wrote it. CI proves the code runs
in the harness; this review is about what it does to a player's client at 8 PM on raid night.

## Blockers (do not merge)

1. **Protected calls outside a hardware event.** `SendChatMessage` to CHANNEL/SAY/YELL, `JoinChannelByName`
   from a timer, anything the client taints. Addon messages are fine; plain channel chat is not unless it runs
   inside an edit-box hook. See `wow-api-gotchas.md`.
2. **Flood risk.** The server disconnects clients that send too many messages. Outgoing traffic must stay behind
   the send queue (1 message per second) and the de-dupe window. No loops that send per roster entry, per event,
   or per frame.
3. **Lua errors visible to players.** Any path that can hit `nil` indexing, a missing API on this client
   (guard with `if X then`), or a secret value (`issecretvalue`) in instanced content.
4. **Protocol breakage.** Changing `PROTO`, field order or `~` separator without keeping older versions readable
   on receive, or without bumping the version. Players update at different times.
5. **Guild Info line format changes** that stop existing lines from parsing. The GM should never have to repaste.
6. **Chat spam to the player.** New `Print` calls on timers, on every roster update, or on every incoming packet.
   Diagnostics belong behind `/cl` status, not in the chat stream.
7. **Writes to Blizzard frames or saved variables that are not ours.** Only `CORELinkDB`.

## Must check

- `OnUpdate` scripts, tickers faster than 1 s, or work inside `CHAT_MSG_*` handlers that is more than a table
  lookup. Chat events fire constantly in a busy guild.
- Unbounded tables: `seen`, `displayed`, `heard`, `nicks`, queues. Everything must expire or be capped.
- Behaviour when: not in a guild, not configured, channel not joined, lockdown active, Guild Info empty,
  another guild still on an older version.
- The TOC `## Interface:` matches the live client (`scripts/check-game-version.sh`); CI enforces this.
- Harness has a `check(...)` for the new behaviour and `tests/run.sh` passes, including luacheck with no new
  entries in `.luacheckrc` that are not real WoW globals.
- New diagnostics go through `Debug(...)` (kept for `/cl report`), not `Print`, unless the player must act on them.
- README command table updated when user-visible. `## Version:` in the TOCs untouched (`@project-version@`).
  Commit subjects readable as release-note lines.

## Report format

Post the review as a PR comment: a verdict line (`approve` / `needs changes`), then one bullet per finding with
file and line, then "not verified in game" or the in-game steps performed.
