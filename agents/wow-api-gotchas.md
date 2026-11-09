# WoW API constraints that bit this project

Read before changing anything in the relay, channel or chat code.

1. **Custom channel chat needs a hardware event.** Since patch 8.2.5, `SendChatMessage(..., "CHANNEL", ...)` is
   refused unless the call happens inside a keypress or click. Chat event handlers and `C_Timer` callbacks are
   not hardware events. If you ever send plain channel chat, do it from a post-hook on the chat edit box
   (`hooksecurefunc(ChatFrameNEditBox, "ParseText", ...)`), the way GreenWall does.
2. **Addon messages on player-made channels WORK on the Forever client** (confirmed in a live two-guild test on
   2026-10-05 with 0.1.0). Classic 1.13.3 disallowed `SendAddonMessage(..., "CHANNEL", ...)`, and standard
   channels (General, Trade) still refuse them, so do not assume this on other Classic flavors. The result code
   (`Enum.SendAddonMessageResult`, 0 = ok, 4 = InvalidChatType, 7 = InvalidChannel) is what `/cl` shows as
   `last send result`. Keep that visible. Addon messages need no hardware event, which is why the timer-based
   send queue in 0.1.0 is fine while plain channel chat (point 1) would not be.
3. **Never swallow send results with `pcall` silently.** Record the result so `/cl` can show it. A silent failure
   cost the team several days.
4. **Channel joins are asynchronous.** `GetChannelName` returns 0 until the server answers; confirm joins from
   `CHAT_MSG_CHANNEL_NOTICE` (`YOU_JOINED` / `YOU_CHANGED`) or re-check later. Never print a failure on the same tick.
5. **Guild Information is read-only for addons** and capped at 500 characters. Give the GM text to paste.
6. **Chat filters, not `GetChatWindowMessages`, decide what shows.** `GetChatWindowMessages` returns message
   groups (`GUILD`, `SAY`); `GetChatWindowChannels` returns channels. `ChatFrame_RemoveChannel` wants a frame
   object, not a name string.
7. **Packet size.** Channel and addon messages are limited to 255 bytes including the prefix. Trim on UTF-8 and
   `|c...|r` / `|H...|h` boundaries; a half link gets the whole message rejected.
8. **Secret values.** On Midnight-era clients chat payloads can be secret inside instances; guard with
   `issecretvalue` and pause relaying when `C_ChatInfo.InChatMessagingLockdown()` is true.
9. **Factions.** Custom channels are faction-bound on Classic clients; cross-faction bridging is not possible.
   **Realms.** On live Forever realms are not chat boundaries: custom channels, guild addon messages and
   whispers all cross them (normalized names drop the spaces: `CAMWOWUS1Realm1PvE`). The beta had per-realm
   channels; that was a beta artefact.
   **Custom channels on live Forever** (tested 2026-11-08): a custom chat channel is shared by every realm (text
   typed on Realm 7 shows on Realm 5), its text arrives readable to addons with the author's full name, but
   `SendAddonMessage(..., "CHANNEL", id)` is answered by the server with `NOT_ALLOWED_IN_CHANNEL` every time,
   for every character and channel tried. Chat text can only be sent from inside the player's keypress. So:
   relay as text from the send hooks, never as addon packets on a channel. The beta allowed the packets.
   **Forever names are unique across realms** (tested 2026-11-06): a chat whisper to a plain `First Surname`
   reaches a player on another realm, their reply shows no `-Realm` suffix, `/who` returns players from every
   realm, and `C_FriendList.GetWhoInfo` gives `fullName` without a realm. Nothing in `/who` tells a player's
   realm; only `GetNormalizedRealmName()` on their own client does. `/who g-"Name"` is a substring match
   (`g-"CORE"` also returns `Molten Soft Core`); filter on `fullGuildName`. Results are capped at 50.
11. **Communities (`C_Club`) exist on Forever but sends are hardware-gated.** `C_Club.SendMessage` from a
    `/run` (keypress) delivers; the same call from a `C_Timer` is accepted and silently dropped (tested
    2026-10-08). So a community can carry only lines typed by the player, never relays for others.
10. **Interface numbers.** Forever = `16001`. Do not put dotted versions like `12.3.1` in `## Interface:`; use the
    numeric form only.

12. **Community message text is a Kstring placeholder.** `C_Club.GetMessageInfo(...).content` on Forever is a token
    such as `|Kw158|k` (8 bytes). `issecretvalue` says false, string functions run on it, but it carries no text:
    the chat frame renders it, the addon cannot match it, and on another client it draws as "Unknown", so it
    cannot be relayed or forwarded. Author name, guid and class come from `info.author` and
    `C_Club.GetMemberInfo`; our own and guildmates' posts are recognised by guid against the roster. Put anything
    readers must see (tag, rank, nickname) in the posted text itself. Measured 2026-10-13 with the probe
    `print(#i.content, i.content:byte(1, 12))`.
