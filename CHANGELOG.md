# Changelog

From 0.1.2 on, release notes are generated on the GitHub Releases page from the merged pull-request titles:
https://github.com/core-wow-community/CORELink/releases. This file is kept for the first two versions only.

## 0.1.1 - 2026-10-05

- `/cl report`: one pasteable diagnostic line (version, channel, last send result, lockdown, queue, guilds heard,
  table sizes, last 20 debug events) shown in chat and in the copy box.
- `/cl debug on|off`: echo relay events (config loaded, join, queued, sent with result, shown, ignored) to chat.
  Events are recorded regardless, so a report after the fact still has them.
- A failed relay send (result other than 0) is now reported to the player instead of being swallowed.
- Tooling: luacheck runs locally and in CI with the WoW globals listed in `.luacheckrc`.

## 0.1.0 - 2026-10-05

First release. Guild chat bridged between co-guilds over a hidden channel using addon messages (protocol CL4),
class-coloured names, officer highlighting with configurable rank cutoff and colour, nicknames shared over the
guild addon channel, `/cl guilds` presence beacons, per-window placement, per-guild mute. Confirmed in a live
two-guild test on the Forever beta.
